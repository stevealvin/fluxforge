import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/novel_reader_page.dart';

void main() {
  testWidgets('NovelReaderPage renders chapter content, supports SelectionArea and catalog drawer cleanly', (WidgetTester tester) async {
    final testChapters = [
      const NovelChapter(
        title: '第1章 宇宙闪烁',
        content: '第一行测试小说正文，宏伟的宇宙规律向人类眨了眨眼睛。\n\n第二行测试小说正文，物理学的大厦轰然作响。',
      ),
      const NovelChapter(
        title: '第2章 科学边界',
        content: '这是第二章的测试内容。',
      ),
    ];

    // 渲染 NovelReaderPage
    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '三体测试版',
          initialChapterIndex: 0,
          chapters: testChapters,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 1. 验证包含了 SelectableText (保证文本可长按划词自由选区复制)
    expect(find.byType(SelectableText), findsWidgets);

    // 2. 验证章节标题和内容切片已正常展示，且不是“正在加载”
    expect(find.text('第1章 宇宙闪烁'), findsOneWidget);
    expect(find.textContaining('第一行测试小说正文'), findsOneWidget);

    // 3. 点击呼出控制栏面板
    await tester.tap(find.byKey(const ValueKey('reader_gesture_area')));
    await tester.pump(const Duration(milliseconds: 200));

    // 验证控制栏出现章节目录按钮 (Ionicons.reorderFourOutline)
    expect(find.byIcon(Ionicons.reorderFourOutline), findsWidgets);

    // 4. 点击目录按钮，验证左侧抽屉打开、章节列表渲染且缓存状态图标正常
    await tester.tap(find.byIcon(Ionicons.reorderFourOutline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 目录应列出后续章节；状态图标已统一为「沙盒离线下载」单一语义：
    // 未下载章节展示云端下载入口（不再出现「已缓存」对勾，避免误以为可断网阅读）
    expect(find.text('第2章 科学边界'), findsWidgets);
    expect(find.byIcon(Ionicons.cloudDownloadOutline), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage renders empty state instead of sample chapters when no chapters provided', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '空章节测试'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 200));

    // 严禁渲染任何示例假章节，必须展示空态引导
    expect(find.text('暂无章节内容'), findsOneWidget);
    expect(find.textContaining('科学边界'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage tap zones turn pages on sides and toggle menu in center', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 终点', content: '第二章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '分区点击测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 1. 点击右侧 1/3 区域：本章仅一页 → 应无缝续读下一章
    // 说明：翻页动画需要一帧注册 ticker，pump() 先推一帧再推进 220ms 动画
    await tester.tapAt(const Offset(700, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('第2章 终点'), findsWidgets);

    // 2. 点击中间 1/3 区域：应呼出控制栏（出现目录按钮）
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byIcon(Ionicons.reorderFourOutline), findsWidgets);

    // 3. 点击左侧 1/3 区域：本章第一页 → 应无缝倒序回退到上一章
    // （与第 1 步相同：翻页动画需要 pump() 先推一帧注册 ticker）
    await tester.tapAt(const Offset(100, 300));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('第1章 起点'), findsWidgets);

    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage error state keeps retry button clickable without tap-zone interception', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 断链', url: 'https://example.com/broken-chapter'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '错误态测试', chapters: chapters),
      ),
    );
    // 未绑定解析规则 → 正文抓取失败，进入错误态
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('重试加载'), findsOneWidget);

    // 点击重试按钮：必须命中按钮本身，而不是被三区热层抢走变成「呼出菜单」
    await tester.tap(find.text('重试加载'));
    await tester.pump(const Duration(milliseconds: 300));

    // 控制栏未被呼出，证明错误态下全屏热层已撤除
    expect(find.byIcon(Ionicons.reorderFourOutline), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage catalog order toggle flips chapter list order', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 发展', content: '第二章正文内容。'),
      NovelChapter(title: '第3章 终点', content: '第三章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '目录排序测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 呼出控制栏并打开章节目录（左抽屉）
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.byIcon(Ionicons.reorderFourOutline).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    double catalogItemTop(String title) => tester
        .getTopLeft(find.descendant(of: find.byType(Drawer), matching: find.text(title)))
        .dy;

    // 默认正序：第 1 章在第 3 章上方
    expect(catalogItemTop('第1章 起点'), lessThan(catalogItemTop('第3章 终点')));

    // 切换为倒序：第 3 章应升到最上方，按钮文案同步变更
    await tester.tap(find.text('正序'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('倒序'), findsOneWidget);
    expect(catalogItemTop('第3章 终点'), lessThan(catalogItemTop('第1章 起点')));

    expect(tester.takeException(), isNull);
  });

  testWidgets('NovelReaderPage horizontal bridge and seek synchronization does not accidentally trigger chapter retreat', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 发展', content: '第二章长篇正文，第一段描述。\n\n第二章第二段描述。\n\n第二章第三段描述。'),
      NovelChapter(title: '第3章 终点', content: '第三章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(
          bookTitle: '桥接同步测试',
          chapters: chapters,
          initialChapterIndex: 1, // 直接从第 2 章开始
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 验证初始状态正确处于第 2 章
    expect(find.text('第2章 发展'), findsWidgets);

    // 呼出控制栏
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 250));

    // 找到章内进度条并拖拽至起始端
    final sliderFinder = find.byType(Slider);
    if (sliderFinder.evaluate().isNotEmpty) {
      await tester.drag(sliderFinder.first, const Offset(-300, 0));
      await tester.pump(const Duration(milliseconds: 350));
      // 必须依然保持在第 2 章，严禁误触发章首桥接页退回第 1 章
      expect(find.text('第2章 发展'), findsWidgets);
    }

    expect(tester.takeException(), isNull);
  });

  testWidgets('正文已就绪时滑到章末衔接页必须无缝续读下一章，不停留过渡页', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 终点', content: '第二章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '无缝续读测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第1章 起点'), findsWidgets);
    expect(find.text('第 1 / 2 章'), findsOneWidget);

    // 说明 1：测试环境下三区热层会让 PageView 收不到拖拽手势，
    // 因此直接驱动 PageController 翻到章末衔接页（页码链路与真实滑动完全一致）。
    // 说明 2：必须用 jumpToPage(页码)，jumpTo 的参数是**像素**，传页码会静默只偏移几像素。
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
    await tester.pump();
    // 只推进两帧（≈32ms），远小于原先 260ms 的强制过渡延迟
    await tester.pump(const Duration(milliseconds: 32));

    // 核心断言 1：页码归属已切到第 2 章。
    // 必须用页码而非章节标题断言 —— 衔接页的 chapterTitle 也是「第2章 终点」，
    // 只看标题会让「停在衔接页」被误判为「已切章」。
    expect(find.text('第 2 / 2 章'), findsOneWidget);
    // 核心断言 2：正文已就绪时必须与点击翻页完全一致 —— 零等待直接进入下一章
    expect(find.text('第2章 终点'), findsWidgets);
    // 过渡页文案不应在屏幕上停留（下一章已就绪，无需任何加载提示）
    expect(find.text('正在进入下一章'), findsNothing);

    expect(tester.takeException(), isNull);
  });

  testWidgets('正文已就绪时滑到章首衔接页必须无缝回退上一章最后一页', (WidgetTester tester) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      NovelChapter(title: '第2章 终点', content: '第二章正文内容。'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '无缝回溯测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 先续读到第 2 章，使 PageView 稳定停在第 2 章正文页
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));
    expect(find.text('第 2 / 2 章'), findsOneWidget);

    // 再从第 2 章正文页滑入章首衔接页（第 0 页）
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 32));

    // 无缝回退到第 1 章（最后一页），且不留过渡页
    expect(find.text('第 1 / 2 章'), findsOneWidget);
    expect(find.text('第1章 起点'), findsWidgets);
    expect(find.text('正在返回上一章'), findsNothing);

    expect(tester.takeException(), isNull);
  });
}
