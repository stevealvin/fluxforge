/// 章节目录导航计算
///
/// 目录的「显示行号映射」与「停靠滚动偏移」抽为纯计算，正序 / 倒序两种排序共用同一套算法，
/// 保证切换排序后仍能自动停靠到正在阅读的章节。
class CatalogNavigator {
  const CatalogNavigator._();

  /// 目录列表固定行高
  ///
  /// 固定行高才能用 `initialScrollOffset` 精确跳转到指定章节（变高列表只能靠逐项测量）。
  static const double itemHeight = 56.0;

  /// 当前章上方保留的上下文行数 —— 定位更自然，不把当前章顶到屏幕最上沿
  static const int contextRows = 2;

  /// 当前章在目录中的显示行号（倒序时镜像翻转）
  static int displayIndex({
    required int chapterIndex,
    required int chapterCount,
    required bool reversed,
  }) => reversed ? chapterCount - 1 - chapterIndex : chapterIndex;

  /// 目录应停靠的滚动偏移
  ///
  /// 注意上界用 `chapterCount` 而非 `chapterCount - 1`：允许滚到末章之后一行的位置，
  /// 使末章也能获得完整的「上方 2 行上下文」视角；实际滚动位置仍由
  /// `ScrollController` 的 `maxScrollExtent` 兜底。
  static double offsetFor({
    required int displayIndex,
    required int chapterCount,
  }) => ((displayIndex - contextRows).clamp(0, chapterCount)) * itemHeight;
}
