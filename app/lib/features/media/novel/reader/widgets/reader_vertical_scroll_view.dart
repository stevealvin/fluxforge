import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 上下连续无缝长篇滚动视口
///
/// 纯展示组件：章节序列、续载状态、锚点与滚动控制器均由上层提供，
/// 续载目标判定由 `VerticalFlowEngine` 负责，本组件只负责渲染。
///
/// ### 核心实现：用 [CustomScrollView.center] 锚点代替「前插后补偿偏移」
///
/// **旧实现的问题**：单条 `ListView` 的偏移原点是整条内容的最顶部，向上前插一章会让
/// 所有已有内容的 index 位移，只能「先布局 → 下一帧量出高度 → `jumpTo` 补偿」。
/// 这必然产生**一帧错位画面**（用户感知为滚动到顶时顿一下），
/// 且新块高度测不到时补偿会被放弃、位置直接偏掉。
///
/// **现实现**：把「进入纵向模式时所在的那一章」作为 [CustomScrollView.center]。
/// 位于锚点之上（负偏移方向）的 sliver 其坐标是**独立于锚点**的，
/// 向上插入内容不会改变锚点及以下的布局坐标 —— **滚动位置天然不变，无需任何补偿**。
///
/// 因此本组件需要把章节序列按锚点切成两段：
/// - 锚点之前 → 上方 sliver（渲染时倒序取用，因为越靠前的项离锚点越远）；
/// - 锚点及之后 → 下方 sliver（[centerKey] 挂在其上，作为坐标原点）。
///
/// ### 其他约定
///
/// 长卷用「外层单个 [SelectionArea] + 内部纯 [Text]」替代「逐块 `SelectableText`」——
/// 后者每个实例都会建立独立的 `EditableText` 与选择容器，多章并存时布局与绘制开销显著；
/// `SelectionArea` 只在整条长卷外层建立一次选择容器，同样支持长按划词与跨章复制。
class ReaderVerticalScrollView extends StatelessWidget {
  const ReaderVerticalScrollView({
    super.key,
    required this.sequence,
    required this.anchorIndex,
    required this.centerKey,
    required this.chapters,
    required this.blockKeys,
    required this.controller,
    required this.readerTheme,
    required this.fontSize,
    required this.lineHeight,
    required this.contentOf,
    required this.hasMore,
    required this.onScrollEnd,
  });

  /// 连续阅读的章节索引序列（升序、连续；首端可被向上前插，末端可被向下追加）
  final List<int> sequence;

  /// 长卷锚点章节索引（进入纵向模式时所在的章，在本轮纵向阅读中保持不变）
  final int anchorIndex;

  /// 锚点 sliver 的稳定 Key
  ///
  /// 必须由上层持有：`center` 是跨帧的坐标基准，若每帧重建 Key 会导致
  /// Viewport 无法识别锚点、滚动位置被重置。
  final Key centerKey;

  /// 全量章节（按真实索引取用）
  final List<NovelChapter> chapters;

  /// 各章节块定位 Key（用于识别当前正在阅读的章节，缺失时按需创建）
  final Map<int, GlobalKey> blockKeys;

  /// 长卷滚动控制器
  final ScrollController controller;

  final ReaderTheme readerTheme;
  final double fontSize;
  final double lineHeight;

  /// 取章节正文（上层按「内存镜像优先、落回章节自有正文」解析）
  final String Function(int index) contentOf;

  /// 下方是否仍有可续载章节（决定底部占位与「已是最后一章」提示）
  final bool hasMore;

  /// 滚动停止回调：上层滚动中的屏中线同步是降频的，停止时靠它补一次精确同步
  final VoidCallback onScrollEnd;

  @override
  Widget build(BuildContext context) {
    // 锚点必然存在于序列中（前插 / 追加都只增不减），索引为 -1 时兜底为 0
    final anchorPos = sequence.indexOf(anchorIndex);
    final splitAt = anchorPos < 0 ? 0 : anchorPos;
    final upCount = splitAt;
    final downCount = sequence.length - splitAt;

    final scrollView = CustomScrollView(
      controller: controller,
      center: centerKey,
      slivers: [
        // 长卷最顶部留白（位于最远端，锚点上方内容为空时它就是顶部留白）
        const SliverToBoxAdapter(child: SizedBox(height: 16)),

        // ---- 锚点之上：向上方向 ----
        // 该 sliver 内越靠前的项离锚点越远，故渲染时倒序取用
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final chIndex = sequence[upCount - 1 - i];
                // 向上区域的每块后面必然还有内容（至少是锚点块）→ 一律画尾部线
                return _buildChapterBlock(context, chIndex, showTrailingDivider: true);
              },
              childCount: upCount,
            ),
          ),
        ),

        // ---- 锚点及之下：向下方向（坐标原点） ----
        SliverPadding(
          key: centerKey,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) {
                final chIndex = sequence[splitAt + i];
                // 除整条长卷的最后一块外，其余块都在尾部画分隔线 ——
                // 尾部线只取决于「后面还有没有块」，因此**向上前插不会改变任何
                // 已有块的布局**（若改用「顶部线」，前插会让锚点块凭空多出一条线，
                // 导致锚点内容整体下移，正是上一版残留 54px 跳变的根因）
                return _buildChapterBlock(
                  context,
                  chIndex,
                  showTrailingDivider: i < downCount - 1,
                );
              },
              childCount: downCount,
            ),
          ),
        ),

        // ---- 底部续载占位 / 全书末尾提示 ----
        if (hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
              child: Center(
                child: Text(
                  '正在续载下一章...',
                  style: TextStyle(fontSize: 12, color: readerTheme.subText),
                ),
              ),
            ),
          ),
      ],
    );

    return SelectionArea(
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          onScrollEnd();
          return false;
        },
        child: scrollView,
      ),
    );
  }

  /// 单个章节块：居中标题 + 正文 + 可选的**尾部**章节分隔
  ///
  /// 分隔线刻意放在块尾而非块首：放在块首时，「本块上方是否有内容」会在向上前插的
  /// 瞬间由 false 变 true，块内凭空多出一条 54px 的分隔线，锚点内容随之整体下移 ——
  /// 这正是「滚到顶顿一下」的最后一环。放在块尾后，前插只会让新块的尾部线生效，
  /// 已有块的布局完全不变。
  Widget _buildChapterBlock(
    BuildContext context,
    int chIndex, {
    required bool showTrailingDivider,
  }) {
    final ch = chapters[chIndex];
    final content = contentOf(chIndex);
    final isLastOverall = sequence.last == chIndex;

    return Column(
      key: blockKeys.putIfAbsent(chIndex, () => GlobalKey()),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Text(
            ch.title,
            style: TextStyle(
              fontSize: fontSize + 4,
              fontWeight: FontWeight.bold,
              color: readerTheme.text,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // 单击手势统一由上层的三区点击热层接管；
        // 长按划词与跨章选择由外层 SelectionArea 统一提供
        Text(
          content.isEmpty ? '正文加载中...' : content,
          style: TextStyle(
            fontSize: fontSize,
            height: lineHeight,
            color: readerTheme.text,
            letterSpacing: 0.5,
          ),
        ),
        // 章节分隔（视觉上位于两块之间）
        if (showTrailingDivider) ...[
          const SizedBox(height: 20),
          Divider(color: readerTheme.subText.withValues(alpha: 0.18)),
          const SizedBox(height: 18),
        ],
        // 全书末尾提示
        if (isLastOverall && !hasMore) ...[
          const SizedBox(height: 36),
          Center(
            child: Text(
              '— 已是最后一章 —',
              style: TextStyle(fontSize: 12, color: readerTheme.subText),
            ),
          ),
        ],
      ],
    );
  }
}
