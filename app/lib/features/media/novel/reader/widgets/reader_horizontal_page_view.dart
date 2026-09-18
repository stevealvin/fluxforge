import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 横向翻页视图（含章首 / 章末衔接页与底部页码指示）
///
/// 纯展示组件：正文切片、页码与衔接页由上层提供，本组件只负责渲染与意图上抛。
///
/// 翻页主体用 [LayoutBuilder] 感知真实物理视口，并把实测宽高上抛给上层驱动
/// `TextPainter` 亚像素级精确分页 —— 分页计算本身不在本组件内进行，
/// 因此视口变化时只需上层重算切片，视图无需感知排版细节。
///
/// 衔接页语义：`previousBridge` / `nextBridge` 非空即代表存在相邻章节，
/// 滑入对应页由上层决定「自动回退上一章」或「自动续读下一章」。
class ReaderHorizontalPageView extends StatelessWidget {
  const ReaderHorizontalPageView({
    super.key,
    required this.chapterTitle,
    required this.bookTitle,
    required this.pageSlices,
    required this.currentChapterIndex,
    required this.chapterCount,
    required this.currentPageIndex,
    required this.pageController,
    required this.readerTheme,
    required this.bodyTextStyle,
    required this.previousBridge,
    required this.nextBridge,
    required this.onViewportResolved,
    required this.onPageChanged,
  });

  /// 当前章节标题（页眉左侧）
  final String chapterTitle;

  /// 书名（页眉右侧）
  final String bookTitle;

  /// 本章已切分好的正文页
  final List<String> pageSlices;

  final int currentChapterIndex;
  final int chapterCount;
  final int currentPageIndex;

  /// 翻页控制器（为空时由 PageView 自建，与重构前行为一致）
  final PageController? pageController;

  final ReaderTheme readerTheme;

  /// 正文排版样式（字号 / 行距 / 字色 / 字距）
  final TextStyle bodyTextStyle;

  /// 章首衔接页（不存在上一章时为 null）
  final Widget? previousBridge;

  /// 章末衔接页（不存在下一章时为 null）
  final Widget? nextBridge;

  /// 物理视口实测完成（上层据此判断是否需要重算分页）
  final void Function(double width, double height) onViewportResolved;

  /// `PageView` 原始页码变化（含衔接页，语义判定交由上层）
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    final prevCount = previousBridge != null ? 1 : 0;
    final nextCount = nextBridge != null ? 1 : 0;
    final totalCount = prevCount + pageSlices.length + nextCount;

    return Column(
      children: [
        // 顶部小标题栏 (章节名与书名)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  chapterTitle,
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
              final renderWidth = (constraints.maxWidth - 40).clamp(100.0, 4000.0);
              final renderHeight = (constraints.maxHeight - 16).clamp(100.0, 4000.0);

              // 上抛实测视口，由上层决定是否需要按新尺寸重排
              onViewportResolved(renderWidth, renderHeight);

              // 空正文保护：正文为空或尚未切片时展示轻量占位，避免 PageView 越界
              if (pageSlices.isEmpty) {
                return Center(
                  child: Text(
                    '正文排版中...',
                    style: TextStyle(fontSize: 12, color: readerTheme.subText),
                  ),
                );
              }

              return PageView.builder(
                key: ValueKey('novel_pageview_${currentChapterIndex}_$totalCount'),
                controller: pageController,
                itemCount: totalCount,
                onPageChanged: onPageChanged,
                itemBuilder: (context, index) {
                  // 1. 章首上一章衔接页
                  if (prevCount == 1 && index == 0) {
                    return previousBridge!;
                  }
                  // 2. 章末下一章衔接页
                  if (nextCount == 1 && index >= prevCount + pageSlices.length) {
                    return nextBridge!;
                  }
                  // 3. 正文内容页
                  final sliceIdx = index - prevCount;
                  if (sliceIdx < 0 || sliceIdx >= pageSlices.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    // 单击手势统一由上层的三区点击热层接管（保留长按划词与拖动选择）
                    child: SelectableText(
                      pageSlices[sliceIdx],
                      // 翻页模式下严格禁用垂直方向滚动物理特性，杜绝上下滑动导致翻页手势冲突
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      style: bodyTextStyle,
                    ),
                  );
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
                      pageSlices.isNotEmpty &&
                      currentPageIndex >= pageSlices.length - 1)
                    Text(
                      '已是最后一章 · ',
                      style: TextStyle(fontSize: 11, color: readerTheme.subText),
                    ),
                  if (currentChapterIndex == 0 &&
                      pageSlices.isNotEmpty &&
                      currentPageIndex == 0)
                    Text(
                      '全书起始 · ',
                      style: TextStyle(fontSize: 11, color: readerTheme.subText),
                    ),
                  Text(
                    pageSlices.isNotEmpty
                        ? '${currentPageIndex + 1} / ${pageSlices.length}'
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
