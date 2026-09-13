import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/rule.dart';
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

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NovelReaderPage(
          bookTitle: widget.data.title.isNotEmpty ? widget.data.title : widget.fallbackTitle,
          initialChapterIndex: initialIndex.clamp(0, readerChapters.length - 1),
          chapters: readerChapters,
          rule: widget.rule,
          customHeaders: widget.data.customHeaders,
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
            onTap: () => _openReader(initialIndex: 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Ionicons.bookOutline, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  chapters.isNotEmpty ? '开始阅读 (共 ${chapters.length} 章)' : '立即畅读正文',
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
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
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
                  onPressed: () => _openReader(initialIndex: 0),
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
