import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/models/search_result.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/app_net_image.dart';

/// 列表模式卡片分发器
///
/// 视频类规则走 16:9 横版卡片，其余（图集 / 小说 / 漫画）走竖版海报卡片。
class SearchListCard extends StatelessWidget {
  const SearchListCard({
    super.key,
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  final NormalizedSearchResult item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    if (SearchAggregator.isVideoRule(item.rule)) {
      return SearchVideoListCard(item: item, isDark: isDark, onTap: onTap);
    }
    return SearchPortraitListCard(item: item, isDark: isDark, onTap: onTap);
  }
}

/// 横屏视频列表卡片（缩略图 140x80，宽大于高）
class SearchVideoListCard extends StatelessWidget {
  const SearchVideoListCard({
    super.key,
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  final NormalizedSearchResult item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final displayTag = item.displayTag;

    return AppCard(
      borderRadius: 12,
      padding: const EdgeInsets.all(8),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 横屏视频封面 16:9 (140x80，宽大于高)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 140,
              height: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(
                    imageUrl: item.cover,
                    fit: BoxFit.cover,
                    headers: item.baseUrl.isNotEmpty ? {'referer': item.baseUrl} : null,
                  ),
                  // 修复关键缺陷：Positioned 必须是 Stack 的直接子组件，严禁被 Builder 等包裹，否则导致 ParentDataWidget 断言崩溃灰屏
                  if (displayTag != null && displayTag.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          displayTag,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          height: 1.25,
                        ),
                      ),
                      if (item.desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.rule.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Ionicons.playCircleOutline, size: 16, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 竖屏列表卡片（适用于图集、小说等非视频源）
class SearchPortraitListCard extends StatelessWidget {
  const SearchPortraitListCard({
    super.key,
    required this.item,
    required this.isDark,
    required this.onTap,
  });

  final NormalizedSearchResult item;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final displayTag = item.displayTag;

    return AppCard(
      borderRadius: 12,
      padding: const EdgeInsets.all(10),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面海报
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 95,
              height: 135,
              child: NetImage(
                imageUrl: item.cover,
                fit: BoxFit.cover,
                headers: item.baseUrl.isNotEmpty ? {'referer': item.baseUrl} : null,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 详情信息区
          Expanded(
            child: SizedBox(
              height: 135,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      if (item.desc.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(
                          item.desc,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  // 底部标签栏 (分类、规则源徽章)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.rule.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      if (displayTag != null && displayTag.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            displayTag,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
