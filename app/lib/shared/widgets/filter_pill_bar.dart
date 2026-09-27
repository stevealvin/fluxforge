import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 筛选条的一项
class FilterPillItem {
  const FilterPillItem({
    required this.key,
    required this.label,
    required this.count,
  });

  /// 选中态比对用的键（语义由调用方定义，如 `all` / `video`）
  final String key;

  final String label;

  /// 该类目下的条目数；为 0 时数量自动降淡
  final int count;
}

/// 横向筛选条（胶囊 + 数量），收藏页与历史中心共用
///
/// 抽出来是因为它已经在两处各写了一遍：收藏页是手写的自绘胶囊、历史中心是
/// Material `ChoiceChip` —— 选中态、底色、有无数量三处都不一样，再各写一遍必然继续漂。
///
/// 样式约定：
/// - **选中**：主色 20% 底 + 主色 1px 描边 + 主色加粗文字；
/// - **未选中**：极淡的「比背景深一档」底、**透明描边占位**（切换时不跳尺寸）；
/// - 末尾带该类目数量，为 0 时降淡 —— 用户不必点进去才发现那一类是空的；
/// - 文案色一律走 `AppColors` 的 muted 语义色，不用裸 `Colors.grey` / `black87`。
class FilterPillBar extends StatelessWidget {
  const FilterPillBar({
    super.key,
    required this.items,
    required this.selectedKey,
    required this.onSelected,
    this.padding = EdgeInsets.zero,
    this.spacing = 6,
  });

  final List<FilterPillItem> items;

  /// 当前选中的 [FilterPillItem.key]
  final String selectedKey;

  final ValueChanged<String> onSelected;

  /// 外层内边距（顶栏内一般传 `EdgeInsets.zero`，AppBar 自身已给行高）
  final EdgeInsetsGeometry padding;

  final double spacing;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final children = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      children.add(
        _FilterPill(
          item: item,
          isSelected: item.key == selectedKey,
          isDark: isDark,
          onTap: () {
            HapticFeedback.selectionClick();
            onSelected(item.key);
          },
        ),
      );
      if (i != items.length - 1) children.add(SizedBox(width: spacing));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(children: children),
    );
  }
}

class _FilterPill extends StatelessWidget {
  const _FilterPill({
    required this.item,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
  });

  final FilterPillItem item;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final idleColor = isDark
        ? AppColors.darkTextSecondary
        : AppColors.lightTextSecondary;
    final labelColor = isSelected ? AppColors.primary : idleColor;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.2)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              item.label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: labelColor,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '${item.count}',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: labelColor.withValues(
                  alpha: item.count == 0 ? 0.4 : 0.75,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
