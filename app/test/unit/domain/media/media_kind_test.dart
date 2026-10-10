import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/domain/media/media_kind.dart';

/// 媒体类型判定：规则类型 → 「影视 / 小说 / 漫画·图集」三分法
///
/// 这份判定被搜索结果排版、规则目录卡片与发现页网格共用（这正是它下沉到 domain
/// 的原因）。一旦口径漂移，同一条规则会在「排版」与「筛选」两处得到相反结论，
/// 因此单独覆盖：既要测三类的归位，也要测兜底与归一化。
void main() {
  group('isVideoRuleType（排版口径）', () {
    test('视频类标识全部命中', () {
      for (final type in ['video', 'tv', 'movie', 'anime', 'short']) {
        expect(isVideoRuleType(type), isTrue, reason: type);
      }
    });

    test('空类型按影视兜底：未标注类型的源绝大多数是影视站', () {
      expect(isVideoRuleType(''), isTrue);
      expect(isVideoRuleType('   '), isTrue);
    });

    test('小说与漫画类不是视频', () {
      expect(isVideoRuleType('novel'), isFalse);
      expect(isVideoRuleType('comic'), isFalse);
      expect(isVideoRuleType('picture'), isFalse);
    });

    test('大小写与首尾空白被归一化', () {
      expect(isVideoRuleType('  VIDEO '), isTrue);
      expect(isVideoRuleType('Novel'), isFalse);
    });
  });

  group('mediaKindOfRuleType（分组）', () {
    test('三类各自归位', () {
      expect(mediaKindOfRuleType('movie'), MediaKind.video);
      expect(mediaKindOfRuleType('novel'), MediaKind.novel);
      expect(mediaKindOfRuleType('manga'), MediaKind.comic);
      expect(mediaKindOfRuleType('gallery'), MediaKind.comic);
    });

    test('未知类型按影视兜底，而不是丢弃', () {
      // 丢弃会让「全部」的源数与三个分档之和对不上，用户会以为源凭空少了
      expect(mediaKindOfRuleType('whatever'), MediaKind.video);
      expect(mediaKindOfRuleType(''), MediaKind.video);
    });
  });

  group('分组标签', () {
    test('每个分组都有可读文案，且与收藏页口径一致', () {
      for (final kind in MediaKind.values) {
        expect(kind.label, isNotEmpty, reason: '$kind');
      }
      expect(MediaKind.all.label, '全部');
      expect(MediaKind.video.label, '影视');
      expect(MediaKind.novel.label, '小说');
      expect(MediaKind.comic.label, '漫画·图集');
    });
  });
}
