import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/models/search_result.dart';
import 'package:fluxforge/features/search/widgets/search_grid_card.dart';
import 'package:fluxforge/features/search/widgets/search_result_footer.dart';

/// 双列瀑布流海报网格视图
///
/// 用 `CustomScrollView + SliverGrid` 而非嵌套 GridView，让底部状态条作为通栏 Sliver
/// 居中展示；纵横比按「本页是否以视频源为主」自适应切换。
class SearchResultGridView extends StatelessWidget {
  const SearchResultGridView({
    super.key,
    required this.isDark,
    required this.results,
    required this.targetRule,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.scrollController,
    required this.onItemTap,
  });

  final bool isDark;
  final List<NormalizedSearchResult> results;

  /// 单源模式的目标规则（全网模式为 null，此时按结果集构成推断纵横比）
  final Rule? targetRule;

  final bool isLoading;
  final bool isLoadingMore;
  final bool hasMore;
  final ScrollController scrollController;
  final ValueChanged<NormalizedSearchResult> onItemTap;

  @override
  Widget build(BuildContext context) {
    final isMostlyVideo = targetRule != null
        ? SearchAggregator.isVideoRule(targetRule!)
        : (results.isEmpty ||
            results.where((r) => SearchAggregator.isVideoRule(r.rule)).length >=
                results.length / 2);
    final showBottomLoader = isLoading || isLoadingMore;
    final showNoMore = !showBottomLoader && !hasMore && results.isNotEmpty;
    final hasFooter = showBottomLoader || showNoMore;

    return CustomScrollView(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: isMostlyVideo ? 1.12 : 0.65,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = results[index];
                return SearchGridCard(
                  item: item,
                  isDark: isDark,
                  onTap: () => onItemTap(item),
                );
              },
              childCount: results.length,
            ),
          ),
        ),
        if (hasFooter)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: SearchResultFooter(
                isDark: isDark,
                isLoading: showBottomLoader,
                loadingLabel: isLoading ? '正在流式检索其余规则源...' : '加载更多中...',
              ),
            ),
          ),
      ],
    );
  }
}
