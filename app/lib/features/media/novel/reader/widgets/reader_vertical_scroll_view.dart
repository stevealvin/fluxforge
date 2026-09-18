import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';

/// 上下连续无缝长篇滚动视口
///
/// 纯展示组件：章节序列、续载状态与滚动控制器均由上层提供，
/// 续载目标判定与偏移补偿由 `VerticalFlowEngine` 负责，本组件只负责渲染。
///
/// 关键实现约定：长卷用「外层单个 [SelectionArea] + 内部纯 [Text]」替代
/// 「逐块 `SelectableText`」—— `SelectableText` 每个实例都会建立独立的
/// `EditableText` 与选择容器，长卷中多章并存时布局与绘制开销显著；
/// `SelectionArea` 只在整条长卷外层建立一次选择容器，同样支持长按划词与跨章复制，
/// 但渲染成本大幅下降。
class ReaderVerticalScrollView extends StatelessWidget {
  const ReaderVerticalScrollView({
    super.key,
    required this.sequence,
    required this.chapters,
    required this.blockKeys,
    required this.controller,
    required this.readerTheme,
    required this.fontSize,
    required this.lineHeight,
    required this.contentOf,
    required this.hasMore,
  });

  /// 连续阅读的章节索引序列
  final List<int> sequence;

  /// 全量章节（按真实索引取用）
  final List<NovelChapter> chapters;

  /// 各章节块定位 Key（用于识别当前正在阅读的章节，缺失时按需创建）
  final Map<int, GlobalKey> blockKeys;

  /// 长卷滚动控制器
  final ScrollController controller;

  final ReaderTheme readerTheme;
  final double fontSize;
  final double lineHeight;

  /// 取章节正文（上层按「内存缓存优先、落回章节自带正文」解析）
  final String Function(int index) contentOf;

  /// 下方是否仍有可续载章节（决定底部占位与「已是最后一章」提示）
  final bool hasMore;

  @override
  Widget build(BuildContext context) {
    final listView = ListView.builder(
      controller: controller,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: sequence.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        // 末尾续载状态占位
        if (i >= sequence.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                '正在续载下一章...',
                style: TextStyle(fontSize: 12, color: readerTheme.subText),
              ),
            ),
          );
        }

        final chIndex = sequence[i];
        final ch = chapters[chIndex];
        final content = contentOf(chIndex);

        return Column(
          key: blockKeys.putIfAbsent(chIndex, () => GlobalKey()),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 章节分隔与标题
            if (i > 0) ...[
              const SizedBox(height: 20),
              Divider(color: readerTheme.subText.withValues(alpha: 0.18)),
              const SizedBox(height: 18),
            ],
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
            // 全书末尾提示
            if (i == sequence.length - 1 && !hasMore) ...[
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
      },
    );

    return SelectionArea(child: listView);
  }
}
