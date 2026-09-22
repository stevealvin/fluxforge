import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_chapter_image_pipeline.dart';

/// 「章节 → 图片」解析管线
///
/// 锁定三件事：**结构容忍**（规则作者常见几种写法都能认）、**失败不缓存**
/// （临时失败不该让这一章在本次阅读里永远翻不出来）、**并发合流**（同一章只解析一次）。
void main() {
  final rule = Rule(
    id: 1,
    name: '测试图源',
    baseUrl: 'https://example.com',
    type: 'comic',
    code: '// noop',
  );

  MediaEpisode chapter(String url, {String title = '第1话'}) =>
      MediaEpisode(title: title, url: url);

  group('extractImageUrls 形态容忍', () {
    test('items 字符串数组（推荐写法）', () {
      expect(
        ComicChapterImagePipeline.extractImageUrls({
          'items': ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg'],
        }),
        ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg'],
      );
    });

    test('images 键 / 直接返回数组 / 元素是对象', () {
      expect(
        ComicChapterImagePipeline.extractImageUrls({
          'images': ['https://cdn.a/1.jpg'],
        }),
        ['https://cdn.a/1.jpg'],
      );
      expect(
        ComicChapterImagePipeline.extractImageUrls(['https://cdn.a/1.jpg']),
        ['https://cdn.a/1.jpg'],
      );
      expect(
        ComicChapterImagePipeline.extractImageUrls({
          'items': [
            {'url': 'https://cdn.a/1.jpg'},
            {'src': 'https://cdn.a/2.jpg'},
          ],
        }),
        ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg'],
      );
    });

    test('相对地址按章节页补全，并去重', () {
      final urls = ComicChapterImagePipeline.extractImageUrls(
        {
          'items': [
            '/static/upload/a.jpg',
            'b.jpg',
            '//cdn.c/c.jpg',
            '/static/upload/a.jpg',
          ],
        },
        baseUrl: 'https://www.jjmhw8.top/chapter/53996',
      );

      expect(urls, [
        'https://www.jjmhw8.top/static/upload/a.jpg',
        // 无斜杠结尾的章节地址按"目录"处理（与详情页既有补全口径一致）
        'https://www.jjmhw8.top/chapter/53996/b.jpg',
        'https://cdn.c/c.jpg',
      ]);
    });

    test('无法识别的结构返回空表', () {
      expect(ComicChapterImagePipeline.extractImageUrls(null), isEmpty);
      expect(ComicChapterImagePipeline.extractImageUrls({'foo': 1}), isEmpty);
    });
  });

  group('resolve：章节 → 图片', () {
    test('解析成功并缓存（同一章只解析一次）', () async {
      var calls = 0;
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async {
          calls++;
          return {
            'items': ['https://cdn.a/$calls.jpg'],
          };
        },
      );

      final first = await pipeline.resolve(
        rule: rule,
        chapter: chapter('https://example.com/chapter/53996'),
      );
      final second = await pipeline.resolve(
        rule: rule,
        chapter: chapter('https://example.com/chapter/53996'),
      );

      expect(first, ['https://cdn.a/1.jpg']);
      expect(second, first);
      expect(calls, 1);
      expect(pipeline.cachedCount, 1);
    });

    test('解析抛错 → 空表且不写缓存（下次仍会重试）', () async {
      var calls = 0;
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async {
          calls++;
          if (calls == 1) throw Exception('网络炸了');
          return {
            'items': ['https://cdn.a/ok.jpg'],
          };
        },
      );

      final failed = await pipeline.resolve(
        rule: rule,
        chapter: chapter('https://example.com/chapter/1'),
      );
      expect(failed, isEmpty);
      expect(pipeline.cachedCount, 0, reason: '失败结果不能被缓存');

      final retried = await pipeline.resolve(
        rule: rule,
        chapter: chapter('https://example.com/chapter/1'),
      );
      expect(retried, ['https://cdn.a/ok.jpg']);
      expect(calls, 2);
    });

    test('章节项本身就是图片时不解析（groups 里直接放图片的写法）', () async {
      var calls = 0;
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async {
          calls++;
          return null;
        },
      );

      final urls = await pipeline.resolve(
        rule: rule,
        chapter: chapter('https://cdn.a/cover.jpg'),
      );

      expect(urls, ['https://cdn.a/cover.jpg']);
      expect(calls, 0);
    });

    test('缺规则 / 缺章节地址 → 空表且不发请求', () async {
      var calls = 0;
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async {
          calls++;
          return null;
        },
      );

      expect(
        await pipeline.resolve(
          rule: null,
          chapter: chapter('https://example.com/c/1'),
        ),
        isEmpty,
      );
      expect(
        await pipeline.resolve(rule: rule, chapter: chapter('')),
        isEmpty,
      );
      expect(calls, 0);
    });

    test('并发请求同一章只解析一次', () async {
      var calls = 0;
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async {
          calls++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return {
            'items': ['https://cdn.a/x.jpg'],
          };
        },
      );

      final results = await Future.wait([
        pipeline.resolve(rule: rule, chapter: chapter('https://example.com/c/9')),
        pipeline.resolve(rule: rule, chapter: chapter('https://example.com/c/9')),
      ]);

      expect(results.first, results.last);
      expect(calls, 1);
    });
  });

  group('prefetchNeighbors', () {
    test('预取相邻章：成功入缓存，失败的静默忽略', () async {
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async {
          if (url.endsWith('/bad')) throw Exception('bad');
          return {
            'items': ['https://cdn.a/ok.jpg'],
          };
        },
      );
      final chapters = [
        chapter('https://example.com/c/good', title: '第1话'),
        chapter('https://example.com/c/bad', title: '第2话'),
        chapter('https://example.com/c/good2', title: '第3话'),
      ];

      pipeline.prefetchNeighbors(rule: rule, chapters: chapters, index: 1);
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(pipeline.cachedCount, 2, reason: '首尾两章预取成功，中间那章失败不入缓存');
    });

    test('越界索引安全（不抛错）', () {
      final pipeline = ComicChapterImagePipeline(parser: (r, url) async => null);

      expect(
        () => pipeline.prefetchNeighbors(
          rule: rule,
          chapters: [chapter('https://example.com/c/1')],
          index: 0,
        ),
        returnsNormally,
      );
    });
  });
}
