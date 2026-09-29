// ignore_for_file: depend_on_referenced_packages
import 'dart:ui' as ui;

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
import 'package:fluxforge/shared/widgets/app_image.dart';
import 'package:fluxforge/features/media/shared/media_detail_page.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/filter_pill_bar.dart';

FavoriteItem _item({
  required String id,
  required String title,
  String mediaType = 'novel',
  String cover = '',
  String lastEpisode = '',
  String latestEpisode = '',
  bool hasUpdate = false,
  DateTime? updatedAt,
  DateTime? lastActiveAt,
}) {
  final favoritedAt = updatedAt ?? DateTime(2026, 9, 21);
  return FavoriteItem(
    id: id,
    title: title,
    mediaType: mediaType,
    cover: cover,
    lastEpisode: lastEpisode,
    latestEpisode: latestEpisode,
    hasUpdate: hasUpdate,
    updatedAt: favoritedAt,
    // 与生产口径一致：收藏当时就算一次活动
    lastActiveAt: lastActiveAt ?? favoritedAt,
  );
}

Future<void> _pumpPage(WidgetTester tester) async {
  // 用手机尺寸（390 × 844）：默认 800×600 的画布又宽又矮，与真机比例差得太多，
  // 布局断言（单列、贴边、行高）在那种画布上量出来的数字没有参考价值。
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

  testWidgets('点击卡片进入详情页：清红点，并记一次「最近活动」', (WidgetTester tester) async {
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
    expect(
      favoriteService.favorites.single.lastActiveAt.isAfter(
        DateTime(2026, 9, 21),
      ),
      isTrue,
      reason: '点击进入即算一次「最近活动」（排序用）',
    );
  });

  testWidgets('筛选条占据顶栏、刷新按钮撤掉，列表为「左封面 + 右信息」单列卡片', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(id: 'https://x/1', title: '流光纪元', cover: 'https://img.test/c.jpg'),
    );

    // 不用 _pumpPage：本用例带了真实封面地址，AppImage 加载网络图时指示器会一直转，
    // pumpAndSettle 必然超时
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const FavoritesPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 筛选胶囊在 AppBar 内（不再是列表上方独立的一行）
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('全部')),
      findsOneWidget,
    );
    // 刷新按钮已撤：追更检查只走下拉刷新，而它与该按钮本就是同一条路径
    expect(find.byTooltip('检查全量追更'), findsNothing);

    // 单列列表，不再是网格
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(GridView), findsNothing);

    // 版式验收点：封面贴卡片左上，信息落在它右侧
    final cardFinder = find.byType(AppCard).first;
    final card = tester.getRect(cardFinder);
    final cover = tester.getRect(
      find.descendant(of: cardFinder, matching: find.byType(ClipRRect)).first,
    );
    final titleLeft = tester.getTopLeft(find.text('流光纪元')).dx;

    expect(cover.left, moreOrLessEquals(card.left, epsilon: 0.5));
    expect(cover.top, moreOrLessEquals(card.top, epsilon: 0.5));
    expect(cover.right, lessThanOrEqualTo(titleLeft), reason: '信息在封面右侧');
  });

  testWidgets('顶栏：左侧页名 + 中间筛选条', (WidgetTester tester) async {
    await favoriteService.addFavorite(_item(id: 'https://x/1', title: '流光纪元'));

    await _pumpPage(tester);

    expect(find.text('收藏'), findsOneWidget, reason: '顶栏左侧应有页名');

    // 筛选条在顶栏内，且整条居中（不再是标题）
    final appBar = tester.getRect(find.byType(AppBar));
    final bar = tester.getRect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(FilterPillBar),
      ),
    );
    expect(bar.left, greaterThanOrEqualTo(appBar.left));
    expect(bar.right, lessThanOrEqualTo(appBar.right));
    // 居中：右侧留白与左侧（页名之后）留白同量级，允许百来 px 的字体宽度差
    expect((bar.center.dx - appBar.center.dx).abs(), lessThan(60));
  });

  testWidgets('封面区：贴卡片左上、160×108，且卡片高度等于封面区高度', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      // 最坏情况：标题占满两行 + 更新行也在，信息区仍不许把卡片撑高
      _item(
        id: 'https://x/1',
        title: '流光纪元之一个相当长的作品标题会折成两行',
        hasUpdate: true,
        latestEpisode: '第 15 章',
      ),
    );

    await _pumpPage(tester);

    final cardFinder = find.byType(AppCard).first;
    final card = tester.getRect(cardFinder);
    final cover = tester.getRect(
      find.descendant(of: cardFinder, matching: find.byType(ClipRRect)).first,
    );

    expect(cover.left, moreOrLessEquals(card.left, epsilon: 0.5));
    expect(
      cover.top,
      moreOrLessEquals(card.top, epsilon: 0.5),
      reason: '卡片不留内边距，封面直接贴左上',
    );
    expect(cover.width, closeTo(160, 0.5), reason: '左列封面宽度');
    expect(cover.height, closeTo(108, 0.5), reason: '封面区高度 = 卡片高度');

    // 高度契约：封面是标尺，信息区只能在这 108 里排版，不许把卡片撑高
    expect(
      card.height,
      moreOrLessEquals(cover.height, epsilon: 0.5),
      reason: '卡片高度 = 封面区高度（信息不参与撑高）',
    );
  });

  testWidgets('封面区：模糊补边在底、清晰封面居中在上', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/1',
        title: '流光纪元',
        cover: 'https://img.test/cover.jpg',
      ),
    );

    // 不用 _pumpPage：本用例带真实封面地址，AppImage 加载网络图时指示器一直转，
    // pumpAndSettle 必然超时
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.lightTheme, home: const FavoritesPage()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final cardFinder = find.byType(AppCard).first;

    // 底：模糊补边（竖封面两侧的空缺靠它填）
    final blurLayer = find.descendant(
      of: cardFinder,
      matching: find.byType(ImageFiltered),
    );
    expect(blurLayer, findsOneWidget, reason: '竖封面在宽幅封面区里的留白要靠同一张封面的模糊版补');
    expect(
      tester.widget<ImageFiltered>(blurLayer).imageFilter,
      isA<ui.ImageFilter>(),
    );

    // 模糊层上必须压遮罩：不压暗的话两侧会比中间的清晰图更抢眼
    expect(
      tester.widgetList<ColoredBox>(
        find.descendant(of: cardFinder, matching: find.byType(ColoredBox)),
      ),
      isNotEmpty,
    );

    // 上：清晰层，与模糊层同源；用 contain 完整显示、不做裁切
    final images = tester
        .widgetList<AppImage>(
          find.descendant(of: cardFinder, matching: find.byType(AppImage)),
        )
        .toList();
    expect(images.length, 2, reason: '同一张封面：一层模糊补边、一层完整居中');
    expect(images.last.fit, BoxFit.contain, reason: '宽图满幅、竖图居中，都不裁切');
  });

  testWidgets('NEW 角标：半透明底', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/1',
        title: '流光纪元',
        latestEpisode: '第 9 章',
        hasUpdate: true,
      ),
    );

    await _pumpPage(tester);

    final badge = tester.widget<Container>(
      find
          .ancestor(of: find.text('NEW'), matching: find.byType(Container))
          .first,
    );
    final color = (badge.decoration as BoxDecoration).color;
    expect(color?.a, lessThan(1.0), reason: '底色改为半透明，压住封面底图的同时透出一层');
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

  testWidgets('默认按「最近观看」排序：刚点开过的那条在上', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/a',
        title: '刚收藏但没点开',
        updatedAt: DateTime(2026, 9, 25), // 收藏更晚
        lastActiveAt: DateTime(2026, 9, 20),
      ),
    );
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/b',
        title: '很久前收藏但刚点开',
        updatedAt: DateTime(2026, 9, 21), // 收藏更早
        lastActiveAt: DateTime(2026, 9, 28),
      ),
    );

    await _pumpPage(tester);

    expect(find.text('最近观看'), findsOneWidget, reason: '默认档位是最近观看');

    final active = tester.getTopLeft(find.text('很久前收藏但刚点开'));
    final stale = tester.getTopLeft(find.text('刚收藏但没点开'));
    expect(active.dy < stale.dy, isTrue, reason: '默认看的是「最近活动」，不是收藏时间');
  });

  testWidgets('顶栏可切到「收藏时间」排序，切完顺序反转', (WidgetTester tester) async {
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/a',
        title: '刚收藏但没点开',
        updatedAt: DateTime(2026, 9, 25), // 收藏更晚
        lastActiveAt: DateTime(2026, 9, 20),
      ),
    );
    await favoriteService.addFavorite(
      _item(
        id: 'https://x/b',
        title: '很久前收藏但刚点开',
        updatedAt: DateTime(2026, 9, 21), // 收藏更早
        lastActiveAt: DateTime(2026, 9, 28),
      ),
    );

    await _pumpPage(tester);

    await tester.tap(find.text('最近观看'));
    await tester.pumpAndSettle();

    expect(find.text('收藏时间'), findsOneWidget, reason: '按钮文案反映当前档位');
    expect(find.text('已按收藏时间排序'), findsOneWidget);

    final newer = tester.getTopLeft(find.text('刚收藏但没点开'));
    final older = tester.getTopLeft(find.text('很久前收藏但刚点开'));
    expect(newer.dy < older.dy, isTrue, reason: '收藏时间倒序：后收藏的在上');

    // 排空提示计时，避免测试结束时残留定时器
    await tester.pump(const Duration(milliseconds: 1200));
    await tester.pumpAndSettle();
  });

  testWidgets('完全无收藏时展示通用空态', (WidgetTester tester) async {
    await _pumpPage(tester);

    expect(find.text('暂无收藏条目'), findsOneWidget);
    expect(find.text('该类型下暂无收藏'), findsNothing);
  });
}
