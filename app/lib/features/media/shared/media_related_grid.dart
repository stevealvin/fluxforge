import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/features/media/shared/media_request_headers.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';

/// 跨媒体通用相关推荐网格 (全面采用 AppCard.flat 平铺卡片，支持 16:9 影视宽屏与 1:1.34 漫画小说黄金竖版两种布局)
class MediaRelatedGrid extends StatelessWidget {
  const MediaRelatedGrid({
    super.key,
    required this.related,
    this.currentRule,
    this.headers,
    this.isWide = false,
    this.onItemTap,
  });

  /// 相关推荐数据列表
  final List<MediaRelatedItem> related;

  /// 当前上下文所使用的规则 (用于继承沙箱解析环境与防盗链 Referer)
  final Rule? currentRule;

  /// 详情解析得到的请求头（含 `detail` 返回的 Referer）
  ///
  /// 与同页封面 / 图集同源；缺省时才回退 [currentRule] 的 baseUrl。
  final Map<String, String>? headers;

  /// 是否采用 16:9 宽屏双列展示 (影视视频推荐)，默认为 false (3列竖版海报)
  final bool isWide;

  /// 点击回调 (若为 null，则由外部统一处理跳转)
  final void Function(MediaRelatedItem item)? onItemTap;

  @override
  Widget build(BuildContext context) {
    if (related.isEmpty) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部标题栏 (翠绿指示条 + 14.5px SemiBold 标题 + 12px 弱化数量提示)
          Padding(
            padding: const EdgeInsets.only(top: 14.0, bottom: 8.0),
            child: Row(
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
                  '相关推荐',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '(${related.length})',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),

          // 卡片自适应网格 (宽屏 2 列 16:9 / 竖屏 3 列 1:1.34，1.34 黄金比消除多余空白)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: isWide ? 2 : 3,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: isWide ? 1.34 : 0.58,
            ),
            itemCount: related.length,
            itemBuilder: (context, index) {
              final item = related[index];
              return _buildCard(context, item, isDark);
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  /// 构建单张推荐卡片 (基于 AppCard.flat 平铺实体底色与防溢出圆角，内嵌暗部渐变与高清晰文本)
  Widget _buildCard(BuildContext context, MediaRelatedItem item, bool isDark) {
    // 解码降采样：按「屏宽 / 列数 × devicePixelRatio」取目标像素宽 ——
    // 一屏 6 张海报若都按原图解码，是长列表掉帧的主要来源
    final coverCacheWidth =
        (MediaQuery.sizeOf(context).width /
                (isWide ? 2 : 3) *
                MediaQuery.devicePixelRatioOf(context))
            .round();

    return AppCard.flat(
      padding: EdgeInsets.zero,
      borderRadius: 10,
      onTap: () {
        if (onItemTap != null) {
          onItemTap!(item);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 宽屏 16:9 或竖屏 1:1.34 封面 (顶部受 AppCard.flat 自动防溢出圆角裁切)
          AspectRatio(
            aspectRatio: isWide ? (16 / 9) : (1 / 1.34),
            child: Stack(
              fit: StackFit.expand,
              children: [
                item.cover.isNotEmpty
                    ? AppImage(
                        imageUrl: item.cover,
                        // 与详情页同口径：优先用详情解析出的请求头（含 detail 返回的 Referer），
                        // 缺省才回退 baseUrl —— 同页只用一套请求头，避免同页两套 Referer
                        headers:
                            headers ??
                            MediaRequestHeaders.withDefaults(
                              const {},
                              referer: currentRule?.baseUrl ?? '',
                            ),
                        cacheWidth: coverCacheWidth,
                        errorWidget: Icon(
                          Ionicons.imageOutline,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                          size: 20,
                        ),
                      )
                    : Center(
                        child: Icon(
                          isWide ? Icons.movie_outlined : Icons.image_outlined,
                          color: isDark
                              ? AppColors.darkTextTertiary
                              : AppColors.lightTextTertiary,
                          size: 20,
                        ),
                      ),
                // 封面底部暗部微渐变 (保证角标与卡片底部分界清晰)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 24,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.65),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ),
                // 右下角角标 (若有)
                if (item.badge != null && item.badge!.isNotEmpty)
                  Positioned(
                    right: 6,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 2. 底部文字信息区 (平铺底色上规范内边距，文字纯净高对比)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 推荐标题 (自适应主题主文本色)
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),

                // 简介或副标题 (次级弱化文字)
                if (item.desc != null && item.desc!.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.desc!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
