import 'package:material_ui/material_ui.dart';

/// 文本分页引擎（纯算法：无状态、无业务依赖）
///
/// **整章只排一次版**：先对全文做一次 `layout`，再取「行度量 + 行首位置」按页高
/// 累加分组，最终只产出**每页起始字符偏移**（不产出文本副本）：
/// - 页高严格适配可用物理空间 —— 既不溢出，也不浪费下半屏；
/// - 断行由引擎按**整章上下文**决定（旧实现是「从页首截断后重排」，断行会丢上下文，
///   标点禁则 / 行首规则可能因此与正文实际排版不一致）；
/// - 成本从「每页二分 × 每次整段重排」（章节十来页 = 上百次 layout）降到 **1 次**。
///
/// ### 为什么产出偏移而不是文本
/// 页 = 偏移是**位置化**的地基：页码 → 位置、位置 → 页码都是 O(1)~O(log n)，
/// 且不再为每页复制一份正文（原先正文在内存里存两份：原文 + 各页副本）。
/// 取文本只在真正渲染那一页时进行（见 [pageText]）。
///
/// 之所以独立成引擎：它只依赖 Flutter 的文本布局能力、不持有任何页面状态，
/// 因此**可以直接单元测试**（给定文本 / 尺寸 / 样式 → 断言页偏移），
/// 这在逻辑内嵌于 2000 行 State 时是做不到的。
class PaginationEngine {
  const PaginationEngine._();

  /// 段落自然吸附的搜索范围：截断点之前 N 个字符内若存在换行符，则优先在此断页
  static const int paragraphSnapRange = 35;

  /// 视口实测尺寸到达后，是否需要重排分页
  ///
  /// 三种情形：
  /// 1. 视口尺寸变化（首次渲染 / 横竖屏旋转 / 分屏）—— 已切的分页全部失效；
  /// 2. 当前没有任何分页；
  /// 3. 当前只有一页、且那一页就是整篇正文 —— 说明这是「尚未测量到尺寸」时的
  ///    兜底结果（见 `_recalculatePages` 的兜底分支）：长文必须重切，
  ///    短文则保持原样，避免为一页短文做无谓重排。
  ///
  /// 之所以抽成纯函数：这段判定原先内联在视口回调里，
  /// 六个条件的组合语义（尤其是第 3 条）无法脱离 Widget 树验证。
  static bool needsRepaginate({
    required double currentWidth,
    required double currentHeight,
    required double nextWidth,
    required double nextHeight,
    required int pageCount,
    required bool firstPageIsWholeContent,
    required int contentLength,
  }) {
    if ((currentWidth - nextWidth).abs() > 1.0 ||
        (currentHeight - nextHeight).abs() > 1.0) {
      return true;
    }
    if (pageCount == 0) return true;
    return pageCount == 1 && firstPageIsWholeContent && contentLength > 300;
  }

  /// 将正文按可用物理尺寸切分，返回**每页起始字符偏移**（严格递增，首项恒为 0）
  ///
  /// 页数与偏移表的约定：第 `i` 页 = `text.substring(starts[i], starts[i+1])`，
  /// 末页结束于 `text.length`。因此 `starts.length` 即页数，且各页拼接恒等于原文。
  ///
  /// - [text] 为空 → 返回 `[0]`（单页空内容）；
  /// - [maxWidth] / [maxHeight] 非法 → 返回 `[0]`（单页全文，由调用方兜底处理）。
  static List<int> sliceIntoPageStarts({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required TextStyle textStyle,
  }) {
    if (text.isEmpty) return const [0];
    if (maxWidth <= 0 || maxHeight <= 0) return const [0];

    // ① 整章只排一次版：断行与行度量都由引擎按整章上下文给出
    final textPainter = TextPainter(
      text: TextSpan(text: text, style: textStyle),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);

    final lines = textPainter.computeLineMetrics();
    if (lines.isEmpty) return const [0];

    // ② 行首字符位置：取每行中点 x=0 处的位置查询（由引擎回答，不自行猜断行位置）。
    //    刻意不用 `getLineBoundary`：它返回的可能是段落范围而不是视觉行。
    final lineStarts = <int>[0];
    var lineTop = 0.0;
    for (var i = 0; i < lines.length; i++) {
      if (i > 0) {
        lineStarts.add(
          textPainter
              .getPositionForOffset(Offset(0, lineTop + lines[i].height / 2))
              .offset
              .clamp(lineStarts[i - 1] + 1, text.length),
        );
      }
      lineTop += lines[i].height;
    }

    // ③ 按页高累加行高切页；分页游标独立推进，保证「各页拼接 == 原文」恒成立
    final pageStarts = <int>[0];
    var pageStart = 0;
    var lineIndex = 0;
    while (lineIndex < lines.length && pageStart < text.length) {
      var used = 0.0;
      var next = lineIndex;
      while (next < lines.length) {
        final height = lines[next].height;
        if (used > 0 && used + height > maxHeight) break;
        used += height;
        next++;
      }
      if (next <= lineIndex) next = lineIndex + 1; // 单行高于整页时的兜底

      var end = next < lines.length ? lineStarts[next] : text.length;

      // 智能段落自然吸附：非末尾且在截断点前若干字符内发现换行符时，优先在换行处断页
      if (end < text.length) {
        final newlineIndex = text.lastIndexOf('\n', end);
        if (newlineIndex != -1 &&
            newlineIndex > pageStart &&
            (end - newlineIndex) <= paragraphSnapRange) {
          end = newlineIndex + 1;
          while (next < lines.length && lineStarts[next] < end) {
            next++;
          }
          if (next <= lineIndex) next = lineIndex + 1;
        }
      }

      // 末页到此结束：**只记录"页起始偏移"**，不把结束位置也塞进表里
      // （否则页数会多出一个空页，扁平下标整体偏移 —— 这正是渲染不出正文的原因）
      if (end >= text.length) break;
      pageStarts.add(end);
      pageStart = end;
      lineIndex = next;
    }

    return pageStarts;
  }

  /// 取第 [index] 页的文本（[starts] 为 [sliceIntoPageStarts] 的产物）
  ///
  /// 越界时返回空串，调用方无需再做边界判断。
  static String pageText(String text, List<int> starts, int index) {
    if (index < 0 || index >= starts.length) return '';
    final start = starts[index].clamp(0, text.length);
    final end = index + 1 < starts.length
        ? starts[index + 1].clamp(start, text.length)
        : text.length;
    return text.substring(start, end);
  }
}
