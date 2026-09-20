import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/shared/widgets/player/player_refresh_engine.dart';

void main() {
  /// 一帧的默认状态（已初始化、正在播放、未缓冲、1.0x、时长 100 秒）
  bool submitDefaults(
    PlayerRefreshEngine engine, {
    bool? isPlaying,
    bool? isBuffering,
    double? playbackSpeed,
    Duration? duration,
    bool? isInitialized,
  }) {
    return engine.submit(
      isPlaying: isPlaying ?? true,
      isBuffering: isBuffering ?? false,
      playbackSpeed: playbackSpeed ?? 1.0,
      duration: duration ?? const Duration(seconds: 100),
      isInitialized: isInitialized ?? true,
    );
  }

  group('首次提交', () {
    test('首次提交恒返回 true（快照为空，需要一次重建铺初值）', () {
      expect(submitDefaults(PlayerRefreshEngine()), isTrue);
    });

    test('reset 后下一次提交重新变为 true', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine);
      expect(submitDefaults(engine), isFalse);

      engine.reset();
      expect(submitDefaults(engine), isTrue);
    });
  });

  group('状态不变时不重建（播放期核心约定）', () {
    test('连续 60 帧相同状态（仅播放位置在推进）全部返回 false', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine); // 首帧

      for (int i = 0; i < 60; i++) {
        expect(submitDefaults(engine), isFalse, reason: '第 $i 帧不应触发整树重建');
      }
    });

    test('状态变化触发一次后，继续提交同值不再触发', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine);

      expect(submitDefaults(engine, isPlaying: false), isTrue);
      expect(submitDefaults(engine, isPlaying: false), isFalse);
    });
  });

  group('各状态类字段变化都会触发重建', () {
    test('isPlaying 变化', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine);
      expect(submitDefaults(engine, isPlaying: false), isTrue);
    });

    test('isBuffering 变化', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine);
      expect(submitDefaults(engine, isBuffering: true), isTrue);
    });

    test('playbackSpeed 变化', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine);
      expect(submitDefaults(engine, playbackSpeed: 2.0), isTrue);
    });

    test('duration 从 0 变为已知（初始化完成）', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine, duration: Duration.zero);
      expect(submitDefaults(engine, duration: const Duration(seconds: 100)), isTrue);
    });

    test('isInitialized 变化', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine, isInitialized: false);
      expect(submitDefaults(engine, isInitialized: true), isTrue);
    });
  });

  group('多字段与往复变化', () {
    test('多个字段同时变化只返回一次 true', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine);

      final first = engine.submit(
        isPlaying: false,
        isBuffering: true,
        playbackSpeed: 2.0,
        duration: const Duration(seconds: 200),
        isInitialized: true,
      );
      expect(first, isTrue);

      final second = engine.submit(
        isPlaying: false,
        isBuffering: true,
        playbackSpeed: 2.0,
        duration: const Duration(seconds: 200),
        isInitialized: true,
      );
      expect(second, isFalse);
    });

    test('播放/暂停往复切换每次都触发（只与上一帧比较，不记历史）', () {
      final engine = PlayerRefreshEngine();
      submitDefaults(engine);

      expect(submitDefaults(engine, isPlaying: false), isTrue);
      expect(submitDefaults(engine, isPlaying: true), isTrue);
      expect(submitDefaults(engine, isPlaying: false), isTrue);
    });
  });
}
