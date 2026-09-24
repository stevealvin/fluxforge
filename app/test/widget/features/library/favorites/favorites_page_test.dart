// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/features/library/favorites/favorites_page.dart';
import 'package:fluxforge/features/media/shared/media_detail_page.dart';

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
  // 用手机尺寸：800×600 的默认测试画布又宽又矮，3 列栅格下卡片高度（≈530）
  // 会高过视口，落在卡片底部的标题就点不到了 —— 长按点不到，面板自然不弹。
  tester.view.physicalSize = const Size(1170, 2532); // 390 × 844 @3x
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

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
    // 打开详情会经 MediaFavoriteActions.ruleOf → ruleService 反查绑定规则
    if (!getIt.isRegistered<RuleService>()) {
      getIt.registerSingleton<RuleService>(RuleService());
    }
    await AppStorage.clear();
    await favoriteService.clearFavorites();
    await playHistoryService.clear();
    await pumpEventQueue();
  });

  testWidgets('卡片带类型标签，筛选胶囊带各类型数量', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(id: 'https://x/1', title: '某漫画', mediaType: 'comic'),
    );
    await favoriteService.addFavorite(
      _item(id: 'https://x/2', title: '某小说', mediaType: 'novel'),
    );

    await _pumpPage(tester);

    // 卡片左下角的类型标签用「漫画」——与筛选胶囊的「漫画/图集」不同名，故可唯一断言
    expect(find.text('漫画'), findsOneWidget);
    expect(find.text('小说'), findsNWidgets(2), reason: '卡片类型标签 + 筛选胶囊各一处');

    // 数量：全部 2、影视 0、小说 1、漫画/图集 1
    expect(find.text('0'), findsOneWidget, reason: '空类型也要显示 0，不必点进去才发现');
    expect(find.text('1'), findsNWidgets(2));
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
    // 角标只写 NEW：集数交给下方那一行，避免同一信息在封面与文字里各说一遍
    expect(find.text('NEW'), findsOneWidget);
    expect(find.text('上次看到：第 7 章'), findsOneWidget);
    expect(find.text('更新至：第 9 章'), findsOneWidget);
  });

  testWidgets('长按弹出操作面板，移除后给出可撤销提示，撤销后条目恢复', (WidgetTester tester) async {
    await favoriteService.addFavorite(_item(id: 'https://x/1', title: '流光纪元'));

    await _pumpPage(tester);

    // 书架网格里放不下垃圾桶按钮：移除入口收进长按面板
    await tester.longPress(find.text('流光纪元'));
    await tester.pumpAndSettle();

    expect(find.text('移除收藏'), findsOneWidget);
    expect(find.text('查看详情'), findsNothing, reason: '面板不放「查看详情」：它与点击卡片完全同路');
    expect(
      favoriteService.favorites,
      isNotEmpty,
      reason: '长按只弹面板，不该直接删除（此前是长按即移除）',
    );

    await tester.tap(find.text('移除收藏'));
    await tester.pumpAndSettle();

    expect(favoriteService.favorites, isEmpty);
    expect(find.text('已移除《流光纪元》'), findsOneWidget);
    expect(find.text('撤销'), findsOneWidget, reason: '移除必须给后悔的机会');

    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();

    expect(favoriteService.favorites.single.title, '流光纪元');
    expect(find.text('流光纪元'), findsOneWidget);

    // 排空 SnackBar 计时，避免测试结束时残留定时器
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('点击卡片进入详情页，并清掉「有更新」红点', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/1',
        title: '流光纪元',
        latestEpisode: '第 9 章',
        hasUpdate: true,
      ),
    );

    await _pumpPage(tester);
    expect(find.text('NEW'), findsOneWidget);

    await tester.tap(find.text('流光纪元'));
    // 该条目没有绑定规则，详情页会走「未指定对应解析规则」分支，不涉及网络
    // 与无限动画，故只推进过渡动画而不 pumpAndSettle
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(MediaDetailPage), findsOneWidget);
    expect(favoriteService.favorites, isNotEmpty, reason: '打开详情不是移除');
    expect(
      favoriteService.favorites.single.hasUpdate,
      isFalse,
      reason: '打开详情即视为已知晓更新，只清红点',
    );
  });

  testWidgets('顶部标题为「收藏」，栅格为 3 列', (WidgetTester tester) async {
    await favoriteService.addFavorite(_item(id: 'https://x/1', title: '流光纪元'));

    await _pumpPage(tester);

    expect(find.text('收藏'), findsOneWidget);

    final grid = tester.widget<GridView>(find.byType(GridView));
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 3);
    // 3 列下格宽 ≈113.7：封面要保住 2:3，比例必须跟着重算而不是沿用 4 列的 0.42
    expect(delegate.childAspectRatio, closeTo(0.47, 0.001));
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

    // 网格里「置顶」= 排在更前的单元格：先比行（dy），同一行再比列（dx）——
    // 只有两个条目时它们必然并排，dy 相同，只比 dy 会恒假
    final updated = tester.getTopLeft(find.text('有更新条目'));
    final normal = tester.getTopLeft(find.text('普通条目'));
    expect(
      updated.dy < normal.dy ||
          (updated.dy == normal.dy && updated.dx < normal.dx),
      isTrue,
    );
  });

  testWidgets('完全无收藏时展示通用空态', (WidgetTester tester) async {
    await _pumpPage(tester);

    expect(find.text('暂无收藏条目'), findsOneWidget);
    expect(find.text('该类型下暂无收藏'), findsNothing);
  });
}
