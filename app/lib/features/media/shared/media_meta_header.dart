import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';
import 'package:extended_image/extended_image.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/domain/media/media.dart';

/// 跨媒体通用详情头部元数据组件 (海报/标题/标签/作者/简介折叠)
class MediaMetaHeader extends StatefulWidget {
  const MediaMetaHeader({
    super.key,
    required this.data,
    this.rule,
    this.fallbackTitle = '',
    this.fallbackCover = '',
    this.showCover = true,
    this.onShareTap,
  });

  /// 结构化媒体详情数据
  final MediaDetailData data;

  /// 所属执行规则
  final Rule? rule;

  /// 兜底标题 (沙箱异步解析前由上一级页面传入)
  final String fallbackTitle;

  /// 兜底封面海报
  final String fallbackCover;

  /// 是否展示左侧海报封面 (视频详情页已有顶部大播放器，可设为 false 隐藏)
  final bool showCover;

  /// 分享回调
  final VoidCallback? onShareTap;

  @override
  State<MediaMetaHeader> createState() => _MediaMetaHeaderState();
}

class _MediaMetaHeaderState extends State<MediaMetaHeader> {
  bool _isDescExpanded = false;

  String get _displayTitle {
    if (widget.data.title.isNotEmpty) return widget.data.title;
    return widget.fallbackTitle.isNotEmpty ? widget.fallbackTitle : '未知作品';
  }

  String get _displayCover {
    if (widget.data.cover.isNotEmpty) return widget.data.cover;
    return widget.fallbackCover;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final targetUrl = widget.data.url;
    final desc = widget.data.desc?.trim();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 头部海报与主元信息行
          if (widget.showCover)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCoverCard(isDark, targetUrl),
                const SizedBox(width: 14),
                Expanded(child: _buildMetaColumn(isDark)),
              ],
            )
          else
            _buildMetaColumn(isDark),

          // 简介内容卡片 (支持展开/折叠)
          if (desc != null && desc.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildDescCard(isDark, desc),
          ],
        ],
      ),
    );
  }

  /// 构建左侧海报卡片 (使用主题统一深色卡片底色与微光边框)
  Widget _buildCoverCard(bool isDark, String targetUrl) {
    return Hero(
      tag: 'media_cover_${targetUrl.isNotEmpty ? targetUrl : _displayTitle}',
      child: Container(
        width: 104,
        height: 144,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? AppColors.darkCard : AppColors.lightSurface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: _displayCover.isNotEmpty
            ? ExtendedImage.network(
                _displayCover,
                fit: BoxFit.cover,
                headers: widget.data.customHeaders,
                loadStateChanged: (state) {
                  if (state.extendedImageLoadState == LoadState.failed) {
                    return Center(
                      child: Icon(Ionicons.imageOutline,
                        color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        size: 28,
                      ),
                    );
                  }
                  return null;
                },
              )
            : Center(
                child: Icon(Ionicons.filmOutline,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  size: 32,
                ),
              ),
      ),
    );
  }

  /// 构建右侧 (或全宽) 元数据列
  Widget _buildMetaColumn(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 主标题 (高对比度深色模式主文本)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _displayTitle,
                style: TextStyle(
                  fontSize: widget.showCover ? 18 : 20,
                  fontWeight: FontWeight.bold,
                  height: 1.3,
                ),
                maxLines: widget.showCover ? 2 : 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onShareTap != null)
              IconButton(
                icon: Icon(Ionicons.shareSocialOutline,
                  size: 18,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
                onPressed: widget.onShareTap,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // 评分与规则来源标牌
        Row(
          children: [
            if (widget.data.rating != null && widget.data.rating!.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 13, color: Colors.amber),
                    const SizedBox(width: 3),
                    Text(
                      widget.data.rating!,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (widget.rule != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.rule!.name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),

        // 作者 / 主演信息
        if (widget.data.author != null && widget.data.author!.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            '作者/主演: ${widget.data.author}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // 更新时间
        if (widget.data.updateTime != null && widget.data.updateTime!.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            '更新: ${widget.data.updateTime}',
            style: TextStyle(
              fontSize: 12,
              color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],

        // 题材标签 Chips (使用实体卡片底色与微光边框)
        if (widget.data.tags.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.data.tags.take(widget.showCover ? 4 : 8).map((tag) {
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }

  /// 作品简介展开/折叠卡片 (采用 AppCard 实体底色与微光边框，彻底消除深色模式下透明发脏问题)
  Widget _buildDescCard(bool isDark, String desc) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 12,
      color: isDark ? AppColors.darkCard : AppColors.lightSurface,
      showBorder: true,
      borderColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
      onTap: () {
        setState(() {
          _isDescExpanded = !_isDescExpanded;
        });
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '作品简介',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(
                _isDescExpanded ? '收起' : '展开',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Icon(
                _isDescExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            desc,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
            ),
            maxLines: _isDescExpanded ? 100 : 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
