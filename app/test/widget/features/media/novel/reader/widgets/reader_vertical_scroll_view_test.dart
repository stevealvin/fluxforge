import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_vertical_scroll_view.dart';

void main() {
  // 正文刻意保持简短，让多章能同屏，便于断言相对位置
  final chapters = List<NovelChapter>.generate(
    8,
    (i) => NovelChapter(title: '第${i + 1}章', content: '正文内容段落。' * 6),
  );

  Widget buildView({
    required List<int> sequence,
    required int anchorIndex,
    required GlobalKey centerKey,
    required Map<int, GlobalKey> blockKeys,
    required ScrollController controller,
    VoidCallback? onScrollEnd,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ReaderVerticalScrollView(
          sequence: sequence,
          anchorIndex: anchorIndex,
          centerKey: centerKey,
          chapters: chapters,
          blockKeys: blockKeys,
          controller: controller,
          readerTheme: ReaderTheme.porcelain,
          fontSize: 16,
          lineHeight: 1.6,
          contentOf: (index) => chapters[index].content,
          hasMore: false,
          onScrollEnd: onScrollEnd ?? () {},
        ),
      ),
    );
  }

  testWidgets('向上前插章节时滚动偏移与锚点内容位置均保持不变（center 锚点生效）', (WidgetTester tester) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};
    var sequence = <int>[3, 4];

    addTearDown(controller.dispose);

    await tester.pumpWidget(buildView(
      sequence: sequence,
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
    ));
    await tester.pumpAndSettle();

    // 锚点顶部即偏移原点
    expect(controller.offset, equals(0.0));
    final anchorTopBefore = tester.getTopLeft(find.text('第4章')).dy;

    // 模拟向上加载到上一章：序列前插，锚点保持不变
    sequence = <int>[2, 3, 4];
    await tester.pumpWidget(buildView(
      sequence: sequence,
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
    ));
    await tester.pumpAndSettle();

    // 核心断言 1：偏移量仍为 0，**没有发生任何补偿跳转**
    // （旧实现会在这里 jumpTo 一个等于新块高度的正向偏移，并先漏出一帧错位画面）
    expect(controller.offset, equals(0.0));
    // 核心断言 2：用户正在看的锚点内容纹丝不动 —— 这才是真正的「无跳变」
    expect(tester.getTopLeft(find.text('第4章')).dy, equals(anchorTopBefore));
  });

  testWidgets('向上区域随前插变长（minScrollExtent 更负），当前偏移不受影响', (WidgetTester tester) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};
    var sequence = <int>[3, 4];

    addTearDown(controller.dispose);

    await tester.pumpWidget(buildView(
      sequence: sequence,
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
    ));
    await tester.pumpAndSettle();

    final minBefore = controller.position.minScrollExtent;
    expect(minBefore, lessThanOrEqualTo(0.0));

    sequence = <int>[0, 1, 2, 3, 4];
    await tester.pumpWidget(buildView(
      sequence: sequence,
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
    ));
    await tester.pumpAndSettle();

    expect(controller.position.minScrollExtent, lessThan(minBefore));
    expect(controller.offset, equals(0.0));
  });

  testWidgets('锚点之前的章节按「越靠前离锚点越远」顺序渲染', (WidgetTester tester) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};

    addTearDown(controller.dispose);

    await tester.pumpWidget(buildView(
      sequence: <int>[1, 2, 3, 4],
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
    ));
    await tester.pumpAndSettle();

    // 向上区域的项在屏幕外，需滚到最顶才能看到；SliverList 懒加载是预期行为
    controller.jumpTo(controller.position.minScrollExtent);
    await tester.pumpAndSettle();

    final top2 = tester.getTopLeft(find.text('第2章')).dy;
    final top3 = tester.getTopLeft(find.text('第3章')).dy;
    final top4 = tester.getTopLeft(find.text('第4章')).dy;

    expect(top2, lessThan(top3), reason: '第2章应排在锚点更远处');
    expect(top3, lessThan(top4), reason: '第3章应紧邻锚点第4章之上');
  });

  testWidgets('已在屏幕内的章节在前插后保持原有屏幕位置', (WidgetTester tester) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};
    var sequence = <int>[3, 4];

    addTearDown(controller.dispose);

    await tester.pumpWidget(buildView(
      sequence: sequence,
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
    ));
    await tester.pumpAndSettle();

    final nextTopBefore = tester.getTopLeft(find.text('第5章')).dy;

    sequence = <int>[0, 1, 2, 3, 4];
    await tester.pumpWidget(buildView(
      sequence: sequence,
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
    ));
    await tester.pumpAndSettle();

    // 锚点下方的章节布局与锚点同属一个坐标区，完全不受向上插入影响
    expect(tester.getTopLeft(find.text('第5章')).dy, equals(nextTopBefore));
  });

  testWidgets('滚动停止时回调 onScrollEnd（供上层精确同步屏中线与窗口裁剪）', (WidgetTester tester) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};
    var endedCount = 0;

    addTearDown(controller.dispose);

    await tester.pumpWidget(buildView(
      sequence: <int>[1, 2, 3, 4, 5, 6],
      anchorIndex: 3,
      centerKey: centerKey,
      blockKeys: blockKeys,
      controller: controller,
      onScrollEnd: () => endedCount++,
    ));
    await tester.pumpAndSettle();

    // 前置条件：锚点上方有内容 → 可向负方向滚动（否则下面的 jumpTo 不会产生滚动通知）
    expect(controller.position.minScrollExtent, lessThan(0.0));

    controller.jumpTo(controller.position.minScrollExtent);
    await tester.pumpAndSettle();

    expect(endedCount, greaterThan(0), reason: '滚动停止必须上报一次，用于补齐降频同步');
  });
}
