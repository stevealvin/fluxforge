import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/media/comic/reader/comic_reader_page.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_chapter_image_pipeline.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_offline_images.dart';

/// 图片类作品阅读宿主：负责「章 → 图片」的解析与切章
///
/// ### 为什么需要宿主
/// 图片类作品的两种写法（见 [MediaContentShape]）在这里被统一：
///
/// - **图集**：detail 已给全图片 → 宿主直接把 [imageList] 交给阅读器，**零网络解析**；
/// - **漫画**：detail 只给章节 → 宿主用 [ComicChapterImagePipeline] 解析当前章并预取
///   相邻章；翻到章末由阅读器回调 [ComicReaderPage.onChapterChange] 触发切章。
///
/// 把「解析 + 切章 + 进度登记」收在宿主，而不塞进阅读器：阅读器因此保持
/// 「只渲染一屏图片」的纯粹职责（它本来也只接受 `imageList`）。
class ComicChapterReaderPage extends StatefulWidget {
  const ComicChapterReaderPage({
    super.key,
    required this.title,
    required this.mediaId,
    this.chapters = const [],
    this.imageList = const [],
    this.rule,
    this.headers,
    this.initialChapterIndex = 0,
    this.initialContinuousMode,
    this.pipeline,
  });

  final String title;

  /// 消费记录 / 收藏 / 下载共用的唯一标识（与详情页 `_mediaId` 同源）
  final String mediaId;

  /// 章节形态：章节表（图集形态传空）
  final List<MediaEpisode> chapters;

  /// 图集形态：detail 直接给出的图片（章节形态传空）
  final List<String> imageList;

  final Rule? rule;
  final Map<String, String>? headers;
  final int initialChapterIndex;
  final bool? initialContinuousMode;

  /// 可注入的解析管线（测试用；缺省自建）
  final ComicChapterImagePipeline? pipeline;

  @override
  State<ComicChapterReaderPage> createState() => _ComicChapterReaderPageState();
}

class _ComicChapterReaderPageState extends State<ComicChapterReaderPage> {
  late final ComicChapterImagePipeline _pipeline;

  late int _chapterIndex;

  /// 本次打开要恢复到的页（仅「同一章 / 同一本图集」有效；换章后归零）
  int _initialPage = 0;

  List<String> _images = const [];
  bool _loading = false;
  String? _error;

  /// 解析会话号：快速连点切章时，丢弃过期章的结果，避免"旧章图片盖在新章上"
  int _session = 0;

  bool get _isChapterShape => widget.chapters.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _pipeline = widget.pipeline ?? ComicChapterImagePipeline();
    _chapterIndex = widget.initialChapterIndex.clamp(
      0,
      widget.chapters.isEmpty ? 0 : widget.chapters.length - 1,
    );

    // 续读位置：记录里的页码只对「同一章 / 同一本图集」才有意义
    final record = playHistoryService.getById(widget.mediaId);
    if (record != null &&
        (!_isChapterShape || record.episodeIndex == _chapterIndex)) {
      _initialPage = record.pageIndex;
    }

    if (_isChapterShape) {
      _loadChapter(_chapterIndex, initial: true);
    } else {
      // 图集形态：图片已在 detail 里给全，直接渲染，不发任何解析请求
      _images = widget.imageList;
    }
  }

  Future<void> _loadChapter(int index, {bool initial = false}) async {
    final session = ++_session;
    final chapter = widget.chapters[index];

    setState(() {
      _chapterIndex = index;
      _loading = true;
      _error = null;
      if (!initial) _images = const [];
    });

    final images = await _pipeline.resolve(rule: widget.rule, chapter: chapter);
    if (!mounted || session != _session) return;

    // 已离线下载的图片换成本地路径（未下载的原样）→ 下载过的章断网也能读
    final localized = await resolveComicOfflineImages(
      images,
      bookId: widget.mediaId,
    );
    if (!mounted || session != _session) return;

    setState(() {
      _loading = false;
      _images = localized;
      _error = localized.isEmpty ? '本章图片解析失败，可稍后重试' : null;
    });

    if (images.isEmpty) return;
    _pipeline.prefetchNeighbors(
      rule: widget.rule,
      chapters: widget.chapters,
      index: index,
    );
    _persistProgress(chapter);
  }

  void _onChapterChange(int delta) {
    final target = _chapterIndex + delta;
    if (target < 0 || target >= widget.chapters.length) return;
    HapticFeedback.selectionClick();
    _loadChapter(target);
  }

  /// 章节目录：直接跳到任意一章（长作品不必逐章翻）
  void _openCatalog() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      // 用 Material 承载底色（而非带色 DecoratedBox）：ListTile 的墨溅画在最近的
      // Material 上，被有底色的容器挡在外面会丢掉点击反馈（Flutter 会直接断言）。
      // 底色与文字**跟随主题**：原来写死深色底 + 白色字，浅色主题下是一块突兀的黑。
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final titleColor = isDark
            ? AppColors.darkTextPrimary
            : AppColors.lightTextPrimary;
        final mutedColor = isDark
            ? AppColors.darkTextMuted
            : AppColors.lightTextMuted;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          child: Material(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            child: SizedBox(
              height: MediaQuery.of(sheetContext).size.height * 0.62,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                    child: Row(
                      children: [
                        Text(
                          '章节目录',
                          style: TextStyle(
                            color: titleColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '共 ${widget.chapters.length} 章',
                          style: TextStyle(color: mutedColor, fontSize: 12),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: Icon(
                            Ionicons.closeOutline,
                            color: mutedColor,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: isDark ? Colors.white12 : Colors.black12,
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: widget.chapters.length,
                      itemBuilder: (context, index) {
                        final selected = index == _chapterIndex;
                        return ListTile(
                          dense: true,
                          title: Text(
                            widget.chapters[index].title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              color: selected ? AppColors.primary : titleColor,
                              fontWeight: selected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                            ),
                          ),
                          trailing: selected
                              ? const Icon(
                                  Ionicons.playCircle,
                                  size: 16,
                                  color: AppColors.primary,
                                )
                              : null,
                          onTap: () {
                            Navigator.pop(sheetContext);
                            if (index != _chapterIndex) _loadChapter(index);
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// 页内位置变化 → 登记「看到第几页」
  ///
  /// 不传 `forceNotify`：服务层自带刷盘节流，纵向连续滚动时不会每帧写盘。
  void _onPageChanged(int index, int total) {
    if (widget.mediaId.isEmpty) return;
    final chapter = _isChapterShape ? widget.chapters[_chapterIndex] : null;
    playHistoryService.updateProgress(
      id: widget.mediaId,
      episodeName: chapter?.title ?? widget.title,
      episodeIndex: _isChapterShape ? _chapterIndex : 0,
      totalEpisodes: _isChapterShape ? widget.chapters.length : total,
      pageIndex: index,
    );
  }

  /// 切章即登记进度（「我的 → 继续阅读」据此回到正确的章）
  void _persistProgress(MediaEpisode chapter) {
    if (widget.mediaId.isEmpty) return;
    playHistoryService.updateProgress(
      id: widget.mediaId,
      episodeName: chapter.title,
      episodeIndex: _chapterIndex,
      totalEpisodes: widget.chapters.length,
      // 换章即回到该章第 0 页：否则会把上一章的页码带过来（续读会跳到错误位置）
      pageIndex: 0,
      forceNotify: true,
    );
  }

  String get _chapterTitle {
    if (!_isChapterShape) return widget.title;
    final chapter = widget.chapters[_chapterIndex];
    final name = chapter.title.trim();
    if (name.isEmpty) return widget.title;
    return '${widget.title} · $name';
  }

  @override
  Widget build(BuildContext context) {
    if (_isChapterShape && _images.isEmpty) {
      return _buildStatusView();
    }

    return ComicReaderPage(
      // 每章一个 key：换章即重建阅读器，避免残留上一章的滚动位置与页码
      key: ValueKey<String>('comic-chapter-$_chapterIndex'),
      imageList: _images,
      title: _chapterTitle,
      initialIndex: _initialPage.clamp(
        0,
        _images.isEmpty ? 0 : _images.length - 1,
      ),
      onPageChanged: _onPageChanged,
      headers: widget.headers,
      initialContinuousMode: widget.initialContinuousMode,
      onChapterChange: _isChapterShape ? _onChapterChange : null,
      onOpenCatalog: _isChapterShape ? _openCatalog : null,
      hasPreviousChapter: _isChapterShape && _chapterIndex > 0,
      hasNextChapter:
          _isChapterShape && _chapterIndex < widget.chapters.length - 1,
    );
  }

  /// 解析中 / 解析失败态（章节形态下图片为空时）
  Widget _buildStatusView() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.chapters[_chapterIndex].title,
          style: const TextStyle(fontSize: 15),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_loading)
              const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                ),
              )
            else
              const Icon(
                Ionicons.alertCircleOutline,
                size: 34,
                color: Colors.white38,
              ),
            const SizedBox(height: 12),
            Text(
              _loading ? '正在解析本章图片…' : (_error ?? '暂无图片'),
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            if (!_loading) ...[
              const SizedBox(height: 14),
              TextButton(
                onPressed: () => _loadChapter(_chapterIndex),
                child: const Text('重新解析'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
