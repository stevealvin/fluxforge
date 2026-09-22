import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/features/media/novel/reader/engines/vertical_flow_engine.dart';

/// 纵向长卷流程引擎单元测试
///
/// 覆盖此前只能靠手工滚动验证的边界：首章 / 末章、加载中、失败熔断、
/// 内容不足一屏时的双向续载，以及前插后的滚动偏移补偿与 clamp。
void main() {
  group('resolveIntent 续载意图', () {
    test('远离顶部与底部时不续载', () {
      expect(
        VerticalFlowEngine.resolveIntent(pixels: 3000, maxScrollExtent: 9000),
        VerticalLoadIntent.none,
      );
    });

    test('距底不足阈值时向下追加', () {
      expect(
        VerticalFlowEngine.resolveIntent(pixels: 8600, maxScrollExtent: 9000),
        VerticalLoadIntent.appendNext,
      );
    });

    test('距顶不足阈值时向上前插', () {
      expect(
        VerticalFlowEngine.resolveIntent(pixels: 120, maxScrollExtent: 9000),
        VerticalLoadIntent.prependPrev,
      );
    });

    test('内容不足一屏时上下同时触发', () {
      expect(
        VerticalFlowEngine.resolveIntent(pixels: 0, maxScrollExtent: 200),
        VerticalLoadIntent.both,
      );
    });

    test('恰好等于阈值时不触发（严格小于判定）', () {
      expect(
        VerticalFlowEngine.resolveIntent(pixels: 480, maxScrollExtent: 9480),
        VerticalLoadIntent.none,
      );
    });

    test('阈值可自定义', () {
      expect(
        VerticalFlowEngine.resolveIntent(
          pixels: 100,
          maxScrollExtent: 10000,
          threshold: 50,
        ),
        VerticalLoadIntent.none,
      );
      expect(
        VerticalFlowEngine.resolveIntent(
          pixels: 100,
          maxScrollExtent: 10000,
          threshold: 200,
        ),
        VerticalLoadIntent.prependPrev,
      );
    });
  });

  group('nextAppendTarget 向下续载目标', () {
    test('序列末章的下一章', () {
      expect(
        VerticalFlowEngine.nextAppendTarget(
          sequence: const [10, 11],
          appending: const {},
          failed: const {},
          chapterCount: 20,
        ),
        12,
      );
    });

    test('序列为空时无目标', () {
      expect(
        VerticalFlowEngine.nextAppendTarget(
          sequence: const [],
          appending: const {},
          failed: const {},
          chapterCount: 20,
        ),
        isNull,
      );
    });

    test('已到全书末尾时无目标', () {
      expect(
        VerticalFlowEngine.nextAppendTarget(
          sequence: const [19],
          appending: const {},
          failed: const {},
          chapterCount: 20,
        ),
        isNull,
      );
    });

    test('该章正在加载时不重复发起', () {
      expect(
        VerticalFlowEngine.nextAppendTarget(
          sequence: const [10],
          appending: const {11},
          failed: const {},
          chapterCount: 20,
        ),
        isNull,
      );
    });

    test('该章此前失败熔断时不再重试', () {
      expect(
        VerticalFlowEngine.nextAppendTarget(
          sequence: const [10],
          appending: const {},
          failed: const {11},
          chapterCount: 20,
        ),
        isNull,
      );
    });
  });

  group('prevPrependTarget 向上前插目标', () {
    test('序列首章的上一章', () {
      expect(
        VerticalFlowEngine.prevPrependTarget(
          sequence: const [10, 11],
          appending: const {},
          failed: const {},
        ),
        9,
      );
    });

    test('已到全书首章时无目标', () {
      expect(
        VerticalFlowEngine.prevPrependTarget(
          sequence: const [0, 1],
          appending: const {},
          failed: const {},
        ),
        isNull,
      );
    });

    test('序列为空时无目标', () {
      expect(
        VerticalFlowEngine.prevPrependTarget(
          sequence: const [],
          appending: const {},
          failed: const {},
        ),
        isNull,
      );
    });

    test('正在加载或已失败熔断时无目标', () {
      expect(
        VerticalFlowEngine.prevPrependTarget(
          sequence: const [10],
          appending: const {9},
          failed: const {},
        ),
        isNull,
      );
      expect(
        VerticalFlowEngine.prevPrependTarget(
          sequence: const [10],
          appending: const {},
          failed: const {9},
        ),
        isNull,
      );
    });
  });

  group('hasMoreBelow 下方是否仍有内容', () {
    test('未到末章时返回 true', () {
      expect(
        VerticalFlowEngine.hasMoreBelow(
          sequence: const [10, 11],
          failed: const {},
          chapterCount: 20,
        ),
        isTrue,
      );
    });

    test('已加载到末章时返回 false', () {
      expect(
        VerticalFlowEngine.hasMoreBelow(
          sequence: const [10, 19],
          failed: const {},
          chapterCount: 20,
        ),
        isFalse,
      );
    });

    test('下一章已失败熔断时返回 false（不再显示加载占位）', () {
      expect(
        VerticalFlowEngine.hasMoreBelow(
          sequence: const [10],
          failed: const {11},
          chapterCount: 20,
        ),
        isFalse,
      );
    });

    test('序列为空时返回 false', () {
      expect(
        VerticalFlowEngine.hasMoreBelow(
          sequence: const [],
          failed: const {},
          chapterCount: 20,
        ),
        isFalse,
      );
    });
  });

  group('failedBelow / failedAbove 熔断可见性', () {
    test('下方熔断：必须能把「加载失败」与「确实没有下一章」分开', () {
      const sequence = [10];
      // 同一个 hasMore=false，两种成因必须可分辨 —— 否则视图会把加载失败
      // 误报成「— 已是最后一章 —」
      expect(
        VerticalFlowEngine.hasMoreBelow(
          sequence: sequence,
          failed: const {11},
          chapterCount: 20,
        ),
        isFalse,
      );
      expect(
        VerticalFlowEngine.failedBelow(
          sequence: sequence,
          failed: const {11},
          chapterCount: 20,
        ),
        isTrue,
      );
      // 已到末章：hasMore 同样是 false，但那不是失败
      expect(
        VerticalFlowEngine.failedBelow(
          sequence: const [19],
          failed: const {},
          chapterCount: 20,
        ),
        isFalse,
      );
    });

    test('下方熔断：已到末章或序列为空时一律 false', () {
      expect(
        VerticalFlowEngine.failedBelow(
          sequence: const [19],
          failed: const {20},
          chapterCount: 20,
        ),
        isFalse,
      );
      expect(
        VerticalFlowEngine.failedBelow(
          sequence: const [],
          failed: const {0},
          chapterCount: 20,
        ),
        isFalse,
      );
    });

    test('上方熔断：首章之前、未熔断、空序列均 false', () {
      expect(
        VerticalFlowEngine.failedAbove(sequence: const [10], failed: const {9}),
        isTrue,
      );
      // 已在首章：上方没有章节，failed 里就算有 -1 也不算
      expect(
        VerticalFlowEngine.failedAbove(sequence: const [0], failed: const {-1}),
        isFalse,
      );
      expect(
        VerticalFlowEngine.failedAbove(sequence: const [10], failed: const {}),
        isFalse,
      );
      expect(
        VerticalFlowEngine.failedAbove(sequence: const [], failed: const {0}),
        isFalse,
      );
    });
  });

  // 注：`compensateOffsetAfterPrepend` 的 5 条测试已随方法一并删除 ——
  // 长卷改用 `CustomScrollView.center` 锚点后不再需要偏移补偿。

  group('resolveWindowTrim 长卷窗口化', () {
    /// 便捷封装：默认锚点与当前章一致，便于表达「以锚点为当前章」的常见情形
    VerticalWindowTrim trim({
      required List<int> sequence,
      required int current,
      required int anchor,
      int radius = VerticalFlowEngine.defaultWindowRadius,
    }) {
      return VerticalFlowEngine.resolveWindowTrim(
        sequence: sequence,
        currentChapterIndex: current,
        anchorChapterIndex: anchor,
        radius: radius,
      );
    }

    test('序列未超出整窗时不裁剪', () {
      // 默认半径 5 → 整窗 11 章；恰好 11 章不裁，12 章才裁
      final eleven = List<int>.generate(11, (i) => i);
      expect(trim(sequence: eleven, current: 5, anchor: 5).isEmpty, isTrue);

      final twelve = List<int>.generate(12, (i) => i);
      expect(trim(sequence: twelve, current: 5, anchor: 5).isEmpty, isFalse);
    });

    test('以锚点为当前章：两端超出部分各裁到半径', () {
      final sequence = List<int>.generate(13, (i) => i); // 0..12
      final result = trim(sequence: sequence, current: 6, anchor: 6);

      expect(result.leading, [0]);
      expect(result.trailing, [12]);
      expect(result.all, {0, 12});
    });

    test('当前章深入锚点之下：首端裁到锚点为止，锚点必须保留', () {
      final sequence = List<int>.generate(21, (i) => i); // 0..20
      final result = trim(sequence: sequence, current: 15, anchor: 5);

      // 窗口左界为 10，但锚点在位置 5 → 只能裁到锚点之前
      expect(result.leading, [0, 1, 2, 3, 4]);
      expect(result.all.contains(5), isFalse, reason: '锚点章节永不摘除');
      expect(result.trailing, isEmpty);
    });

    test('当前章深入锚点之上：末端裁到锚点之后，锚点必须保留', () {
      final sequence = List<int>.generate(13, (i) => i); // 0..12
      final result = trim(sequence: sequence, current: 2, anchor: 10);

      expect(result.leading, isEmpty);
      // 窗口右界为 8，但锚点在位置 10 → 只能裁锚点之后
      expect(result.trailing, [11, 12]);
      expect(result.all.contains(10), isFalse, reason: '锚点章节永不摘除');
    });

    test('锚点不在序列中时不裁剪（无法保证不摘掉坐标原点）', () {
      final sequence = List<int>.generate(13, (i) => i);
      expect(trim(sequence: sequence, current: 6, anchor: 99).isEmpty, isTrue);
    });

    test('当前章不在序列中时不裁剪', () {
      final sequence = List<int>.generate(13, (i) => i);
      expect(trim(sequence: sequence, current: 99, anchor: 6).isEmpty, isTrue);
    });

    test('radius 为 0 时只保留当前章与锚点', () {
      final result = trim(
        sequence: const [10, 11, 12],
        current: 11,
        anchor: 11,
        radius: 0,
      );

      expect(result.leading, [10]);
      expect(result.trailing, [12]);
      expect(result.all.contains(11), isFalse, reason: '当前章（此处即锚点）必须保留');
    });

    test('自定义半径生效', () {
      final sequence = List<int>.generate(9, (i) => i); // 0..8
      final result = trim(sequence: sequence, current: 4, anchor: 4, radius: 1);

      expect(result.leading, [0, 1, 2]);
      expect(result.trailing, [6, 7, 8]);
    });

    test('锚点与当前章相距过远时中间区段无法裁剪 —— 必须先重设锚点', () {
      final sequence = List<int>.generate(101, (i) => i); // 0..100
      final result = trim(sequence: sequence, current: 100, anchor: 0);

      // 中间区段（锚点之下、视口之上）摘除会让下方内容整体上移，
      // 且这些块已被 SliverList 回收、测不到高度无法补偿偏移 →
      // 本方法刻意不处理，交由 needsReanchor 把锚点先移到当前章。
      expect(result.isEmpty, isTrue);
      expect(
        VerticalFlowEngine.needsReanchor(
          currentChapterIndex: 100,
          anchorChapterIndex: 0,
        ),
        isTrue,
      );
    });

    test('重设锚点后同一序列即可被裁剪到窗口内（缺口回归）', () {
      final sequence = List<int>.generate(101, (i) => i); // 0..100
      // 重设锚点后 anchor == current，中间区段变成「锚点之上」→ 零成本摘除
      final result = trim(sequence: sequence, current: 100, anchor: 100);

      expect(result.trailing, isEmpty);
      final kept = sequence.where((c) => !result.all.contains(c)).toList();
      expect(kept, [95, 96, 97, 98, 99, 100], reason: '序列收敛到当前章前 5 章');
    });
  });

  group('needsReanchor 锚点漂移判定', () {
    test('漂移在允许范围内时无需重设', () {
      expect(
        VerticalFlowEngine.needsReanchor(
          currentChapterIndex: 104,
          anchorChapterIndex: 100,
        ),
        isFalse,
      );
    });

    test('恰好等于允许漂移时不触发（严格大于才触发）', () {
      expect(
        VerticalFlowEngine.needsReanchor(
          currentChapterIndex: 105,
          anchorChapterIndex: 100,
          maxDrift: 5,
        ),
        isFalse,
      );
      expect(
        VerticalFlowEngine.needsReanchor(
          currentChapterIndex: 106,
          anchorChapterIndex: 100,
          maxDrift: 5,
        ),
        isTrue,
      );
    });

    test('向下与向上漂移都算（取绝对值）', () {
      expect(
        VerticalFlowEngine.needsReanchor(
          currentChapterIndex: 90,
          anchorChapterIndex: 100,
        ),
        isTrue,
      );
      expect(
        VerticalFlowEngine.needsReanchor(
          currentChapterIndex: 110,
          anchorChapterIndex: 100,
        ),
        isTrue,
      );
    });

    test('锚点尚未建立时不触发（进入纵向模式的初始化路径自负其责）', () {
      expect(
        VerticalFlowEngine.needsReanchor(
          currentChapterIndex: 10,
          anchorChapterIndex: -1,
        ),
        isFalse,
      );
    });
  });
}
