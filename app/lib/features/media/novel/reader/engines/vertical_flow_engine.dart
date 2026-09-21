import 'dart:math' as math;

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

  /// 下方那一章是否已处于「加载失败熔断」状态
  ///
  /// 必须与 [hasMoreBelow] 分开判断：后者把「加载失败」与「确实没有下一章」
  /// 都归为 `false`，视图单看它无法区分两者 —— 结果就是**把加载失败误报成
  /// 「— 已是最后一章 —」**，让用户以为书读完了。宿主据此显示重试入口。
  static bool failedBelow({
    required List<int> sequence,
    required Set<int> failed,
    required int chapterCount,
  }) {
    if (sequence.isEmpty) return false;
    final next = sequence.last + 1;
    if (next >= chapterCount) return false;
    return failed.contains(next);
  }

  /// 上方那一章是否已处于「加载失败熔断」状态（长卷顶部据此显示重试入口）
  static bool failedAbove({
    required List<int> sequence,
    required Set<int> failed,
  }) {
    if (sequence.isEmpty) return false;
    final prev = sequence.first - 1;
    if (prev < 0) return false;
    return failed.contains(prev);
  }

  // 注：原 `compensateOffsetAfterPrepend`（前插后按实测高度补偿偏移）已删除。
  // 长卷改为 `CustomScrollView.center` 锚点结构后，向上方向的坐标独立于锚点，
  // 前插内容不会移动既有内容的布局坐标，因此**不再需要任何偏移补偿** ——
  // 旧的「先布局、下一帧量高度、再 jumpTo」方案必然产生一帧错位画面。

  /// 长卷窗口半径：当前章前后各保留的章节数
  static const int defaultWindowRadius = 5;

  /// 锚点允许的最大漂移（章），超过即需重设锚点
  ///
  /// 锚点与当前章之间的「中间区段」（锚点之下、视口之上）无法免费摘除 ——
  /// 摘除会让下方内容整体上移，而这些块多已被 `SliverList` 回收、测不到高度无法补偿。
  /// 把锚点移到当前章后，该区段变成「锚点之上」，摘除重新归零成本。
  static const int maxAnchorDrift = defaultWindowRadius;

  /// 当前章距锚点是否已超过允许漂移；锚点未建立（负数）时返回 false
  static bool needsReanchor({
    required int currentChapterIndex,
    required int anchorChapterIndex,
    int maxDrift = maxAnchorDrift,
  }) {
    if (anchorChapterIndex < 0) return false;
    return (currentChapterIndex - anchorChapterIndex).abs() > maxDrift;
  }

  /// 计算窗口化需要摘除的章节
  ///
  /// 摘除是零成本的：锚点及其以下内容的坐标独立于锚点之上，且只摘除视口外的章节，
  /// 用户当前看到的位置不会移动，无需偏移补偿。
  /// **锚点章节永不摘除**（它是 Viewport 坐标原点），故两端边界都受锚点约束；
  /// 锚点或当前章不在序列中时返回空结果，宁可不裁剪。
  static VerticalWindowTrim resolveWindowTrim({
    required List<int> sequence,
    required int currentChapterIndex,
    required int anchorChapterIndex,
    int radius = defaultWindowRadius,
  }) {
    // 序列尚未超出整窗（含 radius == 0 时只留当前章的情形）→ 无需裁剪
    if (radius < 0 || sequence.length <= radius * 2 + 1) {
      return VerticalWindowTrim.none;
    }

    final currentPos = sequence.indexOf(currentChapterIndex);
    final anchorPos = sequence.indexOf(anchorChapterIndex);
    if (currentPos < 0 || anchorPos < 0) return VerticalWindowTrim.none;

    // 首端：保留当前章之前 radius 章，但不得越过锚点（锚点即坐标原点）
    final leadEnd = (currentPos - radius).clamp(0, anchorPos);
    // 末端：保留当前章之后 radius 章，且**不得吞掉锚点本身** ——
    // 用户向上读到锚点之上时（currentPos < anchorPos），锚点及其之后的内容整体位于
    // 视口下方、看似「可以摘」，但锚点是坐标原点，摘掉会让滚动位置被重置。
    final trailStart =
        math.max(currentPos + radius + 1, anchorPos + 1).clamp(0, sequence.length);

    if (leadEnd <= 0 && trailStart >= sequence.length) {
      return VerticalWindowTrim.none;
    }

    return VerticalWindowTrim(
      leading: sequence.sublist(0, leadEnd),
      trailing: sequence.sublist(trailStart),
    );
  }
}

/// 长卷窗口化的裁剪结果（首端 / 末端分开返回）
///
/// 两侧的滚动影响不同：首端摘除缩小 `minScrollExtent`，末端摘除缩小 `maxScrollExtent`。
class VerticalWindowTrim {
  const VerticalWindowTrim({required this.leading, required this.trailing});

  /// 空裁剪结果（无需摘除任何章节）
  static const VerticalWindowTrim none =
      VerticalWindowTrim(leading: [], trailing: []);

  /// 从序列**首端**摘除的章节（当前章上方、已远离视口的部分）
  final List<int> leading;

  /// 从序列**末端**摘除的章节（当前章下方、已远离视口的部分）
  final List<int> trailing;

  bool get isEmpty => leading.isEmpty && trailing.isEmpty;

  /// 需要摘除的全部章节
  Set<int> get all => {...leading, ...trailing};
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
