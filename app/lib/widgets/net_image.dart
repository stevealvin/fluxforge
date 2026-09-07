import 'dart:math';

import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';

class NetImage extends StatelessWidget {
  const NetImage({
    super.key,
    required this.imageUrl,
    this.cache = true,
    this.headers,
    this.borderRadius,
    this.fit = BoxFit.cover,
    this.shape = BoxShape.rectangle,
    this.width,
    this.height,
  });

  final String imageUrl;
  final bool cache;
  final Map<String, String>? headers;
  final BorderRadius? borderRadius;
  final BoxFit? fit;
  final BoxShape? shape;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return ExtendedImage.network(
      imageUrl,
      cache: cache,
      headers: headers,
      fit: fit,
      shape: shape,
      borderRadius: borderRadius,
      width: width,
      height: height,
      loadStateChanged: (state) {
        switch (state.extendedImageLoadState) {
          case LoadState.failed:
            return ExtendedImage.asset('assets/icon/fail.png');
          default:
            return null;
        }
      },
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