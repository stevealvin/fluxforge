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
    bool failedAbove = false,
    bool failedBelow = false,
    bool currentFailed = false,
    VoidCallback? onRetryAbove,
    VoidCallback? onRetryBelow,
    VoidCallback? onRetryCurrent,
    VoidCallback? onScrollEnd,
    String Function(int)? contentOf,
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
          contentOf: contentOf ?? (index) => chapters[index].content,
          hasMore: false,
          failedAbove: failedAbove,
          failedBelow: failedBelow,
          currentFailed: currentFailed,
          onRetryAbove: onRetryAbove ?? () {},
          onRetryBelow: onRetryBelow ?? () {},
          onRetryCurrent: onRetryCurrent ?? () {},
          onScrollEnd: onScrollEnd ?? () {},
        ),
      ),
    );
  }

  testWidgets('向上前插章节时滚动偏移与锚点内容位置均保持不变（center 锚点生效）', (
    WidgetTester tester,
  ) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};
    var sequence = <int>[3, 4];

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: sequence,
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    // 锚点顶部即偏移原点
    expect(controller.offset, equals(0.0));
    final anchorTopBefore = tester.getTopLeft(find.text('第4章')).dy;

    // 模拟向上加载到上一章：序列前插，锚点保持不变
    sequence = <int>[2, 3, 4];
    await tester.pumpWidget(
      buildView(
        sequence: sequence,
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    // 核心断言 1：偏移量仍为 0，**没有发生任何补偿跳转**
    // （旧实现会在这里 jumpTo 一个等于新块高度的正向偏移，并先漏出一帧错位画面）
    expect(controller.offset, equals(0.0));
    // 核心断言 2：用户正在看的锚点内容纹丝不动 —— 这才是真正的「无跳变」
    expect(tester.getTopLeft(find.text('第4章')).dy, equals(anchorTopBefore));
  });

  testWidgets('向上区域随前插变长（minScrollExtent 更负），当前偏移不受影响', (
    WidgetTester tester,
  ) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};
    var sequence = <int>[3, 4];

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: sequence,
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    final minBefore = controller.position.minScrollExtent;
    expect(minBefore, lessThanOrEqualTo(0.0));

    sequence = <int>[0, 1, 2, 3, 4];
    await tester.pumpWidget(
      buildView(
        sequence: sequence,
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(controller.position.minScrollExtent, lessThan(minBefore));
    expect(controller.offset, equals(0.0));
  });

  testWidgets('锚点之前的章节按「越靠前离锚点越远」顺序渲染', (WidgetTester tester) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[1, 2, 3, 4],
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
      ),
    );
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

    await tester.pumpWidget(
      buildView(
        sequence: sequence,
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    final nextTopBefore = tester.getTopLeft(find.text('第5章')).dy;

    sequence = <int>[0, 1, 2, 3, 4];
    await tester.pumpWidget(
      buildView(
        sequence: sequence,
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    // 锚点下方的章节布局与锚点同属一个坐标区，完全不受向上插入影响
    expect(tester.getTopLeft(find.text('第5章')).dy, equals(nextTopBefore));
  });

  testWidgets('滚动停止时回调 onScrollEnd（供上层精确同步屏中线与窗口裁剪）', (
    WidgetTester tester,
  ) async {
    final controller = ScrollController();
    final centerKey = GlobalKey();
    final blockKeys = <int, GlobalKey>{};
    var endedCount = 0;

    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[1, 2, 3, 4, 5, 6],
        anchorIndex: 3,
        centerKey: centerKey,
        blockKeys: blockKeys,
        controller: controller,
        onScrollEnd: () => endedCount++,
      ),
    );
    await tester.pumpAndSettle();

    // 前置条件：锚点上方有内容 → 可向负方向滚动（否则下面的 jumpTo 不会产生滚动通知）
    expect(controller.position.minScrollExtent, lessThan(0.0));

    controller.jumpTo(controller.position.minScrollExtent);
    await tester.pumpAndSettle();

    expect(endedCount, greaterThan(0), reason: '滚动停止必须上报一次，用于补齐降频同步');
  });

  testWidgets('下方续载失败：显示重试入口，且不得误报「已是最后一章」', (WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[3, 4],
        anchorIndex: 3,
        centerKey: GlobalKey(),
        blockKeys: <int, GlobalKey>{},
        controller: controller,
        failedBelow: true,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('下一章加载失败 · 点击重试'), findsOneWidget);
    // 核心回归：加载失败 ≠ 全书读完（此前会向用户误报「已是最后一章」）
    expect(find.text('— 已是最后一章 —'), findsNothing);
    // 失败时也不该继续显示续载占位
    expect(find.text('正在续载下一章...'), findsNothing);
  });

  testWidgets('点击下方重试入口回调上层', (WidgetTester tester) async {
    final controller = ScrollController();
    var retried = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[3, 4],
        anchorIndex: 3,
        centerKey: GlobalKey(),
        blockKeys: <int, GlobalKey>{},
        controller: controller,
        failedBelow: true,
        onRetryBelow: () => retried++,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('下一章加载失败 · 点击重试'));
    await tester.pump();
    expect(retried, equals(1));
  });

  testWidgets('确实没有下一章时仍照常显示「已是最后一章」', (WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[3, 4],
        anchorIndex: 3,
        centerKey: GlobalKey(),
        blockKeys: <int, GlobalKey>{},
        controller: controller,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('— 已是最后一章 —'), findsOneWidget);
    expect(find.text('下一章加载失败 · 点击重试'), findsNothing);
  });

  testWidgets('上方前插失败：顶部显示重试入口并回调上层', (WidgetTester tester) async {
    final controller = ScrollController();
    var retried = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[3, 4],
        anchorIndex: 3,
        centerKey: GlobalKey(),
        blockKeys: <int, GlobalKey>{},
        controller: controller,
        failedAbove: true,
        onRetryAbove: () => retried++,
      ),
    );
    await tester.pumpAndSettle();

    // 顶部提示位于锚点之上，滚到最顶才可见
    controller.jumpTo(controller.position.minScrollExtent);
    await tester.pumpAndSettle();

    expect(find.text('上一章加载失败 · 点击重试'), findsOneWidget);
    await tester.tap(find.text('上一章加载失败 · 点击重试'));
    await tester.pump();
    expect(retried, equals(1));
  });

  testWidgets('当前章正文未就绪：块内就地占位（保留阅读框架，不整屏切换）', (WidgetTester tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[3],
        anchorIndex: 3,
        centerKey: GlobalKey(),
        blockKeys: <int, GlobalKey>{},
        controller: controller,
        // 当前章正文尚未到达
        contentOf: (index) => '',
      ),
    );
    // 占位内含无限转圈动画 → 只能有限帧推进，pumpAndSettle 会超时
    await tester.pump();
    await tester.pump();

    // 章节标题仍在（阅读框架不丢），加载文案与横向桥接页同源
    expect(find.text('第4章'), findsOneWidget);
    expect(find.text('正在加载本章'), findsOneWidget);
    // 未就绪 ≠ 失败：不应出现重试入口
    expect(find.text('本章正文加载失败 · 点击重试'), findsNothing);
  });

  testWidgets('当前章抓取失败：块内给出重试入口并回调上层', (WidgetTester tester) async {
    final controller = ScrollController();
    var retried = 0;
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      buildView(
        sequence: <int>[3],
        anchorIndex: 3,
        centerKey: GlobalKey(),
        blockKeys: <int, GlobalKey>{},
        controller: controller,
        contentOf: (index) => '',
        currentFailed: true,
        onRetryCurrent: () => retried++,
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('正在加载本章'), findsNothing);
    expect(find.text('本章正文加载失败 · 点击重试'), findsOneWidget);

    await tester.tap(find.text('本章正文加载失败 · 点击重试'));
    await tester.pump();
    expect(retried, equals(1));
  });
}
