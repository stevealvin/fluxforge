import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/engines/search_concurrency_pool.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/features/search/models/search_result.dart';

/// 跨源检索会话（页面 UI 状态容器）
///
/// 持有本轮检索的全部可变状态：聚合结果、各源状态、分页游标与轮次 Epoch。
/// 页面只订阅本会话并负责渲染，不再直接改状态字段。
///
/// 关键机制 —— **轮次 Epoch**：每轮检索分配独立 epoch，所有回包都会校验 epoch，
/// 彻底杜绝「上一轮迟到的结果污染新一轮结果集」导致的错乱。
class SearchSession extends ChangeNotifier {
  SearchSession({
    required this.resolveRules,
    this.maxConcurrency = SearchConcurrencyPool.defaultConcurrency,
  });

  /// 解析当前应参与检索的规则源（单源模式与全网模式由页面注入决定）
  final List<Rule> Function() resolveRules;

  /// 受控并发度
  final int maxConcurrency;

  /// 全源聚合结果集
  final List<NormalizedSearchResult> allResults = [];

  /// 规则状态字典：Key 为规则唯一标识 (id 或 name)
  final Map<String, RuleSearchStatus> statusMap = {};

  /// 分页游标：记录每个规则当前已加载的页码
  final Map<String, int> rulePageMap = {};

  /// 本轮并发检索中
  bool loading = false;

  /// 上滑分页加载中
  bool loadingMore = false;

  /// 当前检索关键词
  String currentQuery = '';

  /// 页面选中的筛选源（null 代表「全部」）
  Rule? selectedRule;

  int _epoch = 0;
  bool _disposed = false;

  /// 当前筛选模式下是否还有更多页可加载
  bool get hasMore => SearchAggregator.hasMoreFor(
        statusMap: statusMap,
        selectedRule: selectedRule,
      );

  /// 经过源过滤后的最终展示列表
  List<NormalizedSearchResult> get displayResults =>
      SearchAggregator.filterByRule(allResults, selectedRule);

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// 安全通知：已销毁时静默忽略，避免 `notifyListeners after dispose`
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// 轮次是否已过期（用户中止 / 新一轮检索开启 / 页面已销毁）
  bool _isStale(int epoch) => _disposed || epoch != _epoch;

  /// 切换筛选源
  void selectRule(Rule? rule) {
    selectedRule = rule;
    _notify();
  }

  /// 手动中止正在进行的跨源并发检索 (开源阅读同款 Stop 机制)
  void cancel() {
    if (!loading) return;
    _epoch++;
    loading = false;
    // 防御性复位：正常路径下 cancel 只在首轮检索期间可达（与分页严格互斥），
    // 但若存在在途分页也必须一并放开标志，否则会永久卡住上滑分页
    loadingMore = false;
    // 将剩余尚未完成的规则源标记为已停止
    for (final status in statusMap.values) {
      status.isSearching = false;
    }
    _notify();
  }

  /// 清空结果并回到未检索状态（返回上一级 / 清空关键词时调用）
  ///
  /// 会一并递增轮次 Epoch，等价于「隐式取消」在途检索：
  /// 否则用户已退回历史面板，后台仍在跑完所有源，且回包会写回刚被清空的
  /// [allResults] / [statusMap]，形成「已清空却仍有幽灵数据」的脏状态。
  void clearResults() {
    _epoch++;
    allResults.clear();
    // 各源状态与分页游标同步归零，避免命名与行为不符的残留
    statusMap.clear();
    rulePageMap.clear();
    currentQuery = '';
    loading = false;
    loadingMore = false;
    _notify();
  }

  /// 发起一轮新的跨源并发流式检索
  ///
  /// [timeoutSeconds] 由页面按设置注入（首页检索要求更短的收窄超时）。
  Future<void> search(String query, {required int timeoutSeconds}) async {
    final rules = resolveRules();
    if (rules.isEmpty) return;

    final thisEpoch = ++_epoch;

    currentQuery = query;
    loading = true;
    // 新一轮必须清掉上一轮的分页标志：旧轮次的 loadMore 会被 epoch 守卫提前 return，
    // 若不复位就会永久卡在 true，导致底部一直转圈且上滑分页彻底失效
    loadingMore = false;
    allResults.clear();
    statusMap.clear();
    rulePageMap.clear();

    // 初始化各源检索状态（统一使用安全 Key 提取，防御 int 类型主键崩溃）
    for (final rule in rules) {
      final key = SearchAggregator.ruleKeyOf(rule);
      statusMap[key] = RuleSearchStatus(rule: rule, isSearching: true);
      rulePageMap[key] = 1;
    }
    _notify();

    // 让出主事件队列确保 UI 能够先平滑渲染顶部进度条与流式准备态
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (_isStale(thisEpoch)) return;

    await SearchConcurrencyPool.run<Rule>(
      rules,
      maxConcurrency: maxConcurrency,
      shouldAbort: () => _isStale(thisEpoch),
      action: (rule) => _runRuleSearch(rule, query, thisEpoch, timeoutSeconds),
    );

    if (_isStale(thisEpoch)) return;
    loading = false;
    _notify();
  }

  /// 单源首页检索
  Future<void> _runRuleSearch(
    Rule rule,
    String query,
    int epoch,
    int timeoutSeconds,
  ) async {
    final key = SearchAggregator.ruleKeyOf(rule);

    try {
      final raw = await RuleEngine.search(rule, query, page: 1, timeoutSeconds: timeoutSeconds)
          .timeout(Duration(seconds: timeoutSeconds + 1));
      if (_isStale(epoch)) return;

      final parsed = SearchAggregator.parseResults(raw, rule);
      final items = SearchAggregator.itemsOf(raw);
      // 严格遵循规则引擎契约：显式 hasMore 优先，否则以本页条目是否非空兜底
      final ruleHasMore = SearchAggregator.hasMoreOf(raw, items);
      if (_isStale(epoch)) return;

      // 单源只要搜到数据即刻流式上屏，用户无需等待全部源跑完即可立刻浏览
      allResults.addAll(parsed);
      final status = statusMap[key];
      if (status != null) {
        status.isSearching = false;
        status.count = parsed.length;
        status.hasMore = ruleHasMore;
      }
      _notify();
    } catch (e) {
      debugPrint('【流式搜索】源 [${rule.name}] 检索异常: $e');
      if (_isStale(epoch)) return;
      final status = statusMap[key];
      if (status != null) {
        status.isSearching = false;
        status.hasError = true;
        status.errorMessage = e.toString();
        // 出错源直接封禁分页加载，避免无限重试报错
        status.hasMore = false;
      }
      _notify();
    }
  }

  /// 加载下一页数据
  Future<void> loadMore({required int timeoutSeconds}) async {
    // 若正在检索 / 正在分页 / 关键词为空 / 当前筛选范围已无更多数据，直接拦截，严禁发起无谓请求
    // （补上 loading 守卫：分页与首轮检索必须严格互斥，避免标志位互相踩踏）
    if (loading || loadingMore || currentQuery.isEmpty || !hasMore) return;

    final thisEpoch = _epoch;
    final targetRules = selectedRule != null ? [selectedRule!] : resolveRules();

    // 关键过滤：仅对尚未用尽分页数据的规则源发起下一页请求
    final eligibleRules = targetRules.where((rule) {
      final status = statusMap[SearchAggregator.ruleKeyOf(rule)];
      return status != null && status.hasMore;
    }).toList();
    if (eligibleRules.isEmpty) return;

    loadingMore = true;
    _notify();

    // 让出主事件队列保证「加载更多」底部指示器先渲染完成
    // (使用微延时替代易死锁挂起的 endOfFrame)
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (_disposed) return;

    for (final rule in eligibleRules) {
      if (_isStale(thisEpoch)) break;
      final key = SearchAggregator.ruleKeyOf(rule);
      final nextPage = (rulePageMap[key] ?? 1) + 1;

      try {
        final raw =
            await RuleEngine.search(rule, currentQuery, page: nextPage, timeoutSeconds: timeoutSeconds)
                .timeout(Duration(seconds: timeoutSeconds + 2));
        if (_isStale(thisEpoch)) break;

        final items = SearchAggregator.itemsOf(raw);
        // 未显式声明 hasMore 时，空列表即判定彻底无更多
        final ruleHasMore = SearchAggregator.hasMoreOf(raw, items);
        final parsed = SearchAggregator.parseResults(raw, rule);

        if (parsed.isNotEmpty) {
          allResults.addAll(parsed);
          rulePageMap[key] = nextPage;
        }
        final status = statusMap[key];
        if (status != null) {
          status.count += parsed.length;
          status.hasMore = ruleHasMore;
        }
        _notify();
      } catch (e) {
        debugPrint('【搜索分页】源 [${rule.name}] 第 $nextPage 页加载失败: $e');
        if (_isStale(thisEpoch)) break;
        final status = statusMap[key];
        if (status != null) {
          // 分页异常时标记此源结束，防止因单源异常死循环触发上滑
          status.hasMore = false;
        }
        _notify();
      }
    }

    // 分页标志必须复位，且只在「仍属于自己这一轮」时复位：
    // 若已被新检索 / 清空接管，则标志由接管方负责，避免旧轮次误关新轮次正在进行的分页
    if (_epoch == thisEpoch) {
      loadingMore = false;
    }
    _notify();
  }
}
