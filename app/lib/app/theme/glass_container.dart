import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';

/// 高性能 Apple 极简现代材质容器 (GlassContainer)
/// 支持无描边纯净面材质与细腻环境阴影，最大化内容可用空间与滑动穿透质感
class GlassContainer extends StatefulWidget {
  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final bool enableBlur;
  final bool showBorder;
  final Color? customBgColor;
  final Color? customBorderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final BoxBorder? customBorder;
  final Gradient? gradient;

  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 18,
    this.blur = 12,
    this.enableBlur = false,
    this.showBorder = false,
    this.customBgColor,
    this.customBorderColor,
    this.onTap,
    this.onLongPress,
    this.customBorder,
    this.gradient,
  });

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgColor = widget.customBgColor ??
        (isDark
            ? const Color(0xFF161E2E)
            : Colors.white);

    Border? border;
    if (widget.customBorder != null) {
      border = widget.customBorder as Border?;
    } else if (widget.showBorder) {
      final borderColor = widget.customBorderColor ??
          (isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFE2E8F0));
      border = Border.all(color: borderColor, width: 0.8);
    } else if (isDark) {
      // 深色模式下仅保留极细微光边缘
      border = Border.all(color: Colors.white.withValues(alpha: 0.04), width: 0.5);
    }

    final decoration = BoxDecoration(
      color: widget.gradient == null ? bgColor : null,
      gradient: widget.gradient,
      borderRadius: BorderRadius.circular(widget.borderRadius),
      border: border,
      boxShadow: [
        BoxShadow(
          color: isDark
              ? Colors.black.withValues(alpha: 0.2)
              : const Color(0xFF0F172A).withValues(alpha: 0.04),
          blurRadius: 14,
          offset: const Offset(0, 3),
        ),
      ],
    );

    Widget content = Container(
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: widget.child,
      ),
    );

    if (widget.enableBlur) {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
          child: content,
        ),
      );
    }

    if (widget.onTap == null && widget.onLongPress == null) {
      return Container(
        margin: widget.margin,
        child: content,
      );
    }

    return Container(
      margin: widget.margin,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _isPressed ? 0.98 : 1.0,
          duration: const Duration(milliseconds: 90),
          curve: Curves.easeOutQuad,
          child: content,
        ),
      ),
    );
  }
}
