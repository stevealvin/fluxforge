import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/media/media.dart';

/// 视频详情页「选集」模块：多线路切换 + 单行横向快速选集
///
/// 纯展示 + 事件上抛：本组件不持有任何播放状态，选中线路 / 集数 / 排序全部由宿主传入，
/// 交互以语义化回调（`onEpisodeTap(index)` 等）上抛，宿主不必把内部字段摊平传进来。
///
/// 离线下载入口不在此处：详情页顶部栏右上角统一提供（点击底部弹出下载面板）。
class VideoEpisodesSection extends StatelessWidget {
  const VideoEpisodesSection({
    super.key,
    required this.isDark,
    required this.episodes,
    required this.groups,
    required this.selectedGroupIndex,
    required this.currentEpisodeIndex,
    required this.isReversed,
    required this.onGroupSelected,
    required this.onEpisodeTap,
    required this.onToggleReverse,
    required this.onShowAll,
  });

  final bool isDark;

  /// 当前线路的选集
  final List<MediaEpisode> episodes;

  /// 全部线路（多于 1 条时展示切换栏）
  final List<MediaGroup> groups;

  final int selectedGroupIndex;
  final int currentEpisodeIndex;

  /// 是否倒序展示
  final bool isReversed;

  final ValueChanged<int> onGroupSelected;
  final ValueChanged<int> onEpisodeTap;
  final VoidCallback onToggleReverse;

  /// 点击「全部」（宿主呼出选集面板）
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final int count = episodes.length;
    final displayIndices = List.generate(
      count,
      (i) => isReversed ? (count - 1 - i) : i,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 多播放线路切换栏 (若沙箱返回多个 group)
        if (groups.length > 1) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: groups.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final g = groups[index];
                  final isSelected = index == selectedGroupIndex;

                  return ChoiceChip(
                    label: Text(g.name),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: isDark
                        ? AppColors.darkCard
                        : AppColors.lightSurface,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark
                                ? AppColors.darkBorder
                                : AppColors.lightBorder),
                      width: 0.8,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: isSelected
                          ? Colors.white
                          : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                    ),
                    onSelected: (val) {
                      if (val && selectedGroupIndex != index) {
                        HapticFeedback.selectionClick();
                        onGroupSelected(index);
                      }
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 2. 选集控制头部栏 (标题 + 集数统计 + 下载 / 正倒序 / 全部)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                    '选集',
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '共 $count 集',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? AppColors.darkTextMuted
                          : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  // 正序 / 倒序切换按钮
                  IconButton(
                    tooltip: isReversed ? '切换为正序' : '切换为倒序',
                    icon: Icon(
                      Ionicons.swapVerticalOutline,
                      size: 14,
                      color: isReversed
                          ? AppColors.primary
                          : (isDark
                                ? AppColors.darkTextSecondary
                                : AppColors.lightTextSecondary),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onToggleReverse();
                    },
                  ),

                  // 全部选集网格弹窗抽屉按钮 (超过 5 集时展示)
                  if (count > 5)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(
                        Ionicons.gridOutline,
                        size: 13,
                        color: AppColors.primary,
                      ),
                      label: const Text(
                        '全部',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: onShowAll,
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. 商业级单行横向快速选集滑动条 (紧凑高度 38px，即点即播，选中态翠绿高光微阴影)
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final realIndex = displayIndices[i];
              final item = episodes[realIndex];
              final isCurrent = realIndex == currentEpisodeIndex;

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onEpisodeTap(realIndex),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minWidth: 46),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.primary
                        : (isDark
                              ? AppColors.darkCard
                              : AppColors.lightSurface),
                    borderRadius: BorderRadius.circular(8),
                    // 未选中不画默认边框线：底色已足以区分边界，选中才亮主色描边
                    border: isCurrent
                        ? Border.all(color: AppColors.primary, width: 0.8)
                        : null,
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCurrent) ...[
                        const Icon(
                          Ionicons.playOutline,
                          size: 9,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isCurrent
                              ? FontWeight.bold
                              : FontWeight.w500,
                          color: isCurrent
                              ? Colors.white
                              : (isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary),
                        ),
                      ),
                    ],
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
