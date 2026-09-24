// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/comic/comic_detail_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.empty();

  setUp(() {
    // 详情视图会登记消费记录；只注册这一个依赖即可
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
  });

  /// 图集形态的详情数据（`imageList` 非空即判定为图集，不触发章节相关分支）
  MediaDetailData galleryData(int imageCount) => MediaDetailData(
    title: '某图集',
    url: 'https://x.test/gallery/1',
    cover: 'https://img.test/cover.jpg',
    mediaType: MediaType.comic,
    imageList: List.generate(
      imageCount,
      (i) => 'https://img.test/${i + 1}.jpg',
    ),
  );

  /// 渲染详情视图
  ///
  /// 视图自带「固定头部 + 下方独立滚动」的骨架，故**不能**再套一层
  /// SingleChildScrollView（那会让高度约束变成无限，Expanded 直接报错）——
  /// 这里与真实详情页一致：直接放进有界的 body。
  Future<void> pumpView(WidgetTester tester, MediaDetailData data) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: ComicDetailView(data: data)),
      ),
    );
    // 不用 pumpAndSettle：图集里的 AppImage 在测试环境取不到网络图，
    // 加载指示器是无限动画，settle 必然超时
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  /// 图集画卷的网格（滚动区里的懒加载 sliver 网格）
  SliverGrid galleryGrid(WidgetTester tester) =>
      tester.widgetList<SliverGrid>(find.byType(SliverGrid)).first;

  /// 画卷网格声明的条目数（图集形态下只有一个网格）
  int galleryItemCount(WidgetTester tester) =>
      galleryGrid(tester).delegate.estimatedChildCount ?? 0;

  double viewportHeight(WidgetTester tester) =>
      tester.view.physicalSize.height / tester.view.devicePixelRatio;

  testWidgets('图集画卷展示全部图片，不再截断到 9 张', (WidgetTester tester) async {
    await pumpView(tester, galleryData(12));

    expect(find.text('图集画卷'), findsOneWidget);
    expect(find.text('共 12 张'), findsOneWidget);

    // 旧实现是 `imageList.length.clamp(0, 9)`：标题写着 12 张，网格只画 9 个
    expect(galleryItemCount(tester), 12);
  });

  testWidgets('画卷列表吃满剩余高度，且自己可滑（不再被冻住）', (WidgetTester tester) async {
    await pumpView(tester, galleryData(12));

    final scrollView = tester.widget<CustomScrollView>(
      find.byType(CustomScrollView),
    );
    expect(
      scrollView.physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
      reason: '画卷全量铺开后必须能自己滑，否则超出的部分永远看不到',
    );

    // 此前画卷被框在「按屏宽反算的两行高小窗口」里，滚动区高度根本没占满
    expect(
      tester.getBottomLeft(find.byType(CustomScrollView)).dy,
      closeTo(viewportHeight(tester), 1.0),
      reason: '滚动区应当一直延伸到屏幕底部',
    );
  });

  testWidgets('顶部区域固定：滚动画卷时头部位置不动', (WidgetTester tester) async {
    await pumpView(tester, galleryData(30));

    final titleBefore = tester.getTopLeft(find.text('某图集'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.getTopLeft(find.text('某图集')),
      titleBefore,
      reason: '头部（封面 / 标题 / 简介）属于固定区，不参与下方滚动',
    );
  });

  testWidgets('画卷标题吸顶：滚动列表时标题位置不动', (WidgetTester tester) async {
    await pumpView(tester, galleryData(30));

    final before = tester.getTopLeft(find.text('图集画卷'));
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.getTopLeft(find.text('图集画卷')),
      before,
      reason: '小节标题属于固定层：滑到一半也要能看出自己在看哪一段',
    );
  });

  testWidgets('图片只有几张时同样正常渲染（不依赖凑满 9 张）', (WidgetTester tester) async {
    await pumpView(tester, galleryData(3));

    expect(find.text('共 3 张'), findsOneWidget);
    expect(galleryItemCount(tester), 3);
  });
}
