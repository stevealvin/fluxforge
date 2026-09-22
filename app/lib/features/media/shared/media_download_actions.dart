import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/core/utils/media_utils.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/library/downloads/engines/download_action_resolver.dart';
import 'package:fluxforge/features/library/downloads/models/download_unit.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_chapter_image_pipeline.dart';

/// 详情页「离线下载」的统一动作层
///
/// 原先小说 / 漫画 / 视频三个详情页各自实现「任务状态 → 动作」的接线（三份逐行同构，
/// 只有「全新下载」那一步的调用不同）。这里收敛为唯一入口：详情页（顶部栏下载入口 +
/// 底部下载面板）只负责展示与提示，取数与动作全在这里。
///
/// 与 `backup_actions.dart` 同一模式：动作返回**面向用户的提示文案**，由 UI 只负责展示。
class MediaDownloadActions {
  const MediaDownloadActions._();

  /// 下载任务的唯一键（与三类详情页共用同一口径）
  ///
  /// 优先媒体 URL，缺失时退回标题 —— 关键是「查询任务」与「发起下载」必须用同一个键，
  /// 否则会出现「点了下载却查不到任务」。
  static String taskKey(
    MediaDetailData data,
    String fallbackTitle, {
    Rule? rule,
  }) {
    final raw = data.url.trim();
    // 相对地址（如 `/detail/1.html`）用规则 baseUrl 归一化为绝对地址：
    // 键要唯一，而相对地址在不同站点间会撞。请求时用的原文另存于 MediaRef/记录里。
    if (raw.isNotEmpty) {
      return resolveMediaUrl(raw, baseUrl: rule?.baseUrl ?? '');
    }
    if (fallbackTitle.trim().isNotEmpty) return fallbackTitle.trim();
    return data.title;
  }

  /// 可下载单元清单（选集下载的候选项）
  ///
  /// 与 [handleTap] 的「全部下载」**同源同序**：视频都取首条线路、漫画都按同一份
  /// 章节/图片清单，因此单元下标与下载任务里的目标下标一一对应。
  static List<DownloadUnit> unitsOf(MediaDetailData data) {
    switch (data.mediaType) {
      case MediaType.novel:
        return [
          for (int i = 0; i < data.chapters.length; i++)
            DownloadUnit(
              index: i,
              title: _fallbackTitle(data.chapters[i].title, '第 ${i + 1} 章'),
            ),
        ];
      case MediaType.comic:
        final chapters = [
          for (final group in data.readableComicGroups) ...group.items,
        ];
        // 图集形态：detail 已给全图片，按「页」为单位提供
        if (chapters.isEmpty || !data.needsChapterParse) {
          final pages = data.imageList
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          return [
            for (int i = 0; i < pages.length; i++)
              DownloadUnit(index: i, title: '第 ${i + 1} 页'),
          ];
        }
        return [
          for (int i = 0; i < chapters.length; i++)
            DownloadUnit(
              index: i,
              title: _fallbackTitle(chapters[i].title, '第 ${i + 1} 章'),
            ),
        ];
      default:
        return [
          for (final (index, episode) in _downloadableEpisodes(data))
            DownloadUnit(
              index: index,
              title: _fallbackTitle(episode.title, '第 ${index + 1} 集'),
            ),
        ];
    }
  }

  /// 各单元对应的直链地址（大小探测用）；无地址的位置为空串
  static List<String> unitUrls(MediaDetailData data) {
    switch (data.mediaType) {
      case MediaType.novel:
        return [for (final c in data.chapters) c.url.trim()];
      case MediaType.comic:
        final chapters = [
          for (final group in data.readableComicGroups) ...group.items,
        ];
        if (chapters.isEmpty || !data.needsChapterParse) {
          return [
            for (final url in data.imageList)
              if (url.trim().isNotEmpty) url.trim(),
          ];
        }
        // 漫画每章要再解析一层才知道地址，探测成本高且无意义 → 不提供
        return const [];
      default:
        return [
          for (final (_, episode) in _downloadableEpisodes(data))
            episode.url.trim(),
        ];
    }
  }

  /// 选集下载：忽略既有任务状态，直接按选中的单元范围（重新）调度
  ///
  /// 与 [handleTap] 的分工：那个入口面向「状态机」（暂停 / 继续 / 重试 / 新建），
  /// 这个入口面向「范围」—— 用户明确要在这次下载哪些单元，直接照办。
  static Future<String> downloadSelection({
    required MediaDetailData data,
    required Rule? rule,
    required Set<int> selection,
    String fallbackTitle = '',
    String fallbackCover = '',
  }) async {
    if (rule == null) return '未绑定解析规则，无法下载';
    if (selection.isEmpty) return '请先选择要下载的内容';

    final bookId = taskKey(data, fallbackTitle, rule: rule);
    final message = await _startScope(
      data: data,
      rule: rule,
      bookId: bookId,
      title: data.title.isNotEmpty ? data.title : fallbackTitle,
      cover: data.cover.isNotEmpty ? data.cover : fallbackCover,
      selection: selection,
    );
    if (message != null) return message;
    return '已加入下载队列（${selection.length} 项）';
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

    final bookId = taskKey(data, fallbackTitle, rule: rule);
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

    // 全新下载：按媒体类型取产物清单（全部下载 = 范围未限定）
    final message = await _startScope(
      data: data,
      rule: rule,
      bookId: bookId,
      title: title,
      cover: cover,
      selection: null,
    );
    if (message != null) return message;
    return '已加入下载队列，可在「我的 → 离线下载」查看进度';
  }

  /// 按范围发起下载；返回 `null` 表示已入队，否则返回给用户的提示文案
  static Future<String?> _startScope({
    required MediaDetailData data,
    required Rule rule,
    required String bookId,
    required String title,
    required String cover,
    required Set<int>? selection,
  }) async {
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
          selectedIndices: selection,
        );
      case MediaType.comic:
        final result = await collectComicDownload(
          data: data,
          rule: rule,
          selectedChapters: selection,
        );
        if (result.urls.isEmpty) return '暂无可下载的图片';
        await downloadService.startComicDownload(
          rule: rule,
          bookId: bookId,
          title: title,
          cover: cover,
          imageUrls: result.urls,
          headers: data.customHeaders,
          selectedIndices: result.selection,
        );
      default:
        final episodes = _videoEpisodes(data);
        if (episodes.isEmpty) return '暂无可下载的剧集';
        await downloadService.startVideoDownload(
          rule: rule,
          bookId: bookId,
          title: title,
          cover: cover,
          episodes: episodes,
          selectedIndices: selection,
        );
    }
    return null;
  }

  /// 视频待下载分集：以首条线路为准（详情页顶部栏不掌握线路切换状态）
  static List<MediaEpisode> _videoEpisodes(MediaDetailData data) {
    if (data.videoGroups.isNotEmpty &&
        data.videoGroups.first.items.isNotEmpty) {
      return data.videoGroups.first.items;
    }
    return data.items;
  }

  /// 可下载的分集（**原下标** + 分集）
  ///
  /// 无地址的分集既进不了下载目标，也不该出现在选集列表里 ——
  /// 选中它只会得到一个 0/0 的空任务。下标保留原位置：下载目标清单是全量的，
  /// 选集靠下标定位（见 `DownloadService.startVideoDownload` 的重映射）。
  static List<(int, MediaEpisode)> _downloadableEpisodes(MediaDetailData data) {
    final all = _videoEpisodes(data);
    final result = <(int, MediaEpisode)>[];
    for (int i = 0; i < all.length; i++) {
      if (all[i].url.trim().isEmpty) continue;
      result.add((i, all[i]));
    }
    return result;
  }

  static String _fallbackTitle(String title, String fallback) =>
      title.trim().isNotEmpty ? title.trim() : fallback;

  /// 收集图片类作品可离线下载的全部图片地址
  ///
  /// **按内容形态分流**（元素类型推断，见 [MediaContentShape]）：
  /// - **图集**：`items` 直接就是图片 → 直接收集；
  /// - **漫画**：`items` / `groups` 只给**章节页地址** → 逐章解析出真正的图片列表。
  ///
  /// 单章解析失败只跳过该章，不影响其余章节入队。
  static Future<List<String>> collectComicImageUrls(
    MediaDetailData data, {
    Rule? rule,
    ComicChapterImagePipeline? pipeline,
  }) async {
    final result = await collectComicDownload(
      data: data,
      rule: rule,
      pipeline: pipeline,
    );
    return result.urls;
  }

  /// 收集图片类作品的图片地址，并给出「选中单元 → 图片下标」的映射
  ///
  /// 与 [collectComicImageUrls] 的唯一区别是**保留下标语义**：
  /// - 图集：单元就是「页」，直接按 `imageList` 的有效项对齐下标（不去重，
  ///   否则页号会与下标错位）；
  /// - 漫画：逐章解析得到图片，同一地址只留首次出现的位置（下载一次即可），
  ///   选中章贡献的图片下标收进 [selection]。
  static Future<({List<String> urls, Set<int>? selection})>
  collectComicDownload({
    required MediaDetailData data,
    Rule? rule,
    ComicChapterImagePipeline? pipeline,
    Set<int>? selectedChapters,
  }) async {
    final chapters = [
      for (final group in data.readableComicGroups) ...group.items,
    ];

    // 图集形态（详情已给全图片）或无法解析（缺规则）→ 不做二次解析
    if (chapters.isEmpty || !data.needsChapterParse || rule == null) {
      final pages = [
        for (final url in data.imageList)
          if (url.trim().isNotEmpty) url.trim(),
      ];
      return (
        urls: pages,
        selection: selectedChapters == null
            ? null
            : {
                for (final i in selectedChapters)
                  if (i >= 0 && i < pages.length) i,
              },
      );
    }

    final engine = pipeline ?? ComicChapterImagePipeline();
    final urls = <String>[];
    final indexOf = <String, int>{};
    final selection = <int>{};

    for (int c = 0; c < chapters.length; c++) {
      final chapterSelected =
          selectedChapters == null || selectedChapters.contains(c);
      final images = await engine.resolve(rule: rule, chapter: chapters[c]);
      for (final raw in images) {
        final url = raw.trim();
        if (url.isEmpty) continue;
        final existing = indexOf[url];
        if (existing != null) {
          if (chapterSelected) selection.add(existing);
          continue;
        }
        indexOf[url] = urls.length;
        urls.add(url);
        if (chapterSelected) selection.add(urls.length - 1);
      }
    }

    return (urls: urls, selection: selectedChapters == null ? null : selection);
  }
}
