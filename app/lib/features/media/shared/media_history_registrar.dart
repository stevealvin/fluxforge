import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/play_history_service.dart';

/// 媒体详情页「消费记录」的登记 / 更新（视频 · 小说 · 漫画共用）
///
/// 三种媒体的详情页此前各抄了一份同样的 `_registerPlayRecord`，
/// 但**保留语义并不相同**，且这个差异只存在于两份实现的细节里、没有任何注释或测试兜底：
///
/// | 媒体 | 集号 / 集名 | 播放进度（秒） |
/// |---|---|---|
/// | video | 取**当前播放集** | **沿用既有**（否则每次进详情页都会清掉「继续观看」断点） |
/// | novel / comic | **沿用既有**（进详情页不应改变"读到第几章"） | 恒为 0（[PlayRecord] 约定） |
///
/// 因此这里把「沿用哪种字段」提升为**显式参数**，并由纯函数 [merge] 承载规则 ——
/// 谁抄错一版，单测立刻会红。
class MediaHistoryRegistrar {
  const MediaHistoryRegistrar._();

  /// 合并新旧消费记录（**纯函数**，可纯 Dart 单测）
  ///
  /// - [preserveEpisode]：集号 / 集名沿用 [existing]（小说 / 漫画用）；
  /// - [preservePlaybackProgress]：播放秒数与总时长沿用 [existing]（视频用）。
  static PlayRecord merge({
    required PlayRecord? existing,
    required String id,
    required String title,
    String url = '',
    required String cover,
    required String mediaType,
    required String ruleId,
    required int totalEpisodes,
    required String episodeName,
    required int episodeIndex,
    required bool preserveEpisode,
    required bool preservePlaybackProgress,
    required DateTime updatedAt,
  }) {
    return PlayRecord(
      id: id,
      url: url,
      title: title,
      cover: cover,
      mediaType: mediaType,
      ruleId: ruleId,
      episodeName: preserveEpisode
          ? (existing?.episodeName ?? '')
          : episodeName,
      episodeIndex: preserveEpisode
          ? (existing?.episodeIndex ?? 0)
          : episodeIndex,
      totalEpisodes: totalEpisodes,
      positionSeconds: preservePlaybackProgress
          ? (existing?.positionSeconds ?? 0)
          : 0,
      durationSeconds: preservePlaybackProgress
          ? (existing?.durationSeconds ?? 0)
          : 0,
      updatedAt: updatedAt,
    );
  }

  /// 登记 / 更新当前媒体的消费记录
  ///
  /// [id] 为空时直接跳过（详情页 URL 与标题都缺失时无法标识媒体）。
  static void register({
    required String id,
    required String title,
    String url = '',
    required String cover,
    required String mediaType,
    required String ruleId,
    required int totalEpisodes,
    String episodeName = '',
    int episodeIndex = 0,
    bool preserveEpisode = false,
    bool preservePlaybackProgress = false,
    DateTime? now,
  }) {
    if (id.isEmpty) return;

    playHistoryService.upsert(
      merge(
        existing: playHistoryService.getById(id),
        id: id,
        url: url,
        title: title,
        cover: cover,
        mediaType: mediaType,
        ruleId: ruleId,
        totalEpisodes: totalEpisodes,
        episodeName: episodeName,
        episodeIndex: episodeIndex,
        preserveEpisode: preserveEpisode,
        preservePlaybackProgress: preservePlaybackProgress,
        updatedAt: now ?? DateTime.now(),
      ),
    );
  }
}
