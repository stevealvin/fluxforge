import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/features/media/shared/media_download_actions.dart';
import 'package:fluxforge/features/media/shared/media_meta_header.dart';
import 'package:fluxforge/features/media/shared/media_related_grid.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/comic/reader/comic_chapter_reader_page.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_offline_images.dart';

/// 漫画与画廊图集业务专属详情视图
class ComicDetailView extends StatefulWidget {
  const ComicDetailView({
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
  State<ComicDetailView> createState() => _ComicDetailViewState();
}

class _ComicDetailViewState extends State<ComicDetailView> {
  int _selectedGroupIndex = 0;
  bool _isReversed = false;

  /// 当前作品的唯一键（**归一化后的绝对地址**；相对地址用规则 baseUrl 补全）
  ///
  /// 与收藏、下载任务、消费记录共用同一口径 —— 三处必须同源，否则进度关联不上。
  String get _mediaId => MediaDownloadActions.taskKey(
    widget.data,
    widget.fallbackTitle,
    rule: widget.rule,
  );

  @override
  void initState() {
    super.initState();
    _registerPlayRecord();
  }

  /// 登记 / 更新当前漫画的消费记录 (保留既有阅读进度)
  void _registerPlayRecord() {
    if (_mediaId.isEmpty) return;
    final existing = playHistoryService.getById(_mediaId);
    final groups = widget.data.readableComicGroups;
    final total = groups.isNotEmpty
        ? groups.first.items.length
        : widget.data.imageList.length;
    playHistoryService.upsert(
      PlayRecord(
        id: _mediaId,
        // 原文地址：进详情时原样交给规则
        url: widget.data.url,
        title: widget.data.title.isNotEmpty
            ? widget.data.title
            : widget.fallbackTitle,
        cover: widget.data.cover.isNotEmpty
            ? widget.data.cover
            : widget.fallbackCover,
        mediaType: 'comic',
        ruleId: widget.rule?.id?.toString() ?? '',
        episodeName: existing?.episodeName ?? '',
        episodeIndex: existing?.episodeIndex ?? 0,
        totalEpisodes: total,
        updatedAt: DateTime.now(),
      ),
    );
  }

  Future<void> _openReader({int initialIndex = 0}) async {
    HapticFeedback.lightImpact();

    final groups = widget.data.readableComicGroups;
    final hasGroups = groups.isNotEmpty && _selectedGroupIndex < groups.length;
    final activeItems = hasGroups
        ? groups[_selectedGroupIndex].items
        : const <MediaEpisode>[];

    // 内容形态决定这一跳要不要"章 → 图片"的二次解析（元素类型推断，规则无需声明）
    final isChapterShape = widget.data.needsChapterParse;

    // 章节形态：把**章节表**交给宿主逐章解析（"章 → 图片"由宿主负责）。
    final chapters = isChapterShape
        ? (activeItems.isNotEmpty ? activeItems : widget.data.chapters)
        : const <MediaEpisode>[];

    var images = isChapterShape ? const <String>[] : widget.data.imageList;
    if (!isChapterShape && images.isEmpty && widget.data.cover.isNotEmpty) {
      images = [widget.data.cover];
    }

    final readerTitle = widget.data.title.isNotEmpty
        ? widget.data.title
        : widget.fallbackTitle;

    // 离线优先：已下载的图片替换为本地沙盒路径，实现断网阅读（图集形态）
    final resolvedImages = await _resolveOfflineImages(images);

    // 记录本次阅读的位置（供「我的」页继续阅读展示进度）
    final chapterTitle = (chapters.isNotEmpty && initialIndex < chapters.length)
        ? chapters[initialIndex].title
        : readerTitle;
    playHistoryService.updateProgress(
      id: _mediaId,
      episodeName: chapterTitle,
      episodeIndex: initialIndex,
      totalEpisodes: chapters.isNotEmpty
          ? chapters.length
          : widget.data.imageList.length,
      forceNotify: true,
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicChapterReaderPage(
          title: readerTitle.isNotEmpty ? readerTitle : '漫画阅读',
          mediaId: _mediaId,
          chapters: chapters,
          imageList: resolvedImages,
          rule: widget.rule,
          headers: widget.data.customHeaders,
          initialChapterIndex: chapters.isEmpty
              ? 0
              : initialIndex.clamp(0, chapters.length - 1),
        ),
      ),
    );
  }

  /// 把已离线下载的图片 URL 替换为本地文件路径（未下载的保持网络 URL）
  ///
  /// 与阅读宿主里的章节形态共用同一份实现，避免"图集能断网看、章节不能"的割裂。
  Future<List<String>> _resolveOfflineImages(List<String> urls) =>
      resolveComicOfflineImages(urls, bookId: _mediaId);

  /// 图集网格容器的高度：约两行（含行间距），按屏宽换算
  ///
  /// 网格是 3 列、单格 4:3（`childAspectRatio: 0.75`），行高由**列宽**决定 ——
  /// 写死高度会在窄屏多露一行、宽屏少露一行，故按可用宽度反算。
  double _imageGridHeight(BuildContext context) {
    const horizontalPadding = 32.0; // 区块左右各 16
    const spacing = 8.0;
    final cellWidth =
        (MediaQuery.sizeOf(context).width - horizontalPadding - spacing * 2) / 3;
    return cellWidth / 0.75 * 2 + spacing;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MediaMetaHeader(
          data: widget.data,
          rule: widget.rule,
          fallbackTitle: widget.fallbackTitle,
          fallbackCover: widget.fallbackCover,
          onShareTap: widget.onShareTap,
        ),

        // 离线下载入口已上移至顶部栏右上角图标（底部弹出下载面板）

        // 漫画分组切换 (实体底色区分选中态，无描边)
        if (widget.data.readableComicGroups.length > 1) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.data.readableComicGroups.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final group = widget.data.readableComicGroups[index];
                  final isSelected = index == _selectedGroupIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedGroupIndex = index;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark
                                  ? AppColors.darkCard
                                  : AppColors.lightSurface),
                        borderRadius: BorderRadius.circular(17),
                      ),
                      child: Center(
                        child: Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : (isDark
                                      ? AppColors.darkTextSecondary
                                      : AppColors.lightTextSecondary),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),
        ],

        // 漫画章节选集列表
        if (widget.data.readableComicGroups.isNotEmpty) ...[
          Builder(
            builder: (context) {
              final activeGroup =
                  widget.data.readableComicGroups[_selectedGroupIndex.clamp(
                    0,
                    widget.data.readableComicGroups.length - 1,
                  )];
              final chapters = activeGroup.items;
              final displayChapters = _isReversed
                  ? chapters.reversed.toList()
                  : chapters;

              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16.0,
                  vertical: 6.0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
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
                          '漫画章节',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '共 ${chapters.length} 话',
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
                    const SizedBox(height: 10),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 2.4,
                          ),
                      itemCount: displayChapters.length,
                      itemBuilder: (context, index) {
                        final ch = displayChapters[index];
                        final realIndex = _isReversed
                            ? (chapters.length - 1 - index)
                            : index;
                        return AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          borderRadius: 8,
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.lightSurface,
                          onTap: () => _openReader(initialIndex: realIndex),
                          child: Center(
                            child: Text(
                              ch.title,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark
                                    ? AppColors.darkTextPrimary
                                    : AppColors.lightTextPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
          ),
        ],

        // 独立图集网格
        if (widget.data.imageList.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
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
                  '图集画卷',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '共 ${widget.data.imageList.length} 张',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextTertiary
                        : AppColors.lightTextTertiary,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              // 固定高度 + 独立滚动：图集动辄几十张，全量铺开会把详情页撑到极长；
              // 给约两行的窗口让它自己滑 —— 既能看到全部，又不破坏页面节奏。
              // （窗口更高时手指在内层滑到底不会带动外层，这是嵌套同向滚动的固有
              // 取舍；此处图集本身是"看小图挑一张"，局部滚动更顺手。）
              height: _imageGridHeight(context),
              child: GridView.builder(
                // 有确定高度后 shrinkWrap 只会让布局多算一遍
                physics: const ClampingScrollPhysics(),
                padding: EdgeInsets.zero,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.75,
                ),
                // 不再截断到 9 张：标题写着「共 N 张」，却只画 9 个是自相矛盾
                itemCount: widget.data.imageList.length,
                itemBuilder: (context, index) {
                  final imgUrl = widget.data.imageList[index];
                  return GestureDetector(
                    onTap: () => _openReader(initialIndex: index),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        // 图集每格只用底色与圆角区分，不再描边（去掉整片网格的细线噪点）
                        decoration: BoxDecoration(
                          color: isDark
                              ? AppColors.darkCard
                              : AppColors.lightSurface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: AppImage(
                          imageUrl: imgUrl,
                          headers: widget.data.customHeaders,
                          // 3 列网格：单格约 120dp → 3x 屏取 360，避免按原图解码
                          cacheWidth: 360,
                          errorWidget: Icon(
                            Ionicons.imageOutline,
                            size: 20,
                            color: isDark
                                ? AppColors.darkTextTertiary
                                : AppColors.lightTextTertiary,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 相关推荐（同页共用详情解析出的请求头，避免"同页两套 Referer"）
        MediaRelatedGrid(
          related: widget.data.related,
          currentRule: widget.rule,
          headers: widget.data.customHeaders,
          onItemTap: widget.onRelatedItemTap,
        ),
      ],
    );
  }
}
