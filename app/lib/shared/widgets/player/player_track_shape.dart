import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 自定义纯净流光进度条轨道形状
///
/// 1. 彻底消除 Flutter 原生 `Slider` 默认左右强制 24px 的内缩留白边距；
/// 2. 严密统一未加载(背景轨)、已加载(缓冲轨)、已播放(翡翠轨)的高度与圆角，彻底消除粗细断层感；
/// 3. 支持网络缓冲/加载中的动态羽化流光光斑扫光动画。
class AuraSliderTrackShape extends RoundedRectSliderTrackShape {
  const AuraSliderTrackShape({
    this.bufferedFraction = 0.0,
    this.isBuffering = false,
    this.shimmerProgress = 0.0,
  });

  /// 已加载缓冲比例 (0.0 ~ 1.0)
  final double bufferedFraction;

  /// 是否处于缓冲加载中
  final bool isBuffering;

  /// 流光扫光动画进度 (0.0 ~ 1.0)
  final double shimmerProgress;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 3.5;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double trackHeight = trackRect.height;
    final Radius trackRadius = Radius.circular(trackHeight / 2);
    final RRect fullRRect = RRect.fromRectAndRadius(trackRect, trackRadius);

    final Canvas canvas = context.canvas;

    // 1. 底层：未加载背景轨道（高度严格等于 trackHeight，圆角严格统一）
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.white24
      ..style = PaintingStyle.fill;
    canvas.drawRRect(fullRRect, inactivePaint);

    // 2. 中层：已加载缓冲轨道（Buffered Track，与未加载保持完全一致粗细）
    if (bufferedFraction > 0.0) {
      final double bufferedWidth = (trackRect.width * bufferedFraction.clamp(0.0, 1.0));
      final Rect bufferedRect = Rect.fromLTWH(
        trackRect.left,
        trackRect.top,
        bufferedWidth,
        trackHeight,
      );
      final Paint bufferedPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.clipRRect(fullRRect);
      canvas.drawRect(bufferedRect, bufferedPaint);
      canvas.restore();
    }

    // 3. 顶层：已播放极光翡翠轨道 (Active Track，高度与未加载完全一样粗)
    final double activeWidth = (thumbCenter.dx - trackRect.left).clamp(0.0, trackRect.width);
    final Rect activeRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      activeWidth,
      trackHeight,
    );
    final Paint activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? AppColors.primary
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipRRect(fullRRect);
    canvas.drawRect(activeRect, activePaint);
    canvas.restore();

    // 4. 加载/缓冲状态动效
    if (isBuffering) {
      final double bufferedWidth = (trackRect.width * bufferedFraction.clamp(0.0, 1.0));
      final double loadedRight = math.max(activeRect.right, trackRect.left + bufferedWidth);
      final double unloadedLeft = loadedRight;
      final double unloadedWidth = trackRect.right - unloadedLeft;

      // 圆弧旋转相位：每动画周期转 3 圈（与条纹滚动相位解耦，
      // 保证条纹放宽后加载指示仍保持活跃的旋转节奏）
      final double angle = shimmerProgress * 2 * math.pi * 3;

      // A. 未加载区域：灰白斜条纹滚动（Barber Pole 转筒）
      //    深浅两档灰白斜条纹沿轨道方向循环平移，表达「后续内容正在滚动加载」。
      //    注：轨道仅 2.5~3.5px 高，45° 斜切在此高度只产生同等像素的斜边位移，
      //    斜度弱于普通转筒，动感主要由相位滚动承担。
      if (unloadedWidth > 4.0) {
        final Rect unloadedRect = Rect.fromLTWH(unloadedLeft, trackRect.top, unloadedWidth, trackHeight);

        canvas.save();
        canvas.clipRRect(fullRRect); // 约束在圆角轨道内
        canvas.clipRect(unloadedRect); // 严格约束仅在未加载空白区域内

        const double period = 32.0; // 一个完整「亮灰 + 暗灰」周期的宽度（单条 16px）
        final double phase = (shimmerProgress * period) % period;

        // 相位平移 + 45° 斜切；斜切使条纹 x 偏移 ±trackHeight，故绘制范围左右外扩
        canvas.translate(unloadedLeft - period + phase, 0);
        canvas.skew(-1.0, 0);

        final Paint stripeLight =
            Paint()..color = Colors.white.withValues(alpha: 0.50);
        final Paint stripeDim =
            Paint()..color = Colors.white.withValues(alpha: 0.18);

        final double drawStart = -trackHeight - period;
        final double drawEnd = unloadedWidth + trackHeight + period;
        var even = true;
        for (double x = drawStart; x < drawEnd; x += period / 2) {
          canvas.drawRect(
            Rect.fromLTWH(x, trackRect.top, period / 2, trackHeight),
            even ? stripeLight : stripeDim,
          );
          even = !even;
        }

        canvas.restore();
      }

      // B. 缓冲前沿灰白旋转弧：以缓冲端点为圆心的灰白扫掠圆弧持续旋转，
      //    是「正在加载后续内容」最直观的表达；半径略大于轨道高度，
      //    因此不参与上方裁剪，画在轨道外圈
      final double arcRadius = math.max(trackHeight * 1.5, 5.0);
      final double arcCenterX = loadedRight.clamp(
        trackRect.left + arcRadius,
        trackRect.right - arcRadius,
      );
      final Rect arcRect = Rect.fromCircle(
        center: Offset(arcCenterX, trackRect.center.dy),
        radius: arcRadius,
      );
      final Paint arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: [
            Colors.white.withValues(alpha: 0.85),
            Colors.white.withValues(alpha: 0.25),
            Colors.white.withValues(alpha: 0.85),
          ],
          transform: GradientRotation(-angle),
        ).createShader(arcRect);
      canvas.drawArc(arcRect, -math.pi / 2, math.pi * 1.35, false, arcPaint);
    }
  }
}
