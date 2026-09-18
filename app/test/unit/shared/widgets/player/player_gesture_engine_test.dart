import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/shared/widgets/player/player_gesture_engine.dart';

/// 播放器手势引擎单元测试
///
/// 重点覆盖两处只能靠真机拖动发现的边界：
/// 1. **浮点累积**：逐帧取整会让慢速滑动「一顿一停」；
/// 2. **越界回写**：拖到片头片尾后继续滑动会累积无效位移，回滑出现空窗期。
void main() {
  group('zoneOf 手势分区', () {
    test('左侧 35% 为亮度区', () {
      expect(
        PlayerGestureEngine.zoneOf(localX: 0, totalWidth: 1000),
        PlayerGestureZone.brightness,
      );
      expect(
        PlayerGestureEngine.zoneOf(localX: 349, totalWidth: 1000),
        PlayerGestureZone.brightness,
      );
    });

    test('右侧 35% 为音量区', () {
      expect(
        PlayerGestureEngine.zoneOf(localX: 651, totalWidth: 1000),
        PlayerGestureZone.volume,
      );
      expect(
        PlayerGestureEngine.zoneOf(localX: 1000, totalWidth: 1000),
        PlayerGestureZone.volume,
      );
    });

    test('中间 30% 不响应垂直滑动（边界值归入中间）', () {
      expect(
        PlayerGestureEngine.zoneOf(localX: 350, totalWidth: 1000),
        PlayerGestureZone.none,
      );
      expect(
        PlayerGestureEngine.zoneOf(localX: 650, totalWidth: 1000),
        PlayerGestureZone.none,
      );
      expect(
        PlayerGestureEngine.zoneOf(localX: 500, totalWidth: 1000),
        PlayerGestureZone.none,
      );
    });

    test('宽度为 0（尚未布局）时返回 none，避免除零误判', () {
      expect(
        PlayerGestureEngine.zoneOf(localX: 0, totalWidth: 0),
        PlayerGestureZone.none,
      );
    });
  });

  group('applyVerticalDrag 垂直滑动换算', () {
    test('按 1.5 倍灵敏度换算', () {
      expect(
        PlayerGestureEngine.applyVerticalDrag(
          current: 0.5,
          deltaRatio: 0.1,
          min: 0,
          max: 1,
        ),
        closeTo(0.65, 1e-9),
      );
    });

    test('上限封顶', () {
      expect(
        PlayerGestureEngine.applyVerticalDrag(
          current: 0.95,
          deltaRatio: 0.1,
          min: 0,
          max: 1,
        ),
        1.0,
      );
    });

    test('亮度下限为 0.15（避免调成全黑）', () {
      expect(
        PlayerGestureEngine.applyVerticalDrag(
          current: 0.2,
          deltaRatio: -0.1,
          min: 0.15,
          max: 1.0,
        ),
        closeTo(0.15, 1e-9),
      );
    });

    test('音量下限为 0', () {
      expect(
        PlayerGestureEngine.applyVerticalDrag(
          current: 0.02,
          deltaRatio: -0.5,
          min: 0.0,
          max: 1.0,
        ),
        0.0,
      );
    });
  });

  group('seekSecondsPerScreen 滑动档位分档', () {
    test('短片用 60 秒/屏', () {
      expect(
        PlayerGestureEngine.seekSecondsPerScreen(const Duration(seconds: 120)),
        60.0,
      );
    });

    test('恰好 300 秒仍为短片档位', () {
      expect(
        PlayerGestureEngine.seekSecondsPerScreen(const Duration(seconds: 300)),
        60.0,
      );
    });

    test('超过 300 秒改用 120 秒/屏', () {
      expect(
        PlayerGestureEngine.seekSecondsPerScreen(const Duration(seconds: 301)),
        120.0,
      );
      expect(
        PlayerGestureEngine.seekSecondsPerScreen(const Duration(hours: 1)),
        120.0,
      );
    });

    test('时长未知时按兜底档位计算（120 秒 → 短片档）', () {
      expect(
        PlayerGestureEngine.seekSecondsPerScreen(Duration.zero),
        60.0,
      );
    });
  });

  group('resolveSeekTarget 快进快退累积', () {
    const duration = Duration(seconds: 120); // 短片档：60 秒/屏

    test('半屏滑动即前进 30 秒', () {
      final result = PlayerGestureEngine.resolveSeekTarget(
        startPosition: Duration.zero,
        accumulatedSeconds: 0,
        deltaRatio: 0.5,
        totalDuration: duration,
      );

      expect(result.accumulatedSeconds, closeTo(30.0, 1e-9));
      expect(result.target, const Duration(seconds: 30));
    });

    test('浮点累积不做逐帧取整（慢速滑动不丢精度）', () {
      // 每帧 0.004 屏 ≈ 0.24 秒：若逐帧取整会被截断为 0，累积三帧仍是 0
      var accumulated = 0.0;
      Duration target = Duration.zero;
      for (var i = 0; i < 3; i++) {
        final r = PlayerGestureEngine.resolveSeekTarget(
          startPosition: Duration.zero,
          accumulatedSeconds: accumulated,
          deltaRatio: 0.004,
          totalDuration: duration,
        );
        accumulated = r.accumulatedSeconds;
        target = r.target;
      }

      expect(accumulated, closeTo(0.72, 1e-9));
      expect(target.inMilliseconds, 720);
    });

    test('拖到片尾后越界位移被回写，回滑立即响应', () {
      // 起始 110 秒，一次滑满整屏（+60 秒）会越过 120 秒片尾
      final overshoot = PlayerGestureEngine.resolveSeekTarget(
        startPosition: const Duration(seconds: 110),
        accumulatedSeconds: 0,
        deltaRatio: 1.0,
        totalDuration: duration,
      );

      expect(overshoot.target, duration, reason: '目标位置封顶到片尾');
      expect(
        overshoot.accumulatedSeconds,
        closeTo(10.0, 1e-9),
        reason: '累积值应回写为「实际生效的 10 秒」，而不是 60 秒',
      );

      // 紧接着回滑半屏（-30 秒）：因为越界已被回写，位置会立刻后退到 90 秒
      final back = PlayerGestureEngine.resolveSeekTarget(
        startPosition: const Duration(seconds: 110),
        accumulatedSeconds: overshoot.accumulatedSeconds,
        deltaRatio: -0.5,
        totalDuration: duration,
      );

      expect(back.target, const Duration(seconds: 90));
      expect(back.accumulatedSeconds, closeTo(-20.0, 1e-9));
    });

    test('拖到片头时同样封顶并回写', () {
      final result = PlayerGestureEngine.resolveSeekTarget(
        startPosition: const Duration(seconds: 5),
        accumulatedSeconds: 0,
        deltaRatio: -1.0,
        totalDuration: duration,
      );

      expect(result.target, Duration.zero);
      expect(result.accumulatedSeconds, closeTo(-5.0, 1e-9));
    });

    test('时长未知（0）时目标恒为 0，不产生非法 Duration', () {
      final result = PlayerGestureEngine.resolveSeekTarget(
        startPosition: Duration.zero,
        accumulatedSeconds: 0,
        deltaRatio: 0.5,
        totalDuration: Duration.zero,
      );

      expect(result.target, Duration.zero);
      expect(result.target.isNegative, isFalse);
    });
  });

  group('displayDeltaSeconds 浮层秒数', () {
    test('四舍五入展示', () {
      expect(PlayerGestureEngine.displayDeltaSeconds(15.4), 15);
      expect(PlayerGestureEngine.displayDeltaSeconds(15.6), 16);
      expect(PlayerGestureEngine.displayDeltaSeconds(-7.6), -8);
    });
  });
}
