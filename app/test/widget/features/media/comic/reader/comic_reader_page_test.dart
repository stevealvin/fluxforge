import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/comic/reader/comic_reader_page.dart';

/// 图片阅读器：底部入口 + 页进度滑动
void main() {
  const testImages = [
    'https://example.com/page1.jpg',
    'https://example.com/page2.jpg',
    'https://example.com/page3.jpg',
  ];

  Future<void> pumpReader(
    WidgetTester tester, {
    bool continuous = false,
    VoidCallback? onOpenCatalog,
    void Function(int index, int total)? onPageChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(
          imageList: testImages,
          initialIndex: 0,
          initialContinuousMode: continuous,
          onOpenCatalog: onOpenCatalog,
          onPageChanged: onPageChanged,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
  }

  /// 推进动画但**不等待收敛**：图片加载指示器是无限动画，
  /// 用 `pumpAndSettle` 会直接超时。
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  /// 多推几帧：长图定位是「估算跳 → 等一帧 → 精修」的收敛循环，需要逐帧推进
  Future<void> settleFrames(WidgetTester tester, [int frames = 8]) async {
    for (var i = 0; i < frames; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  /// 长图集：60 张，用于验证"目标项还没被构建"时的定位
  List<String> longGallery() =>
      List.generate(60, (i) => 'https://example.com/p${i + 1}.jpg');

  double listOffset(WidgetTester tester) =>
      tester.widget<ListView>(find.byType(ListView)).controller!.offset;

  testWidgets('阅读方式入口在底部栏，弹出面板里切换长漫画与左右翻页', (tester) async {
    await pumpReader(tester);

    // 默认左右翻页：底部入口直接显示当前方式，页码只由底部栏给出
    expect(find.text('1 / 3'), findsOneWidget);
    expect(find.text('左右翻页'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);

    // 点底部入口 → 底部弹出「阅读方式」面板
    await tester.tap(find.text('左右翻页'));
    await settle(tester);
    expect(find.text('阅读方式'), findsOneWidget);
    expect(find.text('长漫画'), findsOneWidget);

    // 在面板里选「长漫画」→ 切到纵向连续
    await tester.tap(find.byKey(const ValueKey('reading_mode_true')));
    await settle(tester);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('长漫画'), findsOneWidget, reason: '底部入口显示当前方式');
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.padding, equals(EdgeInsets.zero), reason: '零内边距铺满');

    // 再切回左右翻页
    await tester.tap(find.text('长漫画'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('reading_mode_false')));
    await settle(tester);
    expect(find.text('左右翻页'), findsOneWidget);
    expect(find.byType(ListView), findsNothing);
  });

  testWidgets('章节形态：目录入口同样在底部栏', (tester) async {
    var opened = 0;
    await pumpReader(tester, onOpenCatalog: () => opened++);

    expect(find.byTooltip('目录'), findsOneWidget);
    expect(find.text('目录'), findsOneWidget);

    await tester.tap(find.text('目录'));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('进度条左右的上下页按钮可翻页，边界不越界', (tester) async {
    final pages = <int>[];
    await pumpReader(tester, onPageChanged: (index, _) => pages.add(index));

    expect(find.byTooltip('上一页'), findsOneWidget);
    expect(find.byTooltip('下一页'), findsOneWidget);

    // 第 1 页：上一页不越界
    await tester.tap(find.byTooltip('上一页'));
    await settle(tester);
    expect(pages, isEmpty);

    // 下一页 → 第 2 页
    await tester.tap(find.byTooltip('下一页'));
    await settle(tester);
    expect(pages, [1]);
    expect(find.text('2 / 3'), findsOneWidget);

    // 上一页 → 回到第 1 页
    await tester.tap(find.byTooltip('上一页'));
    await settle(tester);
    expect(pages, [1, 0]);
    expect(find.text('1 / 3'), findsOneWidget);
  });

  testWidgets('页进度：拖动期间不跳页，松手才定位一次', (tester) async {
    final pageChanges = <int>[];
    await pumpReader(
      tester,
      onPageChanged: (index, _) => pageChanges.add(index),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    for (int i = 0; i < 12; i++) {
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(
      pageChanges,
      isEmpty,
      reason: '拖动中一旦跳页，滚动 / 翻页回写会把滑块拽回原处 —— 快滑就"没反应"',
    );

    await gesture.up();
    await settle(tester);

    expect(pageChanges.length, 1, reason: '松手只定位一次');
    expect(pageChanges.single, greaterThan(0));
  });

  testWidgets('页进度：快速甩动同样生效', (tester) async {
    final pageChanges = <int>[];
    await pumpReader(
      tester,
      onPageChanged: (index, _) => pageChanges.add(index),
    );

    await tester.fling(find.byType(Slider), const Offset(400, 0), 6000);
    await settle(tester);

    expect(pageChanges, isNotEmpty, reason: '滑得快也必须定位到位');
    expect(pageChanges.length, 1, reason: '一次甩动仍只定位一次');
  });

  testWidgets('长图模式：按 initialIndex 打开时定位到该张（不回到第一张）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(
          imageList: longGallery(),
          initialIndex: 40,
          initialContinuousMode: true,
        ),
      ),
    );
    await settleFrames(tester);

    // 页码由"屏幕中心落在哪张"推导，短占位图下会偏一两张；这里断言滚动位置更准
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(find.textContaining(' / 60'), findsOneWidget);
    expect(
      controller.offset / controller.position.maxScrollExtent,
      greaterThan(0.5),
      reason: '必须真的滚到第 41 张附近：此前目标项还没被构建，ensureVisible 静默失败',
    );
  });

  testWidgets('长图模式：进度条拖到后半段能定位（远处目标也能到）', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(
          imageList: longGallery(),
          initialIndex: 0,
          initialContinuousMode: true,
        ),
      ),
    );
    await settleFrames(tester);
    expect(listOffset(tester), 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await gesture.moveBy(const Offset(150, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await settleFrames(tester);

    expect(
      listOffset(tester),
      greaterThan(0),
      reason: '滑块松手后必须真的滚过去，"没反应"是目标项未构建导致的',
    );
  });

  testWidgets('左右翻页 → 长漫画：保持当前张，不跳回第一张', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(
          imageList: longGallery(),
          initialIndex: 30,
          initialContinuousMode: false,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('31 / 60'), findsOneWidget);

    await tester.tap(find.text('左右翻页'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('reading_mode_true')));
    await settleFrames(tester);
    // 长图模式下页码按屏幕中心推导，短占位图下会偏几张 —— 用位置比例判断更可靠

    expect(find.byType(ListView), findsOneWidget);
    final controller = tester
        .widget<ListView>(find.byType(ListView))
        .controller!;
    expect(
      controller.offset / controller.position.maxScrollExtent,
      greaterThan(0.4),
      reason: '切到长图后应停在第 31 张附近；此前会回到顶部第一张',
    );
  });

  testWidgets('长漫画 → 左右翻页：同样保持当前页', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ComicReaderPage(
          imageList: longGallery(),
          initialIndex: 30,
          initialContinuousMode: true,
        ),
      ),
    );
    await settleFrames(tester);

    // 记下切换前的页码：长图模式下它可能已按屏幕中心更新过，切换后必须保持一致
    final labelBefore = tester.widget<Text>(find.textContaining(' / 60')).data!;

    await tester.tap(find.text('长漫画'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('reading_mode_false')));
    await settleFrames(tester);

    expect(find.byType(ListView), findsNothing);
    expect(
      find.text(labelBefore),
      findsOneWidget,
      reason: 'PageView 重建当帧控制器还没挂上，单帧 jumpToPage 会静默失败（掉回第 1 页）',
    );
  });

  testWidgets('连续模式下图片占位页高度唯一：加载中与失败不得两种高度', (tester) async {
    await pumpReader(tester, continuous: true);
    await settle(tester);

    // 测试环境无网络 → 图片进入加载中 / 失败态，两者共用同一占位高度。
    // 断言「高度集合只有一个元素」：此前加载中 280、失败 220，
    // 状态切换会让列表项高度突变、滚动位置抖动。
    final placeholderHeights = tester
        .widgetList<Container>(find.byType(Container))
        .map((container) => container.constraints?.maxHeight)
        .whereType<double>()
        // 只关心固定高度的占位容器：撑满父级的约束是无限值，不参与比较
        .where((height) => height.isFinite && height > 200)
        .toSet();

    expect(placeholderHeights, {
      kComicPagePlaceholderHeight,
    }, reason: '加载中与失败的占位高度必须一致');
  });
}
