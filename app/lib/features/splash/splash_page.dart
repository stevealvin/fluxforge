import 'dart:math';

import 'package:material_ui/material_ui.dart';
import 'package:fluxforge/app/router/app_navigator.dart';

class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _radiusAnim;
  late Animation<double> _fadeAnim;

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
    // 图标渐隐与白圆扩散同源反向：进度 0 → 可见，进度 1 → 完全隐去
    _fadeAnim = ReverseAnimation(_radiusAnim);

    // 延迟起播：页面可能在延迟窗口内就被销毁（提前导航 / 测试环境），
    // 必须在回调里守卫 mounted —— 否则会在已 dispose 的 controller 上 forward 而抛异常
    Future.delayed(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      _controller.forward();
    });

    _controller.addStatusListener((status) {
      // 同理：动画跑完时 State 可能已经卸载，此时用 context 导航会抛错
      if (status == AnimationStatus.completed && mounted) {
        context.goHome();
      }
    });
  }

  @override
  void dispose() {
    // 此前漏了释放：本页是初始路由，播完即换页，controller 与它的 ticker 会一直挂着
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    maxRadius = sqrt(size.width * size.width + size.height * size.height);

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC), // 浅灰白
      body: AnimatedBuilder(
        animation: _radiusAnim,
        // child 交给 AnimatedBuilder 持有：动画每帧只跑 builder，
        // 图标与 Hero 不参与逐帧重建（Image.asset 非 const 构造，故此处不能加 const）
        child: Hero(
          tag: 'logo',
          child: Image.asset('assets/icon/icon.png', width: 80),
        ),
        builder: (context, child) {
          return CustomPaint(
            painter: RevealPainterWhite(
              radius: maxRadius * _radiusAnim.value,
            ),
            child: Center(
              // FadeTransition 只更新 RenderObject 的透明度，
              // 不像 Opacity 那样每帧重建子树、每帧 saveLayer
              child: FadeTransition(opacity: _fadeAnim, child: child),
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
