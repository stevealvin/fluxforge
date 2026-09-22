import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 视频详情页元数据区：主标题 · 评分 · 规则源 · 题材标签 · 作者 · 可展开简介
///
/// 简介的展开 / 收起是**纯展示的局部状态**，因此由组件自身持有 ——
/// 宿主（详情页）不必为一个 UI 开关保存字段，也不必为此实现 setState。
/// 组件只接收「展示什么」与「分享点了做什么」。
class VideoMetaSection extends StatefulWidget {
  const VideoMetaSection({
    super.key,
    required this.isDark,
    required this.title,
    this.rating,
    this.ruleName,
    this.tags = const [],
    this.author,
    this.desc,
    this.onShareTap,
  });

  final bool isDark;

  /// 已解析好的展示标题（兜底逻辑留在宿主）
  final String title;

  final String? rating;

  /// 规则源名称（为空则不展示规则标签）
  final String? ruleName;

  final List<String> tags;

  final String? author;

  final String? desc;

  final VoidCallback? onShareTap;

  @override
  State<VideoMetaSection> createState() => _VideoMetaSectionState();
}

class _VideoMetaSectionState extends State<VideoMetaSection> {
  bool _isDescExpanded = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final desc = widget.desc?.trim();
    final rating = widget.rating;
    final author = widget.author;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行与分享操作
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onShareTap != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Ionicons.shareSocialOutline,
                  size: 17,
                  color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
                ),
                onPressed: widget.onShareTap,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // 状态、评分、规则源、题材标签与作者流
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 评分徽标 (琥珀黄金色胶囊)
            if (rating != null && rating.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B)
                      .withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.star_rounded,
                      size: 13,
                      color: Color(0xFFF59E0B),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      rating,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),

            // 规则源标识
            if (widget.ruleName != null)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(
                    alpha: isDark ? 0.2 : 0.12,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.ruleName!,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),

            // 分类题材标签 (微光实体药丸)
            ...widget.tags.map(
              (tag) => Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 7,
                  vertical: 2.5,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : AppColors.lightBorder,
                    width: 0.8,
                  ),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),

            // 演职员 / 作者
            if (author != null && author.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Ionicons.personOutline,
                    size: 11,
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    author,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),

        // 剧情简介：平铺直接呈现，无多余边框大卡片，带流畅展开折叠动效
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              setState(() {
                _isDescExpanded = !_isDescExpanded;
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _isDescExpanded
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: Text(
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                  secondChild: Text(
                    desc,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark
                          ? AppColors.darkTextSecondary
                          : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isDescExpanded ? '收起简介' : '展开简介',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 3),
                    Icon(
                      _isDescExpanded
                          ? Ionicons.chevronUpOutline
                          : Ionicons.chevronDownOutline,
                      size: 11,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
