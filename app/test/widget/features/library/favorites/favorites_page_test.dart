// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/features/library/favorites/favorites_page.dart';

FavoriteItem _item({
  required String id,
  required String title,
  String mediaType = 'novel',
  String lastEpisode = '',
  String latestEpisode = '',
  bool hasUpdate = false,
  DateTime? updatedAt,
}) {
  return FavoriteItem(
    id: id,
    title: title,
    mediaType: mediaType,
    lastEpisode: lastEpisode,
    latestEpisode: latestEpisode,
    hasUpdate: hasUpdate,
    updatedAt: updatedAt ?? DateTime(2026, 9, 21),
  );
}

Future<void> _pumpPage(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.lightTheme, home: const FavoritesPage()),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() async {
    if (!getIt.isRegistered<FavoriteService>()) {
      getIt.registerSingleton<FavoriteService>(FavoriteService());
    }
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
    await AppStorage.clear();
    await favoriteService.clearFavorites();
    await playHistoryService.clear();
    await pumpEventQueue();
  });

  testWidgets('展示条目与 NEW 角标，「上次看到」取真实消费进度', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/1',
        title: '流光纪元',
        lastEpisode: '第 3 章',
        latestEpisode: '第 9 章',
        hasUpdate: true,
      ),
    );
    // 真实进度晚于收藏写入：展示必须以此为准
    await playHistoryService.upsert(
      PlayRecord(
        id: 'https://x/1',
        title: '流光纪元',
        mediaType: 'novel',
        episodeName: '第 7 章',
        updatedAt: DateTime(2026, 9, 21),
      ),
    );

    await _pumpPage(tester);

    expect(find.text('流光纪元'), findsOneWidget);
    expect(find.textContaining('NEW · 第 9 章'), findsOneWidget);
    expect(find.text('上次看到：第 7 章'), findsOneWidget);
    expect(find.text('最新更新：第 9 章'), findsOneWidget);
  });

  testWidgets('移除收藏给出可撤销提示，撤销后条目恢复', (WidgetTester tester) async {
    await favoriteService.addFavorite(_item(id: 'https://x/1', title: '流光纪元'));

    await _pumpPage(tester);

    await tester.tap(find.byIcon(Ionicons.trashOutline));
    await tester.pumpAndSettle();

    expect(favoriteService.favorites, isEmpty);
    expect(find.text('已移除《流光纪元》'), findsOneWidget);

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(favoriteService.favorites.single.title, '流光纪元');
    expect(find.text('流光纪元'), findsOneWidget);

    // 排空 SnackBar 计时，避免测试结束时残留定时器
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('筛选到无条目的类型时给出区分文案', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(id: 'https://x/1', title: '流光纪元', mediaType: 'novel'),
    );

    await _pumpPage(tester);

    await tester.tap(find.text('影视'));
    await tester.pumpAndSettle();

    expect(find.text('该类型下暂无收藏'), findsOneWidget);
    expect(find.text('流光纪元'), findsNothing);
  });

  testWidgets('有更新的条目置顶', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/a',
        title: '普通条目',
        updatedAt: DateTime(2026, 9, 21, 12),
      ),
    );
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/b',
        title: '有更新条目',
        hasUpdate: true,
        latestEpisode: '第 9 章',
        updatedAt: DateTime(2026, 9, 20),
      ),
    );

    await _pumpPage(tester);

    final updatedY = tester.getTopLeft(find.text('有更新条目')).dy;
    final normalY = tester.getTopLeft(find.text('普通条目')).dy;
    expect(updatedY, lessThan(normalY));
  });

  testWidgets('完全无收藏时展示通用空态', (WidgetTester tester) async {
    await _pumpPage(tester);

    expect(find.text('暂无收藏条目'), findsOneWidget);
    expect(find.text('该类型下暂无收藏'), findsNothing);
  });
}
