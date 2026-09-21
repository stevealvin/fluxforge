import 'dart:math';

import 'package:extended_image/extended_image.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 统一的网络图片组件 —— 全仓图片加载的**唯一出口**
///
/// 把「加载策略」集中在一处：协议校验、请求头、缓存开关、**解码降采样**、
/// 加载 / 失败占位。调用点只描述这次要什么，不再各自点 `ExtendedImage`。
///
/// 为什么是 `extended_image` 而非 `cached_network_image`：两者磁盘缓存同源
/// （都基于 `flutter_cache_manager`），而前者额外提供阅读器必需的手势缩放
/// （`ExtendedImageGesturePageView`）、编辑裁剪与加载状态机 —— 全仓统一到一套，
/// 也避免同一张图被两套缓存各存一份。
class AppImage extends StatelessWidget {
  const AppImage({
    super.key,
    required this.imageUrl,
    this.cache = true,
    this.headers,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.shape = BoxShape.rectangle,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.placeholder,
    this.errorWidget,
    this.onTap,
  });

  final String imageUrl;

  /// 是否启用磁盘缓存（缺省启用）
  final bool cache;

  /// 请求头（防盗链 Referer / Cookie 等由调用方传入）
  final Map<String, String>? headers;

  final BorderRadius? borderRadius;
  final BoxFit? fit;
  final BoxShape? shape;
  final double? width;
  final double? height;

  /// 解码降采样尺寸（逻辑像素 × devicePixelRatio 即可）
  ///
  /// **网格 / 列表里务必传**：不传则按原图尺寸解码 —— 一张 2000px 宽的图
  /// 解码后约 24MB，这是长列表滑动掉帧的主要来源。
  final int? cacheWidth;
  final int? cacheHeight;

  /// 加载中的自定义占位（缺省不渲染占位，保持透明）
  final Widget? placeholder;

  /// 加载失败的自定义占位（缺省为居中 `Ionicons.imageOutline`）
  final Widget? errorWidget;

  /// 点击回调（可选，命中区域即整张图）
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final trimmedUrl = imageUrl.trim();
    // 防御性校验：空串或非 http(s) 协议 → 优雅回退内置占位图，杜绝底层抛错
    if (trimmedUrl.isEmpty ||
        (!trimmedUrl.startsWith('http://') && !trimmedUrl.startsWith('https://'))) {
      return errorWidget ??
          ImagePlaceholder(
            borderRadius: borderRadius ?? BorderRadius.zero,
            shape: shape ?? BoxShape.rectangle,
          );
    }

    final image = ExtendedImage.network(
      trimmedUrl,
      cache: cache,
      headers: headers,
      fit: fit,
      shape: shape,
      borderRadius: borderRadius,
      width: width,
      height: height,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.loading:
            return placeholder;
          case LoadState.failed:
            return errorWidget ?? const _ImageLoadFallback();
          default:
            return null;
        }
      },
    );

    if (onTap == null) return image;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: image,
    );
  }
}

/// 加载失败的默认占位
///
/// 原先是一张 `assets/icon/fail.png` 位图；现统一为矢量图标，
/// 既减少一份资源，也与全仓图标体系（Ionicons）一致。
class _ImageLoadFallback extends StatelessWidget {
  const _ImageLoadFallback();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: Icon(
        Ionicons.imageOutline,
        size: 24,
        color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
      ),
    );
  }
}

class ImagePlaceholder extends StatelessWidget {
  final double size;
  final Color backgroundColor;
  final Color iconColor;
  final double iconSizeRatio;
  final BorderRadius borderRadius;
  final BoxShape shape;
  final Widget? child;

  const ImagePlaceholder({
    super.key,
    this.size = 120,
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.iconColor = const Color(0xFFE0E0E0),
    this.iconSizeRatio = 0.6,
    this.borderRadius = BorderRadius.zero,
    this.shape = BoxShape.rectangle,
    this.child,
  });

  const ImagePlaceholder.circle({
    super.key,
    this.size = 120,
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.iconColor = const Color(0xFFE0E0E0),
    this.iconSizeRatio = 0.6,
    this.borderRadius = BorderRadius.zero,
    this.child,
  })  : shape = BoxShape.circle;

  const ImagePlaceholder.rounded({
    super.key,
    this.size = 120,
    this.backgroundColor = const Color(0xFFF5F5F5),
    this.iconColor = const Color(0xFFE0E0E0),
    this.iconSizeRatio = 0.6,
    this.child,
    required this.borderRadius,
  })  : shape = BoxShape.rectangle;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * iconSizeRatio;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: shape,
        borderRadius: shape == BoxShape.rectangle ? borderRadius : null,
      ),
      child: child ?? CustomPaint(
        size: Size(size, size),
        painter: _ImagePlaceholderPainter(
          iconColor: iconColor,
          iconSize: iconSize,
        ),
      ),
    );
  }
}

class _ImagePlaceholderPainter extends CustomPainter {
  final Color iconColor;
  final double iconSize;

  _ImagePlaceholderPainter({
    required this.iconColor,
    required this.iconSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final iconPaint = Paint()
      ..color = iconColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // 绘制外部矩形框（代表图片边框）
    final outerRect = Rect.fromCenter(
      center: center,
      width: iconSize * 0.7,
      height: iconSize * 0.7,
    );
    
    canvas.drawRect(outerRect, iconPaint);

    // 绘制山脉轮廓（抽象的山形）
    final mountainPath = Path()
      ..moveTo(center.dx - iconSize * 0.2, center.dy + iconSize * 0.1)
      ..lineTo(center.dx, center.dy - iconSize * 0.2)
      ..lineTo(center.dx + iconSize * 0.2, center.dy + iconSize * 0.1);

    canvas.drawPath(mountainPath, iconPaint);

    // 绘制太阳/圆形元素
    final sunOffset = Offset(center.dx - iconSize * 0.15, center.dy - iconSize * 0.1);
    canvas.drawCircle(sunOffset, iconSize * 0.05, iconPaint);

    // 绘制装饰线条（波浪线代表风景）
    final wavePath = Path()
      ..moveTo(center.dx - iconSize * 0.25, center.dy + iconSize * 0.15)
      ..quadraticBezierTo(
        center.dx - iconSize * 0.1,
        center.dy + iconSize * 0.05,
        center.dx + iconSize * 0.1,
        center.dy + iconSize * 0.15,
      )
      ..quadraticBezierTo(
        center.dx + iconSize * 0.25,
        center.dy + iconSize * 0.25,
        center.dx + iconSize * 0.25,
        center.dy + iconSize * 0.15,
      );

    canvas.drawPath(wavePath, iconPaint);

    // 绘制虚线边框效果
    final dashPaint = Paint()
      ..color = iconColor.withValues(alpha: 0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    _drawDashedRect(canvas, outerRect, dashPaint);
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dashWidth = 3.0;
    const dashSpace = 4.0;
    final topLeft = rect.topLeft;
    final topRight = rect.topRight;
    final bottomRight = rect.bottomRight;
    final bottomLeft = rect.bottomLeft;

    // 绘制顶部虚线
    _drawDashedLine(canvas, topLeft, topRight, dashWidth, dashSpace, paint);
    // 绘制右侧虚线
    _drawDashedLine(canvas, topRight, bottomRight, dashWidth, dashSpace, paint);
    // 绘制底部虚线
    _drawDashedLine(canvas, bottomRight, bottomLeft, dashWidth, dashSpace, paint);
    // 绘制左侧虚线
    _drawDashedLine(canvas, bottomLeft, topLeft, dashWidth, dashSpace, paint);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    double dashWidth,
    double dashSpace,
    Paint paint,
  ) {
    final distance = (end - start).distance;
    final direction = (end - start) / distance;
    
    var currentDistance = 0.0;
    var draw = true;
    
    while (currentDistance < distance) {
      final currentPoint = start + direction * currentDistance;
      final nextDistance = currentDistance + (draw ? dashWidth : dashSpace);
      final nextPoint = start + direction * min(nextDistance, distance);
      
      if (draw) {
        canvas.drawLine(currentPoint, nextPoint, paint);
      }
      
      draw = !draw;
      currentDistance = nextDistance;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is _ImagePlaceholderPainter &&
        (oldDelegate.iconColor != iconColor ||
            oldDelegate.iconSize != iconSize);
  }
}
