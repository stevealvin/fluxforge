import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/shared/widgets/player/player_completion_engine.dart';

void main() {
  const total = Duration(seconds: 100);

  bool submit(
    PlayerCompletionEngine engine, {
    bool? isInitialized,
    bool? isCompleted,
    Duration? position,
    Duration? duration,
  }) {
    return engine.shouldReport(
      isInitialized: isInitialized ?? true,
      isCompleted: isCompleted ?? false,
      position: position ?? Duration.zero,
      duration: duration ?? total,
    );
  }

  group('未播完时不上报', () {
    test('播放中不上报', () {
      final engine = PlayerCompletionEngine();
      expect(submit(engine, position: const Duration(seconds: 30)), isFalse);
    });

    test('未初始化不上报（即使位置已达时长）', () {
      final engine = PlayerCompletionEngine();
      expect(
        submit(engine, isInitialized: false, position: total),
        isFalse,
      );
    });

    test('时长未知时位置比较不生效（避免直播 / 未就绪时误判）', () {
      final engine = PlayerCompletionEngine();
      expect(
        submit(engine, position: Duration.zero, duration: Duration.zero),
        isFalse,
      );
    });
  });

  group('播完上报一次（核心约定）', () {
    test('位置达时长即上报', () {
      final engine = PlayerCompletionEngine();
      expect(submit(engine, position: total), isTrue);
    });

    test('上报后持续相同的「已播完」状态不再重复上报', () {
      final engine = PlayerCompletionEngine();
      expect(submit(engine, position: total), isTrue);

      // 库自身会在完成后 pause + seekTo(duration)，后续每帧仍满足完成条件
      for (int i = 0; i < 10; i++) {
        expect(
          submit(engine, isCompleted: true, position: total),
          isFalse,
          reason: '第 $i 帧不应重复触发结束回调',
        );
      }
    });

    test('平台 completed 事件优先于位置（位置未达时长也上报）', () {
      final engine = PlayerCompletionEngine();
      expect(
        submit(engine, isCompleted: true, position: const Duration(seconds: 99)),
        isTrue,
      );
    });
  });

  group('闩锁释放后可再次上报', () {
    test('用户 seek 回中间再播完，可再次上报', () {
      final engine = PlayerCompletionEngine();
      expect(submit(engine, position: total), isTrue);

      // seek 回中间 → 未播完 → 闩锁释放
      expect(submit(engine, position: const Duration(seconds: 10)), isFalse);
      expect(submit(engine, position: total), isTrue);
    });

    test('重新播放（isCompleted 清零）后再播完，可再次上报', () {
      final engine = PlayerCompletionEngine();
      expect(submit(engine, isCompleted: true, position: total), isTrue);

      expect(submit(engine, isCompleted: false, position: Duration.zero), isFalse);
      expect(submit(engine, position: total), isTrue);
    });

    test('循环播放场景：每绕一圈各上报一次', () {
      final engine = PlayerCompletionEngine();
      expect(submit(engine, position: total), isTrue);
      // 循环实现为 seekTo(0) + play() → 回到未播完
      expect(submit(engine, position: Duration.zero), isFalse);
      expect(submit(engine, position: total), isTrue);
    });

    test('reset 后立即恢复可上报（切换播放源 / 重建控制器）', () {
      final engine = PlayerCompletionEngine();
      expect(submit(engine, position: total), isTrue);
      expect(submit(engine, position: total), isFalse);

      engine.reset();
      expect(submit(engine, position: total), isTrue);
    });
  });
}
