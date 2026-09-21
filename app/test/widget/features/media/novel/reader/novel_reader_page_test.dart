import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/chapter_content_pipeline.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/novel_reader_page.dart';

void main() {
  testWidgets(
    'NovelReaderPage renders chapter content, supports SelectionArea and catalog drawer cleanly',
    (WidgetTester tester) async {
      final testChapters = [
        const NovelChapter(
          title: '第1章 宇宙闪烁',
          content: '第一行测试小说正文，宏伟的宇宙规律向人类眨了眨眼睛。\n\n第二行测试小说正文，物理学的大厦轰然作响。',
        ),
        const NovelChapter(title: '第2章 科学边界', content: '这是第二章的测试内容。'),
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

      // 1. 验证包含 SelectionArea (保证文本可长按划词自由选区复制)
      expect(find.byType(SelectionArea), findsWidgets);

      // 横向分页与纵向长卷已统一选择实现：外层一个 SelectionArea + 内部纯 Text，
      // 不再逐页创建 SelectableText（每页都会建立独立的 EditableText 与选择容器）
      expect(find.byType(SelectableText), findsNothing);

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
    },
  );

  testWidgets('连续跨章翻页多次后仍能正确渲染（分页切片按滑窗裁剪不影响阅读）', (WidgetTester tester) async {
    // 每章正文很短 → 一章一页，点击右侧区域即跨一章，便于稳定地连续换章
    final chapters = List<NovelChapter>.generate(
      8,
      (i) => NovelChapter(title: '第${i + 1}章', content: '第${i + 1}章正文内容。'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(bookTitle: '滑窗切片裁剪测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 连续向前读 5 章：渲染窗口不断右移，最早的分页切片会被裁剪
    for (int i = 0; i < 5; i++) {
      await tester.tapAt(const Offset(700, 300));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    expect(tester.takeException(), isNull);
    // 裁剪后仍必须能渲染正文 —— 若误伤当前章切片，会退化成「正文排版中...」占位
    expect(find.textContaining('正文内容'), findsWidgets);
  });

  testWidgets(
    'NovelReaderPage renders empty state instead of sample chapters when no chapters provided',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: NovelReaderPage(bookTitle: '空章节测试')),
      );
      await tester.pump(const Duration(milliseconds: 200));

      // 严禁渲染任何示例假章节，必须展示空态引导
      expect(find.text('暂无章节内容'), findsOneWidget);
      expect(find.textContaining('科学边界'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'NovelReaderPage tap zones turn pages on sides and toggle menu in center',
    (WidgetTester tester) async {
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
    },
  );

  testWidgets(
    'NovelReaderPage error state keeps retry button clickable without tap-zone interception',
    (WidgetTester tester) async {
      const chapters = [
        NovelChapter(
          title: '第1章 断链',
          url: 'https://example.com/broken-chapter',
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(
          home: NovelReaderPage(bookTitle: '错误态测试', chapters: chapters),
        ),
      );
      // 未绑定解析规则 → 正文抓取失败，进入错误态
      await tester.pump(const Duration(milliseconds: 400));

      // 横向模式不再整屏切错误页：失败由窗内桥接页原地表达，重试入口在页内
      expect(find.text('重新加载本章'), findsOneWidget);

      // 点击重试按钮：必须命中按钮本身，而不是被三区热层抢走变成「呼出菜单」
      await tester.tap(find.text('重新加载本章'));
      await tester.pump(const Duration(milliseconds: 300));

      // 控制栏未被呼出，证明错误态下全屏热层已撤除
      expect(find.byIcon(Ionicons.reorderFourOutline), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('NovelReaderPage catalog order toggle flips chapter list order', (
    WidgetTester tester,
  ) async {
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
        .getTopLeft(
          find.descendant(of: find.byType(Drawer), matching: find.text(title)),
        )
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

  testWidgets(
    'NovelReaderPage horizontal bridge and seek synchronization does not accidentally trigger chapter retreat',
    (WidgetTester tester) async {
      const chapters = [
        NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
        NovelChapter(
          title: '第2章 发展',
          content: '第二章长篇正文，第一段描述。\n\n第二章第二段描述。\n\n第二章第三段描述。',
        ),
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
    },
  );

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

  testWidgets('横向跨章正文未就绪时不得整屏顶掉 PageView（占位页原地接住并给出重试）', (
    WidgetTester tester,
  ) async {
    const chapters = [
      NovelChapter(title: '第1章 起点', content: '第一章正文内容。'),
      // 未绑定解析规则 → 该章抓取必然失败，用于稳定复现「跨章未就绪」
      NovelChapter(title: '第2章 终点', url: 'https://example.com/chapter-2'),
    ];

    await tester.pumpWidget(
      const MaterialApp(
        home: NovelReaderPage(bookTitle: '跨章未就绪测试', chapters: chapters),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(PageView), findsOneWidget);

    // 滑入第 2 章（未就绪）
    tester.widget<PageView>(find.byType(PageView)).controller!.jumpToPage(1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 核心断言：必须仍由同一个 PageView 承载 ——
    // 整屏切到加载 / 错误视图会销毁 PageView（控制器失去 clients → 重建后跳页），
    // 这正是「章节最后一页翻到下一章时直接跳过去」的成因。
    expect(find.byType(PageView), findsOneWidget);
    // 占位页给出该章的失败说明与重试入口（否则该章会永远转圈）
    expect(find.text('重新加载本章'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('上一章正文延迟到达时，往前翻必须落到其最后一页（而不是章首）', (WidgetTester tester) async {
    // 第 1 章正文用可控 Completer 延迟交付，复现「预取晚于首次分页」的真实时序：
    // 进入第 2 章时第 1 章尚未就绪，其正文在用户回退之前才到达。
    final completer = Completer<Object?>();
    final chapters = [
      const NovelChapter(title: '第1章 起点', url: 'https://example.com/chapter-1'),
      NovelChapter(
        title: '第2章 终点',
        content: List.generate(
          12,
          (i) => '第 ${i + 1} 段正文内容，用于撑出多页排版。',
        ).join('\n\n'),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '延迟到达测试',
          chapters: chapters,
          initialChapterIndex: 1,
          rule: Rule(
            id: 1,
            name: '测试书源',
            baseUrl: 'https://example.com',
            type: 'novel',
            code: '',
          ),
          parseRule: (rule, url) => completer.future,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    // 第 1 章正文此刻尚未到达 → 它在滑窗里只占 1 个占位页
    expect(find.byType(PageView), findsOneWidget);

    // 预取完成：第 1 章正文到达 → 补齐分片，窗口内页索引随之平移
    completer.complete({
      'content': List.generate(
        30,
        (i) => '第 1 章第 ${i + 1} 段正文，用于撑出多页。',
      ).join('\n\n'),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // 模拟用户从第 2 章第一页往前翻（回退到上一章最后一页）
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    controller.jumpToPage(controller.page!.round() - 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('第 1 / 2 章'), findsOneWidget);

    // 核心断言：落点为第 1 章最后一页 → 底部「当前页 / 总页数」两侧数值相等。
    // 若落点漂成章首（旧缺陷），此处为「1 / N」。
    final pageLabels = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => RegExp(r'^\d+ / \d+$').hasMatch(s))
        .toList();
    expect(pageLabels, isNotEmpty, reason: '已进入第 1 章正文页，底部应展示页码');

    final parts = pageLabels.first.split(' / ');
    expect(parts[1], isNot('1'), reason: '第 1 章应为多页，否则本用例失去意义');
    expect(parts[0], parts[1], reason: '往前翻必须落到上一章最后一页，而不是章首');

    expect(tester.takeException(), isNull);
  });

  testWidgets('跨章拖拽过半不得中途跳章，松手后才落地（双向）', (WidgetTester tester) async {
    // 4 章、每章一页：从第 2 章（下标 1）进入，窗口为 [0,1,2]，
    // 于是向前跨到第 3 章时窗口会整体左移 —— 这正是旧实现「滑到一半被扯走」的场景
    final chapters = List<NovelChapter>.generate(
      4,
      (i) => NovelChapter(title: '第${i + 1}章', content: '第${i + 1}章正文内容。'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '拖拽跨章测试',
          chapters: chapters,
          initialChapterIndex: 1,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第 2 / 4 章'), findsOneWidget);

    // 慢慢左拖过半页：分步移动模拟真实手速（单次大跳可能被手势竞技场判定为斜率不足）
    // 关键：PageView 的 onPageChanged 在拖过半页那一刻就会触发（尚未松手）
    final forward = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (int i = 0; i < 10; i++) {
      await forward.moveBy(const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    // 防呆：确认拖拽真的被 PageView 接管（否则下面的「不得跨章」会空转通过）
    final pageDuringDrag = tester
        .widget<PageView>(find.byType(PageView))
        .controller!
        .page!;
    expect(pageDuringDrag, greaterThan(1.0), reason: '拖拽应已过半页');

    // 核心断言：没松手就不许切章。旧实现会在此时平移滑窗 + jumpToPage，
    // 表现为「章节最后一页滑到一半被强制跳到下一章」
    expect(find.text('第 2 / 4 章'), findsOneWidget, reason: '拖拽中不得跨章');

    await forward.up();
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 4 章'), findsOneWidget);

    // 反向：从第 3 章第一页往回拖，同样不得中途跳回第 2 章
    final backward = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (int i = 0; i < 10; i++) {
      await backward.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(find.text('第 3 / 4 章'), findsOneWidget, reason: '回拖中不得跨章');

    await backward.up();
    await tester.pumpAndSettle();
    expect(find.text('第 2 / 4 章'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('点击翻页跨章：动画未走完时不得切章（停下后才落地）', (WidgetTester tester) async {
    // 这条路径与拖拽不同：点击右侧走的是 controller.nextPage(220ms) 动画。
    // 「已经松手」≠「动画走完」—— 若按前者判定，动画继续跑的时候平移滑窗同样会扯走画面。
    final chapters = List<NovelChapter>.generate(
      4,
      (i) => NovelChapter(title: '第${i + 1}章', content: '第${i + 1}章正文内容。'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '点击跨章测试',
          chapters: chapters,
          initialChapterIndex: 1,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('第 2 / 4 章'), findsOneWidget);

    // 点击右侧 1/3 区域 → 翻页动画启动
    await tester.tapAt(const Offset(700, 300));
    await tester.pump();
    // 动画过半：onPageChanged 已经触发（页码按四舍五入变化），但动画远未结束
    await tester.pump(const Duration(milliseconds: 110));

    expect(find.text('第 2 / 4 章'), findsOneWidget, reason: '翻页动画未走完不得切章');

    // 动画结束 → 此刻才做切章 + 平移滑窗 + 索引补偿
    await tester.pumpAndSettle();
    expect(find.text('第 3 / 4 章'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('拖拽跨出去再滑回原位后松手，必须停在当前章（不得消费陈旧的跨章意图）', (WidgetTester tester) async {
    final chapters = List<NovelChapter>.generate(
      5,
      (i) => NovelChapter(title: '第${i + 1}章', content: '第${i + 1}章正文内容。'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '拖回原位测试',
          chapters: chapters,
          initialChapterIndex: 2,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第 3 / 5 章'), findsOneWidget);

    // 向左拖过半页：落点已指向第 4 章，但手指不松
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (int i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('第 3 / 5 章'), findsOneWidget, reason: '拖拽中不得跨章');

    // 原路滑回：落点重新指回当前章第一页
    for (int i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();

    // 核心断言：松手必须停在当前章。
    // 旧实现只在跨章落点时记录意图，「滑回原处」不会覆盖它 → 松手仍消费最初那次
    // 跨章意图，把界面扯到第 4 章（用户看到的正是「滑回来又自己跳走」）。
    expect(find.text('第 3 / 5 章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('已离线下载的邻居章进入窗口即被静默预载：滑过去直接是正文，不停在就绪占位页', (
    WidgetTester tester,
  ) async {
    // 第 1 章正文只存在于沙盒（offlineStore），网络抓取不可用 ——
    // 于是「滑过去能看到正文」只能来自「离线 → 内存 → 分片」这条预载通路。
    final store = _FakeOfflineStore({
      0: List.generate(
        20,
        (i) => '第 1 章第 ${i + 1} 段正文内容，用于撑出多页。',
      ).join('\n\n'),
    });
    final chapters = [
      const NovelChapter(title: '第1章 起点', url: 'https://example.com/chapter-1'),
      NovelChapter(
        title: '第2章 终点',
        content: List.generate(
          8,
          (i) => '第 2 章第 ${i + 1} 段正文内容。',
        ).join('\n\n'),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '离线预载测试',
          chapters: chapters,
          initialChapterIndex: 1,
          offlineBookId: 'book-offline-1',
          offlineStore: store,
          rule: Rule(
            id: 1,
            name: '测试书源',
            baseUrl: 'https://example.com',
            type: 'novel',
            code: '',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 预载已把第 1 章正文读进内存并完成分片 → 窗口内不再有未就绪占位页
    expect(find.text('正在加载上一章'), findsNothing);
    expect(find.text('正文已就绪，即将无缝续读'), findsNothing);

    // 滑到上一章：必须直接是正文，而不是「已就绪待分片」的占位页
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    controller.jumpToPage(controller.page!.round() - 1);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('第 1 / 2 章'), findsOneWidget);
    expect(find.textContaining('第 1 章第'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('拖拽途中邻居章正文到达（页索引整体平移）不得打断手势或提前切章', (
    WidgetTester tester,
  ) async {
    final completer = Completer<Object?>();
    final chapters = [
      const NovelChapter(title: '第1章 起点', url: 'https://example.com/chapter-1'),
      NovelChapter(
        title: '第2章 终点',
        content: List.generate(
          10,
          (i) => '第 2 章第 ${i + 1} 段正文内容。',
        ).join('\n\n'),
      ),
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: NovelReaderPage(
          bookTitle: '拖拽中到货测试',
          chapters: chapters,
          initialChapterIndex: 1,
          rule: Rule(
            id: 1,
            name: '测试书源',
            baseUrl: 'https://example.com',
            type: 'novel',
            code: '',
          ),
          parseRule: (rule, url) => completer.future,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('第 2 / 2 章'), findsOneWidget);

    // 从第 2 章第一页往右拖向上一章，拖过半页后保持按住不松
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    for (int i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    // 防呆：确认手势真被 PageView 接管且已越过半页 ——
    // 否则下面「不得切章」会空转通过（页码不跨界时 onPageChanged 根本不触发）
    expect(
      tester.widget<PageView>(find.byType(PageView)).controller!.page,
      lessThan(0.5),
      reason: '拖拽应已越过半页',
    );
    expect(find.text('第 2 / 2 章'), findsOneWidget, reason: '拖拽中不得切章');

    // 按住不放的同时，上一章正文到达 → 分片补齐 → 窗口总页数变化
    completer.complete({
      'content': List.generate(
        30,
        (i) => '第 1 章第 ${i + 1} 段正文内容。',
      ).join('\n\n'),
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 核心断言：页索引平移不得触发程序化跳页把人扯走 ——
    // 旧实现在拖拽中 jumpToPage，既改写了用户正按着的位置，也伪造出 ScrollEnd
    // 提前消费落点（表现为「滑到一半被强制跳章」）
    expect(find.text('第 2 / 2 章'), findsOneWidget, reason: '分片平移不得在拖拽中切章');

    await gesture.up();
    await tester.pumpAndSettle();

    // 松手才落地：用户拖的是上一章方向 → 落到第 1 章
    expect(find.text('第 1 / 2 章'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

/// 内存版离线章节存储替身（测试用）
///
/// 用于在无沙盒 / 无网络环境下构造「该章已离线下载」这一前置条件。
class _FakeOfflineStore implements OfflineChapterStore {
  _FakeOfflineStore(this._contents);

  final Map<int, String> _contents;

  @override
  bool isDownloaded(String bookId, int index) => _contents.containsKey(index);

  @override
  int downloadedCount(String bookId) => _contents.length;

  @override
  Future<String?> read(String bookId, int index) async => _contents[index];

  @override
  Future<bool> save({
    required Rule rule,
    required String bookId,
    required String title,
    required List<MediaEpisode> chapters,
    required int index,
    required String content,
  }) async {
    _contents[index] = content;
    return true;
  }
}
