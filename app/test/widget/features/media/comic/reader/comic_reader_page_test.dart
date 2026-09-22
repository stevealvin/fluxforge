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
    await tester.tap(find.widgetWithText(ListTile, '长漫画'));
    await settle(tester);
    expect(find.byType(ListView), findsOneWidget);
    expect(find.text('长漫画'), findsOneWidget, reason: '底部入口显示当前方式');
    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.padding, equals(EdgeInsets.zero), reason: '零内边距铺满');

    // 再切回左右翻页
    await tester.tap(find.text('长漫画'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ListTile, '左右翻页'));
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
}
