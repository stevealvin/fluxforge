import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/media/media_kind.dart';

/// 发现页的频道切换栏（媒体类型分组）
///
/// 这一层取代了此前「列出所有规则源逐个切换」的导航：**类型是主轴，源退到后台**。
/// 用户不必理解「什么是规则源」也能浏览，而每个频道内部是**跨源聚合**的结果。
///
/// 胶囊上带各频道的条目数 —— 数字来自实际聚合结果，能让用户预期点进去能看到多少。
class DiscoverChannelBar extends StatelessWidget {
  const DiscoverChannelBar({
    super.key,
    required this.isDark,
    required this.selected,
    required this.onSelected,
    required this.counts,
  });

  final bool isDark;
  final MediaKind selected;
  final ValueChanged<MediaKind> onSelected;

  /// 各频道当前的条目数
  final Map<MediaKind, int> counts;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final kind in MediaKind.values)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _buildChip(kind),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(MediaKind kind) {
    final isSelected = kind == selected;
    final count = counts[kind] ?? 0;
    // 没有任何条目的频道置灰：点了也只会得到一个空频道
    final isEnabled = kind == MediaKind.all || count > 0;

    final Color fg;
    if (isSelected) {
      fg = Colors.white;
    } else if (isEnabled) {
      fg = isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary;
    } else {
      fg = isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary;
    }

    return GestureDetector(
      onTap: isEnabled && !isSelected ? () => onSelected(kind) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          // 选中态从「主色实底 + 白字」改为「主色淡底 + 主色文字」：
          // 实底胶囊在这一排里太重，淡底更像筛选而不是操作按钮
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.16)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.045)),
          borderRadius: BorderRadius.circular(16),
          // 描边始终存在（未选中用透明占位），切换时尺寸不跳
          border: Border.all(
            color: isSelected
                ? AppColors.primary.withValues(alpha: 0.55)
                : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              kind.label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppColors.primary : fg,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppColors.primary.withValues(alpha: 0.7)
                      : fg.withValues(alpha: 0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
