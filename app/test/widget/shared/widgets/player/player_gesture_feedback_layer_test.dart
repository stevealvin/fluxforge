import 'package:flutter_test/flutter_test.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/shared/widgets/player/player_capsules.dart';
import 'package:fluxforge/shared/widgets/player/player_gesture_feedback_layer.dart';

/// 亮度 / 音量手势浮层的行为测试
///
/// 这组行为此前**完全没有测试**（`aura_player_test.dart` 只覆盖错误路径与 active 切换），
/// 而它正是「状态下沉」重构的对照基准：浮层出现、自动消失、每次更新重新计时、三态图标。
///
/// 亮度与音量已改为作用于真实设备（`screen_brightness` / `volume_controller`），
/// 浮层只保留数值反馈，故断言对象是胶囊数值而非此前的变暗遮罩。
void main() {
  Future<GlobalKey<PlayerGestureFeedbackLayerState>> buildLayer(
    WidgetTester tester, {
    bool isFullScreen = false,
  }) async {
    final key = GlobalKey<PlayerGestureFeedbackLayerState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PlayerGestureFeedbackLayer(key: key, isFullScreen: isFullScreen),
        ),
      ),
    );
    return key;
  }

  testWidgets('初始不显示任何浮层', (WidgetTester tester) async {
    await buildLayer(tester);
    await tester.pump();

    expect(find.byType(PlayerVerticalIndicatorCapsule), findsNothing);
  });

  testWidgets('显示亮度：胶囊出现且数值与推送一致', (WidgetTester tester) async {
    final key = await buildLayer(tester);
    await tester.pump();

    key.currentState!.showBrightness(0.5);
    await tester.pump();

    expect(find.byType(PlayerVerticalIndicatorCapsule), findsOneWidget);
    expect(find.byIcon(Ionicons.sunnyOutline), findsOneWidget);
    // 亮度已改为作用于真实屏幕背光（screen_brightness），浮层不再压暗画面，
    // 因此直接断言胶囊数值
    expect(
      tester
          .widget<PlayerVerticalIndicatorCapsule>(
            find.byType(PlayerVerticalIndicatorCapsule),
          )
          .value,
      closeTo(0.5, 0.001),
    );
  });

  testWidgets('1 秒后自动消失（未到点仍在）', (WidgetTester tester) async {
    final key = await buildLayer(tester);
    await tester.pump();

    key.currentState!.showBrightness(0.6);
    await tester.pump();
    expect(find.byType(PlayerVerticalIndicatorCapsule), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 900));
    expect(
      find.byType(PlayerVerticalIndicatorCapsule),
      findsOneWidget,
      reason: '未到 1 秒不应提前隐藏',
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlayerVerticalIndicatorCapsule), findsNothing);
  });

  testWidgets('连续更新会重新计时（拖动过程中不会中途消失）', (WidgetTester tester) async {
    final key = await buildLayer(tester);
    await tester.pump();

    key.currentState!.showBrightness(0.4);
    await tester.pump();
    // 800ms 时再拖一次：计时应重新开始
    await tester.pump(const Duration(milliseconds: 800));
    key.currentState!.showBrightness(0.55);
    await tester.pump();

    await tester.pump(const Duration(milliseconds: 900));
    expect(
      find.byType(PlayerVerticalIndicatorCapsule),
      findsOneWidget,
      reason: '第二次更新后仍在 1 秒窗口内',
    );

    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(PlayerVerticalIndicatorCapsule), findsNothing);
  });

  testWidgets('音量三态图标：静音 / 低 / 高', (WidgetTester tester) async {
    final key = await buildLayer(tester);
    await tester.pump();

    key.currentState!.showVolume(0);
    await tester.pump();
    expect(find.byIcon(Ionicons.volumeMuteOutline), findsOneWidget);

    key.currentState!.showVolume(0.3);
    await tester.pump();
    expect(find.byIcon(Ionicons.volumeLowOutline), findsOneWidget);

    key.currentState!.showVolume(0.9);
    await tester.pump();
    expect(find.byIcon(Ionicons.volumeHighOutline), findsOneWidget);
  });

  testWidgets('亮度与音量浮层互不干扰，各自独立计时', (WidgetTester tester) async {
    final key = await buildLayer(tester);
    await tester.pump();

    key.currentState!.showBrightness(0.7);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    key.currentState!.showVolume(0.2);
    await tester.pump();

    // 亮度的计时起点更早 → 先消失，音量的仍在
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byIcon(Ionicons.sunnyOutline), findsNothing);
    expect(find.byIcon(Ionicons.volumeLowOutline), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byType(PlayerVerticalIndicatorCapsule), findsNothing);
  });
}
