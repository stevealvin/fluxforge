import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';

/// 视频详情页「剧照与预览」横滑区（16:10 宽屏卡片）
///
/// 纯展示：只接收图片地址与请求头（防盗链由宿主按规则解析后传入）。
class VideoPreviewsSection extends StatelessWidget {
  const VideoPreviewsSection({
    super.key,
    required this.isDark,
    required this.previews,
    this.headers = const {},
  });

  final bool isDark;

  /// 剧照 / 预览图地址列表（为空时宿主不渲染本区块）
  final List<String> previews;

  /// 图片请求头（防盗链 Referer 等）
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3.5,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '剧照与预览',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${previews.length})',
              style: TextStyle(
                fontSize: 12,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: previews.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final imgUrl = previews[index];
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: AppImage(
                    imageUrl: imgUrl,
                    headers: headers.isNotEmpty ? headers : null,
                    errorWidget: Icon(
                      Ionicons.imageOutline,
                      color: isDark
                          ? AppColors.darkTextTertiary
                          : AppColors.lightTextTertiary,
                      size: 20,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
