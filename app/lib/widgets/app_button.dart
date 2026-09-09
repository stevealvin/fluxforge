import 'package:material_ui/material_ui.dart';
import '../core/theme/app_colors.dart';
import 'loading_indicator.dart';

/// 按钮样式变体
enum AppButtonVariant {
  primary,
  tonal,
  outlined,
  ghost,
}

/// 按钮尺寸规范
enum AppButtonSize {
  /// 常规标准高度 (~42px，适合独立大操作、表单提交)
  regular,

  /// 紧凑高度 (~30px，专为卡片内部操作、AppBar 顶栏动作区定制)
  compact,

  /// 极小徽章高度 (~24px，适合行内超微型操作)
  mini,
}

/// 全局统一现代化按钮组件 (AppButton)
///
/// 解决 Flutter Material 3 默认按钮最小尺寸 (40~48px) 在卡片与 AppBar 中导致布局臃肿的问题，
/// 提供紧凑度控制、极光翡翠设计语言规范与开箱即用的加载中 (Loading) 动画。
class AppButton extends StatelessWidget {
  final String? label;
  final Widget? icon;
  final VoidCallback? onPressed;
  final bool loading;
  final AppButtonVariant variant;
  final AppButtonSize size;
  final Color? color;
  final Color? textColor;
  final double? borderRadius;
  final EdgeInsetsGeometry? padding;
  final bool isFullWidth;

  const AppButton({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.variant = AppButtonVariant.primary,
    this.size = AppButtonSize.regular,
    this.color,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.isFullWidth = false,
  });

  /// 紧凑型主色按钮（高 30px，专为卡片列表操作打造）
  const AppButton.compact({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.color,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.isFullWidth = false,
  })  : variant = AppButtonVariant.primary,
        size = AppButtonSize.compact;

  /// 紧凑型次要按钮（高 30px，浅色翡翠绿底色，专为 AppBar 顶栏、分类筛选打造）
  const AppButton.compactTonal({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.color,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.isFullWidth = false,
  })  : variant = AppButtonVariant.tonal,
        size = AppButtonSize.compact;

  /// 常规次级浅色背景按钮 (Tonal)
  const AppButton.tonal({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.size = AppButtonSize.regular,
    this.color,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.isFullWidth = false,
  })  : variant = AppButtonVariant.tonal;

  /// 镂空边框按钮 (Outlined)
  const AppButton.outlined({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.size = AppButtonSize.regular,
    this.color,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.isFullWidth = false,
  })  : variant = AppButtonVariant.outlined;

  /// 幽灵文本按钮 (Ghost / Text)
  const AppButton.ghost({
    super.key,
    this.label,
    this.icon,
    this.onPressed,
    this.loading = false,
    this.size = AppButtonSize.regular,
    this.color,
    this.textColor,
    this.borderRadius,
    this.padding,
    this.isFullWidth = false,
  })  : variant = AppButtonVariant.ghost;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 1. 尺寸参数与内边距解析
    final double targetHeight;
    final double fontSize;
    final double iconSize;
    final double radius;
    final EdgeInsets resolvedPadding;

    switch (size) {
      case AppButtonSize.mini:
        targetHeight = 24.0;
        fontSize = 11.0;
        iconSize = 12.0;
        radius = borderRadius ?? 6.0;
        resolvedPadding = padding as EdgeInsets? ??
            const EdgeInsets.symmetric(horizontal: 8, vertical: 2);
        break;
      case AppButtonSize.compact:
        targetHeight = 30.0;
        fontSize = 12.0;
        iconSize = 13.0;
        radius = borderRadius ?? 8.0;
        resolvedPadding = padding as EdgeInsets? ??
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4);
        break;
      case AppButtonSize.regular:
        targetHeight = 42.0;
        fontSize = 14.0;
        iconSize = 16.0;
        radius = borderRadius ?? 12.0;
        resolvedPadding = padding as EdgeInsets? ??
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10);
        break;
    }

    // 2. 颜色与边框解析
    final Color effectivePrimary = color ?? AppColors.primary;
    final Color effectiveBg;
    final Color effectiveFg;
    final BorderSide? borderSide;

    switch (variant) {
      case AppButtonVariant.primary:
        effectiveBg = effectivePrimary;
        effectiveFg = textColor ?? Colors.white;
        borderSide = null;
        break;
      case AppButtonVariant.tonal:
        effectiveBg = color ??
            (isDark
                ? AppColors.primaryLight.withValues(alpha: 0.15)
                : AppColors.primaryLight.withValues(alpha: 0.12));
        effectiveFg = textColor ?? (isDark ? AppColors.primaryLight : AppColors.primary);
        borderSide = null;
        break;
      case AppButtonVariant.outlined:
        effectiveBg = Colors.transparent;
        effectiveFg = textColor ?? (isDark ? AppColors.primaryLight : AppColors.primary);
        borderSide = BorderSide(
          color: (color ?? effectiveFg).withValues(alpha: 0.35),
          width: 1.0,
        );
        break;
      case AppButtonVariant.ghost:
        effectiveBg = Colors.transparent;
        effectiveFg = textColor ?? (isDark ? AppColors.primaryLight : AppColors.primary);
        borderSide = null;
        break;
    }

    // 3. 图标与 Loading 转圈处理
    Widget? effectiveIcon;
    if (loading) {
      effectiveIcon = LoadingIndicator.compact(
        size: iconSize,
        strokeWidth: 1.8,
        color: effectiveFg,
      );
    } else if (icon != null) {
      effectiveIcon = IconTheme.merge(
        data: IconThemeData(size: iconSize, color: effectiveFg),
        child: icon!,
      );
    }

    final buttonStyle = ButtonStyle(
      minimumSize: WidgetStatePropertyAll(Size(0, targetHeight)),
      fixedSize: WidgetStatePropertyAll(Size.fromHeight(targetHeight)),
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      padding: WidgetStatePropertyAll(resolvedPadding),
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return effectiveBg.withValues(alpha: 0.38);
        }
        return effectiveBg;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return effectiveFg.withValues(alpha: 0.45);
        }
        return effectiveFg;
      }),
      side: borderSide != null ? WidgetStatePropertyAll(borderSide) : null,
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      ),
      elevation: const WidgetStatePropertyAll(0),
    );

    final effectiveOnPressed = loading ? null : onPressed;

    Widget button;
    if (effectiveIcon != null && label != null) {
      button = FilledButton.icon(
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        icon: effectiveIcon,
        label: Text(
          label!,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      );
    } else if (effectiveIcon != null) {
      button = FilledButton(
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: effectiveIcon,
      );
    } else {
      button = FilledButton(
        style: buttonStyle,
        onPressed: effectiveOnPressed,
        child: Text(
          label ?? '',
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600),
        ),
      );
    }

    if (isFullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}
