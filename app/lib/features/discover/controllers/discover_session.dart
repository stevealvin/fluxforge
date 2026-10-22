import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:fluxforge/core/concurrency/concurrency_pool.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/discover/engines/discover_aggregator.dart';
import 'package:fluxforge/features/discover/models/discover_item.dart';
import 'package:fluxforge/features/discover/models/discover_source_status.dart';

/// 发现页的跨源聚合会话（页面 UI 状态容器）
///
/// 持有本轮聚合的全部可变状态：聚合条目流、轮播池、各源状态、当前频道与轮次 Epoch。
/// 页面只订阅本会话并负责渲染，不再直接改状态字段。
///
/// 关键机制 —— **轮次 Epoch**：每轮聚合分配独立 epoch，所有回包都会校验 epoch，
/// 杜绝「上一轮迟到的结果污染新一轮」造成的错乱（与搜索页同款思路）。
///
/// 另一处关键设计 —— **轮播与网格互斥**：轮播展示的条目不会同时出现在下方网格，
/// 否则同一条内容会在一屏里出现两次（去重键由 [DiscoverItem.dedupeKey] 提供）。
class DiscoverSession extends ChangeNotifier {
  DiscoverSession({
    required this.resolveAllRules,
    this.maxConcurrency = ConcurrencyPool.defaultConcurrency,
    this.loader,
  });

  /// 解析当前全部启用规则源（页面注入，便于测试与「无规则」空态）
  final List<Rule> Function() resolveAllRules;

  /// 单源加载器：缺省走真实沙箱，单测可注入可控假实现
  final Future<dynamic> Function(Rule rule)? loader;

  /// 受控并发度
  final int maxConcurrency;

  /// 聚合后的条目流（跨源去重，按到达顺序累积）
  List<DiscoverItem> allItems = [];

  /// 轮播池：每个源贡献一条代表内容（先到先入）
  List<DiscoverItem> heroPool = [];

  /// 各源状态（Key 为源唯一标识）
  final Map<String, DiscoverSourceStatus> statusMap = {};

  /// 当前频道（媒体类型分组）
  MediaKind selectedKind = MediaKind.all;

  /// 本轮聚合中
  bool loading = false;

  int _epoch = 0;
  bool _disposed = false;

  /// 本轮参与的源数
  int get sourceCount => statusMap.length;

  /// 已完成（含失败）的源数
  int get finishedCount => statusMap.values.where((s) => !s.loading).length;

  /// 失败源数
  int get failedCount => statusMap.values.where((s) => s.hasError).length;

  /// 聚合进度（0.0 ~ 1.0）
  double get progress =>
      statusMap.isEmpty ? 0.0 : (finishedCount / sourceCount).clamp(0.0, 1.0);

  /// 是否全部源都失败（用于区分「还在加载」与「真的取不到」）
  bool get allFailed =>
      statusMap.isNotEmpty && failedCount == sourceCount && !loading;

  /// 当前频道的条目（排除已进入轮播的，保证两处不重复展示）
  List<DiscoverItem> get channelItems {
    final heroKeys = heroPool.map((e) => e.dedupeKey).toSet();
    return allItems.where((item) {
      if (selectedKind != MediaKind.all && item.kind != selectedKind) {
        return false;
      }
      return !heroKeys.contains(item.dedupeKey);
    }).toList(growable: false);
  }

  /// 参与本轮聚合的源（按当前频道收窄）
  List<Rule> get _eligibleRules {
    final all = resolveAllRules();
    if (selectedKind == MediaKind.all) return all;
    return all
        .where((r) => mediaKindOfRuleType(r.type) == selectedKind)
        .toList(growable: false);
  }

  /// 切换频道
  ///
  /// 频道决定「聚合哪些类型的源」，因此源集合随之变化，需要补拉。
  /// 但**不等待**：先用已有数据立即填充新频道（不闪空），再在后台补拉缺口。
  void selectKind(MediaKind kind) {
    if (kind == selectedKind) return;
    selectedKind = kind;
    _notify();
    unawaited(load());
  }

  /// 拉取一轮聚合
  ///
  /// 增量语义：已取到的条目**不清空**，新结果并入后统一去重。
  /// 因此切换频道时不会闪回空白 —— 这是「先显示、再补齐」体验的关键。
  Future<void> load() async {
    final epoch = ++_epoch;
    loading = true;

    final rules = _eligibleRules;

    // 只移除本轮不再参与的源的状态，保留其余 —— 避免进度条在切频道时闪回 0
    final eligibleKeys = rules.map((r) => r.id?.toString() ?? r.name).toSet();
    statusMap.removeWhere((key, _) => !eligibleKeys.contains(key));

    _notify();

    if (rules.isEmpty) {
      loading = false;
      _notify();
      return;
    }

    await ConcurrencyPool.run<Rule>(
      rules,
      action: (rule) => _loadOne(rule, epoch),
      shouldAbort: () => _isStale(epoch),
    );

    if (_isStale(epoch)) return;
    loading = false;
    _notify();
  }

  Future<void> _loadOne(Rule rule, int epoch) async {
    final status = DiscoverSourceStatus(rule: rule);
    statusMap[status.key] = status;
    _notify();

    try {
      final raw = await (loader ?? _defaultLoader)(rule);
      // 在途期间被中止 / 被新一轮顶替：结果作废
      if (_isStale(epoch)) return;

      final items = DiscoverAggregator.parseItems(raw, rule);
      status.count = items.length;
      status.loading = false;

      // 增量合并：重复内容由聚合层的去重逻辑吸收，不会叠加
      allItems = DiscoverAggregator.dedupe([...allItems, ...items]);
      // 轮播池随数据增长实时刷新 —— 先到先入，不等所有源
      heroPool = DiscoverAggregator.buildHeroPool(allItems);

      _notify();
    } catch (e) {
      if (_isStale(epoch)) return;
      status.loading = false;
      status.hasError = true;
      status.errorMessage = e.toString();
      _notify();
    }
  }

  Future<dynamic> _defaultLoader(Rule rule) => RuleEngine.discovery(rule);

  /// 中止本轮聚合
  void cancel() {
    _epoch++;
    loading = false;
    for (final status in statusMap.values) {
      status.loading = false;
    }
    _notify();
  }

  bool _isStale(int epoch) => _disposed || epoch != _epoch;

  /// 安全通知：已销毁时静默忽略，避免 `notifyListeners after dispose`
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
