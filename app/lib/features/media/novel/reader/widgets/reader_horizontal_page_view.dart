import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/novel/reader/engines/horizontal_window.dart';
import 'package:fluxforge/features/media/novel/reader/engines/pagination_engine.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 横向翻页视图（滑窗跨章连续渲染）
///
/// 渲染 `[上一章, 当前章, 下一章]` 的扁平页序列，跨章翻页动画与章内完全一致；
/// 未就绪章占一页占位页（由上层 [bridgeBuilder] 提供），就绪后自动顶替。
/// 纯展示组件：切片与窗口由上层提供，实测视口上抛驱动 TextPainter 分页。
class ReaderHorizontalPageView extends StatelessWidget {
  const ReaderHorizontalPageView({
    super.key,
    required this.bookTitle,
    required this.windowChapters,
    required this.windowPageStarts,
    required this.contentOf,
    required this.chapterTitleOf,
    required this.chapterCount,
    required this.currentChapterIndex,
    required this.currentPageIndex,
    required this.pageController,
    required this.readerTheme,
    required this.bodyTextStyle,
    required this.bridgeBuilder,
    required this.onViewportResolved,
    required this.onPageChanged,
  });

  /// 书名（页眉右侧）
  final String bookTitle;

  /// 滑窗内的章号序列（按渲染顺序：上一章 → 当前章 → 下一章）
  final List<int> windowChapters;

  /// 章号 → 该章的**页起始偏移表**；缺失或为空表示正文未就绪（渲染加载占位页）
  ///
  /// 只存偏移不存文本：页码 → 位置、位置 → 页码都是廉价运算，
  /// 且不再为每页复制一份正文（取文本见 [contentOf] + [PaginationEngine.pageText]）。
  final Map<int, List<int>> windowPageStarts;

  /// 章号 → 该章正文原文（按页偏移切出当前页文本）
  final String Function(int chapter) contentOf;

  /// 章号 → 章节标题（页眉与占位页展示用）
  final String Function(int chapter) chapterTitleOf;

  final int chapterCount;

  /// 当前章号与章内页码（页眉 / 页脚展示用；真实状态由上层维护）
  final int currentChapterIndex;
  final int currentPageIndex;

  /// 翻页控制器（为空时由 PageView 自建）
  final PageController? pageController;

  final ReaderTheme readerTheme;

  /// 正文排版样式（字号 / 行距 / 字色 / 字距）
  final TextStyle bodyTextStyle;

  /// 未就绪章的占位页构建器
  ///
  /// 该章是「加载中 / 已就绪待分片 / 加载失败」只有上层知道（视图不掌握加载状态，
  /// 也不应猜测原因），故占位页整体由上层构建。
  final Widget Function(BuildContext context, int chapter) bridgeBuilder;

  /// 物理视口实测完成（上层据此判断是否需要重算分页）
  final void Function(double width, double height) onViewportResolved;

  /// `PageView` 原始扁平页码变化（语义反解交由上层）
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    // 总页数统一走引擎：与页面侧「扁平索引 → (章, 页)」反解同源，
    // 避免「未分片章占 1 页」的规则在此处再写一遍（口径漂移会让翻页落点错位）
    final totalCount = HorizontalWindow.totalPages(
      windowChapters,
      windowPageStarts,
    );

    return Column(
      children: [
        // 顶部小标题栏 (当前章节名与书名)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  chapterTitleOf(currentChapterIndex),
                  style: TextStyle(fontSize: 11, color: readerTheme.subText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                bookTitle,
                style: TextStyle(fontSize: 11, color: readerTheme.subText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // 翻页主体
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final renderWidth = (constraints.maxWidth - 40).clamp(
                100.0,
                4000.0,
              );
              final renderHeight = (constraints.maxHeight - 16).clamp(
                100.0,
                4000.0,
              );

              // 上抛实测视口，由上层决定是否需要按新尺寸重排
              onViewportResolved(renderWidth, renderHeight);

              // 空窗口保护：章节序列为空时展示轻量占位，避免 PageView 越界
              if (windowChapters.isEmpty || totalCount == 0) {
                return Center(
                  child: Text(
                    '正文排版中...',
                    style: TextStyle(fontSize: 12, color: readerTheme.subText),
                  ),
                );
              }

              return SelectionArea(
                // 与纵向长卷统一：外层一个 SelectionArea 承担长按划词与跨页选择，
                // 内部用纯 Text 取代逐页 SelectableText —— 后者每页都会建立独立的
                // EditableText 与选择容器，且自带 Scrollable（原先需靠
                // NeverScrollableScrollPhysics 压制垂直手势冲突）。
                child: PageView.builder(
                  // key 不含章号：跨章不重建，动画保持连续
                  controller: pageController,
                  itemCount: totalCount,
                  onPageChanged: onPageChanged,
                  itemBuilder: (context, index) {
                    // 扁平索引 → (章, 章内页) 与页面侧同源（见 [HorizontalWindow]）
                    final (
                      chapter,
                      pageInChapter,
                    ) = HorizontalWindow.resolveFlat(
                      windowChapters,
                      windowPageStarts,
                      index,
                    );
                    final starts = windowPageStarts[chapter];

                    // 未就绪章：渲染上层提供的占位页（就绪后由上层补分片自动原地顶替）
                    if (starts == null || starts.isEmpty) {
                      return KeyedSubtree(
                        key: ValueKey('bridge_$chapter'),
                        child: bridgeBuilder(context, chapter),
                      );
                    }

                    return Padding(
                      key: ValueKey('chapter_${chapter}_page_$pageInChapter'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      // 单击手势统一由上层的三区点击热层接管；
                      // 长按划词与跨页选择由外层 SelectionArea 统一提供
                      child: Text(
                        PaginationEngine.pageText(
                          contentOf(chapter),
                          starts,
                          pageInChapter,
                        ),
                        style: bodyTextStyle,
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),

        // 底部页码指示器
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 ${currentChapterIndex + 1} / $chapterCount 章',
                style: TextStyle(fontSize: 11, color: readerTheme.subText),
              ),
              Row(
                children: [
                  // 全书最后一页给出明确收尾提示，避免用户反复滑动却无反馈
                  if (currentChapterIndex >= chapterCount - 1 &&
                      windowPageStarts[currentChapterIndex]?.isNotEmpty ==
                          true &&
                      currentPageIndex >=
                          windowPageStarts[currentChapterIndex]!.length - 1)
                    Text(
                      '已是最后一章 · ',
                      style: TextStyle(
                        fontSize: 11,
                        color: readerTheme.subText,
                      ),
                    ),
                  if (currentChapterIndex == 0 && currentPageIndex == 0)
                    Text(
                      '全书起始 · ',
                      style: TextStyle(
                        fontSize: 11,
                        color: readerTheme.subText,
                      ),
                    ),
                  Text(
                    windowPageStarts[currentChapterIndex]?.isNotEmpty == true
                        ? '${currentPageIndex + 1} / ${windowPageStarts[currentChapterIndex]!.length}'
                        : '',
                    style: TextStyle(fontSize: 11, color: readerTheme.subText),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
