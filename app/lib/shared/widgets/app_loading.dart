import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:fluxforge/app/theme/app_colors.dart';

/// 全局统一加载指示器组件（极光彗星环 · A0 基准版）
///
/// 零外部依赖，基于原生 Canvas CustomPainter + 单 Ticker 逐帧绘制。
/// 视觉只剩三件东西：一段渐隐彗尾、一颗彗核亮点，以及随尺寸自适应的线宽 ——
/// 相比此前「外环流光 + 反向差速内环 + 双层底轨 + 呼吸核心 + 中心光晕」的五层叠加大幅减负，
/// 换来的是 14~20px 小尺寸下依然锐利可辨（此时自动降级为实色纯弧，不做渐变也不画彗核）。
/// 配色随「曜夜极光翡翠 / 纯净星暮白」双主题自动切换。
class AppLoading extends StatefulWidget {
  const AppLoading({
    super.key,
    this.message,
    this.size = 42.0,
    this.strokeWidth = 2.8,
    this.color,
  }) : isCompact = false;

  /// 紧凑轻量态：专为按钮内、封面占位、列表触底等极小场景设计（无文案）
  const AppLoading.compact({
    super.key,
    this.size = 18.0,
    this.strokeWidth = 2.0,
    this.color,
  })  : message = null,
        isCompact = true;

  /// 加载提示文案
  final String? message;

  /// 指示器尺寸
  final double size;

  /// 线宽上限：实际线宽按尺寸自适应（见 `_AppLoadingState.build` 内的 strokeWidth 计算），
  /// 传入值只在「自适应结果比它更粗」时起收敛作用 —— 小尺寸不会被拉成糊团，
  /// 大尺寸也不会出现一根过分纤细的蓝丝。
  final double strokeWidth;

  /// 主流光色彩（缺省自动感应深/浅色主题极光绿）
  final Color? color;

  /// 是否为极简紧凑态（只影响是否渲染文案，图形与主态完全一致）
  final bool isCompact;

  @override
  State<AppLoading> createState() => _AppLoadingState();
}

class _AppLoadingState extends State<AppLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 单圈 1.4s；配合绘制器内的正弦调制构成「不匀速」的彗星滑行节奏
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 无障碍：系统开启「减少动画」时不再持续跑帧，停在固定相位上展示静态弧。
    // （组件不可见时 Ticker 已被 TickerMode 自动静音，这里只处理用户显式开关。）
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0.25;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 主题配色：主色深色取极光荧光绿、浅色取品牌幽绿；
    // 副色（彗尾中段色）在调用方自定义主色时由主色推导，否则走主题辅助色
    final primaryColor =
        widget.color ?? (isDark ? AppColors.primaryGlow : AppColors.primary);
    final secondaryColor = widget.color != null
        ? widget.color!.withValues(alpha: 0.7)
        : (isDark ? AppColors.accentBlue : AppColors.accentTeal);

    // 线宽自适应：小尺寸给更大的相对线宽（否则 14px 下几乎看不见），
    // 再用 clamp 收敛到 [1.2, strokeWidth]，保证调用方传入的细线意图不被突破。
    final double adaptiveWidth = widget.size * (widget.size < 20 ? 0.115 : 0.075);
    final double maxWidth = math.max(1.2, widget.strokeWidth).toDouble();
    final double strokeWidth = adaptiveWidth.clamp(1.2, maxWidth).toDouble();

    final indicator = SizedBox(
      width: widget.size,
      height: widget.size,
      // RepaintBoundary：把逐帧重绘隔离在这一层。
      // 否则 60fps 的重绘会一路冒泡到最近的重绘边界（通常就是整页）
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _CometLoadingPainter(
              progress: _controller.value,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              strokeWidth: strokeWidth,
            ),
          ),
        ),
      ),
    );

    // 紧凑态：直接返回图形，零任何额外布局包裹
    if (widget.isCompact) {
      return Center(child: indicator);
    }

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          indicator,
          if (widget.message != null && widget.message!.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              widget.message!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                letterSpacing: -0.2,
                color: isDark
                    ? AppColors.darkTextSecondary
                    : AppColors.lightTextSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 极光彗星环绘制器（A0 基准版）
///
/// 绘制顺序只有两步：
/// 1. 一段 112°（小尺寸 130°）的渐隐彗尾：尾部完全透明 → 头部实色，圆头收笔；
/// 2. 头部一颗彗核亮点，让流动方向一眼可辨。
/// 旋转相位 = 匀速角 + 一层正弦浮动，转速在 1x 上下呼吸，长时间盯着看也不机械。
class _CometLoadingPainter extends CustomPainter {
  _CometLoadingPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.strokeWidth,
  });

  /// 0.0 ~ 1.0 的单圈进度（由 Ticker 驱动）
  final double progress;
  final Color primaryColor;
  final Color secondaryColor;

  /// 已按尺寸自适应后的实际线宽
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final shortSide = math.min(size.width, size.height);
    // 半径留出线宽与 0.5px 抗锯齿余量，保证圆头描边不被画布裁切
    final radius = (shortSide - strokeWidth) / 2 - 0.5;
    if (radius <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);

    // 旋转相位：整体匀速 + 正弦调制 → 头部自 12 点方向起步并带轻微加减速
    final cycle = progress * 2 * math.pi;
    final phase = cycle + math.sin(cycle) * 0.34;

    final sweepAngle = (shortSide < 20 ? 130 : 112) * math.pi / 180;
    final headAngle = phase - math.pi / 2;
    final tailAngle = headAngle - sweepAngle;

    // 小尺寸降级：实色纯弧，零渐变，边缘最锐利
    if (shortSide < 20) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        tailAngle,
        sweepAngle,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..color = primaryColor,
      );
      return;
    }

    // 大尺寸：沿弧扫掠渐变（尾部透明 → 头部实色），圆头收笔
    final arcRect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(
      arcRect,
      tailAngle,
      sweepAngle,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: tailAngle,
          endAngle: headAngle,
          colors: [
            primaryColor.withValues(alpha: 0.0),
            secondaryColor.withValues(alpha: 0.42),
            secondaryColor,
            primaryColor,
          ],
          stops: const [0.0, 0.3, 0.72, 1.0],
        ).createShader(arcRect),
    );

    // 彗核：头部一颗实色亮点
    canvas.drawCircle(
      Offset(
        center.dx + math.cos(headAngle) * radius,
        center.dy + math.sin(headAngle) * radius,
      ),
      strokeWidth * 0.62,
      Paint()
        ..style = PaintingStyle.fill
        ..color = primaryColor,
    );
  }

  @override
  bool shouldRepaint(covariant _CometLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
