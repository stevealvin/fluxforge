import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';

/// 全量剧集底部选集面板（4 列紧凑网格 + 正倒序切换）
///
/// 用 [EpisodePickerSheet.show] 呼出。
///
/// **正倒序为何由面板自己持有**：弹窗是独立路由，宿主的 `setState` 不会重建它
/// （原实现因此不得不用 `StatefulBuilder` + 手动 `setSheetState`）。这里让它持有
/// 面板内的视图状态，同时通过 [onToggleReverse] 通知宿主同步 —— 两边不会各切一半。
class EpisodePickerSheet extends StatefulWidget {
  const EpisodePickerSheet({
    super.key,
    required this.isDark,
    required this.episodes,
    required this.currentEpisodeIndex,
    required this.initiallyReversed,
    required this.onEpisodeTap,
    required this.onToggleReverse,
  });

  final bool isDark;

  final List<MediaEpisode> episodes;

  final int currentEpisodeIndex;

  /// 打开时的排序（由宿主传入，之后由面板自己切换）
  final bool initiallyReversed;

  /// 选中某一集（调用方负责切集与播放）
  final ValueChanged<int> onEpisodeTap;

  /// 面板内切换正倒序时通知宿主，保持两侧排序一致
  final VoidCallback onToggleReverse;

  /// 呼出选集面板
  static Future<void> show({
    required BuildContext context,
    required bool isDark,
    required List<MediaEpisode> episodes,
    required int currentEpisodeIndex,
    required bool isReversed,
    required ValueChanged<int> onEpisodeTap,
    required VoidCallback onToggleReverse,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => EpisodePickerSheet(
        isDark: isDark,
        episodes: episodes,
        currentEpisodeIndex: currentEpisodeIndex,
        initiallyReversed: isReversed,
        onEpisodeTap: onEpisodeTap,
        onToggleReverse: onToggleReverse,
      ),
    );
  }

  @override
  State<EpisodePickerSheet> createState() => _EpisodePickerSheetState();
}

class _EpisodePickerSheetState extends State<EpisodePickerSheet> {
  late bool _isReversed = widget.initiallyReversed;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final episodes = widget.episodes;
    final count = episodes.length;
    final indices = List.generate(
      count,
      (i) => _isReversed ? (count - 1 - i) : i,
    );

    return Container(
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(
          top: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.8,
          ),
        ),
      ),
      child: Column(
        children: [
          // 顶部药丸把手
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 标题栏
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      '全部剧集',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
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
                // 抽屉内正倒序切换
                IconButton(
                  tooltip: _isReversed ? '切换为正序' : '切换为倒序',
                  icon: Icon(
                    Ionicons.swapVerticalOutline,
                    size: 15,
                    color: _isReversed
                        ? AppColors.primary
                        : (isDark
                              ? AppColors.darkTextSecondary
                              : AppColors.lightTextSecondary),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isReversed = !_isReversed;
                    });
                    // 通知宿主同步排序，避免关掉面板后列表又切回去
                    widget.onToggleReverse();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 选集 4 列紧凑网格
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 2.1,
              ),
              itemCount: count,
              itemBuilder: (context, idx) {
                final realIndex = indices[idx];
                final ep = episodes[realIndex];
                final isCurrent = realIndex == widget.currentEpisodeIndex;

                // 选中态靠描边强调；未选中不画默认边框线（透明边框仅占位，切换时不跳尺寸）
                return AppCard.outlined(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  borderRadius: 8,
                  borderColor: isCurrent
                      ? AppColors.primary
                      : Colors.transparent,
                  color: isCurrent
                      ? AppColors.primary.withValues(
                          alpha: isDark ? 0.25 : 0.15,
                        )
                      : (isDark
                            ? const Color(0xFF0F1420)
                            : AppColors.lightSurface),
                  onTap: () {
                    Navigator.pop(context);
                    widget.onEpisodeTap(realIndex);
                  },
                  child: Center(
                    child: Text(
                      ep.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent
                            ? AppColors.primary
                            : (isDark
                                  ? AppColors.darkTextPrimary
                                  : AppColors.lightTextPrimary),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
