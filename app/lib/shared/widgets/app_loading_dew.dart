import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:fluxforge/app/theme/app_colors.dart';

/// 全局统一加载指示器组件（晨露呼吸 · Morning Dew Breathing）
///
/// 零外部依赖，基于原生 Canvas CustomPainter + 单 Ticker 逐帧绘制。
/// 3 颗多色柔光露珠在中心层叠成有机的呼吸律动：
/// 1. **Orb 1 (外层 78px · 靛紫 #818cf8)**：带轻微有机形变与缓动位移，4.2s 正弦深呼吸；
/// 2. **Orb 2 (中层 64px · 淡紫 #c084fc)**：相位错开 1.4s (120°)，形成反相位差速流转；
/// 3. **Orb 3 (核心 48px · 天青 #38bdf8)**：微透镜内高光 + 外漫射柔光，如晨曦朝露般晶莹透润。
///
/// 彻底摆脱机械式的旋转转圈，以 4.2s 自然界流体张力呼吸，极度安抚等待焦虑。
/// 小尺寸（<22px）自动收敛对比度与轮廓，在 14px 按钮与 12px 筛选标签中如宝石微珠般锐利澄澈。
class DewLoading extends StatefulWidget {
  const DewLoading({
    super.key,
    this.message,
    this.size = 42.0,
    this.strokeWidth = 2.1,
    this.color,
  }) : isCompact = false;

  /// 紧凑轻量态：专为按钮内、封面占位、列表触底等极小场景设计（无文案）
  const DewLoading.compact({
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

  /// 兼容线宽参数（晨露水珠自适应尺寸缩放）
  final double strokeWidth;

  /// 主流光色彩（缺省自动感应晨露天青与靛紫调色板）
  final Color? color;

  /// 是否为极简紧凑态（只影响是否渲染文案，图形与主态完全一致）
  final bool isCompact;

  @override
  State<DewLoading> createState() => _DewLoadingState();
}

class _DewLoadingState extends State<DewLoading>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // 单周期 4.2s (4200ms)；与晨露呼吸的 cubic-bezier 缓动节拍保持一致
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 无障碍：系统开启「减少动画」时不再持续跑帧，停在饱满呼吸相位（0.5）展示静态露珠
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0.5;
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

    // 配色方案：缺省采用晨露三色调色板（#818cf8 靛紫、#c084fc 淡紫、#38bdf8 天青晶露）
    // 调用方自定义主色时，由主色推导谐振色相，确保任意自定义颜色均和谐优雅
    final Color orb1Color;
    final Color orb2Color;
    final Color coreColor;
    final Color glowColor;

    if (widget.color != null) {
      final hsl = HSLColor.fromColor(widget.color!);
      orb1Color = hsl.withHue((hsl.hue + 45.0) % 360.0).toColor();
      orb2Color = hsl.withHue((hsl.hue + 85.0) % 360.0).toColor();
      coreColor = widget.color!;
      glowColor = widget.color!;
    } else {
      orb1Color = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
      orb2Color = isDark ? const Color(0xFFC084FC) : const Color(0xFFA855F7);
      coreColor = isDark ? const Color(0xFF38BDF8) : const Color(0xFF0284C7);
      glowColor = isDark ? const Color(0xFF818CF8) : const Color(0xFF6366F1);
    }

    final indicator = SizedBox(
      width: widget.size,
      height: widget.size,
      // RepaintBoundary：把逐帧重绘隔离在这一层
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => CustomPaint(
            painter: _MorningDewPainter(
              progress: _controller.value,
              orb1Color: orb1Color,
              orb2Color: orb2Color,
              coreColor: coreColor,
              glowColor: glowColor,
              isDark: isDark,
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

/// 晨露呼吸绘制器（Morning Dew Breathing Painter）
///
/// 严格 1:1 还原 CSS 3 颗晨露珠的层叠空间物理（参考舞台 110px）：
/// - Orb 1 (78px): 偏左上，82% ~ 118% 缩放，(-6px, -4px) ~ (6px, 4px) 位移，
///   圆角由正圆「50%」渐变到「46% 54% 52% 48%」的有机形变；
/// - Orb 2 (64px): 偏右上，相位提前 1.4s，114% ~ 85% 缩放，(5px, -5px) ~ (-5px, 5px) 位移；
/// - Orb 3 (48px Core): 中心晨露晶核，90% ~ 108% 缩放，opacity 0.75 ~ 1.0，
///   外漫射微光晕 + 顶端微透镜高光反光。
///
/// **未做 `backdrop-filter: blur(6px)`**：与播放器胶囊那次同一口径 —— 模糊既费性能，
/// 又只是让本就半透明的露珠更糊；质感由双径向渐变与内外光晕承担即可。
class _MorningDewPainter extends CustomPainter {
  _MorningDewPainter({
    required this.progress,
    required this.orb1Color,
    required this.orb2Color,
    required this.coreColor,
    required this.glowColor,
    required this.isDark,
  });

  /// 0.0 ~ 1.0 的单周期进度（对应 4.2s 单循环）
  final double progress;
  final Color orb1Color;
  final Color orb2Color;
  final Color coreColor;
  final Color glowColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final shortSide = math.min(size.width, size.height);
    if (shortSide <= 0) return;

    final cx = size.width / 2;
    final cy = size.height / 2;
    final isSmall = shortSide < 22;

    // k 基于 110px 参考视口缩放
    final k = shortSide / 110.0;

    // 缓动曲线：cubic-bezier(0.37, 0, 0.63, 1) 对应 easeInOutSine
    final u1 = progress % 1.0;
    final f1 = (1.0 - math.cos(u1 * 2 * math.pi)) / 2.0;

    // Orb 2 相位提前 1.4s (1.4 / 4.2 = 1/3)
    final u2 = (u1 + 1.0 / 3.0) % 1.0;
    final f2 = (1.0 - math.cos(u2 * 2 * math.pi)) / 2.0;

    final fCore = f1;

    // ----------------------------------------------------
    // Orb 1: 78px, 缩放 0.82 ~ 1.18, 位移 (-6, -4) ~ (6, 4)
    // ----------------------------------------------------
    {
      final baseR = 39.0 * k;
      final scale = 0.82 + 0.36 * f1;
      final r = baseR * scale;
      final dx = (-6.0 + 12.0 * f1) * k;
      final dy = (-4.0 + 8.0 * f1) * k;
      final center = Offset(cx + dx, cy + dy);

      final gradient = RadialGradient(
        center: const Alignment(-0.4, -0.4),
        radius: 1.0,
        colors: [
          orb1Color.withValues(alpha: isSmall ? 0.65 : 0.45),
          orb1Color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.75],
      );

      // 圆角形变：正圆（半径 = r）↔「46% 54% 52% 48%」的轻微有机形变
      // （CSS 的百分比以直径计，故 46% × 2r = 0.92r）
      final rect = Rect.fromCenter(
        center: center,
        width: r * 2,
        height: r * 2,
      );
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(r * (1.0 - 0.08 * f1)),
        topRight: Radius.circular(r * (1.0 + 0.08 * f1)),
        bottomRight: Radius.circular(r * (1.0 + 0.04 * f1)),
        bottomLeft: Radius.circular(r * (1.0 - 0.04 * f1)),
      );

      final paint = Paint()..shader = gradient.createShader(rect);
      canvas.drawRRect(rrect, paint);
    }

    // ----------------------------------------------------
    // Orb 2: 64px, 缩放 1.14 ~ 0.85, 位移 (5, -5) ~ (-5, 5)
    // ----------------------------------------------------
    {
      final baseR = 32.0 * k;
      final scale = 1.14 - 0.29 * f2;
      final r = baseR * scale;
      final dx = (5.0 - 10.0 * f2) * k;
      final dy = (-5.0 + 10.0 * f2) * k;
      final center = Offset(cx + dx, cy + dy);

      final gradient = RadialGradient(
        center: const Alignment(0.4, -0.4),
        radius: 1.0,
        colors: [
          orb2Color.withValues(alpha: isSmall ? 0.75 : 0.55),
          orb2Color.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.75],
      );

      final rect = Rect.fromCircle(center: center, radius: r);
      final paint = Paint()..shader = gradient.createShader(rect);
      canvas.drawCircle(center, r, paint);
    }

    // ----------------------------------------------------
    // Orb 3 (Core): 48px, 缩放 0.90 ~ 1.08, opacity 0.75 ~ 1.0
    // ----------------------------------------------------
    {
      final baseR = 24.0 * k;
      final scale = 0.90 + 0.18 * fCore;
      final r = baseR * scale;
      final opacity = 0.75 + 0.25 * fCore;
      final center = Offset(cx, cy);

      // 外漫射微光晕 (box-shadow: 0 0 25px rgba(129, 140, 248, 0.25))
      if (!isSmall) {
        final glowR = r + 15.0 * k;
        final glowGradient = RadialGradient(
          colors: [
            glowColor.withValues(alpha: (isDark ? 0.35 : 0.22) * opacity),
            glowColor.withValues(alpha: 0.0),
          ],
          stops: const [0.4, 1.0],
        );
        final glowRect = Rect.fromCircle(center: center, radius: glowR);
        canvas.drawCircle(
          center,
          glowR,
          Paint()..shader = glowGradient.createShader(glowRect),
        );
      }

      // 核心渐变露珠水滴 (radial-gradient(circle at 50% 70%, #38bdf8, rgba(255,255,255,0.2) 80%))
      final coreGradient = RadialGradient(
        center: const Alignment(0.0, 0.4),
        radius: 1.0,
        colors: [
          coreColor.withValues(alpha: isSmall ? 0.95 : opacity),
          coreColor.withValues(alpha: (isSmall ? 0.95 : opacity) * 0.75),
          Colors.white.withValues(alpha: (isSmall ? 0.8 : 0.4) * opacity),
          coreColor.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 0.85, 1.0],
      );

      final coreRect = Rect.fromCircle(center: center, radius: r);
      canvas.drawCircle(
        center,
        r,
        Paint()..shader = coreGradient.createShader(coreRect),
      );

      // 晨露顶端微透镜内高光 (inset 0 0 12px rgba(255, 255, 255, 0.45))
      final glintR = r * 0.36;
      final glintCenter = Offset(cx - r * 0.25, cy - r * 0.25);
      final glintPaint = Paint()
        ..color = Colors.white.withValues(alpha: isSmall ? 0.75 : 0.55);
      canvas.drawCircle(glintCenter, glintR, glintPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _MorningDewPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.orb1Color != orb1Color ||
        oldDelegate.orb2Color != orb2Color ||
        oldDelegate.coreColor != coreColor ||
        oldDelegate.glowColor != glowColor ||
        oldDelegate.isDark != isDark;
  }
}
