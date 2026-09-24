import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/features/media/shared/media_download_actions.dart';
import 'package:fluxforge/features/media/shared/media_history_registrar.dart';
import 'package:fluxforge/features/media/shared/media_meta_header.dart';
import 'package:fluxforge/features/media/shared/media_related_grid.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/novel/reader/novel_reader_page.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';

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
    return MediaDownloadActions.taskKey(
      widget.data,
      widget.fallbackTitle,
      rule: widget.rule,
    );
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

  /// 登记 / 更新当前书籍的消费记录
  ///
  /// 小说沿用既有**章节位置**（打开详情页不应改变「读到第几章」），
  /// 播放秒数按 [PlayRecord] 约定恒为 0 —— 规则由 [MediaHistoryRegistrar] 统一承载。
  void _registerPlayRecord() {
    MediaHistoryRegistrar.register(
      id: _mediaId,
      url: widget.data.url,
      title: widget.data.title.isNotEmpty
          ? widget.data.title
          : widget.fallbackTitle,
      cover: widget.data.cover.isNotEmpty
          ? widget.data.cover
          : widget.fallbackCover,
      mediaType: 'novel',
      ruleId: widget.rule?.id?.toString() ?? '',
      totalEpisodes: widget.data.chapters.length,
      preserveEpisode: true,
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

  /// 续读主操作（挂在头部右列底部）
  ///
  /// 文案按状态分三档：没有章节时是"畅读正文"（详情已带正文），有进度说
  /// 「继续阅读 第 N 章」，否则是「开始阅读 共 N 章」。
  Widget _buildResumeButton(List<MediaEpisode> chapters) {
    final label = chapters.isEmpty
        ? '立即畅读正文'
        : (_hasReadingProgress
              ? '继续阅读 · 第 ${_resumeChapterIndex + 1} 章'
              : '开始阅读 · 共 ${chapters.length} 章');

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _openReader(initialIndex: _resumeChapterIndex),
        icon: const Icon(Ionicons.bookOutline, size: 15),
        label: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 10),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  /// 打开纯净小说阅读引擎
  void _openReader({int initialIndex = 0}) {
    HapticFeedback.lightImpact();

    final readerChapters = widget.data.chapters.map((ch) {
      return NovelChapter(title: ch.title, content: '', url: ch.url);
    }).toList();

    if (readerChapters.isEmpty) {
      readerChapters.add(
        NovelChapter(
          title: widget.data.title.isNotEmpty
              ? widget.data.title
              : widget.fallbackTitle,
          content: widget.data.textContent ?? '',
          url: widget.data.url,
        ),
      );
    } else if (widget.data.textContent != null &&
        widget.data.textContent!.isNotEmpty) {
      readerChapters[0] = readerChapters[0].copyWith(
        content: widget.data.textContent,
      );
    }

    // 记录本次进入阅读器的起始章节，保证退出后的阅读进度可续读
    final safeIndex = initialIndex.clamp(0, readerChapters.length - 1);
    _onChapterChanged(safeIndex, readerChapters[safeIndex].title);

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovelReaderPage(
          bookTitle: widget.data.title.isNotEmpty
              ? widget.data.title
              : widget.fallbackTitle,
          initialChapterIndex: safeIndex,
          chapters: readerChapters,
          rule: widget.rule,
          customHeaders: widget.data.customHeaders,
          onChapterChanged: _onChapterChanged,
          // 传入离线标识，阅读器将优先读取沙盒中已下载的章节
          offlineBookId: _mediaId,
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
        // 1. 小说头部元信息
        //
        // 续读主操作交给头部的右列底部（[MediaMetaHeader.bottomAction]）：
        // 那一列本来就空着大半个封面高度，主操作落在那儿既不新增行高，
        // 也比原来"下面单开一整行大按钮"更靠近标题。
        MediaMetaHeader(
          data: widget.data,
          rule: widget.rule,
          fallbackTitle: widget.fallbackTitle,
          fallbackCover: widget.fallbackCover,
          onShareTap: widget.onShareTap,
          bottomAction: _buildResumeButton(chapters),
        ),

        // 2. 目录选章标题（固定区）
        if (chapters.isNotEmpty) _buildCatalogHeader(isDark, chapters.length),

        // 3. 目录列表 + 相关推荐：吃满剩余高度并独立滚动
        //
        // 此前是「整页长滑 + 只铺前 30 章 + 末尾一个"进阅读器看全部"」：
        // 章节多的小说想跳到第 200 章，得先进阅读器、再开目录，绕一圈。
        // 现在目录有自己的滚动区（懒加载 SliverList，几万章也只构建可见行），
        // 找章就在原地 —— 与漫画详情页的骨架一致。
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              if (displayChapters.isNotEmpty)
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  sliver: SliverList.builder(
                    itemCount: displayChapters.length,
                    itemBuilder: (context, index) {
                      final ch = displayChapters[index];
                      final realIndex = _isReversed
                          ? (chapters.length - 1 - index)
                          : index;
                      return Padding(
                        // 末项不留尾距：滚动区底部另有留白
                        padding: EdgeInsets.only(
                          bottom: index == displayChapters.length - 1 ? 0 : 6,
                        ),
                        child: AppCard(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 11,
                          ),
                          borderRadius: 10,
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.lightSurface,
                          onTap: () => _openReader(initialIndex: realIndex),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  ch.title,
                                  style: const TextStyle(fontSize: 13),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                                color: isDark
                                    ? AppColors.darkTextTertiary
                                    : AppColors.lightTextTertiary,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

              // 4. 小说相关推荐 (默认 3 列海报纵向卡片)
              SliverToBoxAdapter(
                child: MediaRelatedGrid(
                  related: widget.data.related,
                  currentRule: widget.rule,
                  headers: widget.data.customHeaders,
                  onItemTap: widget.onRelatedItemTap,
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 16)),
            ],
          ),
        ),
      ],
    );
  }

  /// 目录选章标题行（固定区）：主题色竖条 + 名称 + 总章数 + 正序 / 倒序
  Widget _buildCatalogHeader(bool isDark, int total) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
          const Text(
            '目录选章',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          Text(
            '共 $total 章',
            style: TextStyle(
              fontSize: 12,
              color: isDark
                  ? AppColors.darkTextMuted
                  : AppColors.lightTextMuted,
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
                Icon(
                  Ionicons.swapVerticalOutline,
                  size: 13,
                  color: isDark
                      ? AppColors.darkTextSecondary
                      : AppColors.lightTextSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  _isReversed ? '倒序' : '正序',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
