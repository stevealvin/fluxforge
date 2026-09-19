import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/features/search/models/search_result.dart';
import 'package:fluxforge/features/search/widgets/search_placeholder_views.dart';
import 'package:fluxforge/features/search/widgets/search_result_grid_view.dart';
import 'package:fluxforge/features/search/widgets/search_result_list_view.dart';

/// 跨源聚合结果区（开源阅读同款流式响应）
///
/// 只做三态分发：等待态 / 空态 / 结果态，具体渲染交给各子视图：
/// - [SearchPendingView] 检索中尚无数据；
/// - [SearchEmptyView] 检索完成但无结果（含单源异常诊断）；
/// - [SearchResultListView] / [SearchResultGridView] 列表与双列网格。
class SearchResultsView extends StatelessWidget {
  const SearchResultsView({
    super.key,
    required this.isDark,
    required this.results,
    required this.statusMap,
    required this.targetRule,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.isGridView,
    required this.scrollController,
    required this.onRefresh,
    required this.onItemTap,
    required this.onCancel,
    required this.onRetry,
    required this.onGoMarket,
    required this.onDebugRule,
  });

  final bool isDark;

  /// 已按当前源筛选后的结果集
  final List<NormalizedSearchResult> results;

  /// 本轮各源状态（用于进度展示与单源异常诊断）
  final Map<String, RuleSearchStatus> statusMap;

  /// 单源模式的目标规则（全网模式为 null）
  final Rule? targetRule;

  /// 本轮并发检索是否仍在进行
  final bool isLoading;

  /// 上滑分页加载中
  final bool isLoadingMore;

  /// 当前筛选模式下是否还有更多页
  final bool hasMore;

  final bool isGridView;
  final ScrollController scrollController;

  final Future<void> Function() onRefresh;

  final ValueChanged<NormalizedSearchResult> onItemTap;

  /// 中止本轮跨源并发检索
  final VoidCallback onCancel;

  /// 单源模式下重试本轮检索
  final VoidCallback onRetry;

  /// 跳转规则市场
  final VoidCallback onGoMarket;

  /// 跳转规则调试器
  final ValueChanged<Rule> onDebugRule;

  @override
  Widget build(BuildContext context) {
    // 正在检索且当前暂无任何源返回数据 (前数百毫秒等待态，带友好进度指示与一键停止)
    if (results.isEmpty && isLoading) {
      return SearchPendingView(
        isDark: isDark,
        statusMap: statusMap,
        onCancel: onCancel,
      );
    }

    // 检索完成但无匹配结果 (带单源异常诊断感知)
    if (results.isEmpty && !isLoading) {
      return SearchEmptyView(
        isDark: isDark,
        targetRule: targetRule,
        statusMap: statusMap,
        onRetry: onRetry,
        onGoMarket: onGoMarket,
        onDebugRule: onDebugRule,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      color: AppColors.primary,
      child: isGridView
          ? SearchResultGridView(
              isDark: isDark,
              results: results,
              targetRule: targetRule,
              isLoading: isLoading,
              isLoadingMore: isLoadingMore,
              hasMore: hasMore,
              scrollController: scrollController,
              onItemTap: onItemTap,
            )
          : SearchResultListView(
              isDark: isDark,
              results: results,
              isLoading: isLoading,
              isLoadingMore: isLoadingMore,
              hasMore: hasMore,
              scrollController: scrollController,
              onItemTap: onItemTap,
            ),
    );
  }
}
