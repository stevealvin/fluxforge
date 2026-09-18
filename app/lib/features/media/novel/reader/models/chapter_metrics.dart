/// 纵向长卷中单章的实测几何信息
///
/// 由 `RenderAbstractViewport.getOffsetToReveal` 实测得出，用于精确计算「本章内进度」，
/// 避免沿用整条长卷的 `maxScrollExtent` 作分母（后者会随已加载章节数增大而失真）。
class ChapterMetrics {
  const ChapterMetrics({
    required this.top,
    required this.height,
    required this.scrollable,
  });

  /// 章块顶部对应的滚动偏移
  final double top;

  /// 章块完整高度
  final double height;

  /// 章内可滚动距离（章块高度 - 视口高度，不足一屏时按 0 计）
  final double scrollable;
}
