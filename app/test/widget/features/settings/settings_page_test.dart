// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/features/settings/settings_page.dart';
import 'package:fluxforge/shared/widgets/setting_tile.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // AppStorage 基于 SharedPreferencesAsync：给它内存替身，否则改偏好会抛
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() {
    // 设置页只需要 appService（其余服务仅在「关于」面板打开时才用得上）
    if (!getIt.isRegistered<AppService>()) {
      getIt.registerSingleton<AppService>(AppService());
    }
  });

  /// 渲染整页设置
  ///
  /// 设置页是**懒加载列表**：默认 600 高的测试视口只会构建前 3 组，
  /// 断言后两组会误报「不存在」。故放大视口让整页一次性构建。
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const SettingsPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('五张卡统一为「分组标题 + SettingSection + SettingRow」', (
    WidgetTester tester,
  ) async {
    await pumpSettings(tester);

    // 分组标题外移到卡片外（与「我的」页同构）：5 组
    expect(find.byType(SettingSectionTitle), findsNWidgets(5));
    expect(find.byType(SettingSection), findsNWidgets(5));

    // 行样式统一：卡内不再有手写 ListTile / SwitchListTile
    expect(find.byType(SettingRow), findsWidgets);
    expect(find.byType(ListTile), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
  });

  testWidgets('五个分组标题都渲染出来（扫读顺序稳定）', (WidgetTester tester) async {
    await pumpSettings(tester);

    for (final title in const [
      '播放与视听',
      '浏览与阅读',
      '规则沙箱与网络',
      '外观与主题',
      '数据、诊断与关于',
    ]) {
      expect(find.text(title), findsOneWidget, reason: '缺少分组标题：$title');
    }
  });

  testWidgets('开关行整行可点：点标题即可切换该偏好', (WidgetTester tester) async {
    await pumpSettings(tester);

    final before = appService.settings.enableLongPress2x;
    // 点行内标题（而非开关本身）应同样生效 —— 这是「整行可点」的验收点
    await tester.tap(find.text('长按瞬时加速与触觉震动'));
    await tester.pumpAndSettle();

    expect(appService.settings.enableLongPress2x, !before);
  });

  testWidgets('点击「界面风格主题」弹出主题选择面板', (WidgetTester tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('界面风格主题'));
    await tester.pumpAndSettle();

    expect(find.text('选择系统主题外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
  });
}
