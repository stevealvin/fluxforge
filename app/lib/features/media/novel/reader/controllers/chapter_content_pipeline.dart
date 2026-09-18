import 'package:flutter/foundation.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/domain/text/novel_text.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/chapter_cache.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';

/// 离线章节存取接口
///
/// 把 `DownloadService` 的三项能力收敛为一个窄接口：生产环境用
/// [GlobalOfflineChapterStore] 接全局服务，测试可注入内存替身，
/// 从而让 [ChapterContentPipeline] 能脱离沙盒与网络单测。
abstract class OfflineChapterStore {
  /// 该章是否已落盘
  bool isDownloaded(String bookId, int index);

  /// 读取已落盘的章节正文
  Future<String?> read(String bookId, int index);

  /// 保存章节正文（与下载管理页共用同一套任务记录）
  Future<bool> save({
    required Rule rule,
    required String bookId,
    required String title,
    required List<MediaEpisode> chapters,
    required int index,
    required String content,
  });
}

/// 默认实现：直连全局 `downloadService`
class GlobalOfflineChapterStore implements OfflineChapterStore {
  const GlobalOfflineChapterStore();

  @override
  bool isDownloaded(String bookId, int index) =>
      downloadService.isNovelChapterDownloaded(bookId, index);

  @override
  Future<String?> read(String bookId, int index) =>
      downloadService.readNovelChapter(bookId, index);

  @override
  Future<bool> save({
    required Rule rule,
    required String bookId,
    required String title,
    required List<MediaEpisode> chapters,
    required int index,
    required String content,
  }) =>
      downloadService.saveNovelChapterContent(
        rule: rule,
        bookId: bookId,
        title: title,
        cover: '',
        chapters: chapters,
        index: index,
        content: content,
      );
}

/// 章节正文获取管道
///
/// 统一管理三级正文来源与后台调度：
/// 1. **内存会话缓存**（[ChapterCache]）—— 最快，退出阅读器即释放；
/// 2. **沙盒离线文件**（[OfflineChapterStore]）—— 持久化，断网可读；
/// 3. **网络沙箱抓取**（[RuleEngine] + 正文清洗）—— 最后兜底。
///
/// 并区分两种后台策略：
/// - [prefetch]：只写内存缓存，本次阅读内切章零等待；
/// - [downloadOffline] / [persistOffline]：写入沙盒，长期可读。
class ChapterContentPipeline {
  ChapterContentPipeline({
    required this.bookTitle,
    required this.offlineBookId,
    required this.rule,
    required this.chapters,
    required this.cache,
    required this.prefetching,
    required this.cacheWriter,
    OfflineChapterStore? offlineStore,
    Future<Object?> Function(Rule rule, String url)? parseRule,
    this.onPersisted,
    this.onPrefetched,
  })  : offlineStore = offlineStore ?? const GlobalOfflineChapterStore(),
        _parseRule = parseRule ?? _defaultParseRule;

  static Future<Object?> _defaultParseRule(Rule rule, String url) =>
      RuleEngine.parse(rule, url);

  final String bookTitle;
  final String? offlineBookId;
  final Rule? rule;

  /// 全量章节（按索引取用；管道只读章节自带正文与地址）
  final List<NovelChapter> chapters;

  final ChapterCache cache;

  /// 正在预取 / 下载中的章节索引（与页面共用同一份，用于去重与目录状态展示）
  final Set<int> prefetching;

  /// 写入会话缓存 —— 由页面实现，以便一并完成容量回收与章节模型同步
  final void Function(int index, String content) cacheWriter;

  final OfflineChapterStore offlineStore;

  final Future<Object?> Function(Rule rule, String url) _parseRule;

  /// 落盘成功回调（页面据此解除纵向续载熔断并刷新目录图标）
  final ValueChanged<int>? onPersisted;

  /// 预取成功回调（页面据此刷新「已缓存 N 章」展示）
  final VoidCallback? onPrefetched;

  /// 是否具备离线落盘条件（详情页进入时才会带上书籍标识与解析规则）
  bool get canDownloadOffline =>
      (offlineBookId?.isNotEmpty ?? false) && rule != null;

  /// 已离线下载到沙盒的章节数量（与下载管理页共用同一份任务记录）
  int get downloadedCount {
    final bookId = offlineBookId;
    if (bookId == null || bookId.isEmpty) return 0;
    return downloadService.taskOf(bookId)?.completed.length ?? 0;
  }

  /// 该章节是否已离线下载到本地沙盒
  bool isOfflineDownloaded(int index) {
    final bookId = offlineBookId;
    if (bookId == null || bookId.isEmpty) return false;
    return offlineStore.isDownloaded(bookId, index);
  }

  /// 读取沙盒中已离线下载的章节正文（未下载返回 null）
  Future<String?> readOffline(int index) async {
    final bookId = offlineBookId;
    if (bookId == null || bookId.isEmpty) return null;
    if (!isOfflineDownloaded(index)) return null;
    return offlineStore.read(bookId, index);
  }

  /// 确保指定章节正文可用：内存缓存 → 沙盒离线 → 网络沙箱
  ///
  /// 返回清洗后的正文；失败返回 null（由调用方决定是否降级展示）。
  /// 该方法为「纯数据获取」，不触碰 UI 状态，因此可安全用于后台预取与纵向续载。
  Future<String?> ensureContent(int index) async {
    if (index < 0 || index >= chapters.length) return null;

    final cached = cache[index];
    if (cached != null && cached.isNotEmpty) return cached;

    // 0. 优先读取沙盒中的离线下载正文（断网可读，且无需再走网络请求）
    final offline = await readOffline(index);
    if (offline != null && offline.isNotEmpty) {
      cacheWriter(index, offline);
      return offline;
    }

    final url = chapters[index].url?.trim() ?? '';
    // 无远程地址时退化为本地已有正文
    if (url.isEmpty) {
      final local = chapters[index].content;
      if (local.isNotEmpty) {
        cacheWriter(index, local);
        return local;
      }
      return null;
    }

    final ruleRef = rule;
    if (ruleRef == null) return null;

    try {
      final res = await _parseRule(ruleRef, url);
      final String raw = res is Map
          ? (res['content']?.toString() ?? res['text']?.toString() ?? '')
          : (res is String ? res : '');
      final clean = cleanNovelContent(raw);
      if (clean.isEmpty) return null;
      cacheWriter(index, clean);
      return clean;
    } catch (_) {
      // 后台预取失败静默忽略：用户真正切到该章时会走正常加载与错误提示流程
      return null;
    }
  }

  /// 静默预取指定章节正文（只写内存缓存，不改变当前显示）
  ///
  /// 本次阅读内切章零等待，退出阅读器即释放、不占用磁盘 ——
  /// 需要长期留存（断网可读）请走 [downloadOffline] 或目录里的手动下载。
  ///
  /// 返回是否真的取到了新正文（供调用方决定是否给出反馈）。
  Future<bool> prefetch(int index) async {
    if (index < 0 || index >= chapters.length) return false;
    if (cache.containsKey(index)) return false;
    if (prefetching.contains(index)) return false;

    prefetching.add(index);
    final content = await ensureContent(index);
    prefetching.remove(index);

    if (content == null) return false;
    onPrefetched?.call();
    return true;
  }

  /// 抓取并落盘指定章节（跳章自动下载 / 目录手动下载共用）
  ///
  /// 正文已在内存缓存时**直接复用落盘，不产生额外网络请求**；
  /// 未缓存才调度一次抓取，抓完同时写内存与沙盒。
  Future<bool> downloadOffline(int index) async {
    if (index < 0 || index >= chapters.length) return false;
    if (isOfflineDownloaded(index)) return true;

    final cached = cache[index];
    if (cached != null && cached.isNotEmpty) {
      return persistOffline(index, cached);
    }

    if (prefetching.contains(index)) return false;
    prefetching.add(index);
    final content = await ensureContent(index);
    prefetching.remove(index);

    if (content == null || content.isEmpty) return false;
    return persistOffline(index, content);
  }

  /// 把已抓取到的章节正文落盘为离线数据（复用同一次抓取结果，不二次请求）
  ///
  /// 与手动下载共用同一套沙盒文件与任务记录，因此目录图标、下载管理页与
  /// 阅读器看到的状态始终一致。
  Future<bool> persistOffline(int index, String content) async {
    final bookId = offlineBookId;
    final ruleRef = rule;
    if (bookId == null || bookId.isEmpty || ruleRef == null) return false;
    if (isOfflineDownloaded(index)) return true;

    final saved = await offlineStore.save(
      rule: ruleRef,
      bookId: bookId,
      title: bookTitle,
      chapters: chapters
          .map((c) => MediaEpisode(title: c.title, url: c.url ?? ''))
          .toList(),
      index: index,
      content: content,
    );

    if (saved) onPersisted?.call(index);
    return saved;
  }

  /// 跳章后的相邻章节处理
  ///
  /// - 具备离线条件：把**前后相邻章节各下载一章**到沙盒，保证向上回溯与向下续读
  ///   都不必等待；已缓存的章节复用正文，不会产生额外网络请求；
  /// - 不具备离线条件：退化为纯内存临时预取。
  void handleChapterJumped(int currentIndex) {
    if (!canDownloadOffline) {
      prefetchAdjacent(currentIndex);
      return;
    }

    final prev = currentIndex - 1;
    if (prev >= 0) downloadOffline(prev);

    final next = currentIndex + 1;
    if (next < chapters.length) downloadOffline(next);
  }

  /// 触发相邻章节双向预取（向前/向后均提前预载，实现顺读与回溯零卡顿）
  void prefetchAdjacent(int currentIndex) {
    // 优先预取下一章
    final next = currentIndex + 1;
    if (next < chapters.length && !cache.containsKey(next)) {
      prefetch(next);
    }
    // 同步预取上一章
    final prev = currentIndex - 1;
    if (prev >= 0 && !cache.containsKey(prev)) {
      prefetch(prev);
    }
  }
}
