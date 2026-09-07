import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _radiusAnim;

  double maxRadius = 0;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _radiusAnim = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    Future.delayed(const Duration(milliseconds: 200), () {
      _controller.forward();
    });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        context.go('/');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    maxRadius = sqrt(size.width * size.width + size.height * size.height);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // 浅灰白
      body: AnimatedBuilder(
        animation: _radiusAnim,
        builder: (context, child) {
          return CustomPaint(
            painter: RevealPainterWhite(
              radius: maxRadius * _radiusAnim.value,
            ),
            child: Container(
              alignment: Alignment(0, 0),
              child: Opacity(
                opacity: 1 - _radiusAnim.value,
                child: Hero(
                  tag: 'logo',
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 80,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class RevealPainterWhite extends CustomPainter {
  final double radius;

  RevealPainterWhite({required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [
          Colors.white,
          const Color(0xFFF1F3F5), // 浅灰
        ],
      ).createShader(Rect.fromCircle(center: Offset(size.width / 2, size.height / 2), radius: radius));

    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant RevealPainterWhite oldDelegate) {
    return oldDelegate.radius != radius;
  }
}