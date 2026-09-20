import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
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
  bool _isGridView = false;

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

  /// 获取当前有效的检索规则列表
  List<Rule> _getEligibleRules() {
    if (widget.targetRule != null) {
      return [widget.targetRule!];
    }
    return ruleService.rules.where((r) => r.enabled).toList();
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

            // 源筛选胶囊栏 (仅在聚合多源检索且源数大于1时呈现，单源模式隐藏以保持界面清爽)
            if (!_showHistory && statusMap.length > 1)
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
