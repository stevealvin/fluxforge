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

    // 4. 加载/缓冲状态动效：严格仅在【未加载区域 (Unloaded Area)】流动呈现
    if (isBuffering) {
      final double bufferedWidth = (trackRect.width * bufferedFraction.clamp(0.0, 1.0));
      final double loadedRight = math.max(activeRect.right, trackRect.left + bufferedWidth);
      final double unloadedLeft = loadedRight;
      final double unloadedWidth = trackRect.right - unloadedLeft;

      // 仅当存在未加载的空白轨道时执行未加载专属动画
      if (unloadedWidth > 4.0) {
        final Rect unloadedRect = Rect.fromLTWH(unloadedLeft, trackRect.top, unloadedWidth, trackHeight);

        canvas.save();
        canvas.clipRRect(fullRRect); // 约束在圆角轨道内
        canvas.clipRect(unloadedRect); // 严格约束仅在未加载空白区域内

        // A. 未加载区域柔和呼吸底色 (Breathing Pulse)
        final double pulseOpacity = 0.12 + 0.10 * (0.5 + 0.5 * math.sin(shimmerProgress * 2 * math.pi));
        final Paint pulsePaint = Paint()
          ..color = Colors.white.withValues(alpha: pulseOpacity)
          ..style = PaintingStyle.fill;
        canvas.drawRect(unloadedRect, pulsePaint);

        // B. 未加载区域专属流光光斑 (Shimmer Sweep，从缓冲端点向右掠过)
        final double shimmerWidth = math.max(unloadedWidth * 0.45, 36.0);
        final double shimmerLeft = unloadedLeft - shimmerWidth + (unloadedWidth + shimmerWidth * 2) * shimmerProgress;
        final Rect shimmerRect = Rect.fromLTWH(shimmerLeft, trackRect.top, shimmerWidth, trackHeight);

        final Paint shimmerPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.60),
              Colors.transparent,
            ],
          ).createShader(shimmerRect);

        canvas.drawRect(shimmerRect, shimmerPaint);

        // C. 已缓冲端点向右微光波纹 (Buffer Head Glow)
        final double headGlowWidth = 14.0;
        final Rect headGlowRect = Rect.fromLTWH(unloadedLeft, trackRect.top, headGlowWidth, trackHeight);
        final Paint headGlowPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.70),
              Colors.transparent,
            ],
          ).createShader(headGlowRect);
        canvas.drawRect(headGlowRect, headGlowPaint);

        canvas.restore();
      }
    }
  }
}
