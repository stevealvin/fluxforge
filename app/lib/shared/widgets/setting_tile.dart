import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 设置分组的「标题 + 卡片容器」两件套
///
/// 原 `SettingTile`（图标徽章 + 标题 + 副标题 + 尾部插槽）已删除：全仓只有
/// 「我的」页两处调用，行样式改由该页私有的 `_ProfileActionRow` 承担
/// （占用体积改为右侧数值、整行可点）。只有一处使用的东西不该挂在 `shared/` 里。
///
/// 这两个分组件保留：它们与具体行样式解耦，任何页面都能往里塞自己的行。

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
  const SettingSection({super.key, required this.children, this.margin});

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
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : AppColors.lightBorder,
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
