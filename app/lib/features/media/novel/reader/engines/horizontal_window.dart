/// 横向滑窗的「页数统计 + 扁平页索引 ⇄ (章, 章内页) 换算」（纯逻辑，可纯 Dart 单测）
///
/// 横向模式把「上一章 / 当前章 / 下一章」的页拼成一条扁平序列交给 `PageView`，
/// 于是页面与视图都需要同一套换算：视图按总页数构建 `PageView`，页面按扁平索引
/// 反解「第 N 页属于哪章哪页」。
///
/// 这套规则原先在两处各写一遍（「未分片章占 1 页」的判定共出现 3 次），且必须
/// 逐位一致 —— 任何一处口径漂移都不会报错，只会让**翻页落点与底部页码静默错位**。
/// 故收敛为唯一出处，并可脱离 Widget 树直接单测。
class HorizontalWindow {
  const HorizontalWindow._();

  /// 某章在扁平序列中占的页数：正文未分片时恒占 1 页（加载占位页）
  static int pageCountOf(List<String>? slices) =>
      (slices != null && slices.isNotEmpty) ? slices.length : 1;

  /// 窗口内某章的占位页数（按「章号 → 分片」映射取用；缺章视为未分片）
  static int pageCountIn(
    Map<int, List<String>> slicesByChapter,
    int chapter,
  ) =>
      pageCountOf(slicesByChapter[chapter]);

  /// 滑窗扁平总页数
  static int totalPages(
    List<int> windowChapters,
    Map<int, List<String>> slicesByChapter,
  ) {
    var total = 0;
    for (final chapter in windowChapters) {
      total += pageCountIn(slicesByChapter, chapter);
    }
    return total;
  }

  /// 扁平页索引 → (章号, 章内页码)
  ///
  /// 越界（含负数）兜底为窗口最后一章第 0 页；[windowChapters] 恒非空
  /// （调用方构造滑窗时必含当前章）。
  static (int, int) resolveFlat(
    List<int> windowChapters,
    Map<int, List<String>> slicesByChapter,
    int rawIndex,
  ) {
    var remaining = rawIndex < 0 ? 0 : rawIndex;
    for (final chapter in windowChapters) {
      final count = pageCountIn(slicesByChapter, chapter);
      if (remaining < count) return (chapter, remaining);
      remaining -= count;
    }
    return (windowChapters.last, 0);
  }

  /// (章号, 章内页码) → 扁平页索引（章不在窗口内时兜底 0）
  ///
  /// 与 [resolveFlat] 互为逆运算：对窗口内任一合法扁平索引 `i`，
  /// `flatIndexOf(resolveFlat(i)) == i`。
  static int flatIndexOf(
    List<int> windowChapters,
    Map<int, List<String>> slicesByChapter,
    int chapter,
    int pageInChapter,
  ) {
    var base = 0;
    for (final c in windowChapters) {
      if (c == chapter) return base + pageInChapter;
      base += pageCountIn(slicesByChapter, c);
    }
    return 0;
  }
}
