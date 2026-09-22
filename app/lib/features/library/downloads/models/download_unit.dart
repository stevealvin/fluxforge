/// 离线下载的「可下载单元」（选集下载的候选项）
///
/// 一类媒体对应一种单元：
/// - 视频 → 分集
/// - 小说 → 章节
/// - 漫画 → 章节；图集形态下 detail 已直接给出图片，则以「页」为单位
///
/// [index] 是该单元在**原清单**中的稳定下标。选集就是一组下标，而下载任务的
/// 目标清单始终保存全量，因此下标不会随选集变化而错位 —— 这是「先下 1-3 集、
/// 之后再补 5-7 集」仍然能正确跳过已下载项的前提。
class DownloadUnit {
  const DownloadUnit({required this.index, required this.title});

  /// 原清单下标
  final int index;

  /// 展示标题（已兜底为「第 N 集 / 章 / 页」）
  final String title;
}
