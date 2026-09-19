/// 纵向长卷（连续滚屏）流程引擎
///
/// 从 `NovelReaderPage` 抽出的**纯逻辑**：给定长卷章节序列与加载状态，
/// 计算本轮滚动该续载哪一章、下方是否还有内容、前插后如何补偿滚动偏移。
///
/// 全部为无状态静态方法，因此可以直接单元测试首章 / 末章 / 加载中 / 失败熔断等边界 ——
/// 这些分支此前埋在手势与 `setState` 之间，只能靠手工滚动验证。
class VerticalFlowEngine {
  const VerticalFlowEngine._();

  /// 距顶 / 距底多少像素内触发续载
  static const double loadThreshold = 480.0;

  /// 依据滚动位置解析本轮续载意图
  ///
  /// 内容不足一屏时顶部与底部条件会同时成立（返回 [VerticalLoadIntent.both]），
  /// 这也是「短章节也能持续向两个方向回溯」的前提。
  static VerticalLoadIntent resolveIntent({
    required double pixels,
    required double maxScrollExtent,
    double threshold = loadThreshold,
  }) {
    final nearTop = pixels < threshold;
    final nearBottom = maxScrollExtent - pixels < threshold;

    if (nearTop && nearBottom) return VerticalLoadIntent.both;
    if (nearBottom) return VerticalLoadIntent.appendNext;
    if (nearTop) return VerticalLoadIntent.prependPrev;
    return VerticalLoadIntent.none;
  }

  /// 向下续载的目标章节
  ///
  /// 返回 null 表示无需动作：序列为空 / 已到全书末尾 / 该章正在加载 / 该章此前已失败熔断。
  static int? nextAppendTarget({
    required List<int> sequence,
    required Set<int> appending,
    required Set<int> failed,
    required int chapterCount,
  }) {
    if (sequence.isEmpty) return null;
    final next = sequence.last + 1;
    if (next >= chapterCount) return null;
    if (appending.contains(next)) return null;
    if (failed.contains(next)) return null;
    return next;
  }

  /// 向上前插的目标章节
  ///
  /// 返回 null 表示无需动作：序列为空 / 已到全书首章 / 该章正在加载 / 该章此前已失败熔断。
  static int? prevPrependTarget({
    required List<int> sequence,
    required Set<int> appending,
    required Set<int> failed,
  }) {
    if (sequence.isEmpty) return null;
    final prev = sequence.first - 1;
    if (prev < 0) return null;
    if (appending.contains(prev)) return null;
    if (failed.contains(prev)) return null;
    return prev;
  }

  /// 下方是否仍有可续载章节（决定底部是否显示加载占位 / 「全书完」提示）
  static bool hasMoreBelow({
    required List<int> sequence,
    required Set<int> failed,
    required int chapterCount,
  }) {
    if (sequence.isEmpty) return false;
    final last = sequence.last;
    if (last >= chapterCount - 1) return false;
    return !failed.contains(last + 1);
  }

  // 注：原 `compensateOffsetAfterPrepend`（前插后按实测高度补偿偏移）已删除。
  // 长卷改为 `CustomScrollView.center` 锚点结构后，向上方向的坐标独立于锚点，
  // 前插内容不会移动既有内容的布局坐标，因此**不再需要任何偏移补偿** ——
  // 旧的「先布局、下一帧量高度、再 jumpTo」方案必然产生一帧错位画面。
}

/// 纵向长卷的续载意图
enum VerticalLoadIntent {
  /// 不需要续载
  none,

  /// 仅向下追加下一章
  appendNext,

  /// 仅向上前插上一章
  prependPrev,

  /// 上下都需要（内容不足一屏时同时成立）
  both,
}
