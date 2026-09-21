import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/features/media/shared/media_meta_header.dart';
import 'package:fluxforge/features/media/shared/media_related_grid.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/comic/reader/comic_reader_page.dart';

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

  /// 当前图集/漫画的唯一消费标识 (优先详情页 URL，兜底标题)
  String get _mediaId {
    if (widget.data.url.isNotEmpty) return widget.data.url;
    if (widget.fallbackTitle.isNotEmpty) return widget.fallbackTitle;
    return widget.data.title;
  }

  @override
  void initState() {
    super.initState();
    _registerPlayRecord();
  }

  /// 登记 / 更新当前漫画的消费记录 (保留既有阅读进度)
  void _registerPlayRecord() {
    if (_mediaId.isEmpty) return;
    final existing = playHistoryService.getById(_mediaId);
    final groups = widget.data.comicGroups;
    final total = groups.isNotEmpty
        ? groups.first.items.length
        : widget.data.imageList.length;
    playHistoryService.upsert(
      PlayRecord(
        id: _mediaId,
        title: widget.data.title.isNotEmpty ? widget.data.title : widget.fallbackTitle,
        cover: widget.data.cover.isNotEmpty ? widget.data.cover : widget.fallbackCover,
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

    List<String> images = [];
    final groups = widget.data.comicGroups;
    if (groups.isNotEmpty && _selectedGroupIndex < groups.length) {
      final items = groups[_selectedGroupIndex].items;
      if (items.isNotEmpty && initialIndex < items.length) {
        images = [items[initialIndex].url];
      }
    }

    if (images.isEmpty) {
      images = widget.data.imageList;
    }

    if (images.isEmpty && widget.data.cover.isNotEmpty) {
      images = [widget.data.cover];
    }

    final readerTitle = widget.data.title.isNotEmpty ? widget.data.title : widget.fallbackTitle;

    // 离线优先：已下载的图片替换为本地沙盒路径，实现断网阅读
    final resolvedImages = await _resolveOfflineImages(images);

    // 记录本次阅读的章节位置（供「我的」页继续观看/阅读展示进度）
    final activeItems = (groups.isNotEmpty && _selectedGroupIndex < groups.length)
        ? groups[_selectedGroupIndex].items
        : const <MediaEpisode>[];
    final chapterTitle = (activeItems.isNotEmpty && initialIndex < activeItems.length)
        ? activeItems[initialIndex].title
        : readerTitle;
    playHistoryService.updateProgress(
      id: _mediaId,
      episodeName: chapterTitle,
      episodeIndex: initialIndex,
      totalEpisodes: activeItems.isNotEmpty ? activeItems.length : widget.data.imageList.length,
      forceNotify: true,
    );

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ComicReaderPage(
          imageList: resolvedImages,
          title: readerTitle.isNotEmpty ? readerTitle : '漫画阅读',
          initialIndex: 0,
          headers: widget.data.customHeaders,
        ),
      ),
    );
  }

  /// 把已离线下载的图片 URL 替换为本地文件路径（未下载的保持网络 URL）
  Future<List<String>> _resolveOfflineImages(List<String> urls) async {
    if (urls.isEmpty) return urls;
    return Future.wait(
      urls.map((url) async {
        final local = await downloadService.localComicImagePath(_mediaId, url);
        return local ?? url;
      }),
    );
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

        // 漫画分组切换 (使用 darkCard 实体底色与微边框)
        if (widget.data.comicGroups.length > 1) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.data.comicGroups.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final group = widget.data.comicGroups[index];
                  final isSelected = index == _selectedGroupIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() {
                        _selectedGroupIndex = index;
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkCard : AppColors.lightSurface),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(
                          color: isSelected
                              ? AppColors.primary
                              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          width: 0.8,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
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
        if (widget.data.comicGroups.isNotEmpty) ...[
          Builder(
            builder: (context) {
              final activeGroup = widget.data.comicGroups[_selectedGroupIndex.clamp(0, widget.data.comicGroups.length - 1)];
              final chapters = activeGroup.items;
              final displayChapters = _isReversed ? chapters.reversed.toList() : chapters;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
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
                    const SizedBox(height: 10),

                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: EdgeInsets.zero,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemCount: displayChapters.length,
                      itemBuilder: (context, index) {
                        final ch = displayChapters[index];
                        final realIndex = _isReversed ? (chapters.length - 1 - index) : index;
                        return AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          borderRadius: 8,
                          showBorder: true,
                          borderColor: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                          onTap: () => _openReader(initialIndex: realIndex),
                          child: Center(
                            child: Text(
                              ch.title,
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
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
                  '图集画卷',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '共 ${widget.data.imageList.length} 张',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  ),
                ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.75,
              ),
              itemCount: widget.data.imageList.length.clamp(0, 9),
              itemBuilder: (context, index) {
                final imgUrl = widget.data.imageList[index];
                return GestureDetector(
                  onTap: () => _openReader(initialIndex: index),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                        border: Border.all(
                          color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                          width: 0.8,
                        ),
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
                          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        ),
                      ),
                    ),
                  ),
                );
              },
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
