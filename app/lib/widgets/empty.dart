import 'package:material_ui/material_ui.dart';

class Empty extends StatelessWidget {
  const Empty({super.key, this.image, this.text = '暂无数据', this.size = 210});

  final Widget? image;
  final String text;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: const Alignment(0, -.5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: size,
            child:
                image ??
                CustomPaint(
                  size: Size(size, size),
                  painter: _EmptyIconPainter(),
                ),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _EmptyIconPainter extends CustomPainter {
  // 可配置的颜色参数
  final Color backgroundColor;
  final Color primaryColor;
  final Color secondaryColor;
  final Color accentColor;
  final Color shadowColor;

  // 构造函数带默认颜色
  _EmptyIconPainter({
    Color? backgroundColor,
    Color? primaryColor,
    Color? secondaryColor,
    Color? accentColor,
    Color? shadowColor,
  }) : backgroundColor = backgroundColor ?? const Color(0xFFEEF0F2),
       primaryColor = primaryColor ?? const Color(0xFFD8D9DB),
       secondaryColor = secondaryColor ?? const Color(0xFFBFC0C2),
       accentColor = accentColor ?? const Color(0xFFFCFCFC),
       shadowColor = shadowColor ?? const Color(0xFFE7E9EB);

  @override
  void paint(Canvas canvas, Size size) {
    // 计算缩放比例以适应不同大小
    final scale = size.width / 1024;

    // 保存画布状态
    canvas.save();
    canvas.scale(scale);

    // 1. 绘制背景波浪
    _drawBackgroundWave(canvas);

    // 2. 绘制底部椭圆
    _drawBottomEllipse(canvas);

    // 3. 绘制装饰元素
    _drawDecorationElements(canvas);

    // 4. 绘制主体图形
    _drawMainGraphic(canvas);

    // 5. 绘制圆形元素
    _drawCircleElements(canvas);

    canvas.restore();
  }

  void _drawBackgroundWave(Canvas canvas) {
    final path = Path()
      ..moveTo(3.31, 707.15)
      ..cubicTo(51.72, 552.09, 215.85, 553.24, 215.85, 553.24)
      ..cubicTo(305.85, 553.8, 375.62, 594.37, 433.1, 613.32)
      ..cubicTo(480.37, 628.87, 519.32, 623.56, 554.3, 622.04)
      ..cubicTo(631.84, 618.63, 715.22, 584.32, 796.14, 587.16)
      ..cubicTo(877.07, 589.82, 887.85, 621.66, 942.5, 638.53)
      ..cubicTo(984.1, 651.42, 1024, 677.39, 1024, 699.53)
      ..cubicTo(1024, 726.14, 1008.68, 759.23, 958, 767.63)
      ..cubicTo(883.69, 779.77, 649.8, 864.3, 396.8, 842.13)
      ..cubicTo(166.5, 821.9, 0, 775.18, 0, 721.45)
      ..cubicTo(0, 715.15, 1.1, 710.65, 3.31, 707.15)
      ..close();

    final paint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          shadowColor.withValues(alpha: 0),
          shadowColor.withValues(alpha: 0.1),
          shadowColor,
        ],
        stops: const [0, 0.32, 1],
      ).createShader(const Rect.fromLTRB(0, 0, 1024, 1024))
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  void _drawBottomEllipse(Canvas canvas) {
    final paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    canvas.drawOval(
      Rect.fromCenter(
        center: const Offset(512, 809.23),
        width: 201.14 * 2,
        height: 36.57 * 2,
      ),
      paint,
    );
  }

  void _drawDecorationElements(Canvas canvas) {
    // 左侧装饰元素
    _drawLeftDecoration(canvas);

    // 右侧装饰元素
    _drawRightDecoration(canvas);

    // 装饰小圆点
    _drawDecorationCircles(canvas);
  }

  void _drawLeftDecoration(Canvas canvas) {
    // 左侧主形状
    final leftPath = Path()
      ..moveTo(146.28, 483.07)
      ..cubicTo(146.28, 483.07, 144.57, 497.07, 149.28, 503.49)
      ..cubicTo(150.98, 505.76, 160.43, 510.76, 161.19, 522.1)
      ..cubicTo(161.76, 533.25, 157.19, 553.87, 127.72, 555.01)
      ..cubicTo(100.5, 556.15, 65.14, 546.88, 75.16, 506.24)
      ..cubicTo(81.59, 485.06, 101.63, 489.42, 99.55, 453.49)
      ..cubicTo(99.19, 428.91, 111.65, 403.57, 120.17, 404.71)
      ..cubicTo(127.92, 405.65, 128.48, 417.65, 133.96, 427.52)
      ..cubicTo(137.56, 434.09, 147.58, 442.41, 146.28, 483.07)
      ..close();

    final leftPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(leftPath, leftPaint);

    // 左侧细节
    final leftDetailPath = Path()
      ..moveTo(117.32, 588.58)
      ..cubicTo(117.32, 588.58, 122.23, 589.34, 122.23, 584.05)
      ..cubicTo(122.04, 578.93, 121.87, 563.81, 121.11, 555.89)
      ..cubicTo(120.92, 553.62, 119.6, 548.7, 119.79, 547.38)
      ..cubicTo(120.35, 544.38, 124.32, 534.71, 125.27, 531.68)
      ..cubicTo(127.62, 524.47, 127.99, 514.16, 128.35, 505.72)
      ..cubicTo(128.35, 503.49, 129.67, 498.57, 129.48, 497.25)
      ..cubicTo(129.04, 494.25, 125.08, 484.58, 124.12, 481.55)
      ..cubicTo(122.8, 477.34, 121.48, 457.67, 123.56, 457.86)
      ..cubicTo(125.64, 458.06, 125.64, 469.59, 126, 476.78)
      ..cubicTo(126.37, 481.92, 125.08, 492.69, 123.56, 497.25)
      ..cubicTo(123.19, 498.19, 120.91, 501.59, 118.07, 496.1)
      ..cubicTo(115.23, 490.61, 98.78, 465.84, 106.54, 447.31)
      ..cubicTo(109, 441.64, 105.4, 442.4, 102.26, 447.88)
      ..cubicTo(100.61, 450.9, 99.55, 454.91, 99.19, 457.67)
      ..cubicTo(97.67, 472.97, 99.19, 494.61, 110.12, 546.0)
      ..cubicTo(110.12, 546.0, 115.6, 555.42, 117.32, 561.73)
      ..cubicTo(117.32, 561.73, 117.32, 588.58, 117.32, 588.58)
      ..close();

    final leftDetailPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(leftDetailPath, leftDetailPaint);
  }

  void _drawRightDecoration(Canvas canvas) {
    // 右侧主形状
    final rightPath = Path()
      ..moveTo(935.89, 536.0)
      ..cubicTo(935.89, 536.0, 934.19, 550.0, 938.89, 556.42)
      ..cubicTo(940.59, 558.69, 950.04, 563.69, 950.8, 575.03)
      ..cubicTo(951.36, 586.19, 946.8, 606.8, 917.33, 607.95)
      ..cubicTo(890.1, 609.08, 854.75, 599.82, 864.77, 559.17)
      ..cubicTo(871.2, 537.99, 891.24, 542.34, 889.16, 506.41)
      ..cubicTo(888.79, 481.83, 901.26, 456.49, 909.77, 457.63)
      ..cubicTo(917.53, 458.57, 918.09, 470.57, 923.57, 480.44)
      ..cubicTo(927.18, 487.0, 937.2, 495.36, 935.89, 536.0)
      ..close();

    final rightPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(rightPath, rightPaint);

    // 右侧细节
    final rightDetailPath = Path()
      ..moveTo(908.83, 641.52)
      ..cubicTo(908.83, 641.52, 913.74, 642.28, 913.74, 636.99)
      ..cubicTo(913.55, 631.87, 913.37, 616.75, 912.61, 608.83)
      ..cubicTo(912.42, 606.56, 911.1, 601.64, 911.29, 600.32)
      ..cubicTo(911.86, 597.32, 915.83, 587.65, 916.78, 584.62)
      ..cubicTo(919.13, 577.41, 919.5, 567.1, 919.86, 558.66)
      ..cubicTo(919.86, 556.43, 921.18, 551.51, 920.99, 550.19)
      ..cubicTo(920.55, 547.19, 916.59, 537.52, 915.63, 534.49)
      ..cubicTo(914.31, 530.28, 912.99, 510.61, 915.07, 510.8)
      ..cubicTo(917.15, 511.0, 917.15, 522.53, 917.51, 529.72)
      ..cubicTo(917.88, 534.86, 916.59, 545.63, 915.07, 550.19)
      ..cubicTo(914.7, 551.13, 912.42, 554.53, 909.58, 549.04)
      ..cubicTo(906.74, 543.55, 890.29, 518.78, 898.05, 500.25)
      ..cubicTo(900.51, 494.58, 896.91, 495.34, 893.77, 500.82)
      ..cubicTo(892.12, 503.84, 891.06, 507.85, 890.7, 510.61)
      ..cubicTo(889.18, 525.91, 890.7, 547.55, 901.62, 599.0)
      ..cubicTo(901.62, 599.0, 907.1, 608.42, 908.27, 614.67)
      ..cubicTo(908.83, 614.67, 908.83, 641.52, 908.83, 641.52)
      ..close();

    final rightDetailPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(rightDetailPath, rightDetailPaint);
  }

  void _drawDecorationCircles(Canvas canvas) {
    final paint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    // 左上角圆
    canvas.drawCircle(const Offset(134.92, 274.89), 24.39, paint);

    // 左下角圆
    canvas.drawCircle(const Offset(35.26, 526.74), 18.91, paint);

    // 右上角圆
    canvas.drawCircle(const Offset(871.02, 350.53), 34.03, paint);
  }

  void _drawMainGraphic(Canvas canvas) {
    // 绘制主要图形
    _drawMainShape(canvas);
    _drawMainLines(canvas);
    _drawAccentShape(canvas);
  }

  void _drawMainShape(Canvas canvas) {
    // 主形状
    final mainPath = Path()
      ..moveTo(224.13, 297.07)
      ..cubicTo(224.13, 244.8, 275.78, 236.34, 275.78, 236.34)
      ..cubicTo(324.36, 236.34, 360.86, 302.45, 360.86, 302.45)
      ..lineTo(316.55, 313.38)
      ..cubicTo(316.55, 313.38, 327.42, 322.38, 327.42, 335.12)
      ..cubicTo(327.42, 335.12, 327.18, 362.3, 292.08, 362.3)
      ..cubicTo(292.08, 362.3, 224.13, 358.59, 224.13, 297.07)
      ..close();

    final mainPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(mainPath, mainPaint);

    // 主形状阴影
    final shadowPath = Path()
      ..moveTo(360.75, 302.0)
      ..lineTo(316.07, 313.43)
      ..cubicTo(316.07, 313.43, 326.94, 322.43, 326.94, 335.17)
      ..cubicTo(326.94, 335.17, 324.07, 362.31, 292.5, 362.31)
      ..lineTo(299.2, 362.0)
      ..lineTo(380.67, 341.52)
      ..close();

    final shadowPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(shadowPath, shadowPaint);
  }

  void _drawMainLines(Canvas canvas) {
    // 主要线条路径
    final linesPath = Path()
      // 基础形状
      ..moveTo(224.13, 295.24)
      ..cubicTo(219.13, 246.35, 275.78, 231.03, 275.78, 231.03)
      ..lineTo(561.17, 180.2)
      ..cubicTo(561.17, 180.2, 661.74, 195.79, 661.74, 314.0)
      ..cubicTo(661.74, 314.0, 660.54, 366.0, 650.86, 399.61)
      ..cubicTo(650.86, 399.61, 637.27, 435.69, 637.27, 463.83)
      ..cubicTo(637.27, 463.83, 632.11, 544.75, 699.79, 586.89)
      ..lineTo(528.55, 640.38)
      ..cubicTo(528.55, 640.38, 544.85, 675.16, 544.85, 675.16)
      ..cubicTo(544.85, 675.16, 538.72, 723.31, 498.65, 723.31)
      ..cubicTo(498.65, 723.31, 459.93, 715.55, 417.1, 667.13)
      ..cubicTo(417.1, 667.13, 357.3, 612.4, 357.3, 533.36)
      ..cubicTo(357.3, 533.36, 354.74, 484.9, 368.05, 439.74)
      ..cubicTo(368.05, 439.74, 373.49, 426.57, 373.49, 375.52)
      ..cubicTo(373.49, 375.52, 376.44, 334.52, 357.13, 300.62)
      ..cubicTo(357.13, 300.62, 324.18, 239.09, 275.58, 239.09)
      ..cubicTo(275.58, 239.09, 230.73, 244.23, 224.13, 295.24)
      ..close();

    final linesPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [backgroundColor, const Color(0xFFDDDEE0)],
      ).createShader(const Rect.fromLTRB(0, 0, 1024, 1024))
      ..style = PaintingStyle.fill;

    canvas.drawPath(linesPath, linesPaint);
  }

  void _drawCircleElements(Canvas canvas) {
    // 绘制圆形元素（仪表盘等）
    _drawDial(canvas);
    _drawDialDetails(canvas);
  }

  void _drawDial(Canvas canvas) {
    // 仪表盘主体
    final dialPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    final dialPath = Path()
      ..moveTo(698.76, 531.55)
      ..cubicTo(698.76, 531.55, 693.86, 526.65, 683.91, 527.51)
      ..lineTo(639.1, 450.36)
      ..cubicTo(656.66, 437.31, 656.66, 437.31, 656.66, 437.31)
      ..lineTo(702.76, 516.78)
      ..cubicTo(702.76, 516.78, 704.71, 527.51, 698.81, 531.55)
      ..close();

    canvas.drawPath(dialPath, dialPaint);

    // 仪表盘细节
    final detailPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.fill;

    final detailPath = Path()
      ..moveTo(667.0, 455.14)
      ..lineTo(671.39, 462.73)
      ..cubicTo(671.39, 462.73, 657.5, 474.49, 657.5, 474.49)
      ..lineTo(647.5, 457.28)
      ..close();

    canvas.drawPath(detailPath, detailPaint);
  }

  void _drawDialDetails(Canvas canvas) {
    // 大圆环
    final outerRingPath = Path()
      ..moveTo(552.0, 397.12)
      ..cubicTo(552.0, 441.0, 580.64, 477.0, 617.23, 481.0)
      ..cubicTo(610.43, 481.41, 610.43, 481.41, 610.43, 481.41)
      ..cubicTo(570.65, 481.41, 538.43, 443.68, 538.43, 397.15)
      ..cubicTo(538.43, 350.62, 570.68, 312.89, 610.46, 312.89)
      ..cubicTo(610.46, 312.89, 617.26, 313.3, 617.26, 313.3)
      ..cubicTo(580.67, 317.27, 552.0, 353.27, 552.0, 397.12)
      ..close();

    final outerRingPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(outerRingPath, outerRingPaint);

    // 内圆环
    final innerRingPath = Path()
      ..moveTo(624.0, 481.38)
      ..cubicTo(584.22, 481.38, 552.0, 443.65, 552.0, 397.12)
      ..cubicTo(552.0, 350.59, 584.25, 312.86, 624.03, 312.86)
      ..cubicTo(663.81, 312.86, 696.03, 350.59, 696.03, 397.12)
      ..cubicTo(696.03, 443.65, 663.78, 481.38, 624.0, 481.38)
      ..close()
      ..moveTo(614.51, 340.0)
      ..cubicTo(590.49, 340.0, 571.02, 365.0, 571.02, 395.76)
      ..cubicTo(571.02, 426.52, 590.49, 451.48, 614.51, 451.48)
      ..cubicTo(638.53, 451.48, 658.0, 426.48, 658.0, 395.76)
      ..cubicTo(658.0, 365.04, 638.53, 340.0, 614.51, 340.0)
      ..close();

    final innerRingPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(innerRingPath, innerRingPaint);

    // 圆环阴影
    final ringShadowPath = Path()
      ..moveTo(621.3, 454.2)
      ..cubicTo(621.3, 454.2, 595.14, 445.59, 595.14, 445.59)
      ..cubicTo(588.35, 447.39, 583.71, 448.79, 583.71, 448.79)
      ..cubicTo(592.1, 451.44, 603.33, 452.69, 614.51, 452.69)
      ..cubicTo(614.51, 452.69, 621.3, 454.2, 621.3, 454.2)
      ..close()
      ..moveTo(614.51, 340.0)
      ..cubicTo(603.33, 340.0, 592.1, 341.25, 583.71, 343.9)
      ..cubicTo(583.71, 343.9, 588.35, 345.3, 595.14, 347.1)
      ..cubicTo(595.14, 347.1, 621.3, 339.49, 621.3, 339.49)
      ..cubicTo(621.3, 339.49, 627.77, 340.74, 634.56, 343.9)
      ..cubicTo(634.56, 343.9, 639.2, 345.3, 645.31, 347.1)
      ..cubicTo(645.31, 347.1, 633.77, 341.25, 621.3, 339.49)
      ..cubicTo(621.3, 339.49, 614.51, 340.0, 614.51, 340.0)
      ..close();

    final ringShadowPaint = Paint()
      ..color = primaryColor
      ..style = PaintingStyle.fill;

    canvas.drawPath(ringShadowPath, ringShadowPaint);
  }

  void _drawAccentShape(Canvas canvas) {
    final accentPath = Path()
      ..moveTo(699.79, 584.67)
      ..lineTo(528.39, 640.47)
      ..cubicTo(538.68, 649.34, 542.39, 661.47, 542.5, 675.04)
      ..cubicTo(542.5, 675.04, 538.74, 723.29, 498.66, 723.29)
      ..lineTo(515.0, 723.29)
      ..lineTo(775.9, 633.6)
      ..cubicTo(775.9, 633.6, 797.64, 625.07, 797.64, 595.6)
      ..cubicTo(797.64, 595.6, 796.18, 568.17, 784.05, 557.6)
      ..close();

    final accentPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [const Color(0xFFF1F3F5), const Color(0xFFE2E3E6)],
      ).createShader(const Rect.fromLTRB(0, 0, 1024, 1024))
      ..style = PaintingStyle.fill;

    canvas.drawPath(accentPath, accentPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate is _EmptyIconPainter &&
        (oldDelegate.backgroundColor != backgroundColor ||
            oldDelegate.primaryColor != primaryColor ||
            oldDelegate.secondaryColor != secondaryColor ||
            oldDelegate.accentColor != accentColor ||
            oldDelegate.shadowColor != shadowColor);
  }
}
