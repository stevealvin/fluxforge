import 'package:fluxforge/features/media/novel/reader/models/chapter_metrics.dart';

/// 阅读进度与阅读位置换算引擎
///
/// 从 `NovelReaderPage` 抽出的**纯计算**：页码 ↔ 字符偏移 ↔ 章内比例 ↔ 滚动目标。
/// 全部为无状态静态方法，可脱离 Widget 树直接单测边界
/// （空切片、字符偏移恰好落在页边界、偏移超出正文、章块不足一屏等）。
class ReaderProgress {
  const ReaderProgress._();

  /// 横向：当前页码之前各页的字符长度之和
  ///
  /// 页码超出范围时按已有切片累加，空切片返回 0，调用方无需再做边界判断。
  static int charOffsetFromPage(List<String> pageSlices, int pageIndex) {
    if (pageSlices.isEmpty) return 0;
    int offset = 0;
    for (int i = 0; i < pageIndex && i < pageSlices.length; i++) {
      offset += pageSlices[i].length;
    }
    return offset;
  }

  /// 横向：由字符偏移反查所在页码
  ///
  /// 边界语义：偏移**恰好落在页边界**时归入下一页（用户可见的正是下一页首字）；
  /// 偏移超出正文总长时归入末页；空切片返回 0。
  static int pageIndexFromCharOffset(List<String> pageSlices, int charOffset) {
    if (pageSlices.isEmpty) return 0;

    int target = 0;
    int acc = 0;
    for (int i = 0; i < pageSlices.length; i++) {
      if (acc + pageSlices[i].length > charOffset) {
        target = i;
        break;
      }
      acc += pageSlices[i].length;
      target = i;
    }
    return target.clamp(0, pageSlices.length - 1);
  }

  /// 横向章内进度（读完第 [pageIndex] 页即为该页占比）
  static double horizontalProgress(int pageIndex, int sliceCount) {
    if (sliceCount <= 0) return 0.0;
    return ((pageIndex + 1) / sliceCount).clamp(0.0, 1.0);
  }

  /// 横向：进度条比例 → 目标页码
  ///
  /// 用 `ceil - 1` 使得「拖到 0% 落在第 1 页、拖到 100% 精确落在末页」，
  /// 不会多出一页导致进度条拖到底反而回退。
  static int pageIndexFromRatio(double ratio, int sliceCount) {
    if (sliceCount <= 0) return 0;
    final safeRatio = ratio.clamp(0.0, 1.0);
    return ((safeRatio * sliceCount).ceil() - 1).clamp(0, sliceCount - 1);
  }

  /// 纵向章内进度
  ///
  /// 章块不足一屏时没有滚动空间，直接视为本章已读完（1.0）。
  static double verticalProgress({
    required double currentOffset,
    required ChapterMetrics metrics,
  }) {
    if (metrics.scrollable <= 0) return 1.0;
    final scrolled =
        (currentOffset - metrics.top).clamp(0.0, metrics.scrollable);
    return (scrolled / metrics.scrollable).clamp(0.0, 1.0);
  }

  /// 纵向：章内比例 → 章块内滚动目标偏移
  ///
  /// 返回的是章块内绝对偏移（未对整卷 `maxScrollExtent` 取整），由调用方决定是否 clamp。
  static double verticalOffsetFromRatio({
    required double ratio,
    required ChapterMetrics metrics,
  }) =>
      metrics.top + ratio.clamp(0.0, 1.0) * metrics.scrollable;

  /// 纵向：字符偏移 → 章内比例
  static double ratioFromCharOffset(int charOffset, int contentLength) {
    if (contentLength <= 0) return 0.0;
    return (charOffset / contentLength).clamp(0.0, 1.0);
  }

  /// 章内进度文案（横向：页码）
  static String horizontalLabel(int pageIndex, int sliceCount) =>
      sliceCount <= 0 ? '--' : '本章 第 ${pageIndex + 1} / $sliceCount 页';

  /// 章内进度文案（纵向：百分比）
  static String verticalLabel(double progress) =>
      '本章 ${(progress * 100).round()}%';
}
