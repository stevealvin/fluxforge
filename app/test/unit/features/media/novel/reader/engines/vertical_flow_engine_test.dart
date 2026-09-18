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

  group('compensateOffsetAfterPrepend 前插偏移补偿', () {
    test('按新块实测高度等量右移', () {
      expect(
        VerticalFlowEngine.compensateOffsetAfterPrepend(
          beforeOffset: 500,
          insertedHeight: 1200,
          maxScrollExtent: 9000,
        ),
        1700,
      );
    });

    test('超出可滚动范围时 clamp 到 maxScrollExtent', () {
      expect(
        VerticalFlowEngine.compensateOffsetAfterPrepend(
          beforeOffset: 8800,
          insertedHeight: 1200,
          maxScrollExtent: 9000,
        ),
        9000,
      );
    });

    test('新块尚未布局（高度为 0）时返回 null，不跳转', () {
      expect(
        VerticalFlowEngine.compensateOffsetAfterPrepend(
          beforeOffset: 500,
          insertedHeight: 0,
          maxScrollExtent: 9000,
        ),
        isNull,
      );
    });

    test('异常负高度时返回 null', () {
      expect(
        VerticalFlowEngine.compensateOffsetAfterPrepend(
          beforeOffset: 500,
          insertedHeight: -10,
          maxScrollExtent: 9000,
        ),
        isNull,
      );
    });

    test('异常负偏移时 clamp 到 0', () {
      expect(
        VerticalFlowEngine.compensateOffsetAfterPrepend(
          beforeOffset: -80,
          insertedHeight: 50,
          maxScrollExtent: 9000,
        ),
        0,
      );
    });
  });
}
