import 'package:material_ui/material_ui.dart';
import '../core/theme/app_colors.dart';

/// 全局统一现代化卡片组件 (AppCard)
///
/// 遵循 FluxForge 设计规范：
/// - 自动感应「曜夜极光翡翠 / 纯净星暮白」双主题色彩与微光边框；
/// - 统一 16px 现代圆角与柔和环境微阴影；
/// - 自带防溢出水波纹点击反馈（Material + InkWell）与可选 Apple 质感弹性微缩；
/// - 提供标准、平铺 (flat)、描边弱底 (outlined)、流光渐变 (gradient) 等多种场景预设。
class AppCard extends StatefulWidget {
  /// 卡片内容
  final Widget child;

  /// 内边距（缺省为 EdgeInsets.all(16)）
  final EdgeInsetsGeometry? padding;

  /// 外边距
  final EdgeInsetsGeometry? margin;

  /// 宽度
  final double? width;

  /// 高度
  final double? height;

  /// 圆角半径（缺省为 16.0）
  final double borderRadius;

  /// 自定义背景色（缺省自动根据深浅主题获取 AppColors.darkCard / lightCard）
  final Color? color;

  /// 自定义边框颜色（缺省自动根据主题获取 AppColors.darkCardBorder / lightCardBorder）
  final Color? borderColor;

  /// 边框粗细（缺省为 0.8）
  final double borderWidth;

  /// 是否显示微边框
  final bool showBorder;

  /// 是否显示微阴影
  final bool showShadow;

  /// 自定义渐变背景
  final Gradient? gradient;

  /// 点击回调（提供时自动启用严格圆角防溢出水波纹反馈）
  final VoidCallback? onTap;

  /// 长按回调
  final VoidCallback? onLongPress;

  /// 是否启用触觉按压弹性微缩反馈 (0.98 scale)
  final bool enablePressScale;

  /// 内容裁切行为
  final Clip clipBehavior;

  /// 1. 标准卡片构造
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 16.0,
    this.color,
    this.borderColor,
    this.borderWidth = 0.8,
    this.showBorder = false,
    this.showShadow = true,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.enablePressScale = false,
    this.clipBehavior = Clip.antiAlias,
  });

  /// 2. 纯净平铺态卡片构造（无边框、无阴影，纯净色块）
  const AppCard.flat({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 16.0,
    this.color,
    this.onTap,
    this.onLongPress,
    this.enablePressScale = false,
    this.clipBehavior = Clip.antiAlias,
  })  : showBorder = false,
        showShadow = false,
        borderColor = null,
        borderWidth = 0.0,
        gradient = null;

  /// 3. 描边弱底色卡片构造（用于次级分组、过滤筛选、信息标签容器）
  const AppCard.outlined({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 14.0,
    this.color = Colors.transparent,
    this.borderColor,
    this.borderWidth = 0.8,
    this.onTap,
    this.onLongPress,
    this.enablePressScale = false,
    this.clipBehavior = Clip.antiAlias,
  })  : showBorder = true,
        showShadow = false,
        gradient = null;

  /// 4. 流光渐变卡片构造（用于 Hero 概览、VIP 标识、高光看板等）
  const AppCard.gradient({
    super.key,
    required this.child,
    required this.gradient,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 18.0,
    this.borderColor,
    this.borderWidth = 0.8,
    this.showBorder = true,
    this.showShadow = true,
    this.onTap,
    this.onLongPress,
    this.enablePressScale = false,
    this.clipBehavior = Clip.antiAlias,
  }) : color = null;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedRadius = BorderRadius.circular(widget.borderRadius);

    // 计算背景色
    final resolvedBgColor = widget.color ??
        (isDark ? AppColors.darkCard : AppColors.lightCard);

    // 计算边框颜色
    final resolvedBorderColor = widget.borderColor ??
        (isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder);

    // 内部点击水波与 Padding 处理
    final hasInteraction = widget.onTap != null || widget.onLongPress != null;
    Widget innerContent;

    if (hasInteraction) {
      innerContent = Material(
        color: Colors.transparent,
        borderRadius: resolvedRadius,
        child: InkWell(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          borderRadius: resolvedRadius,
          onHighlightChanged: widget.enablePressScale
              ? (highlighted) {
                  if (_isPressed != highlighted) {
                    setState(() => _isPressed = highlighted);
                  }
                }
              : null,
          child: Padding(
            padding: widget.padding ?? EdgeInsets.zero,
            child: widget.child,
          ),
        ),
      );
    } else {
      innerContent = Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: widget.child,
      );
    }

    // 边框计算：若显式开启边框则用指定或主题边框；若未开启边框，深色模式下自动赋予 0.5px 微光倒角以形成通透立体层次
    BoxBorder? resolvedBorder;
    if (widget.showBorder) {
      resolvedBorder = Border.all(color: resolvedBorderColor, width: widget.borderWidth);
    } else if (isDark && widget.showShadow) {
      resolvedBorder = Border.all(color: Colors.white.withValues(alpha: 0.05), width: 0.5);
    }

    // 外层容器与微边框、阴影
    Widget card = Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: widget.clipBehavior,
      decoration: BoxDecoration(
        color: widget.gradient == null ? resolvedBgColor : null,
        gradient: widget.gradient,
        borderRadius: resolvedRadius,
        border: resolvedBorder,
        boxShadow: widget.showShadow
            ? [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.22)
                      : const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: innerContent,
    );

    // 按压弹性微缩效果
    if (widget.enablePressScale && hasInteraction) {
      card = AnimatedScale(
        scale: _isPressed ? 0.98 : 1.0,
        duration: const Duration(milliseconds: 90),
        curve: Curves.easeOutQuad,
        child: card,
      );
    }

    // 外边距包裹
    if (widget.margin != null) {
      card = Padding(
        padding: widget.margin!,
        child: card,
      );
    }

    return card;
  }
}
