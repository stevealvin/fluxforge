import 'package:material_ui/material_ui.dart';

/// 文本分页引擎（纯算法：无状态、无业务依赖）
///
/// 使用 `TextPainter` 结合**二分查找**做亚像素级精准分页：
/// - 每页高度严格适配可用物理空间 —— 既不超出屏幕垂直溢出，也不浪费下半屏空间；
/// - 断点附近存在段落换行符时优先在该处断页，实现自然的段落断句体验。
///
/// 之所以独立成引擎：它只依赖 Flutter 的文本布局能力、不持有任何页面状态，
/// 因此**可以直接单元测试**（给定文本 / 尺寸 / 样式 → 断言分页结果），
/// 这在逻辑内嵌于 2000 行 State 时是做不到的。
class PaginationEngine {
  const PaginationEngine._();

  /// 段落自然吸附的搜索范围：截断点之前 N 个字符内若存在换行符，则优先在此断页
  static const int paragraphSnapRange = 35;

  /// 将正文按可用物理尺寸切分为逐页文本
  ///
  /// - [text] 为空 → 返回单页空串；
  /// - [maxWidth] / [maxHeight] 非法 → 原样返回单页全文（由调用方兜底处理）。
  static List<String> sliceIntoPages({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required TextStyle textStyle,
  }) {
    if (text.isEmpty) return [''];
    if (maxWidth <= 0 || maxHeight <= 0) return [text];

    final List<String> pages = [];
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    int start = 0;
    final totalLen = text.length;

    while (start < totalLen) {
      final remain = totalLen - start;
      if (remain <= 0) break;

      // 二分查找当前视口高度下能容纳的最大字符长度
      int low = 1;
      int high = remain;
      int bestLen = 1;

      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final candidate = text.substring(start, start + mid);
        textPainter.text = TextSpan(text: candidate, style: textStyle);
        textPainter.layout(maxWidth: maxWidth);

        if (textPainter.height <= maxHeight) {
          bestLen = mid;
          low = mid + 1; // 还能容纳更多字符
        } else {
          high = mid - 1; // 高度溢出，收缩字符区间
        }
      }

      int end = start + bestLen;

      // 智能段落自然吸附：非全书末尾且在截断点前若干字符内发现换行符时，优先在换行处断页
      if (end < totalLen) {
        final newlineIndex = text.lastIndexOf('\n', end);
        if (newlineIndex != -1 &&
            newlineIndex > start &&
            (end - newlineIndex) <= paragraphSnapRange) {
          end = newlineIndex + 1;
        }
      }

      final pageText = text.substring(start, end);
      if (pageText.isNotEmpty) {
        pages.add(pageText);
      }
      start = end;
    }

    if (pages.isEmpty) pages.add(text);
    return pages;
  }
}
