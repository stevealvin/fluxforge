import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 设置分组的「标题 + 卡片容器 + 行」三件套
///
/// 原 `SettingTile`（图标徽章 + 标题 + 副标题 + 尾部插槽）已删除，由 [SettingRow] 取代 ——
/// 设置页与「我的」页现在**共用同一处行实现**。此前是设置页各卡手写 `ListTile`、
/// 「我的」页另有一份私有行组件，同一套视觉语言两处维护，必然漂移。
///
/// 三者刻意解耦：标题在卡片**外**（[SettingSectionTitle]，分组语义），
/// 容器只管边框与分隔线（[SettingSection]），行自带样式（[SettingRow]）。

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
/// 内部自动为相邻子项插入分隔线，避免各页面重复手写 `Divider`。
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
        // 缩进到行内文字起点：14（行左内边距）+ 38（图标徽章）+ 12（间距）
        rows.add(Divider(height: 1, indent: 64, color: dividerColor));
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

/// 统一设置行 (SettingRow)：图标徽章 + 标题 + 说明 + 右侧尾部
///
/// 行规范（「我的」页与设置页共同遵守）：
/// - 图标 38×38 / 圆角 11 / **14% 语义色底**；标题 14 w600；说明 11.5 muted；
/// - **整行可点**（移动端热区更大，不必精准点中尾部小控件）；
/// - **数值右置**（[value]）：可扫读，不必从说明句子里找数字；
/// - [trailing] 留给开关 / 下拉 / 徽标等自绘尾部；
/// - 右箭头**只由 [onTap] 决定**：行可点就给箭头；开关与下拉自身即反馈，故不给
///   （它们用 [trailing] 表达，[onTap] 可同时传入以实现「整行可点」）；
/// - 破坏性动作把 [color] 传 [AppColors.danger]，与普通行在视觉上分开。
class SettingRow extends StatelessWidget {
  const SettingRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.value,
    this.trailing,
    this.busy = false,
  });

  final IconData icon;

  /// 语义色：同时决定徽章底色（14% 透明）与图标色
  final Color color;

  final String title;
  final String subtitle;

  /// 整行点击（开关 / 下拉行也建议传入，让整行可点）
  final VoidCallback? onTap;

  /// 右侧数值（如缓存占用、条目数）
  final String? value;

  /// 右侧自定义尾部（开关 / 下拉 / 徽标）
  final Widget? trailing;

  /// 进行中：右侧改显示进度环
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final hasValue = value != null && value!.isNotEmpty;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              if (hasValue)
                Text(
                  value!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              if (hasValue && trailing != null) const SizedBox(width: 8),
              ?trailing,
              if (onTap != null && trailing == null) ...[
                const SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios_rounded, size: 13, color: muted),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// 行尾箭头：给自绘尾部（如「徽标 + 箭头」）复用的统一图标
///
/// 单独导出是为了让 [SettingRow.trailing] 里的自绘组合与本组件的默认箭头**完全同源**，
/// 避免尺寸 / 颜色的再次分叉。
class SettingRowChevron extends StatelessWidget {
  const SettingRowChevron({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Icon(
      Icons.arrow_forward_ios_rounded,
      size: 13,
      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
    );
  }
}
