import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 统一设置/菜单行组件 (SettingTile)
///
/// 抽取自「我的」页与系统设置页中长期重复手写的高度相似 ListTile 样板：
/// 统一「圆角图标徽章 + 标题 + 副标题 + 尾部操作区」的现代卡片行样式，
/// 支持箭头、徽标、开关、下拉等任意尾部插槽。
class SettingTile extends StatelessWidget {
  const SettingTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.onTap,
    this.trailing,
    this.showArrow = false,
    this.iconColor,
    this.iconBackgroundColor,
    this.padding,
  });

  /// 左侧图标（Ionicons / Material 图标均可）
  final IconData icon;

  /// 主标题
  final String title;

  /// 副标题说明
  final String? subtitle;

  /// 点击回调（为空则不可点击）
  final VoidCallback? onTap;

  /// 尾部插槽（开关、下拉、徽标等），优先于 [showArrow] 展示
  final Widget? trailing;

  /// 是否在尾部展示右向箭头
  final bool showArrow;

  /// 图标主色（缺省使用品牌极光幽绿）
  final Color? iconColor;

  /// 图标徽章底色（缺省使用品牌色 12% 透明底）
  final Color? iconBackgroundColor;

  /// 内边距自定义
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveIconColor = iconColor ?? AppColors.primary;

    return ListTile(
      contentPadding: padding,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconBackgroundColor ?? effectiveIconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: effectiveIconColor, size: 18),
      ),
      title: Text(
        title,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
      trailing: trailing ??
          (showArrow
              ? const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey)
              : null),
      onTap: onTap,
    );
  }
}

/// 统一设置分组标题 (SettingSectionTitle)
class SettingSectionTitle extends StatelessWidget {
  const SettingSectionTitle({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.4,
          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
        ),
      ),
    );
  }
}

/// 统一设置分组卡片容器 (SettingSection)
///
/// 内部自动为相邻子项插入 56px 缩进的分隔线，避免各页面重复手写 Divider。
class SettingSection extends StatelessWidget {
  const SettingSection({
    super.key,
    required this.children,
    this.margin,
  });

  final List<Widget> children;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dividerColor = isDark ? AppColors.darkBorder : AppColors.lightBorder;

    final rows = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i != children.length - 1) {
        rows.add(Divider(height: 1, indent: 56, color: dividerColor));
      }
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : AppColors.lightCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.04) : AppColors.lightBorder,
          width: 0.8,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.20)
                : const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: rows),
    );
  }
}
