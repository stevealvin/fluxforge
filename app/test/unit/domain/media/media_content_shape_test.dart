import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media.dart';

/// 图片类作品的内容形态推断（元素类型推断，规则无需声明任何字段）
void main() {
  MediaEpisode ep(String url) => MediaEpisode(title: url, url: url);

  MediaDetailData data({
    List<String> images = const [],
    List<MediaEpisode> chapters = const [],
    List<MediaGroup> groups = const [],
  }) => MediaDetailData(
    title: '测试作品',
    url: 'https://example.com/detail/1',
    cover: '',
    imageList: images,
    chapters: chapters,
    comicGroups: groups,
  );

  test('items: [String] → 图集形态（无需二次解析）', () {
    final d = data(images: ['https://cdn.a/1.jpg', 'https://cdn.a/2.jpg']);

    expect(d.contentShape, MediaContentShape.images);
    expect(d.needsChapterParse, isFalse);
  });

  test('图集形态下顺带生成的 chapters 不会把形态带偏', () {
    // 详情解析对每张图也会生成一条 episode（历史行为），所以 imageList 必须优先于 chapters
    final d = data(
      images: ['https://cdn.a/1.jpg'],
      chapters: [ep('https://cdn.a/1.jpg')],
    );

    expect(d.contentShape, MediaContentShape.images);
  });

  test('items: [{title,url}] → 章节形态，并合成可读章表', () {
    final d = data(
      chapters: [
        ep('https://example.com/chapter/53996'),
        ep('https://example.com/chapter/53997'),
      ],
    );

    expect(d.contentShape, MediaContentShape.chapters);
    expect(d.needsChapterParse, isTrue);
    expect(d.readableComicGroups, hasLength(1));
    expect(d.readableComicGroups.single.items, hasLength(2));
    expect(d.readableComicGroups.single.name, isNotEmpty);
  });

  test('groups → 章节形态，可读章表原样返回（多分组）', () {
    final d = data(
      groups: [
        MediaGroup(
          name: '章节列表',
          items: [ep('https://example.com/chapter/1')],
        ),
        MediaGroup(
          name: '番外篇',
          items: [ep('https://example.com/chapter/2')],
        ),
      ],
    );

    expect(d.contentShape, MediaContentShape.chapters);
    expect(d.readableComicGroups, hasLength(2));
    expect(d.readableComicGroups.first.name, '章节列表');
  });

  test('全空 → none，且可读章表为空', () {
    final d = data();

    expect(d.contentShape, MediaContentShape.none);
    expect(d.needsChapterParse, isFalse);
    expect(d.readableComicGroups, isEmpty);
  });

  test('空分组的 items 不构成章节形态', () {
    final d = data(groups: [const MediaGroup(name: '空分组', items: [])]);

    expect(d.contentShape, MediaContentShape.none);
  });
}
