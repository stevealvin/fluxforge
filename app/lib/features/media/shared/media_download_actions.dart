import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/library/downloads/engines/download_action_resolver.dart';

/// 详情页「离线下载」的统一动作层
///
/// 原先小说 / 漫画 / 视频三个详情页各自实现「任务状态 → 动作」的接线（三份逐行同构，
/// 只有「全新下载」那一步的调用不同）。这里收敛为唯一入口：详情页（顶部栏下载入口 +
/// 底部下载面板）只负责展示与提示，取数与动作全在这里。
///
/// 与 `backup_actions.dart` 同一模式：动作返回**面向用户的提示文案**，由 UI 只负责展示。
class MediaDownloadActions {
  const MediaDownloadActions._();

  /// 下载任务的唯一键（与三类详情页原先的口径一致）
  ///
  /// 优先媒体 URL，缺失时退回标题 —— 关键是「查询任务」与「发起下载」必须用同一个键，
  /// 否则会出现「点了下载却查不到任务」。
  static String taskKey(MediaDetailData data, String fallbackTitle) {
    if (data.url.trim().isNotEmpty) return data.url.trim();
    if (fallbackTitle.trim().isNotEmpty) return fallbackTitle.trim();
    return data.title;
  }

  /// 点击下载入口：按任务状态执行 暂停 / 继续 / 重试 / 新建，返回提示文案
  static Future<String> handleTap({
    required MediaDetailData data,
    required Rule? rule,
    required DownloadTask? task,
    String fallbackTitle = '',
    String fallbackCover = '',
  }) async {
    if (rule == null) return '未绑定解析规则，无法下载';

    final bookId = taskKey(data, fallbackTitle);
    final title = data.title.isNotEmpty ? data.title : fallbackTitle;
    final cover = data.cover.isNotEmpty ? data.cover : fallbackCover;

    // 任务状态 → 动作的判定统一由引擎给出（三类详情页共用同一份）
    switch (DownloadActionResolver.resolve(task)) {
      case DownloadAction.pause:
        downloadService.pause(task!.id);
        return '已暂停下载';
      case DownloadAction.alreadyFinished:
        return '该作品已完整下载到本地沙盒';
      case DownloadAction.retryFailed:
        downloadService.retryFailed(task!.id);
        return '已重新开始下载失败内容';
      case DownloadAction.resume:
        downloadService.resume(task!.id);
        return '已继续下载';
      case DownloadAction.start:
        break;
    }

    // 全新下载：按媒体类型取产物清单
    switch (data.mediaType) {
      case MediaType.novel:
        final chapters = data.chapters;
        if (chapters.isEmpty) return '暂无可下载的章节';
        await downloadService.startNovelDownload(
          rule: rule,
          bookId: bookId,
          title: title,
          cover: cover,
          chapters: chapters,
        );
      case MediaType.comic:
        final urls = collectComicImageUrls(data);
        if (urls.isEmpty) return '暂无可下载的图片';
        await downloadService.startComicDownload(
          rule: rule,
          bookId: bookId,
          title: title,
          cover: cover,
          imageUrls: urls,
          headers: data.customHeaders,
        );
      default:
        // 视频：以首条线路为准（详情页顶部栏不掌握选集线路的切换状态）
        final episodes =
            data.videoGroups.isNotEmpty && data.videoGroups.first.items.isNotEmpty
                ? data.videoGroups.first.items
                : data.items;
        if (episodes.isEmpty) return '暂无可下载的剧集';
        await downloadService.startVideoDownload(
          rule: rule,
          bookId: bookId,
          title: title,
          cover: cover,
          episodes: episodes,
        );
    }
    return '已加入下载队列，可在「我的 → 离线下载」查看进度';
  }

  /// 收集图片类作品可离线下载的全部图片地址（图集 + 各分组章节）
  ///
  /// 原先私有实现在漫画详情页内部，现随动作层一起上提。
  static List<String> collectComicImageUrls(MediaDetailData data) {
    final urls = <String>{};
    for (final url in data.imageList) {
      if (url.trim().isNotEmpty) urls.add(url.trim());
    }
    for (final group in data.comicGroups) {
      for (final item in group.items) {
        if (item.url.trim().isNotEmpty) urls.add(item.url.trim());
      }
    }
    return urls.toList();
  }
}
