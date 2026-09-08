import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import '../core/theme/app_colors.dart';

/// 全局统一极光流光加载指示器组件 (Aurora Flow Loading Indicator)
/// 零外部依赖，基于原生 Canvas CustomPainter 与 Ticker 极速流光绘制，
/// 完美适配「曜夜极光翡翠 / 纯净星暮白」现代科技双主题。
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({
    super.key,
    this.message,
    this.size = 42.0,
    this.strokeWidth = 2.8,
    this.color,
    this.secondaryColor,
    this.showGlow = true,
    this.showInnerRing = true,
    this.padding,
  })  : isCompact = false,
        isCard = false,
        isPulseOnly = false;

  /// 紧凑轻量态：专为按钮内、封面占位、列表触底等极小场景设计
  const LoadingIndicator.compact({
    super.key,
    this.size = 18.0,
    this.strokeWidth = 2.0,
    this.color,
    this.secondaryColor,
  })  : message = null,
        showGlow = false,
        showInnerRing = false,
        padding = EdgeInsets.zero,
        isCompact = true,
        isCard = false,
        isPulseOnly = false;

  /// 卡片悬浮态：带有微光渐变圆角卡片背景的加载态
  const LoadingIndicator.card({
    super.key,
    this.message,
    this.size = 38.0,
    this.strokeWidth = 2.8,
    this.color,
    this.secondaryColor,
    this.showGlow = true,
    this.showInnerRing = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
  })  : isCompact = false,
        isCard = true,
        isPulseOnly = false;

  /// 呼吸脉冲徽标态：极光核心能量律动，适用于轻量级同步与占位提示
  const LoadingIndicator.pulse({
    super.key,
    this.message,
    this.size = 32.0,
    this.color,
  })  : strokeWidth = 2.5,
        secondaryColor = null,
        showGlow = true,
        showInnerRing = false,
        padding = null,
        isCompact = false,
        isCard = false,
        isPulseOnly = true;

  /// 加载提示文案
  final String? message;

  /// 环形指示器线条宽度
  final double strokeWidth;

  /// 指示器尺寸
  final double size;

  /// 主流光色彩（缺省自动感应深/浅色主题极光绿）
  final Color? color;

  /// 辅助副流光色彩（缺省自动感应科技蓝或青绿）
  final Color? secondaryColor;

  /// 是否显示中心极光微芒呼吸核心
  final bool showGlow;

  /// 是否显示反向差速内环
  final bool showInnerRing;

  /// 外层边距
  final EdgeInsetsGeometry? padding;

  /// 是否为极简紧凑态
  final bool isCompact;

  /// 是否呈现浮层卡片背景
  final bool isCard;

  /// 是否仅使用脉冲光晕形态
  final bool isPulseOnly;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final primaryColor = widget.color ??
        (isDark ? AppColors.primaryGlow : AppColors.primary);
    final secondaryColor = widget.secondaryColor ??
        (widget.color != null
            ? widget.color!.withValues(alpha: 0.7)
            : (isDark ? AppColors.accentBlue : AppColors.accentTeal));

    Widget indicatorCore = SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          if (widget.isPulseOnly) {
            return CustomPaint(
              painter: _PulseLoadingPainter(
                progress: _controller.value,
                color: primaryColor,
                isDark: isDark,
              ),
            );
          }

          return CustomPaint(
            painter: _AuroraLoadingPainter(
              progress: _controller.value,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              strokeWidth: widget.strokeWidth,
              showInnerRing: widget.showInnerRing && widget.size >= 24,
              showGlow: widget.showGlow,
              isDark: isDark,
            ),
          );
        },
      ),
    );

    // 紧凑态：直接返回图形，零任何额外布局包裹
    if (widget.isCompact) {
      return Center(child: indicatorCore);
    }

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        indicatorCore,
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
    );

    if (widget.isCard) {
      content = Container(
        padding: widget.padding ??
            const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.darkCard.withValues(alpha: 0.88)
              : AppColors.lightCard.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? AppColors.darkCardBorder : AppColors.lightCardBorder,
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.4)
              : AppColors.primary.withValues(alpha: 0.08),
              blurRadius: 28,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: content,
      );
    } else if (widget.padding != null) {
      content = Padding(
        padding: widget.padding!,
        child: content,
      );
    }

    return Center(child: content);
  }
}

/// 极光双环差速流光绘制器
class _AuroraLoadingPainter extends CustomPainter {
  final double progress; // 0.0 ~ 1.0
  final Color primaryColor;
  final Color secondaryColor;
  final double strokeWidth;
  final bool showInnerRing;
  final bool showGlow;
  final bool isDark;

  _AuroraLoadingPainter({
    required this.progress,
    required this.primaryColor,
    required this.secondaryColor,
    required this.strokeWidth,
    required this.showInnerRing,
    required this.showGlow,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = (math.min(size.width, size.height) - strokeWidth) / 2;
    if (outerRadius <= 0) return;

    // 1. 外环超轻底轨 (Subtle Base Track)
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 0.7
      ..color = primaryColor.withValues(alpha: isDark ? 0.12 : 0.07);
    canvas.drawCircle(center, outerRadius, trackPaint);

    // 2. 外环极光流光 (Outer Aurora Comet Sweep)
    const outerSweepAngle = math.pi * 1.55; // 约 280 度弧长
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(progress * 2 * math.pi);

    final outerRect = Rect.fromCircle(center: Offset.zero, radius: outerRadius);
    final outerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0.0,
        endAngle: outerSweepAngle,
        colors: [
          primaryColor.withValues(alpha: 0.0),
          secondaryColor.withValues(alpha: 0.35),
          secondaryColor,
          primaryColor,
        ],
        stops: const [0.0, 0.3, 0.7, 1.0],
      ).createShader(outerRect);

    canvas.drawArc(outerRect, 0.0, outerSweepAngle, false, outerPaint);
    canvas.restore();

    // 3. 内环反向差速极光 (Inner Reverse Ring)
    if (showInnerRing && outerRadius > 10) {
      final innerRadius = outerRadius * 0.62;
      final innerStroke = strokeWidth * 0.75;

      // 内环底轨
      final innerTrackPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = innerStroke * 0.7
        ..color = secondaryColor.withValues(alpha: isDark ? 0.09 : 0.05);
      canvas.drawCircle(center, innerRadius, innerTrackPaint);

      // 内环流光
      const innerSweepAngle = math.pi * 1.25; // 约 225 度弧长
      canvas.save();
      canvas.translate(center.dx, center.dy);
      // 逆时针 1.6 倍差速反向旋转
      canvas.rotate(-progress * 3.2 * math.pi);

      final innerRect =
          Rect.fromCircle(center: Offset.zero, radius: innerRadius);
      final innerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = innerStroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          startAngle: 0.0,
          endAngle: innerSweepAngle,
          colors: [
            secondaryColor.withValues(alpha: 0.0),
            primaryColor.withValues(alpha: 0.4),
            primaryColor,
            secondaryColor,
          ],
          stops: const [0.0, 0.25, 0.7, 1.0],
        ).createShader(innerRect);

      canvas.drawArc(innerRect, 0.0, innerSweepAngle, false, innerPaint);
      canvas.restore();
    }

    // 4. 极光呼吸微芒核心 (Pulse Core)
    if (showGlow && outerRadius > 12) {
      final pulse = (math.sin(progress * 2 * math.pi) + 1.0) / 2.0; // 0.0 ~ 1.0
      final coreRadius = outerRadius * 0.22 * (0.8 + 0.3 * pulse);

      // 外散柔和光晕
      if (isDark) {
        final glowRadius = outerRadius * 0.5 * (0.8 + 0.3 * pulse);
        final glowPaint = Paint()
          ..shader = RadialGradient(
            colors: [
              primaryColor.withValues(alpha: 0.32 * (0.7 + 0.3 * pulse)),
              primaryColor.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: center, radius: glowRadius));
        canvas.drawCircle(center, glowRadius, glowPaint);
      }

      // 实心微芒核心点
      final corePaint = Paint()
        ..color = (isDark ? primaryColor : secondaryColor)
            .withValues(alpha: 0.85 + 0.15 * pulse)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(center, coreRadius, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AuroraLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.showInnerRing != showInnerRing ||
        oldDelegate.showGlow != showGlow ||
        oldDelegate.isDark != isDark;
  }
}

/// 呼吸脉冲能量徽标绘制器
class _PulseLoadingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isDark;

  _PulseLoadingPainter({
    required this.progress,
    required this.color,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) / 2;
    if (maxRadius <= 0) return;

    // 外层扩散波纹
    final rippleProgress = (progress + 0.5) % 1.0;
    final rippleRadius = maxRadius * (0.45 + 0.55 * rippleProgress);
    final rippleAlpha = (1.0 - rippleProgress) * (isDark ? 0.32 : 0.18);
    final ripplePaint = Paint()
      ..color = color.withValues(alpha: rippleAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, rippleRadius, ripplePaint);

    // 中间脉冲波纹
    final waveRadius = maxRadius * (0.35 + 0.65 * progress);
    final waveAlpha = (1.0 - progress) * (isDark ? 0.45 : 0.28);
    final wavePaint = Paint()
      ..color = color.withValues(alpha: waveAlpha)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, waveRadius, wavePaint);

    // 核心微光圆
    final pulseScale = 0.88 + 0.12 * math.sin(progress * 2 * math.pi);
    final coreRadius = maxRadius * 0.38 * pulseScale;
    final coreGlowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          color.withValues(alpha: isDark ? 0.75 : 0.5),
          color.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: coreRadius * 2.0));
    canvas.drawCircle(center, coreRadius * 1.8, coreGlowPaint);

    final coreSolidPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, coreRadius, coreSolidPaint);
  }

  @override
  bool shouldRepaint(covariant _PulseLoadingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isDark != isDark;
  }
}
