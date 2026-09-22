import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_chapter_image_pipeline.dart';
import 'package:fluxforge/features/media/shared/media_download_actions.dart';

/// 图片类作品的下载产物收集
///
/// 核心回归：**章节形态不能再把章节页地址当成图片**（改造前会下载一堆 HTML 页面）。
void main() {
  final rule = Rule(
    id: 7,
    name: '测试图源',
    baseUrl: 'https://example.com',
    type: 'comic',
    code: '// noop',
  );

  MediaEpisode ep(String url) => MediaEpisode(title: url, url: url);

  MediaDetailData data({
    List<String> images = const [],
    List<MediaEpisode> chapters = const [],
  }) => MediaDetailData(
    title: '测试作品',
    url: 'https://example.com/detail/1',
    cover: '',
    imageList: images,
    chapters: chapters,
  );

  test('图集形态：直接收集图片，一次解析都不发', () async {
    var calls = 0;
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async {
        calls++;
        return null;
      },
    );

    final urls = await MediaDownloadActions.collectComicImageUrls(
      data(images: ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg']),
      rule: rule,
      pipeline: pipeline,
    );

    expect(urls, ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg']);
    expect(calls, 0);
  });

  test('章节形态：逐章展开为真实图片地址', () async {
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async {
        final id = url.split('/').last;
        return {
          'items': ['https://cdn.a/$id-1.jpg', 'https://cdn.a/$id-2.jpg'],
        };
      },
    );

    final urls = await MediaDownloadActions.collectComicImageUrls(
      data(
        chapters: [
          ep('https://example.com/chapter/53996'),
          ep('https://example.com/chapter/53997'),
        ],
      ),
      rule: rule,
      pipeline: pipeline,
    );

    expect(urls, [
      'https://cdn.a/53996-1.jpg',
      'https://cdn.a/53996-2.jpg',
      'https://cdn.a/53997-1.jpg',
      'https://cdn.a/53997-2.jpg',
    ]);
    expect(
      urls.any((u) => u.contains('/chapter/')),
      isFalse,
      reason: '章节页地址绝不能进入下载产物',
    );
  });

  test('章节解析失败时跳过该章，其余章仍入队', () async {
    final pipeline = ComicChapterImagePipeline(
      parser: (r, url) async {
        if (url.endsWith('/53997')) throw Exception('这一章挂了');
        return {
          'items': ['https://cdn.a/ok.jpg'],
        };
      },
    );

    final urls = await MediaDownloadActions.collectComicImageUrls(
      data(
        chapters: [
          ep('https://example.com/chapter/53996'),
          ep('https://example.com/chapter/53997'),
        ],
      ),
      rule: rule,
      pipeline: pipeline,
    );

    expect(urls, ['https://cdn.a/ok.jpg']);
  });

  test('缺规则时退回直接收集（不抛错）', () async {
    final urls = await MediaDownloadActions.collectComicImageUrls(
      data(chapters: [ep('https://example.com/chapter/1')]),
    );

    expect(urls, isEmpty);
  });
}
