import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:extended_image/extended_image.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/features/library/downloads/widgets/download_bar.dart';
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

  /// 收集本作可离线下载的全部图片地址（图集 + 各分组章节）
  List<String> _collectDownloadUrls() {
    final urls = <String>{};
    for (final url in widget.data.imageList) {
      if (url.trim().isNotEmpty) urls.add(url.trim());
    }
    for (final group in widget.data.comicGroups) {
      for (final item in group.items) {
        if (item.url.trim().isNotEmpty) urls.add(item.url.trim());
      }
    }
    return urls.toList();
  }

  /// 统一轻提示
  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(milliseconds: 1800)),
    );
  }

  /// 点击下载条：按当前状态执行 暂停 / 继续 / 重试 / 新建
  Future<void> _handleDownloadTap(DownloadTask? task) async {
    final rule = widget.rule;
    if (rule == null) {
      _showSnack('未绑定解析规则，无法下载');
      return;
    }

    final urls = _collectDownloadUrls();
    if (urls.isEmpty) {
      _showSnack('暂无可下载的图片');
      return;
    }

    HapticFeedback.lightImpact();

    // 1. 下载中 → 暂停
    if (task != null && task.isActive) {
      downloadService.pause(task.id);
      _showSnack('已暂停下载');
      return;
    }

    // 2. 已完成 → 提示
    if (task != null && task.isFinished) {
      _showSnack('该作品已完整下载到本地沙盒');
      return;
    }

    // 3. 已暂停 / 部分失败 → 继续或重试
    if (task != null) {
      if (task.failed.isNotEmpty) {
        downloadService.retryFailed(task.id);
        _showSnack('已重新开始下载失败图片');
      } else {
        downloadService.resume(task.id);
        _showSnack('已继续下载');
      }
      return;
    }

    // 4. 全新下载
    await downloadService.startComicDownload(
      rule: rule,
      bookId: _mediaId,
      title: widget.data.title.isNotEmpty ? widget.data.title : widget.fallbackTitle,
      cover: widget.data.cover.isNotEmpty ? widget.data.cover : widget.fallbackCover,
      imageUrls: urls,
      headers: widget.data.customHeaders,
    );
    _showSnack('已加入下载队列，可在「我的 → 离线下载」查看进度');
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

        // 离线下载入口（App 沙盒内整部保存，支持断点续传）
        Padding(
          padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 0.0),
          child: DownloadBar(
            bookId: _mediaId,
            unitLabel: '页',
            idleLabel: '下载本作（离线阅读，无网也能看）',
            onTap: _handleDownloadTap,
          ),
        ),

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
                      child: ExtendedImage.network(
                        imgUrl,
                        fit: BoxFit.cover,
                        headers: widget.data.customHeaders,
                        loadStateChanged: (state) {
                          if (state.extendedImageLoadState == LoadState.failed) {
                            return Center(
                              child: Icon(
                                Icons.broken_image_rounded,
                                size: 20,
                                color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                              ),
                            );
                          }
                          return null;
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],

        // 相关推荐
        MediaRelatedGrid(
          related: widget.data.related,
          currentRule: widget.rule,
          onItemTap: widget.onRelatedItemTap,
        ),
      ],
    );
  }
}
