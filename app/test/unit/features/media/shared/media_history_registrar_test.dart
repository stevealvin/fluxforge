import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/features/media/shared/media_history_registrar.dart';

/// 消费记录登记规则单元测试
///
/// 这条规则原先以「两份各写一版的私有方法」存在，且两版的**保留语义并不相同**：
/// 视频要沿用播放秒数，小说要沿用章节位置 —— 谁抄错一版都会静默破坏续播 / 续读。
void main() {
  final updatedAt = DateTime(2026, 9, 21, 12);

  PlayRecord existingRecord() => PlayRecord(
    id: 'media-1',
    title: '旧标题',
    cover: 'old.jpg',
    mediaType: 'video',
    ruleId: 'rule-1',
    episodeName: '第 8 集',
    episodeIndex: 7,
    totalEpisodes: 24,
    positionSeconds: 620,
    durationSeconds: 1400,
    updatedAt: DateTime(2026, 9, 20),
  );

  PlayRecord merge({
    PlayRecord? existing,
    String episodeName = '第 3 集',
    int episodeIndex = 2,
    bool preserveEpisode = false,
    bool preservePlaybackProgress = false,
  }) {
    return MediaHistoryRegistrar.merge(
      existing: existing,
      id: 'media-1',
      title: '新标题',
      cover: 'new.jpg',
      mediaType: 'video',
      ruleId: 'rule-1',
      totalEpisodes: 24,
      episodeName: episodeName,
      episodeIndex: episodeIndex,
      preserveEpisode: preserveEpisode,
      preservePlaybackProgress: preservePlaybackProgress,
      updatedAt: updatedAt,
    );
  }

  group('视频语义：取当前集，但沿用播放进度', () {
    test('播放秒数与总时长沿用既有记录，集号取当前播放集', () {
      final merged = merge(
        existing: existingRecord(),
        preservePlaybackProgress: true,
      );

      expect(merged.positionSeconds, equals(620), reason: '断点不能因进入详情页而清零');
      expect(merged.durationSeconds, equals(1400));
      expect(merged.episodeName, equals('第 3 集'), reason: '视频取当前播放集');
      expect(merged.episodeIndex, equals(2));
      // 元信息按新值更新
      expect(merged.title, equals('新标题'));
      expect(merged.cover, equals('new.jpg'));
      expect(merged.updatedAt, equals(updatedAt));
    });

    test('没有既有记录时进度为 0', () {
      final merged = merge(preservePlaybackProgress: true);
      expect(merged.positionSeconds, equals(0));
      expect(merged.durationSeconds, equals(0));
    });
  });

  group('小说 / 漫画语义：沿用章节位置，进度恒为 0', () {
    test('集号与集名沿用既有记录（打开详情页不改变「读到第几章」）', () {
      final merged = merge(existing: existingRecord(), preserveEpisode: true);

      expect(merged.episodeName, equals('第 8 集'));
      expect(merged.episodeIndex, equals(7));
      // 按 PlayRecord 约定，小说 / 漫画的播放秒数恒为 0
      expect(merged.positionSeconds, equals(0));
      expect(merged.durationSeconds, equals(0));
    });

    test('没有既有记录时集号兜底为 0 / 空', () {
      final merged = merge(preserveEpisode: true);
      expect(merged.episodeName, equals(''));
      expect(merged.episodeIndex, equals(0));
    });
  });

  test('两种保留语义互不影响（可各自单独开启）', () {
    final onlyProgress = merge(
      existing: existingRecord(),
      preservePlaybackProgress: true,
    );
    expect(onlyProgress.positionSeconds, equals(620));
    expect(
      onlyProgress.episodeIndex,
      equals(2),
      reason: '未开启 preserveEpisode 时用传入值',
    );

    final onlyEpisode = merge(
      existing: existingRecord(),
      preserveEpisode: true,
    );
    expect(onlyEpisode.episodeIndex, equals(7));
    expect(onlyEpisode.positionSeconds, equals(0));
  });
}
