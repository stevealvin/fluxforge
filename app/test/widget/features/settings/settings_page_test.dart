// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_reader_preferences.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/reader_preferences.dart';
import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/settings/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // AppStorage 基于 SharedPreferencesAsync：给它内存替身，否则改偏好会抛
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() {
    if (!getIt.isRegistered<AppService>()) {
      getIt.registerSingleton<AppService>(AppService());
    }
    // 仪表盘会读规则 / 收藏 / 记录的条数
    if (!getIt.isRegistered<RuleService>()) {
      getIt.registerSingleton<RuleService>(RuleService());
    }
    if (!getIt.isRegistered<FavoriteService>()) {
      getIt.registerSingleton<FavoriteService>(FavoriteService());
    }
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
  });

  /// 渲染整页设置
  ///
  /// 设置页是**懒加载列表**：放大视口让整页一次性完整构建。
  Future<void> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const SettingsPage()),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('方案一 Hero 仪表盘渲染正常，严格不展示任何延迟字样', (WidgetTester tester) async {
    await pumpSettings(tester);

    // 1. 仪表盘微内核状态胶囊
    expect(find.text('沙箱微内核 · 活跃就绪'), findsOneWidget);

    // 2. 本地缓存容量条与一键瘦身
    expect(find.text('本地临时与媒体缓存占用'), findsOneWidget);
    expect(find.text('一键瘦身'), findsOneWidget);

    // 3. 核心资产三联统计磁贴
    expect(find.text('已启用规则'), findsOneWidget);
    expect(find.text('媒体消费资产'), findsOneWidget);
    expect(find.text('沙箱自愈诊断'), findsOneWidget);

    // 4. 严格断言：坚决无任何模拟延迟或 ms 显示
    expect(find.textContaining('延迟'), findsNothing);
    expect(find.textContaining('延时'), findsNothing);
    expect(find.textContaining('168ms'), findsNothing);
  });

  testWidgets('方案一 4 大核心场景专区磁贴（影音、阅读、外观、网络）渲染正常', (WidgetTester tester) async {
    await pumpSettings(tester);

    // 场景专区标题
    expect(find.text('核心场景专区'), findsOneWidget);

    // 四大专区卡片主标题
    expect(find.text('影音与播放'), findsOneWidget);
    expect(find.text('阅读与排版'), findsOneWidget);
    expect(find.text('外观与风格'), findsOneWidget);
    expect(find.text('网络与安全'), findsOneWidget);

    // 专区徽标与摘要引导
    expect(find.text('配置 3 项 ›'), findsOneWidget);
    expect(find.text('配置 2 项 ›'), findsOneWidget);
    expect(find.text('切换主题 ›'), findsOneWidget);
    expect(find.text('配置 4 项 ›'), findsOneWidget);
  });

  testWidgets('点击「影音与播放」专区弹出抽屉，整行点击切换长按瞬时加速', (WidgetTester tester) async {
    await pumpSettings(tester);

    // 点击专区卡片呼出抽屉
    await tester.tap(find.text('影音与播放'));
    await tester.pumpAndSettle();

    expect(find.text('影音与播放偏好'), findsOneWidget);
    expect(find.text('长按瞬时加速'), findsOneWidget);

    final before = appService.settings.enableLongPress2x;
    // 整行可点：点行内标题切换开关
    await tester.tap(find.text('长按瞬时加速'));
    await tester.pumpAndSettle();

    expect(appService.settings.enableLongPress2x, !before);
  });

  testWidgets('点击「外观与风格」专区直达主题选择面板并切换主题', (WidgetTester tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('外观与风格'));
    await tester.pumpAndSettle();

    expect(find.text('选择系统主题外观'), findsOneWidget);
    expect(find.text('跟随系统'), findsOneWidget);
    expect(find.text('纯净星暮白'), findsOneWidget);
    expect(find.text('曜夜极光翡翠'), findsOneWidget);

    // 切换至浅色
    await tester.tap(find.text('纯净星暮白'));
    await tester.pumpAndSettle();

    expect(appService.settings.themeMode, ThemeMode.light);
  });

  testWidgets('点击「阅读与排版」专区弹出抽屉，下拉切换小说与漫画阅读偏好并写入持久化', (WidgetTester tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('阅读与排版'));
    await tester.pumpAndSettle();

    expect(find.text('阅读与排版偏好'), findsOneWidget);

    // 小说翻页：默认平滑横翻 → 选「上下滚动」
    await tester.tap(find.byType(DropdownButton<PageTurnMode>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('上下滚动').last);
    await tester.pumpAndSettle();

    final novel = await ReaderPreferences.load();
    expect(
      novel.pageMode,
      PageTurnMode.verticalScroll,
      reason: '必须写进阅读器持久化存储',
    );

    // 漫画阅读方式：默认左右翻页 → 选「长条连读」
    await tester.tap(find.byType(DropdownButton<bool>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('长条连读').last);
    await tester.pumpAndSettle();

    expect(await ComicReaderPreferences.loadContinuousMode(), isTrue);
  });

  testWidgets('恢复默认偏好：二次确认后只重置偏好', (WidgetTester tester) async {
    await pumpSettings(tester);

    // 先改两处，确认重置真把它们改回来
    await appService.updateSettings(
      appService.settings.copyWith(
        enableLongPress2x: false,
        requestTimeoutSeconds: 60,
      ),
    );
    await ComicReaderPreferences.saveContinuousMode(true);
    await tester.pumpAndSettle();

    await tester.tap(find.text('恢复默认偏好'));
    await tester.pumpAndSettle();
    expect(find.text('恢复默认偏好？'), findsOneWidget, reason: '不可逆操作必须二次确认');

    await tester.tap(find.text('恢复默认'));
    await tester.pumpAndSettle();

    expect(appService.settings.enableLongPress2x, isTrue);
    expect(appService.settings.requestTimeoutSeconds, 30);
    expect(
      await ComicReaderPreferences.loadContinuousMode(),
      isFalse,
      reason: '阅读器的偏好不归 AppSettings 管，重置时必须一并写回默认值',
    );
    expect(find.text('已恢复默认偏好'), findsOneWidget);
  });
}
