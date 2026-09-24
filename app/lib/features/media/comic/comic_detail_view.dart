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
///
/// 版面骨架是**固定头部 + 下方独立滚动**（而不是整页长滑）：
/// 封面、标题、简介与分组切换留在原位不动，章节 / 画卷 / 相关推荐一起放进
/// 下方那个吃满剩余高度的滚动区。这样"画卷列表"才是一个正常的列表视口 ——
/// 此前它被框在一个按屏宽反算出来的「两行高小窗口」里，页面下方还接着长内容，
/// 内层滑到底也不会带动外层（嵌套同向滚动的固有毛病）。
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
          // 图集形态：明说"点的是第几张"，否则阅读器只会从续读页 / 第一张开始
          initialPage: chapters.isEmpty ? initialIndex : null,
        ),
      ),
    );
  }

  /// 续读入口（挂在头部右列底部）
  ///
  /// 只在**有章节、有章级进度、且只有一组分组**时出现：
  /// - 图集没有"读到第几话"这一说，故无章节时不给；
  /// - 进度为 0 时"继续阅读"与章节列表第一格是同一个动作，属于噪音；
  /// - 多分组时进度里的下标属于"当时那一组"，换了组之后就会指到另一话，
  ///   在没有分组维度记录之前不猜（宁可不出这个按钮）。
  Widget? _buildResumeButton(List<MediaEpisode> chapters) {
    if (chapters.isEmpty || widget.data.readableComicGroups.length > 1) {
      return null;
    }
    final index = playHistoryService.getById(_mediaId)?.episodeIndex ?? 0;
    if (index <= 0) return null;

    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () =>
            _openReader(initialIndex: index.clamp(0, chapters.length - 1)),
        icon: const Icon(Ionicons.bookOutline, size: 15),
        label: Text(
          '继续阅读 · 第 ${index.clamp(0, chapters.length - 1) + 1} 话',
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

  /// 把已离线下载的图片 URL 替换为本地文件路径（未下载的保持网络 URL）
  ///
  /// 与阅读宿主里的章节形态共用同一份实现，避免"图集能断网看、章节不能"的割裂。
  Future<List<String>> _resolveOfflineImages(List<String> urls) =>
      resolveComicOfflineImages(urls, bookId: _mediaId);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // 吸顶小节标题要用页面底色遮挡滚动内容，否则内容会从标题底下透出来
    final pageBg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final groups = widget.data.readableComicGroups;
    final activeGroup = groups.isEmpty
        ? null
        : groups[_selectedGroupIndex.clamp(0, groups.length - 1)];
    final chapters = activeGroup?.items ?? const <MediaEpisode>[];
    final displayChapters = _isReversed ? chapters.reversed.toList() : chapters;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 固定头部：封面 / 标题 / 简介折叠卡
        //
        // 限高 + 自身可滚只为一件事：「作品简介」能被用户展开到很长，头部固定之后
        // 长简介会把下方列表挤成 0 高（RenderFlex 溢出）。正常状态下
        // SingleChildScrollView 只吃内容高度，不会白占空间。
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.6,
          ),
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            child: MediaMetaHeader(
              data: widget.data,
              rule: widget.rule,
              fallbackTitle: widget.fallbackTitle,
              fallbackCover: widget.fallbackCover,
              onShareTap: widget.onShareTap,
              bottomAction: _buildResumeButton(chapters),
            ),
          ),
        ),

        // 固定：漫画分组切换 (实体底色区分选中态，无描边)
        if (groups.length > 1) ...[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 4.0,
            ),
            child: SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: groups.length,
                separatorBuilder: (context, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final group = groups[index];
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

        // 主列表：吃满剩余高度并独立滚动（章节 / 画卷 / 相关推荐同处一个滚动区）
        Expanded(
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // 漫画章节选集列表
              if (displayChapters.isNotEmpty) ...[
                _SliverSectionHeader(
                  background: pageBg,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 2.4,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
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
                    }, childCount: displayChapters.length),
                  ),
                ),
              ],

              // 独立图集网格（画卷）
              if (widget.data.imageList.isNotEmpty) ...[
                _SliverSectionHeader(
                  background: pageBg,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  // 不再截断到 9 张：标题写着「共 N 张」，却只画 9 个是自相矛盾。
                  // 懒加载的 sliver 网格，几十上百张也只构建可见的那几行。
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: 0.75,
                        ),
                    delegate: SliverChildBuilderDelegate((context, index) {
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
                    }, childCount: widget.data.imageList.length),
                  ),
                ),
              ],

              // 相关推荐（同页共用详情解析出的请求头，避免"同页两套 Referer"）
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
}

/// 吸顶小节标题（「漫画章节」「图集画卷」）
///
/// 这两个标题属于"上面"那一层：列表滚动时标题必须留在原位，否则滑到一半
/// 就不知道自己在看哪一段（此前标题跟着内容一起滑走了）。
///
/// 吸顶有两个硬要求：
/// - **固定高度**：`SliverPersistentHeader` 的 extent 不能由内容决定，
///   故标题行统一 38（3.5×14 竖条 + 14.5/15 号标题 + 上下呼吸）；
/// - **不透明底**：否则滚动内容会从标题底下透出来（底色取页面底色）。
class _SliverSectionHeader extends StatelessWidget {
  const _SliverSectionHeader({required this.child, required this.background});

  final Widget child;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return SliverPersistentHeader(
      pinned: true,
      delegate: _SectionHeaderDelegate(child: child, background: background),
    );
  }
}

class _SectionHeaderDelegate extends SliverPersistentHeaderDelegate {
  _SectionHeaderDelegate({required this.child, required this.background});

  final Widget child;
  final Color background;

  static const double _height = 38;

  @override
  double get minExtent => _height;

  @override
  double get maxExtent => _height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 必须把子树撑到 minExtent：`SliverPersistentHeader` 的 paintExtent 取的是
    // **子树真实高度**（`min(childExtent, 剩余可绘制高度)`），而 layoutExtent 是
    // maxExtent - scrollOffset。子树比 minExtent 矮时（标题行自然高度只有 ~21）
    // 就会写出 layoutExtent(38) > paintExtent(21) 的非法几何，直接抛断言。
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _height),
      child: ColoredBox(color: background, child: child),
    );
  }

  @override
  bool shouldRebuild(covariant _SectionHeaderDelegate oldDelegate) =>
      oldDelegate.child != child || oldDelegate.background != background;
}
