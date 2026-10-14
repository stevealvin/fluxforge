import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:fluxforge/app/theme/app_colors.dart';

/// 全局统一加载指示器组件（磁流体有机核 · Ferrofluid Morph Core）
///
/// 两层不规则磁流体形彼此叠加（上层以 `screen` 混合），边缘互相啃噬、旋转与缩放，
/// 中心一点柔光随之明灭。三条周期互不整除（2.6s / 2.1s 反向 / 1.3s 交替），图案不会
/// 精确重复。
///
/// 轮廓由 CSS 的关键帧直接描述（每角独立的水平 / 垂直半径），外层起伏幅度比参考实现
/// 更大，见 [_FerrofluidPainter._outerScale]。
class AppLoading extends StatefulWidget {
  const AppLoading({
    super.key,
    this.message,
    this.size = 42.0,
    this.strokeWidth = 2.1,
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

  /// 兼容线宽参数（按尺寸自适应缩放）
  final double strokeWidth;

  /// 主色（缺省采用靛蓝 → 品红 / 品红 → 青蓝的双层渐变）
  final Color? color;

  /// 是否为极简紧凑态（只影响是否渲染文案，图形与主态完全一致）
  final bool isCompact;

  @override
  State<AppLoading> createState() => _AppLoadingState();
}

class _AppLoadingState extends State<AppLoading>
    with SingleTickerProviderStateMixin {
  static const Duration _period = Duration(milliseconds: 2600);

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _period)..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 无障碍：系统开启「减少动画」时停在形变最饱满的相位
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 1.0 / 3.0;
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

    final Color c1;
    final Color c2;
    final Color c3;
    if (widget.color != null) {
      final hsl = HSLColor.fromColor(widget.color!);
      c1 = widget.color!;
      c2 = hsl.withHue((hsl.hue + 120.0) % 360.0).toColor();
      c3 = hsl.withHue((hsl.hue + 200.0) % 360.0).toColor();
    } else {
      // 外层换成品绿系（与「极光翠影」主题同族），内层配青蓝 —— 整体是
      // 绿 → 青的和谐过渡；原配色（靛蓝 → 品红 → 青蓝）里绿与品红会撞色
      c1 = const Color(0xFF10B981); // 翡翠绿
      c2 = const Color(0xFF34D399); // 薄荷绿
      c3 = const Color(0xFF0EA5E9); // 天蓝
    }

    final indicator = SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => CustomPaint(
            painter: _FerrofluidPainter(
              progress: _controller.value,
              c1: c1,
              c2: c2,
              c3: c3,
              isDark: isDark,
            ),
          ),
        ),
      ),
    );

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

/// 磁流体有机核绘制器
///
/// 三层相位由主周期推导：外层 `t = progress`；内层取 `1 - (t × 2.6 / 2.1) % 1` 得到
/// 反向；柔光取三角波得到往返。轮廓用 CSS 的 `h1 h2 h3 h4 / v1 v2 v3 v4`（每角独立的
/// 水平与垂直半径），三组关键帧按 `linear` 逐角插值。
class _FerrofluidPainter extends CustomPainter {
  _FerrofluidPainter({
    required this.progress,
    required this.c1,
    required this.c2,
    required this.c3,
    required this.isDark,
  });

  final double progress;
  final Color c1;
  final Color c2;
  final Color c3;
  final bool isDark;

  static const double _secondsOuter = 2.6;
  static const double _secondsInner = 2.1;
  static const double _secondsShine = 1.3;

  /// 关键帧 A / B / C 的水平半径（四角，tl tr br bl，单位 %）
  static const List<double> _hA = [62.0, 38.0, 46.0, 54.0];
  static const List<double> _hB = [38.0, 62.0, 64.0, 36.0];
  static const List<double> _hC = [54.0, 46.0, 35.0, 65.0];

  /// 关键帧 A / B / C 的垂直半径
  static const List<double> _vA = [60.0, 44.0, 56.0, 40.0];
  static const List<double> _vB = [42.0, 58.0, 42.0, 58.0];
  static const List<double> _vC = [52.0, 35.0, 65.0, 48.0];

  /// 外层波浪的取样点数与波形参数
  ///
  /// **点数与幅度必须一起定**：点太少而幅度太大时，相邻点的径向差会接近两点间的弧长，
  /// 平滑曲线只能朝直线塌过去，轮廓就退化成多边形。此处 16 点 + 11% 主波，径向差不到
  /// 弧长的三分之一，平滑无虞。
  static const int _waveSamples = 16;

  /// 主波波数（鼓包个数）与幅度
  static const double _waveNumber = 3.0;
  static const double _waveAmplitude = 0.08;

  /// 次谐波：叠加少量高频起伏，让轮廓不那么"规则"，幅度须远小于主波
  static const double _rippleNumber = 5.0;
  static const double _rippleAmplitude = 0.025;

  @override
  void paint(Canvas canvas, Size size) {
    final shortSide = math.min(size.width, size.height);
    if (shortSide <= 0) return;

    final k = shortSide / 68.0;
    final center = Offset(size.width / 2, size.height / 2);

    // 外层：不做整体缩放，改用「沿周向传播的波浪轮廓」。
    // 整体缩放只是「同一个形状在胀缩」，看久了就是椭圆在呼吸；波浪则是轮廓上多个
    // 鼓包绕圈移动，形状本身在流动，才有流体起伏的观感。
    _paintWave(
      canvas: canvas,
      center: center,
      radius: 30.5 * k,
      t: progress % 1.0,
      from: c1,
      to: c2,
      opacity: 0.88,
    );

    _paintBlob(
      canvas: canvas,
      center: center,
      // 内圈收小：原来 54 时它的最大半径（28.6k）会超过外圈波谷（25.5k），
      // 于是外圈凹下去的地方被顶穿。收到 46 后最大半径 24.4k，与外圈波谷
      // （30.5 × 0.895 ≈ 27.3k）留出约 2.9k 间隙。
      side: 46.0 * k,
      t: 1.0 - ((progress * (_secondsOuter / _secondsInner)) % 1.0),
      from: c2,
      to: c3,
      diagonalDown: false,
      opacity: 0.75,
      scaleRange: const [1.0, 1.06, 0.94],
      blend: BlendMode.screen,
    );

    final shinePhase = (progress * (_secondsOuter / _secondsShine)) % 2.0;
    final shineF = Curves.easeInOut.transform(
      (shinePhase <= 1.0 ? shinePhase : 2.0 - shinePhase).clamp(0.0, 1.0),
    );
    canvas.drawCircle(
      center,
      9.0 * k * (0.65 + 0.55 * shineF),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45 + 0.5 * shineF)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3.0 * k),
    );
  }

  /// 画外层的波浪 blob（无缩放）
  void _paintWave({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double t,
    required Color from,
    required Color to,
    required double opacity,
  }) {
    final path = _wavePath(center: center, radius: radius, t: t);

    final extent =
        radius * (1 + _waveAmplitude + _rippleAmplitude) * 2;

    final gradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        from.withValues(alpha: opacity),
        to.withValues(alpha: opacity),
      ],
    );

    canvas.drawPath(
      path,
      Paint()
        ..shader = gradient.createShader(
          Rect.fromCenter(center: center, width: extent, height: extent),
        ),
    );
  }

  /// 周向传播波轮廓
  ///
  /// 半径沿「角度与时间」做正弦调制：`r = R × (1 + A·sin(kθ − 2πt) + …)`。
  /// 因为是 `kθ − ωt`（而非 `kθ`），波峰位置随 t 移动 —— 鼓包绕着轮廓转圈，
  /// 这正是「波浪」与「整体缩放」的本质区别。
  Path _wavePath({
    required Offset center,
    required double radius,
    required double t,
  }) {
    final points = <Offset>[];
    for (var i = 0; i < _waveSamples; i++) {
      final theta = 2 * math.pi * i / _waveSamples;
      final r = radius *
          (1 +
              _waveAmplitude *
                  math.sin(_waveNumber * theta - 2 * math.pi * t) +
              _rippleAmplitude *
                  math.sin(_rippleNumber * theta + 2 * math.pi * t * 1.3));
      points.add(
        Offset(
          center.dx + r * math.cos(theta),
          center.dy + r * math.sin(theta),
        ),
      );
    }

    // 相邻点中点作端点、数据点作控制点做二次贝塞尔：闭合且处处平滑
    final path = Path();
    final last = points.last;
    final first = points.first;
    path.moveTo((last.dx + first.dx) / 2, (last.dy + first.dy) / 2);
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final next = points[(i + 1) % points.length];
      path.quadraticBezierTo(
        p.dx,
        p.dy,
        (p.dx + next.dx) / 2,
        (p.dy + next.dy) / 2,
      );
    }
    path.close();
    return path;
  }

  /// 画内层磁流体 blob（沿用关键帧形变）
  void _paintBlob({
    required Canvas canvas,
    required Offset center,
    required double side,
    required double t,
    required Color from,
    required Color to,
    required bool diagonalDown,
    required double opacity,
    required List<double> scaleRange,
    BlendMode? blend,
  }) {
    final f = t % 1.0;
    final double scale;
    final double rotation;
    final List<double> h;
    final List<double> v;

    if (f <= 1.0 / 3.0) {
      final u = f / (1.0 / 3.0);
      h = _mix(_hA, _hB, u);
      v = _mix(_vA, _vB, u);
      scale = _lerp(scaleRange[0], scaleRange[1], u);
      rotation = 120.0 * u;
    } else if (f <= 2.0 / 3.0) {
      final u = (f - 1.0 / 3.0) / (1.0 / 3.0);
      h = _mix(_hB, _hC, u);
      v = _mix(_vB, _vC, u);
      scale = _lerp(scaleRange[1], scaleRange[2], u);
      rotation = 120.0 + 120.0 * u;
    } else {
      final u = (f - 2.0 / 3.0) / (1.0 / 3.0);
      h = _mix(_hC, _hA, u);
      v = _mix(_vC, _vA, u);
      scale = _lerp(scaleRange[2], scaleRange[0], u);
      rotation = 240.0 + 120.0 * u;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation * math.pi / 180.0);
    canvas.scale(scale);

    final half = side / 2;
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: side,
      height: side,
    );

    // CSS 的 `h… / v…` 语法：每个角的水平与垂直半径可以不同
    final rrect = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.elliptical(half * h[0] / 50.0, half * v[0] / 50.0),
      topRight: Radius.elliptical(half * h[1] / 50.0, half * v[1] / 50.0),
      bottomRight: Radius.elliptical(half * h[2] / 50.0, half * v[2] / 50.0),
      bottomLeft: Radius.elliptical(half * h[3] / 50.0, half * v[3] / 50.0),
    );

    // 透明度并入渐变色：shader 存在时 Paint.color 只当 alpha 调制用
    final gradient = LinearGradient(
      begin: diagonalDown ? Alignment.topLeft : Alignment.topRight,
      end: diagonalDown ? Alignment.bottomRight : Alignment.bottomLeft,
      colors: [
        from.withValues(alpha: opacity),
        to.withValues(alpha: opacity),
      ],
    );

    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = gradient.createShader(rect)
        ..blendMode = blend ?? BlendMode.srcOver,
    );

    canvas.restore();
  }

  static List<double> _mix(List<double> a, List<double> b, double f) => [
        _lerp(a[0], b[0], f),
        _lerp(a[1], b[1], f),
        _lerp(a[2], b[2], f),
        _lerp(a[3], b[3], f),
      ];

  static double _lerp(double a, double b, double f) => a + (b - a) * f;

  @override
  bool shouldRepaint(covariant _FerrofluidPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.c1 != c1 ||
        oldDelegate.c2 != c2 ||
        oldDelegate.c3 != c3 ||
        oldDelegate.isDark != isDark;
  }
}
