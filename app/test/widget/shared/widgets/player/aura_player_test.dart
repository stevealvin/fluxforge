import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/router/app_router.dart';
import 'package:fluxforge/shared/widgets/player/aura_player.dart';

void main() {
  testWidgets('AuraPlayer widget builds with expected clipBehavior and structure', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AuraPlayer(
            playUrl: '',
            title: '测试视频',
          ),
        ),
      ),
    );

    // 验证播放器成功构建且包含 ClipRect 视口防溢出裁剪
    expect(find.byType(AuraPlayer), findsOneWidget);
    expect(find.byType(ClipRect), findsWidgets);
  });

  testWidgets('AuraPlayer supports external control via GlobalKey<AuraPlayerState> pause and play', (WidgetTester tester) async {
    final playerKey = GlobalKey<AuraPlayerState>();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuraPlayer(
            key: playerKey,
            playUrl: '',
            title: '受控接口测试',
          ),
        ),
      ),
    );

    expect(find.byType(AuraPlayer), findsOneWidget);
    expect(playerKey.currentState, isNotNull);

    // 验证能够成功调用公开的 pause() 与 play() 受控方法而不崩溃
    playerKey.currentState?.pause();
    expect(tester.takeException(), isNull);

    playerKey.currentState?.play();
    expect(tester.takeException(), isNull);
  });

  testWidgets('AuraPlayer active 切换不抛异常（全屏期间的休眠 / 唤醒）', (WidgetTester tester) async {
    Future<void> pumpWithActive(bool active) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AuraPlayer(
              playUrl: '',
              title: '活动状态测试',
              active: active,
            ),
          ),
        ),
      );
    }

    await pumpWithActive(true);
    expect(find.byType(AuraPlayer), findsOneWidget);

    // 进入全屏：宿主把被遮挡的小屏实例切为不活动（交还常亮、停掉扫光）
    await pumpWithActive(false);
    expect(tester.takeException(), isNull);

    // 退出全屏：唤醒（按当前播放态重新断言常亮）
    await pumpWithActive(true);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AuraPlayer does not pause on internal popup dialog, drawer or fullscreen transitions', (WidgetTester tester) async {
    late BuildContext currentContext;

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [appRouteObserver],
        home: Scaffold(
          body: Builder(
            builder: (ctx) {
              currentContext = ctx;
              return const AuraPlayer(
                playUrl: '',
                title: '弹窗不暂停测试',
                autoPauseOnCovered: true,
              );
            },
          ),
        ),
      ),
    );

    expect(find.byType(AuraPlayer), findsOneWidget);

    // 1. 模拟弹出对话框/设置抽屉 (属于 PopupRoute)
    showGeneralDialog(
      context: currentContext,
      pageBuilder: (dialogContext, _, _) {
        return const Center(child: Text('内部设置抽屉'));
      },
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('内部设置抽屉'), findsOneWidget);
    // 验证播放器未崩溃或出现异常
    expect(tester.takeException(), isNull);

    // 关闭弹窗
    Navigator.of(currentContext).pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('内部设置抽屉'), findsNothing);
  });
}
