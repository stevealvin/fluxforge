import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_chapter_image_pipeline.dart';
import 'package:fluxforge/features/media/shared/media_download_actions.dart';

/// 选集下载的**单元清单**与「选中范围 → 下载目标」的映射
///
/// 核心契约：单元下标与下载任务里的目标下标**同源同序**，
/// 否则「选第 5 集」会下载成别的集，或者被误判成「已下载」。
void main() {
  final rule = Rule(
    id: 7,
    name: '测试源',
    baseUrl: 'https://example.com',
    type: 'comic',
    code: '// noop',
  );

  MediaEpisode ep(String url, {String title = ''}) =>
      MediaEpisode(title: title, url: url);

  group('单元清单', () {
    test('视频：取首条线路的分集，标题兜底为「第 N 集」', () {
      final data = MediaDetailData(
        title: '剧名',
        url: 'https://v.example/detail/1',
        cover: '',
        mediaType: MediaType.video,
        videoGroups: [
          MediaGroup(
            name: '线路1',
            items: [
              ep('https://v.example/1-1.m3u8', title: '第 1 集'),
              ep('https://v.example/1-2.m3u8'),
            ],
          ),
          MediaGroup(name: '线路2', items: [ep('https://v.example/alt.m3u8')]),
        ],
      );

      final units = MediaDownloadActions.unitsOf(data);

      expect(units.map((u) => u.index), [0, 1]);
      expect(units.map((u) => u.title), ['第 1 集', '第 2 集']);
      expect(MediaDownloadActions.unitUrls(data), [
        'https://v.example/1-1.m3u8',
        'https://v.example/1-2.m3u8',
      ]);
    });

    test('视频：无地址的分集不进选集，但下标仍按原清单', () {
      final data = MediaDetailData(
        title: '剧名',
        url: 'https://v.example/detail/1',
        cover: '',
        mediaType: MediaType.video,
        videoGroups: [
          MediaGroup(
            name: '线路1',
            items: [
              ep('https://v.example/1-1.m3u8', title: '第 1 集'),
              ep(''),
              ep('https://v.example/1-3.m3u8', title: '第 3 集'),
            ],
          ),
        ],
      );

      final units = MediaDownloadActions.unitsOf(data);

      expect(units.map((u) => u.title), ['第 1 集', '第 3 集']);
      expect(units.map((u) => u.index), [
        0,
        2,
      ], reason: '下标必须指向原清单，下载侧才能正确定位到第 3 集');
      expect(MediaDownloadActions.unitUrls(data), [
        'https://v.example/1-1.m3u8',
        'https://v.example/1-3.m3u8',
      ]);
    });

    test('小说：单元为章节，且与直链一一对齐', () {
      final data = MediaDetailData(
        title: '书名',
        url: 'https://n.example/1',
        cover: '',
        mediaType: MediaType.novel,
        chapters: [
          ep('https://n.example/c1', title: '第一章'),
          ep('https://n.example/c2'),
        ],
      );

      final units = MediaDownloadActions.unitsOf(data);

      expect(units.map((u) => u.title), ['第一章', '第 2 章']);
      expect(MediaDownloadActions.unitUrls(data), [
        'https://n.example/c1',
        'https://n.example/c2',
      ]);
    });

    test('漫画章节形态：单元为章节（地址需二次解析，不参与大小探测）', () {
      final data = MediaDetailData(
        title: '漫画',
        url: 'https://c.example/1',
        cover: '',
        mediaType: MediaType.comic,
        chapters: [
          ep('https://c.example/ch/1', title: '第 1 话'),
          ep('https://c.example/ch/2', title: '第 2 话'),
        ],
      );

      expect(MediaDownloadActions.unitsOf(data).map((u) => u.title), [
        '第 1 话',
        '第 2 话',
      ]);
      expect(MediaDownloadActions.unitUrls(data), isEmpty);
    });

    test('图集形态：单元为「页」，与图片地址逐位对齐', () {
      final data = MediaDetailData(
        title: '图集',
        url: 'https://g.example/1',
        cover: '',
        mediaType: MediaType.comic,
        imageList: ['https://cdn.g/1.jpg', '', 'https://cdn.g/2.jpg'],
      );

      final units = MediaDownloadActions.unitsOf(data);

      expect(units.map((u) => u.title), ['第 1 页', '第 2 页']);
      expect(MediaDownloadActions.unitUrls(data), [
        'https://cdn.g/1.jpg',
        'https://cdn.g/2.jpg',
      ]);
    });
  });

  group('视频下载请求参数', () {
    final videoRule = Rule(
      id: 9,
      name: '影视源',
      baseUrl: 'https://v.example',
      type: 'video',
      code: '// noop',
    );

    MediaDetailData videoData({
      Map<String, String> headers = const {},
      Map<String, dynamic>? episodeExtra,
    }) => MediaDetailData(
      title: '剧名',
      url: 'https://v.example/vod/detail/123',
      cover: '',
      mediaType: MediaType.video,
      customHeaders: headers,
      videoGroups: [
        MediaGroup(
          name: '线路1',
          items: [
            MediaEpisode(
              title: '第 1 集',
              url: 'https://cdn.v.example/1-1.m3u8',
              extra: episodeExtra ?? const {},
            ),
          ],
        ),
      ],
    );

    test('补齐站点根 Referer 与 UA：缺了会被源站 403（表现为「能播放但下载立刻失败」）', () {
      final request = MediaDownloadActions.videoRequestOf(
        videoData(),
        rule: videoRule,
      );

      expect(
        request.headers['Referer'],
        'https://v.example',
        reason: '必须用站点根，而不是详情页的深层地址',
      );
      expect(request.headers['User-Agent']?.trim(), isNotEmpty);
      expect(request.episodes.single.url, 'https://cdn.v.example/1-1.m3u8');
    });

    test('规则已声明的 Referer 与 UA 不被兜底覆盖', () {
      final request = MediaDownloadActions.videoRequestOf(
        videoData(
          headers: const {
            'Referer': 'https://custom.example/',
            'User-Agent': 'CustomUA',
          },
        ),
        rule: videoRule,
      );

      expect(request.headers['Referer'], 'https://custom.example/');
      expect(request.headers['User-Agent'], 'CustomUA');
    });

    test('单集独占请求头并入任务头（部分源站把鉴权放在分集数据里）', () {
      final request = MediaDownloadActions.videoRequestOf(
        videoData(
          episodeExtra: const {
            'headers': {'Cookie': 'sid=abc'},
          },
        ),
        rule: videoRule,
      );

      expect(request.headers['Cookie'], 'sid=abc');
    });
  });

  group('选中范围 → 图片下标', () {
    test('漫画：只选第 2 章时，图片下标对准该章，且清单仍是全量', () async {
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async {
          final id = url.split('/').last;
          return {
            'items': ['https://cdn.a/$id-1.jpg', 'https://cdn.a/$id-2.jpg'],
          };
        },
      );

      final data = MediaDetailData(
        title: '漫画',
        url: 'https://c.example/1',
        cover: '',
        mediaType: MediaType.comic,
        chapters: [ep('https://c.example/ch/1'), ep('https://c.example/ch/2')],
      );

      final result = await MediaDownloadActions.collectComicDownload(
        data: data,
        rule: rule,
        pipeline: pipeline,
        selectedChapters: {1},
      );

      expect(result.urls, [
        'https://cdn.a/1-1.jpg',
        'https://cdn.a/1-2.jpg',
        'https://cdn.a/2-1.jpg',
        'https://cdn.a/2-2.jpg',
      ], reason: '目标清单必须全量，否则已下载下标会错位');
      expect(result.selection, {2, 3}, reason: '选中的是第 2 章贡献的后两张');
    });

    test('漫画：全选时不需要下标限定（selection 为 null）', () async {
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async => {
          'items': ['https://cdn.a/${url.split('/').last}.jpg'],
        },
      );

      final data = MediaDetailData(
        title: '漫画',
        url: 'https://c.example/1',
        cover: '',
        mediaType: MediaType.comic,
        chapters: [ep('https://c.example/ch/1'), ep('https://c.example/ch/2')],
      );

      final result = await MediaDownloadActions.collectComicDownload(
        data: data,
        rule: rule,
        pipeline: pipeline,
      );

      expect(result.urls.length, 2);
      expect(result.selection, isNull);
    });

    test('图集：选中页下标直接映射，越界被丢弃', () async {
      final data = MediaDetailData(
        title: '图集',
        url: 'https://g.example/1',
        cover: '',
        mediaType: MediaType.comic,
        imageList: ['https://cdn.g/1.jpg', 'https://cdn.g/2.jpg'],
      );

      final result = await MediaDownloadActions.collectComicDownload(
        data: data,
        rule: rule,
        selectedChapters: {1, 9},
      );

      expect(result.urls, ['https://cdn.g/1.jpg', 'https://cdn.g/2.jpg']);
      expect(result.selection, {1});
    });

    test('同一张图被多章复用时只下一次，但选中任一章都应包含它', () async {
      final pipeline = ComicChapterImagePipeline(
        parser: (r, url) async => {
          'items': ['https://cdn.a/shared.jpg'],
        },
      );

      final data = MediaDetailData(
        title: '漫画',
        url: 'https://c.example/1',
        cover: '',
        mediaType: MediaType.comic,
        chapters: [ep('https://c.example/ch/1'), ep('https://c.example/ch/2')],
      );

      final result = await MediaDownloadActions.collectComicDownload(
        data: data,
        rule: rule,
        pipeline: pipeline,
        selectedChapters: {1},
      );

      expect(result.urls, ['https://cdn.a/shared.jpg']);
      expect(result.selection, {0});
    });
  });
}
