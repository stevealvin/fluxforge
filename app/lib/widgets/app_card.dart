import 'dart:ui' as ui;
import 'package:material_ui/material_ui.dart';
import '../core/theme/app_colors.dart';

/// 全局统一现代化卡片组件 (AppCard)
///
/// 遵循 FluxForge 设计规范：
/// - 自动感应「曜夜极光翡翠 / 纯净星暮白」双主题色彩与 0.5px 微光倒角边框；
/// - 默认集成 Apple 级纯正磨砂透光毛玻璃 (BackdropFilter) 与冷调环境柔光微阴影；
/// - 统一 16px 现代圆角与柔和微距环境阴影 (Offset(0, 3), blur: 14)；
/// - 自带防溢出水波纹点击反馈（Material + InkWell）与可选 Apple 质感弹性微缩；
/// - 提供标准、平铺 (flat)、描边弱底 (outlined)、流光渐变 (gradient)、纯毛玻璃 (glass) 等多种场景预设。
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

  /// 自定义背景色（缺省自动根据深浅主题获取微透质感底色以呈现磨砂透光）
  final Color? color;

  /// 自定义边框颜色（缺省自动根据主题获取 AppColors.darkCardBorder / lightCardBorder）
  final Color? borderColor;

  /// 边框粗细（缺省为 0.8）
  final double borderWidth;

  /// 是否显示微边框
  final bool showBorder;

  /// 是否显示环境柔光微阴影（缺省为 true）
  final bool showShadow;

  /// 是否启用磨砂毛玻璃背景穿透滤镜（缺省为 true，默认呈现半透磨砂高级质感）
  final bool enableBlur;

  /// 磨砂高斯模糊半径（缺省为 12.0）
  final double blur;

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

  /// 1. 标准卡片构造（实体冷白瓷/曜石黑材质与柔光微阴影，支持弹性微缩）
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 20.0,
    this.color,
    this.borderColor,
    this.borderWidth = 0.8,
    this.showBorder = false,
    this.showShadow = true,
    this.enableBlur = false,
    this.blur = 12.0,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.enablePressScale = true,
    this.clipBehavior = Clip.antiAlias,
  });

  /// 2. 纯净平铺态卡片构造（无边框、无阴影、无模糊，纯净色块）
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
        enableBlur = false,
        blur = 0.0,
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
    this.enableBlur = false,
    this.blur = 0.0,
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
    this.enableBlur = false,
    this.blur = 0.0,
    this.onTap,
    this.onLongPress,
    this.enablePressScale = false,
    this.clipBehavior = Clip.antiAlias,
  }) : color = null;

  /// 5. 纯正磨砂毛玻璃卡片构造（特化强磨砂透光场景）
  const AppCard.glass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.width,
    this.height,
    this.borderRadius = 20.0,
    this.color,
    this.borderColor,
    this.borderWidth = 0.8,
    this.showBorder = false,
    this.showShadow = true,
    this.blur = 14.0,
    this.gradient,
    this.onTap,
    this.onLongPress,
    this.enablePressScale = true,
    this.clipBehavior = Clip.antiAlias,
  }) : enableBlur = true;

  @override
  State<AppCard> createState() => _AppCardState();
}

class _AppCardState extends State<AppCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedRadius = BorderRadius.circular(widget.borderRadius);

    // 计算背景色：启用毛玻璃时默认使用微透高级底色以透出背景模糊，否则使用常规实体底色
    final resolvedBgColor = widget.color ??
        (isDark
            ? (widget.enableBlur
                ? const Color(0xFF161E2E).withValues(alpha: 0.82)
                : const Color(0xFF161E2E))
            : (widget.enableBlur
                ? Colors.white.withValues(alpha: 0.85)
                : Colors.white));

    // 计算边框：显式边框优先；未显式指定边框时，深色模式下保留 0.5px 极微光边缘以呈现精磨玻璃反光
    BoxBorder? resolvedBorder;
    if (widget.showBorder) {
      final borderColor = widget.borderColor ??
          (isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder);
      resolvedBorder = Border.all(color: borderColor, width: widget.borderWidth);
    } else if (isDark) {
      resolvedBorder = Border.all(color: Colors.white.withValues(alpha: 0.04), width: 0.5);
    }

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

    // 材质表面层（承载背景微透色/渐变、边框与内容）
    Widget surface = Container(
      width: widget.width,
      height: widget.height,
      clipBehavior: widget.clipBehavior,
      decoration: BoxDecoration(
        color: widget.gradient == null ? resolvedBgColor : null,
        gradient: widget.gradient,
        borderRadius: resolvedRadius,
        border: resolvedBorder,
      ),
      child: innerContent,
    );

    // 磨砂透光层（BackdropFilter 由 ClipRRect 精准约束在圆角范围内）
    if (widget.enableBlur) {
      surface = ClipRRect(
        borderRadius: resolvedRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: widget.blur, sigmaY: widget.blur),
          child: surface,
        ),
      );
    }

    // 环境柔光微阴影与外层容器（阴影置于 ClipRRect 外部，向外平滑自然发散）
    Widget card = Container(
      margin: widget.margin,
      decoration: widget.showShadow
          ? BoxDecoration(
              borderRadius: resolvedRadius,
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.20)
                      : const Color(0xFF0F172A).withValues(alpha: 0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 3),
                ),
              ],
            )
          : null,
      child: surface,
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

    return card;
  }
}
