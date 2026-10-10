import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 全局加载指示器（极光彗星环 · A6 底轨 + 呼吸）
///
/// 绘制结果无法在 widget 测试里断言像素，所以这里守的是三条**行为契约**：
/// 两种形态的渲染结构、自定义配色的透传，以及最容易被改坏的无障碍降级 ——
/// 系统开启「减少动画」时必须停表，否则它就是一个常驻耗电的空转动画
/// （项目历史上出现过 shimmer 无条件 repeat 导致常驻 60fps 的教训）。
Future<void> _pump(
  WidgetTester tester, {
  required Widget child,
  bool disableAnimations = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('主态渲染指示器与文案', (tester) async {
    await _pump(tester, child: const AppLoading(message: '正在加载发现内容...'));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AppLoading), findsOneWidget);
    expect(find.text('正在加载发现内容...'), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });

  testWidgets('紧凑态只渲染图形、不带文案', (tester) async {
    await _pump(tester, child: const AppLoading.compact(size: 14));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AppLoading), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('自定义主色可透传（不抛异常）', (tester) async {
    await _pump(
      tester,
      child: const AppLoading(size: 20, strokeWidth: 2, color: Colors.orange),
    );
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(AppLoading), findsOneWidget);
  });

  testWidgets('减少动画：停表不再请求新帧（对照：正常模式持续跑帧）', (tester) async {
    // 对照组：正常模式下 Ticker 活跃，应持续有待处理帧
    await _pump(tester, child: const AppLoading());
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: '正常模式应当持续请求新帧（动画在跑）',
    );

    // 开启「减少动画」后必须停表
    await _pump(tester, child: const AppLoading(), disableAnimations: true);
    await tester.pump(const Duration(milliseconds: 50));
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: '系统开启「减少动画」时必须停表，否则就是常驻耗电的空转动画',
    );
  });
}
