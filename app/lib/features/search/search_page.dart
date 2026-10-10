import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/controllers/search_session.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/models/search_result.dart';
import 'package:fluxforge/features/search/widgets/search_app_bar.dart';
import 'package:fluxforge/features/search/widgets/search_history_panel.dart';
import 'package:fluxforge/features/search/widgets/search_results_view.dart';
import 'package:fluxforge/features/search/widgets/search_source_filter_bar.dart';

/// 全局跨媒体多源并发聚合搜索页面
///
/// 页面只负责「输入交互 + 页面装配」：
/// - 检索状态与并发调度全部下沉到 [SearchSession]；
/// - 聚合策略见 [SearchAggregator]；
/// - 各视图（搜索栏、源筛选、历史面板、结果区）见 `widgets/`。
class SearchPage extends StatefulWidget {
  final String? initialKeyword;
  final Rule? targetRule;

  const SearchPage({
    super.key,
    this.initialKeyword,
    this.targetRule,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// 检索会话（全部可变检索状态由它持有）
  late final SearchSession _session;

  /// 视图模式：true 为双列瀑布流海报网格，false 为紧凑卡片列表
  ///
  /// 默认网格：搜索结果是「跨源聚合来的一屏候选」，用户此时在做**扫读与挑选**，
  /// 封面比文字更能帮他快速定位；列表排版留给「已明确要找哪一条」的场景，
  /// 由状态行右侧的切换键随时切回。
  bool _isGridView = true;

  /// 当前选中的媒体类型：搜索**前**收窄源范围（只对匹配类型的源发起检索）
  MediaKind _selectedKind = MediaKind.all;

  /// 历史搜索关键词列表
  List<String> _historyList = [];

  /// 是否展示历史/推荐面板
  bool _showHistory = true;

  @override
  void initState() {
    super.initState();
    _historyList = historyService.searchHistory.toList();

    _session = SearchSession(resolveRules: _getEligibleRules)
      ..selectedRule = widget.targetRule
      ..addListener(_onSessionChanged);

    _scrollController.addListener(_onScroll);
    ruleService.rulesNotifier.addListener(_onRulesChanged);
    _focusNode.addListener(_onFocusChanged);
    historyService.searchHistoryNotifier.addListener(_onHistoryChanged);

    // 处理初始关键词入参自动触发搜索
    if (widget.initialKeyword != null && widget.initialKeyword!.trim().isNotEmpty) {
      _controller.text = widget.initialKeyword!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(_controller.text);
      });
    }
  }

  @override
  void dispose() {
    historyService.searchHistoryNotifier.removeListener(_onHistoryChanged);
    ruleService.rulesNotifier.removeListener(_onRulesChanged);
    _focusNode.removeListener(_onFocusChanged);
    _session
      ..removeListener(_onSessionChanged)
      ..dispose();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _onRulesChanged() {
    if (mounted) setState(() {});
  }

  /// 搜索历史响应式同步更新
  void _onHistoryChanged() {
    if (mounted) {
      setState(() {
        _historyList = historyService.searchHistory.toList();
      });
    }
  }

  /// 焦点状态改变时刷新界面，实现外层容器单圆角高亮过渡
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      // 核心硬性守卫：当无更多数据时，彻底禁止触发上滑加载，防止无限空轮询
      if (!_session.loading &&
          !_session.loadingMore &&
          !_showHistory &&
          _session.allResults.isNotEmpty &&
          _session.hasMore) {
        unawaited(_loadMoreResults());
      }
    }
  }

  /// 单项删除历史记录
  void _removeHistoryItem(String item) {
    historyService.removeHistory(item);
  }

  /// 清空全部历史记录
  void _clearAllHistory() {
    historyService.clearHistory();
  }

  /// 全部启用中的规则（不含类型收窄），用于统计各类型的可用源数
  List<Rule> _enabledRules() =>
      ruleService.rules.where((r) => r.enabled).toList();

  /// 各类型下的可用源数（「全部」即启用源总数）
  Map<MediaKind, int> _kindRuleCounts() {
    final enabled = _enabledRules();
    return {
      for (final kind in MediaKind.values)
        kind: SearchAggregator.filterRulesByKind(enabled, kind).length,
    };
  }

  /// 获取当前有效的检索规则列表
  ///
  /// [SearchPage.targetRule] 是「从某个源页面直达搜索」的场景，固定只搜那一个源，
  /// 不受类型筛选影响 —— 用户是带着明确目标进来的。
  List<Rule> _getEligibleRules() {
    if (widget.targetRule != null) {
      return [widget.targetRule!];
    }
    return SearchAggregator.filterRulesByKind(_enabledRules(), _selectedKind);
  }

  /// 切换媒体类型
  ///
  /// 类型变了 → 参与检索的源集合随之变化，因此**必须重跑一次检索**：
  /// 只过滤已有结果是不够的（那些结果里压根没有新类型的源）。
  void _onKindSelected(MediaKind kind) {
    if (kind == _selectedKind) return;
    setState(() => _selectedKind = kind);

    final query = _session.currentQuery.trim();
    if (query.isEmpty) return;

    // 该类型下没有可用源时明确提示，而不是让结果区静默变空
    if (_getEligibleRules().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('当前没有「${kind.label}」类型的可用规则源'),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }
    _performSearch(query);
  }

  /// 弹出类型筛选面板（行尾筛选按钮的入口）
  ///
  /// 选完即生效：类型决定「搜哪些源」，改了必须重搜，因此不设「应用」按钮 ——
  /// 多一次确认弹层只是徒增一步。
  Future<void> _openKindFilterSheet() async {
    final counts = _kindRuleCounts();
    final picked = await showModalBottomSheet<MediaKind>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _buildKindSheet(counts),
    );
    // 点遮罩关闭时不传值，保持原样
    if (picked == null) return;
    _onKindSelected(picked);
  }

  /// 类型筛选面板：单选列表 + 各类型可用源数
  ///
  /// 用列表而非一排胶囊：面板里有足够空间把「每个类型有几个源」写清楚，
  /// 无源的类型直接置灰，用户不必点进去才发现是空的。
  Widget _buildKindSheet(Map<MediaKind, int> counts) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final textTertiary = isDark
        ? AppColors.darkTextTertiary
        : AppColors.lightTextTertiary;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 顶部拖动条
            Container(
              width: 34,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
              child: Row(
                children: [
                  Text(
                    '按类型搜索',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                      color: textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '只检索该类型的规则源',
                    style: TextStyle(fontSize: 11, color: textTertiary),
                  ),
                ],
              ),
            ),
            for (final kind in MediaKind.values)
              _buildKindSheetRow(
                kind: kind,
                count: counts[kind] ?? 0,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                textTertiary: textTertiary,
              ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildKindSheetRow({
    required MediaKind kind,
    required int count,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
  }) {
    final isSelected = kind == _selectedKind;
    // 「全部」始终可选；具体类型在无可用源时置灰 —— 选了也搜不出东西
    final isEnabled = kind == MediaKind.all || count > 0;

    return InkWell(
      onTap: isEnabled ? () => Navigator.pop(context, kind) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(
              isSelected ? Ionicons.checkmarkCircle : Ionicons.ellipseOutline,
              size: 19,
              color: isSelected
                  ? AppColors.primary
                  : textTertiary.withValues(alpha: isEnabled ? 1.0 : 0.5),
            ),
            const SizedBox(width: 12),
            Text(
              kind.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isEnabled
                    ? (isSelected ? AppColors.primary : textPrimary)
                    : textTertiary.withValues(alpha: 0.6),
              ),
            ),
            const Spacer(),
            Text(
              isEnabled ? '$count 个源' : '暂无可用源',
              style: TextStyle(
                fontSize: 11.5,
                color: isEnabled ? textSecondary : textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 设置项中的请求超时（首页聚合检索收窄上限，避免单个死链源拖垮全局）
  int get _searchTimeout => appService.settingsNotifier.value.requestTimeoutSeconds.clamp(5, 12);

  /// 发起全局多源并发流式检索
  Future<void> _performSearch(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入搜索关键词'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    _focusNode.unfocus();

    // 前置校验：若当前无可用规则，立即提示并引导去市场导入，避免清空界面导致用户困惑
    if (_getEligibleRules().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('暂无可用的规则源，请先在规则市场中导入并启用规则'),
          action: SnackBarAction(
            label: '去导入',
            onPressed: () => context.pushMarket(),
          ),
        ),
      );
      return;
    }

    // 关键修复：全网搜索模式下必须无条件重置选中的源胶囊为「全部」，
    // 彻底杜绝因残留源筛选将新检索出的其他源条目全部过滤为空、
    // 从而引发「一直显示加载动画」的严重假死缺陷
    if (widget.targetRule == null) {
      _session.selectRule(null);
    }
    setState(() {
      _showHistory = false;
    });

    // 异步持久化搜索历史记录
    unawaited(historyService.addHistory(query));

    await _session.search(query, timeoutSeconds: _searchTimeout);
  }

  /// 上滑加载下一页
  Future<void> _loadMoreResults() =>
      _session.loadMore(timeoutSeconds: appService.settingsNotifier.value.requestTimeoutSeconds);

  /// 页面返回逻辑处理
  void _handleBack() {
    if (_showHistory) {
      context.pop();
    } else {
      setState(() {
        _showHistory = true;
      });
      // 先清空结果（内部会中止在途检索），再复位筛选源；
      // 必须走 selectRule 而非直接赋值，否则该字段不会触发重建
      _session.clearResults();
      _session.selectRule(widget.targetRule);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusMap = _session.statusMap;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        appBar: SearchAppBar(
          isDark: isDark,
          controller: _controller,
          focusNode: _focusNode,
          autofocus: widget.initialKeyword == null,
          hintText: widget.targetRule != null
              ? '在「${widget.targetRule!.name}」中搜索...'
              : '搜索海量影视、番剧、小说...',
          isLoading: _session.loading,
          onBack: _handleBack,
          onClear: () {
            _controller.clear();
            setState(() {
              _showHistory = true;
            });
            _session.clearResults();
          },
          onChanged: (_) => setState(() {}),
          onSubmitted: _performSearch,
          onCancel: _session.cancel,
        ),
        body: Column(
          children: [
            // 搜索进度指示条 (并发检索中展示，显示已完成规则比例)
            if (_session.loading)
              LinearProgressIndicator(
                value: statusMap.isEmpty ? null : SearchAggregator.finishedRatio(statusMap),
                minHeight: 2.5,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              ),

            // 检索范围控制栏（来源筛选胶囊 + 行尾筛选入口）
            //
            // 显示条件**不再看「有没有结果」**：这一行同时承载类型筛选入口，
            // 而「只搜索影视类型」这类需求必须在**发起检索前**表达 —— 搜完再过滤已经晚了。
            // 因此只要有可用规则源就显示；搜索前该行左侧显示当前检索范围，
            // 有了结果再自动切换成来源胶囊（两种形态见组件内注释）。
            if (widget.targetRule == null && _enabledRules().isNotEmpty)
              SearchSourceFilterBar(
                isDark: isDark,
                statuses: statusMap.values.toList(growable: false),
                totalCount: _session.allResults.length,
                displayCount: _session.displayResults.length,
                selectedRule: _session.selectedRule,
                isLoading: _session.loading,
                isGridView: _isGridView,
                onRuleSelected: _session.selectRule,
                onToggleView: (value) {
                  setState(() {
                    _isGridView = value;
                  });
                },
                onOpenFilter: _openKindFilterSheet,
                hasKindFilter: _selectedKind != MediaKind.all,
                kindLabel: _selectedKind.label,
              ),

            // 主内容区域：历史/推荐面板或聚合结果
            Expanded(
              child: _showHistory
                  ? SearchHistoryPanel(
                      isDark: isDark,
                      hasActiveRules: _getEligibleRules().isNotEmpty,
                      historyList: _historyList,
                      onPick: (text) {
                        _controller.text = text;
                        _performSearch(text);
                      },
                      onRemove: _removeHistoryItem,
                      onClearAll: _clearAllHistory,
                      onGoMarket: () => context.pushMarket(),
                    )
                  : SearchResultsView(
                      isDark: isDark,
                      results: _session.displayResults,
                      statusMap: statusMap,
                      targetRule: widget.targetRule,
                      isLoading: _session.loading,
                      isLoadingMore: _session.loadingMore,
                      hasMore: _session.hasMore,
                      isGridView: _isGridView,
                      scrollController: _scrollController,
                      onRefresh: () => _performSearch(_session.currentQuery),
                      onItemTap: _navigateToDetail,
                      onCancel: _session.cancel,
                      onRetry: () => _performSearch(_controller.text),
                      onGoMarket: () => context.pushMarket(),
                      onDebugRule: (rule) => context.pushRuleTest(rule),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// 跳转至规则详情或通用媒体分发页
  void _navigateToDetail(NormalizedSearchResult item) {
    context.pushRuleDetail(RuleDetailArgs(
      title: item.title,
      url: item.url,
      cover: item.cover,
      rule: item.rule,
    ));
  }
}
