import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/search/models/search_result.dart';
import 'package:fluxforge/features/search/widgets/search_list_card.dart';
import 'package:fluxforge/features/search/widgets/search_result_footer.dart';

/// 紧凑卡片式列表视图
///
/// 底部通栏跟随「检索中 / 有更多 / 已到底」三态切换，避免用户误判为加载卡死。
class SearchResultListView extends StatelessWidget {
  const SearchResultListView({
    super.key,
    required this.isDark,
    required this.results,
    required this.isLoading,
    required this.isLoadingMore,
    required this.hasMore,
    required this.scrollController,
    required this.onItemTap,
  });

  final bool isDark;
  final List<NormalizedSearchResult> results;

  /// 本轮全局并发检索是否仍在进行
  final bool isLoading;

  /// 上滑分页加载中
  final bool isLoadingMore;

  final bool hasMore;
  final ScrollController scrollController;
  final ValueChanged<NormalizedSearchResult> onItemTap;

  @override
  Widget build(BuildContext context) {
    final showBottomLoader = isLoading || isLoadingMore;
    final showNoMore = !showBottomLoader && !hasMore && results.isNotEmpty;
    final hasFooter = showBottomLoader || showNoMore;

    return ListView.separated(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: results.length + (hasFooter ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return SearchResultFooter(
            isDark: isDark,
            isLoading: showBottomLoader,
            loadingLabel: isLoading ? '正在流式检索其余规则源...' : '加载更多中...',
          );
        }

        final item = results[index];
        return SearchListCard(
          item: item,
          isDark: isDark,
          onTap: () => onItemTap(item),
        );
      },
    );
  }
}
