// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/features/library/favorites/favorites_page.dart';
import 'package:fluxforge/features/shell/shell_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // 外壳会构建各 Tab 页，它们经 DI 读写 AppStorage（基于 SharedPreferencesAsync）
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(configureDependencies);

  /// 渲染外壳
  ///
  /// 不用 `pumpAndSettle`：外壳内含持续动画（氛围渐变 / 加载指示器），settle 会超时。
  /// 且 `PageView` 懒加载 —— 初始只构建「发现」页，切 Tab 后才构建目标页。
  Future<void> pumpShell(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const ShellPage()),
    );
    await tester.pump();
  }

  NavigationBar barOf(WidgetTester tester) =>
      tester.widget<NavigationBar>(find.byType(NavigationBar));

  testWidgets('底部栏顺序为 发现 / 收藏 / 规则 / 站点 / 我的', (WidgetTester tester) async {
    await pumpShell(tester);

    expect(
      barOf(tester).destinations
          .map((d) => (d as NavigationDestination).label)
          .toList(),
      const ['发现', '收藏', '规则', '站点', '我的'],
    );
  });

  testWidgets('点击「收藏」Tab 切到收藏页', (WidgetTester tester) async {
    await pumpShell(tester);
    expect(barOf(tester).selectedIndex, 0);

    await tester.tap(find.text('收藏'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(barOf(tester).selectedIndex, 1);
    expect(find.byType(FavoritesPage), findsOneWidget);
  });

  testWidgets('收藏 Tab 图标不再挂红点（即使有未读更新）', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      FavoriteItem(
        id: 'https://x/1',
        title: '流光纪元',
        mediaType: 'novel',
        hasUpdate: true,
        updatedAt: DateTime(2026, 9, 21),
      ),
    );

    await pumpShell(tester);

    expect(
      find.byType(Badge),
      findsNothing,
      reason: '「有更新」由收藏页内的 NEW 角标表达，底部栏不再重复提示',
    );
  });

  testWidgets('首页顶栏不再有收藏入口（同一份数据不设两个入口）', (WidgetTester tester) async {
    await pumpShell(tester);

    // 底部栏的「收藏」Tab 也用 bookmarkOutline，故必须限定在 AppBar 内查找，
    // 否则会把 Tab 图标误判成顶栏入口
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Ionicons.bookmarkOutline),
      ),
      findsNothing,
    );
  });
}
