import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_chapter_bridge.dart';

/// 横向翻页视图（滑窗跨章连续渲染）
///
/// 渲染 `[上一章, 当前章, 下一章]` 的扁平页序列，跨章翻页动画与章内完全一致；
/// 未就绪章占一页加载占位（[ReaderChapterBridge]），就绪后自动顶替。
/// 纯展示组件：切片与窗口由上层提供，实测视口上抛驱动 TextPainter 分页。
class ReaderHorizontalPageView extends StatelessWidget {
  const ReaderHorizontalPageView({
    super.key,
    required this.bookTitle,
    required this.windowChapters,
    required this.windowSlices,
    required this.chapterTitleOf,
    required this.chapterCount,
    required this.currentChapterIndex,
    required this.currentPageIndex,
    required this.pageController,
    required this.readerTheme,
    required this.bodyTextStyle,
    required this.onViewportResolved,
    required this.onPageChanged,
  });

  /// 书名（页眉右侧）
  final String bookTitle;

  /// 滑窗内的章号序列（按渲染顺序：上一章 → 当前章 → 下一章）
  final List<int> windowChapters;

  /// 章号 → 该章已分好的正文页；缺失或为空表示正文未就绪（渲染加载占位页）
  final Map<int, List<String>> windowSlices;

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

  /// 物理视口实测完成（上层据此判断是否需要重算分页）
  final void Function(double width, double height) onViewportResolved;

  /// `PageView` 原始扁平页码变化（语义反解交由上层）
  final ValueChanged<int> onPageChanged;

  /// 窗口内某章的渲染页数：未就绪章恒占 1 页（加载占位）
  int _pageCountOf(int chapter) {
    final slices = windowSlices[chapter];
    return (slices != null && slices.isNotEmpty) ? slices.length : 1;
  }

  @override
  Widget build(BuildContext context) {
    final totalCount = windowChapters.fold(
      0,
      (sum, chapter) => sum + _pageCountOf(chapter),
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
              final renderWidth =
                  (constraints.maxWidth - 40).clamp(100.0, 4000.0);
              final renderHeight =
                  (constraints.maxHeight - 16).clamp(100.0, 4000.0);

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

              return PageView.builder(
                // key 不含章号：跨章不重建，动画保持连续
                controller: pageController,
                itemCount: totalCount,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  var remaining = index;
                  for (final chapter in windowChapters) {
                    final slices = windowSlices[chapter];
                    final count = (slices != null && slices.isNotEmpty)
                        ? slices.length
                        : 1;
                    if (remaining >= count) {
                      remaining -= count;
                      continue;
                    }

                    // 未就绪章：渲染加载占位页（就绪后由上层补切片自动顶替）
                    if (slices == null || slices.isEmpty) {
                      return ReaderChapterBridge(
                        key: ValueKey('bridge_$chapter'),
                        chapterTitle: chapterTitleOf(chapter),
                        readerTheme: readerTheme,
                        isReady: false,
                        heading: chapter < currentChapterIndex
                            ? '正在加载上一章'
                            : '正在进入下一章',
                        readyHint: '正文已就绪，即将无缝续读',
                        loadingHint: '正在加载正文...',
                      );
                    }

                    return Padding(
                      key: ValueKey('chapter_${chapter}_page_$remaining'),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      // 单击手势统一由上层的三区点击热层接管（保留长按划词与拖动选择）
                      child: SelectableText(
                        slices[remaining],
                        // 翻页模式下严格禁用垂直方向滚动物理特性，杜绝上下滑动导致翻页手势冲突
                        scrollPhysics: const NeverScrollableScrollPhysics(),
                        style: bodyTextStyle,
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
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
                      windowSlices[currentChapterIndex]?.isNotEmpty == true &&
                      currentPageIndex >=
                          windowSlices[currentChapterIndex]!.length - 1)
                    Text(
                      '已是最后一章 · ',
                      style: TextStyle(fontSize: 11, color: readerTheme.subText),
                    ),
                  if (currentChapterIndex == 0 && currentPageIndex == 0)
                    Text(
                      '全书起始 · ',
                      style: TextStyle(fontSize: 11, color: readerTheme.subText),
                    ),
                  Text(
                    windowSlices[currentChapterIndex]?.isNotEmpty == true
                        ? '${currentPageIndex + 1} / ${windowSlices[currentChapterIndex]!.length}'
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
