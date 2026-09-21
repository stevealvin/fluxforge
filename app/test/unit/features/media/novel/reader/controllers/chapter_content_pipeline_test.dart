import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/chapter_cache.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/chapter_content_pipeline.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';

/// 内存版离线存取替身：让管道能脱离沙盒与网络单测
class _FakeOfflineStore implements OfflineChapterStore {
  _FakeOfflineStore({
    Set<int>? downloaded,
    Map<int, String>? contents,
    this.throwOnRead = false,
  })  : downloaded = {...?downloaded},
        contents = {...?contents};

  /// 已落盘章节集合（save 成功后会真实增长，便于断言「加载即下载」）
  final Set<int> downloaded;
  final Map<int, String> contents;
  final bool throwOnRead;

  int readCalls = 0;
  final List<int> saveCalls = [];

  @override
  bool isDownloaded(String bookId, int index) => downloaded.contains(index);

  @override
  int downloadedCount(String bookId) => downloaded.length;

  @override
  Future<String?> read(String bookId, int index) async {
    readCalls++;
    if (throwOnRead) throw const FileSystemException('沙盒文件损坏');
    return contents[index];
  }

  @override
  Future<bool> save({
    required Rule rule,
    required String bookId,
    required String title,
    required List<MediaEpisode> chapters,
    required int index,
    required String content,
  }) async {
    saveCalls.add(index);
    contents[index] = content;
    downloaded.add(index);
    return true;
  }
}

void main() {
  final rule = Rule(
    id: 1,
    name: '测试书源',
    baseUrl: 'https://example.com',
    type: 'novel',
    code: '',
  );

  NovelChapter chapterOf(int index) => NovelChapter(
        title: '第${index + 1}章',
        url: 'https://example.com/chapter/$index',
      );

  /// 组装管道；[parseCalls] 用于断言是否真的走了网络
  (ChapterContentPipeline, ChapterCache, List<String>) buildPipeline({
    required _FakeOfflineStore store,
    List<NovelChapter>? chapters,
  }) {
    final cache = ChapterCache();
    final parseUrls = <String>[];
    final pipeline = ChapterContentPipeline(
      bookTitle: '测试书籍',
      offlineBookId: 'book-1',
      rule: rule,
      chapters: chapters ?? [chapterOf(0), chapterOf(1), chapterOf(2)],
      cache: cache,
      prefetching: <int>{},
      cacheWriter: (index, content) => cache[index] = content,
      offlineStore: store,
      parseRule: (r, url) async {
        parseUrls.add(url);
        return {'content': '网络抓取正文'};
      },
    );
    return (pipeline, cache, parseUrls);
  }

  group('ensureContent 三级来源优先级', () {
    test('内存缓存命中时直接返回，不碰离线也不碰网络', () async {
      final store = _FakeOfflineStore(
        downloaded: {0},
        contents: {0: '离线正文'},
      );
      final (pipeline, cache, parseUrls) = buildPipeline(store: store);
      cache[0] = '内存缓存正文';

      final content = await pipeline.ensureContent(0);

      expect(content, equals('内存缓存正文'));
      expect(store.readCalls, equals(0));
      expect(parseUrls, isEmpty);
    });

    test('缓存未命中但已离线下载时，直接读离线且绝不发起网络请求', () async {
      final store = _FakeOfflineStore(
        downloaded: {1},
        contents: {1: '离线下载正文'},
      );
      final (pipeline, cache, parseUrls) = buildPipeline(store: store);

      final content = await pipeline.ensureContent(1);

      expect(content, equals('离线下载正文'));
      expect(parseUrls, isEmpty, reason: '已离线即断网可读，不应再走网络');
      expect(cache[1], equals('离线下载正文'), reason: '离线正文应回填内存缓存');
    });

    test('缓存与离线都没有时才走网络抓取', () async {
      final store = _FakeOfflineStore();
      final (pipeline, cache, parseUrls) = buildPipeline(store: store);

      final content = await pipeline.ensureContent(2);

      // 网络正文会经过 cleanNovelContent 清洗（加段落缩进），故用 contains 断言
      expect(content, contains('网络抓取正文'));
      expect(parseUrls, hasLength(1));
      expect(cache[2], contains('网络抓取正文'));
    });

    test('离线文件读出空串时降级到网络', () async {
      final store = _FakeOfflineStore(downloaded: {1}, contents: {1: ''});
      final (pipeline, _, parseUrls) = buildPipeline(store: store);

      final content = await pipeline.ensureContent(1);

      expect(content, contains('网络抓取正文'));
      expect(parseUrls, hasLength(1));
    });

    test('离线读取抛异常时静默降级到网络，绝不让本地 IO 异常冒泡', () async {
      final store = _FakeOfflineStore(downloaded: {1}, throwOnRead: true);
      final (pipeline, _, parseUrls) = buildPipeline(store: store);

      final content = await pipeline.ensureContent(1);

      expect(content, contains('网络抓取正文'));
      expect(parseUrls, hasLength(1));
    });

    test('未配置离线书籍标识时完全不触碰离线存取', () async {
      final store = _FakeOfflineStore(downloaded: {0}, contents: {0: '离线正文'});
      final cache = ChapterCache();
      final parseUrls = <String>[];
      final pipeline = ChapterContentPipeline(
        bookTitle: '测试书籍',
        offlineBookId: null,
        rule: rule,
        chapters: [chapterOf(0)],
        cache: cache,
        prefetching: <int>{},
        cacheWriter: (index, content) => cache[index] = content,
        offlineStore: store,
        parseRule: (r, url) async {
          parseUrls.add(url);
          return {'content': '网络抓取正文'};
        },
      );

      final content = await pipeline.ensureContent(0);

      expect(content, contains('网络抓取正文'));
      expect(store.readCalls, equals(0));
    });
  });

  group('readOffline 与 isOfflineDownloaded', () {
    test('未下载时 readOffline 立即返回 null，不做任何读取', () async {
      final store = _FakeOfflineStore();
      final (pipeline, _, _) = buildPipeline(store: store);

      expect(pipeline.isOfflineDownloaded(0), isFalse);
      expect(await pipeline.readOffline(0), isNull);
      expect(store.readCalls, equals(0));
    });

    test('已下载时 readOffline 返回沙盒正文', () async {
      final store = _FakeOfflineStore(downloaded: {0}, contents: {0: '正文'});
      final (pipeline, _, _) = buildPipeline(store: store);

      expect(pipeline.isOfflineDownloaded(0), isTrue);
      expect(await pipeline.readOffline(0), equals('正文'));
    });
  });

  group('「加载到即已下载」语义', () {
    test('内存镜像已有正文时直接复用落盘，不发起任何网络请求', () async {
      final store = _FakeOfflineStore();
      final (pipeline, cache, parseUrls) = buildPipeline(store: store);
      cache[0] = '内存镜像正文';

      final ok = await pipeline.downloadOffline(0);

      expect(ok, isTrue);
      expect(store.saveCalls, equals([0]));
      expect(store.contents[0], equals('内存镜像正文'));
      expect(parseUrls, isEmpty, reason: '已有正文就不该再联网');
      expect(pipeline.isOfflineDownloaded(0), isTrue);
    });

    test('沙盒已有该章时立即返回，不重复落盘也不联网', () async {
      final store = _FakeOfflineStore(downloaded: {0}, contents: {0: '离线正文'});
      final (pipeline, _, parseUrls) = buildPipeline(store: store);

      expect(await pipeline.downloadOffline(0), isTrue);
      expect(store.saveCalls, isEmpty);
      expect(parseUrls, isEmpty);
    });

    test('两处都没有时，一次抓取的结果同时写入内存镜像与沙盒', () async {
      final store = _FakeOfflineStore();
      final (pipeline, cache, parseUrls) = buildPipeline(store: store);

      final ok = await pipeline.downloadOffline(1);

      expect(ok, isTrue);
      expect(parseUrls, hasLength(1));
      expect(store.contents[1], contains('网络抓取正文'));
      expect(cache[1], contains('网络抓取正文'), reason: '内存镜像须同步建立，供本次阅读直接渲染');
      expect(pipeline.isOfflineDownloaded(1), isTrue, reason: '加载到就属于已下载');
    });

    test('downloadAdjacent 下载前后各一章，已在沙盒的章节跳过', () async {
      final store = _FakeOfflineStore(downloaded: {1}, contents: {1: '已有正文'});
      final (pipeline, _, _) = buildPipeline(store: store);

      // 当前在第 2 章（index 1）：应下载 index 2 与 index 0
      pipeline.downloadAdjacent(1);
      // 邻章下载是 fire-and-forget，需等事件队列跑完
      await pumpEventQueue();

      expect(store.saveCalls, contains(2));
      expect(store.saveCalls, contains(0));
      expect(store.saveCalls, isNot(contains(1)), reason: '已落盘的章节必须跳过，不做重复 IO');
    });

    test('handleChapterJumped 与 downloadAdjacent 行为一致（不再有内存专用分支）', () async {
      final store = _FakeOfflineStore();
      final (pipeline, _, _) = buildPipeline(store: store);

      pipeline.handleChapterJumped(1);
      await pumpEventQueue();

      expect(store.saveCalls, containsAll(<int>[0, 2]));
    });
  });
}
