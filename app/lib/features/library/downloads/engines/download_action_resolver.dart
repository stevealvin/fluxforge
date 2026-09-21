import 'package:fluxforge/data/download/download_service.dart';

/// 离线下载「任务状态 → 下一步动作」的判定（纯逻辑，可纯 Dart 单测）
///
/// `DownloadBar` 的五态展示背后对应五种动作，而这套判定原先在小说 / 漫画详情页
/// **各写一遍**（两处逐行同构，只有「全新下载」那一步与文案不同），视频那份更是
/// 只剩「全新开始」—— 于是同一个语义在三处三种实现，谁改都可能漏改。
///
/// 这里收敛为唯一实现：调用方只负责把解析出的 [DownloadAction] 接到
/// `downloadService` 上并给出对应文案。
class DownloadActionResolver {
  const DownloadActionResolver._();

  /// 依据任务当前状态解析动作
  ///
  /// 判定顺序与既有实现保持一致：**进行中 → 已完成 → 部分失败 → 继续 → 新建**。
  /// 顺序有意义：例如「部分失败」的任务同时满足"未完成、非进行中"，
  /// 必须优先判失败，否则会走成「继续下载」而把失败条目一起跳过。
  static DownloadAction resolve(DownloadTask? task) {
    if (task == null) return DownloadAction.start;
    if (task.isActive) return DownloadAction.pause;
    if (task.isFinished) return DownloadAction.alreadyFinished;
    if (task.failed.isNotEmpty) return DownloadAction.retryFailed;
    return DownloadAction.resume;
  }
}

/// 点击下载入口时应当执行的动作
enum DownloadAction {
  /// 全新开始下载（尚无任务）
  start,

  /// 暂停进行中的任务
  pause,

  /// 继续已暂停的任务
  resume,

  /// 重试存在失败条目的任务
  retryFailed,

  /// 已完整下载，无需动作（仅提示）
  alreadyFinished,
}
