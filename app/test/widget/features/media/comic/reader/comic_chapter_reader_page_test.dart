import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/comic/reader/comic_chapter_reader_page.dart';
import 'package:fluxforge/features/media/comic/reader/comic_reader_page.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_chapter_image_pipeline.dart';

/// 漫画阅读宿主：章 → 图片的解析与渲染
///
/// 这是"章节式漫画能不能读"的关键路径（此前章节页地址被直接当图片喂给阅读器）。
void main() {
  setUp(() {
    // 宿主会登记阅读进度，需保证服务已注册
    if (!getIt.isRegistered<PlayHistoryService>()) {
      getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
    }
  });

  final rule = Rule(
    id: 1,
    name: '测试图源',
    baseUrl: 'https://example.com',
    type: 'comic',
    code: '// noop',
  );

  MediaEpisode ep(String url, String title) =>
      MediaEpisode(title: title, url: url);

  Future<void> pumpHost(
    WidgetTester tester, {
    required ComicChapterImagePipeline pipeline,
    List<MediaEpisode>? chapters,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ComicChapterReaderPage(
          title: '测试漫画',
          mediaId: 'https://example.com/detail/1',
          chapters:
              chapters ??
              [
                ep('https://example.com/chapter/1', '第1话'),
                ep('https://example.com/chapter/2', '第2话'),
              ],
          rule: rule,
          pipeline: pipeline,
          initialContinuousMode: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
  }

  testWidgets('章节形态：解析当前章后渲染阅读器，且标题带上章名', (tester) async {
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async => {
        'items': ['https://cdn.a/${url.split('/').last}-1.jpg'],
      },
    );

    await pumpHost(tester, pipeline: pipeline);

    expect(find.byType(ComicReaderPage), findsOneWidget);
    expect(find.textContaining('第1话'), findsOneWidget);
    // 当前章 + 预取的相邻章（第 2 话）都应已入缓存
    expect(pipeline.cachedCount, 2);
  });

  testWidgets('解析失败：给出失败态与重试入口，而不是空白页', (tester) async {
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async => throw Exception('解析炸了'),
    );

    await pumpHost(tester, pipeline: pipeline);

    expect(find.byType(ComicReaderPage), findsNothing);
    expect(find.textContaining('解析失败'), findsOneWidget);
    expect(find.text('重新解析'), findsOneWidget);
  });

  testWidgets('图集形态（chapters 为空）：直接用 detail 的图片，不发解析请求', (tester) async {
    var calls = 0;
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async {
        calls++;
        return null;
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ComicChapterReaderPage(
          title: '测试图集',
          mediaId: 'https://example.com/detail/2',
          imageList: const ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg'],
          rule: rule,
          pipeline: pipeline,
          initialContinuousMode: false,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ComicReaderPage), findsOneWidget);
    expect(calls, 0, reason: '图集形态图片已给全，不应该再走解析');
  });

  testWidgets('图集形态：initialPage 覆盖续读页 —— 点第 N 张就开在第 N 张', (tester) async {
    final pipeline = ComicChapterImagePipeline(parser: (r, url) async => null);
    final images = List.generate(10, (i) => 'https://cdn.a/${i + 1}.jpg');

    // 先写一条「上次读到第 2 张」的续读记录，制造与点击目标的冲突
    await playHistoryService.upsert(
      PlayRecord(
        id: 'https://example.com/detail/3',
        title: '测试图集',
        mediaType: 'comic',
        pageIndex: 1,
        updatedAt: DateTime(2026, 9, 24),
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.darkTheme,
        home: ComicChapterReaderPage(
          title: '测试图集',
          mediaId: 'https://example.com/detail/3',
          imageList: images,
          rule: rule,
          pipeline: pipeline,
          initialPage: 6,
          initialContinuousMode: false,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final reader = tester.widget<ComicReaderPage>(find.byType(ComicReaderPage));
    expect(reader.initialIndex, 6, reason: '调用方指定的是用户的明确动作（点了第 7 张），必须压过续读页');
    expect(find.text('7 / 10'), findsOneWidget);
  });

  testWidgets('目录入口：可跳到任意一章', (tester) async {
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async => {
        'items': ['https://cdn.a/${url.split('/').last}-1.jpg'],
      },
    );
    await pumpHost(tester, pipeline: pipeline);

    await tester.tap(find.byTooltip('目录'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('章节目录'), findsOneWidget);
    expect(find.text('第2话'), findsOneWidget);

    await tester.tap(find.text('第2话'));
    await tester.pump();
    // 等底部面板退场动画走完，否则面板里的"第2话"仍在树上
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('第2话'), findsOneWidget);
  });

  testWidgets('逐页进度：再次打开回到上次读到的页', (tester) async {
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async => {
        'items': [
          'https://cdn.a/1.jpg',
          'https://cdn.a/2.jpg',
          'https://cdn.a/3.jpg',
        ],
      },
    );

    // 详情页会先 upsert 基础记录；这里模拟"上次读到第 3 页"（index = 2）
    playHistoryService.upsert(
      PlayRecord(
        id: 'https://example.com/detail/1',
        title: '测试漫画',
        mediaType: 'comic',
        episodeIndex: 0,
        pageIndex: 2,
        updatedAt: DateTime.now(),
      ),
    );

    await pumpHost(tester, pipeline: pipeline);

    expect(
      find.textContaining('3 / 3'),
      findsOneWidget,
      reason: '应恢复到记录里的第 3 页，而不是从第 1 页开始',
    );
  });
}
