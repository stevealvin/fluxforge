import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/rule.dart';
import '../../../services/di.dart';
import '../../../services/play_history_service.dart';
import '../../../widgets/app_card.dart';
import '../common/media_meta_header.dart';
import '../common/media_related_grid.dart';
import '../../../models/media.dart';
import 'reader/novel_reader_page.dart';

/// 小说文学业务专属详情视图
class NovelDetailView extends StatefulWidget {
  const NovelDetailView({
    super.key,
    required this.data,
    this.rule,
    this.fallbackTitle = '',
    this.fallbackCover = '',
    this.onRelatedItemTap,
    this.onShareTap,
  });

  final MediaDetailData data;
  final Rule? rule;
  final String fallbackTitle;
  final String fallbackCover;
  final void Function(MediaRelatedItem item)? onRelatedItemTap;
  final VoidCallback? onShareTap;

  @override
  State<NovelDetailView> createState() => _NovelDetailViewState();
}

class _NovelDetailViewState extends State<NovelDetailView> {
  bool _isReversed = false;

  /// 当前书籍的唯一消费标识 (优先详情页 URL，兜底标题)
  String get _mediaId {
    if (widget.data.url.isNotEmpty) return widget.data.url;
    if (widget.fallbackTitle.isNotEmpty) return widget.fallbackTitle;
    return widget.data.title;
  }

  /// 是否存在可续读的历史章节进度
  bool get _hasReadingProgress {
    final record = playHistoryService.getById(_mediaId);
    return record != null && record.episodeIndex > 0;
  }

  /// 上次读到的章节索引 (用于「继续阅读」章节级续读)
  int get _resumeChapterIndex {
    final total = widget.data.chapters.length;
    if (total <= 0) return 0;
    final idx = playHistoryService.getById(_mediaId)?.episodeIndex ?? 0;
    return idx.clamp(0, total - 1);
  }

  @override
  void initState() {
    super.initState();
    _registerPlayRecord();
  }

  /// 登记 / 更新当前书籍的消费记录 (保留既有阅读进度)
  void _registerPlayRecord() {
    if (_mediaId.isEmpty) return;
    final existing = playHistoryService.getById(_mediaId);
    playHistoryService.upsert(
      PlayRecord(
        id: _mediaId,
        title: widget.data.title.isNotEmpty ? widget.data.title : widget.fallbackTitle,
        cover: widget.data.cover.isNotEmpty ? widget.data.cover : widget.fallbackCover,
        mediaType: 'novel',
        ruleId: widget.rule?.id?.toString() ?? '',
        episodeName: existing?.episodeName ?? '',
        episodeIndex: existing?.episodeIndex ?? 0,
        totalEpisodes: widget.data.chapters.length,
        updatedAt: DateTime.now(),
      ),
    );
  }

  /// 阅读器章节切换回调 → 同步阅读进度
  void _onChapterChanged(int index, String title) {
    playHistoryService.updateProgress(
      id: _mediaId,
      episodeName: title,
      episodeIndex: index,
      totalEpisodes: widget.data.chapters.length,
      forceNotify: true,
    );
  }

  /// 打开纯净小说阅读引擎
  void _openReader({int initialIndex = 0}) {
    HapticFeedback.lightImpact();

    final readerChapters = widget.data.chapters.map((ch) {
      return NovelChapter(
        title: ch.title,
        content: '',
        url: ch.url,
      );
    }).toList();

    if (readerChapters.isEmpty) {
      readerChapters.add(
        NovelChapter(
          title: widget.data.title.isNotEmpty ? widget.data.title : widget.fallbackTitle,
          content: widget.data.textContent ?? '',
          url: widget.data.url,
        ),
      );
    } else if (widget.data.textContent != null && widget.data.textContent!.isNotEmpty) {
      readerChapters[0] = readerChapters[0].copyWith(content: widget.data.textContent);
    }

    // 记录本次进入阅读器的起始章节，保证退出后的阅读进度可续读
    final safeIndex = initialIndex.clamp(0, readerChapters.length - 1);
    _onChapterChanged(safeIndex, readerChapters[safeIndex].title);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovelReaderPage(
          bookTitle: widget.data.title.isNotEmpty ? widget.data.title : widget.fallbackTitle,
          initialChapterIndex: safeIndex,
          chapters: readerChapters,
          rule: widget.rule,
          customHeaders: widget.data.customHeaders,
          onChapterChanged: _onChapterChanged,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chapters = widget.data.chapters;
    final displayChapters = _isReversed ? chapters.reversed.toList() : chapters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 小说头部元信息 (封面默认展示)
        MediaMetaHeader(
          data: widget.data,
          rule: widget.rule,
          fallbackTitle: widget.fallbackTitle,
          fallbackCover: widget.fallbackCover,
          onShareTap: widget.onShareTap,
        ),

        // 2. 醒目“开始阅读”主操作大卡片
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: AppCard(
            padding: const EdgeInsets.symmetric(vertical: 12),
            borderRadius: 12,
            color: AppColors.primary,
            onTap: () => _openReader(initialIndex: _resumeChapterIndex),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Ionicons.bookOutline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  chapters.isNotEmpty
                      ? (_hasReadingProgress
                          ? '继续阅读 (第 ${_resumeChapterIndex + 1} 章 / 共 ${chapters.length} 章)'
                          : '开始阅读 (共 ${chapters.length} 章)')
                      : '立即畅读正文',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),

        // 3. 目录选章列表 (修复深色模式底色为 darkCard 实体材质与微光边框)
        if (chapters.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Container(
                  width: 3.5,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '目录选章',
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '共 ${chapters.length} 章',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
                const Spacer(),

                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _isReversed = !_isReversed;
                    });
                  },
                  child: Row(
                    children: [
                      Icon(Ionicons.swapVerticalOutline,
                        size: 13,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _isReversed ? '倒序' : '正序',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: displayChapters.length.clamp(0, 30),
              separatorBuilder: (context, index) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final ch = displayChapters[index];
                final realIndex = _isReversed ? (chapters.length - 1 - index) : index;
                return AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  borderRadius: 10,
                  showBorder: true,
                  borderColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  onTap: () => _openReader(initialIndex: realIndex),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          ch.title,
                          style: const TextStyle(
                            fontSize: 13,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          if (chapters.length > 30)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Center(
                child: TextButton.icon(
                  onPressed: () => _openReader(initialIndex: _resumeChapterIndex),
                  icon: const Icon(Ionicons.listOutline, size: 14, color: AppColors.primary),
                  label: Text(
                    '进入阅读器查看全部 ${chapters.length} 章节',
                    style: const TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 12),
        ],

        // 4. 小说相关推荐 (默认 3 列海报纵向卡片)
        MediaRelatedGrid(
          related: widget.data.related,
          currentRule: widget.rule,
          onItemTap: widget.onRelatedItemTap,
        ),
      ],
    );
  }
}
