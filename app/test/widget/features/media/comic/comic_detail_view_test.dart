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

  Future<void> pumpView(WidgetTester tester, MediaDetailData data) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        // 详情视图本身是纯 Column，放进可滚动宿主（与真实详情页的承载方式一致）
        home: Scaffold(
          body: SingleChildScrollView(child: ComicDetailView(data: data)),
        ),
      ),
    );
    // 不用 pumpAndSettle：图集里的 AppImage 在测试环境取不到网络图，
    // 加载指示器是无限动画，settle 必然超时
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
  }

  GridView galleryGrid(WidgetTester tester) =>
      tester.widget<GridView>(find.byType(GridView));

  testWidgets('图集画卷展示全部图片，不再截断到 9 张', (WidgetTester tester) async {
    await pumpView(tester, galleryData(12));

    expect(find.text('图集画卷'), findsOneWidget);
    expect(find.text('共 12 张'), findsOneWidget);

    // 旧实现是 `imageList.length.clamp(0, 9)`：标题写着 12 张，网格只画 9 个
    expect(galleryGrid(tester).childrenDelegate.estimatedChildCount, 12);
  });

  testWidgets('图集区域自身可滚动（不再被 NeverScrollableScrollPhysics 冻住）', (
    WidgetTester tester,
  ) async {
    await pumpView(tester, galleryData(12));

    expect(
      galleryGrid(tester).physics,
      isNot(isA<NeverScrollableScrollPhysics>()),
      reason: '图集全量铺开后必须能自己滑，否则超出的部分永远看不到',
    );
  });

  testWidgets('图片只有几张时同样正常渲染（不依赖凑满 9 张）', (WidgetTester tester) async {
    await pumpView(tester, galleryData(3));

    expect(find.text('共 3 张'), findsOneWidget);
    expect(galleryGrid(tester).childrenDelegate.estimatedChildCount, 3);
  });
}
