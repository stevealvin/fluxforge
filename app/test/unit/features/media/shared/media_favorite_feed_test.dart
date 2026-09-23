import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/shared/media_favorite_actions.dart';

/// 首页 / 搜索结果的收藏口径（纯函数部分）
///
/// 契约：**与详情页同源** —— 键必须用同一套归一化（相对地址按规则 baseUrl 补全），
/// 类型必须按同一套规则推断，否则会出现「详情页收藏了、首页显示未收藏」。
void main() {
  Rule rule(String type, {String baseUrl = 'https://site.example'}) =>
      Rule(id: 3, name: '测试源', baseUrl: baseUrl, type: type, code: '// noop');

  group('规则类型 → 媒体类型', () {
    test('小说类规则映射为 novel', () {
      expect(MediaFavoriteActions.mediaTypeOf(rule('novel')), MediaType.novel);
      expect(MediaFavoriteActions.mediaTypeOf(rule('book')), MediaType.novel);
    });

    test('图片类规则映射为 comic', () {
      expect(MediaFavoriteActions.mediaTypeOf(rule('comic')), MediaType.comic);
      expect(
        MediaFavoriteActions.mediaTypeOf(rule('gallery')),
        MediaType.comic,
      );
      expect(MediaFavoriteActions.mediaTypeOf(rule('manga')), MediaType.comic);
    });

    test('视频类与认不出的类型都归为 video（与详情页分流一致）', () {
      expect(MediaFavoriteActions.mediaTypeOf(rule('video')), MediaType.video);
      expect(MediaFavoriteActions.mediaTypeOf(rule('')), MediaType.video);
      expect(MediaFavoriteActions.mediaTypeOf(rule('未知')), MediaType.video);
    });
  });

  group('首页条目收藏键', () {
    test('相对地址按规则 baseUrl 归一（与详情页同一套键）', () {
      expect(
        MediaFavoriteActions.feedKey(
          title: '标题',
          url: '/detail/1.html',
          rule: rule('video'),
        ),
        'https://site.example/detail/1.html',
      );
    });

    test('绝对地址原样使用', () {
      expect(
        MediaFavoriteActions.feedKey(
          title: '标题',
          url: 'https://other.example/a/1.html',
          rule: rule('video'),
        ),
        'https://other.example/a/1.html',
      );
    });

    test('没有地址时退回标题（至少保证同一部作品键一致）', () {
      expect(
        MediaFavoriteActions.feedKey(
          title: '某部剧',
          url: '  ',
          rule: rule('video'),
        ),
        '某部剧',
      );
    });

    test('无规则时不补全，也不抛错', () {
      expect(
        MediaFavoriteActions.feedKey(title: '标题', url: '/detail/2.html'),
        '/detail/2.html',
      );
    });
  });
}
