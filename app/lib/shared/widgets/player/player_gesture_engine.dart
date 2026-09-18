/// 手势调节区域
enum PlayerGestureZone {
  /// 左侧区域：调节屏幕亮度
  brightness,

  /// 中间区域：不响应垂直滑动
  none,

  /// 右侧区域：调节应用内音量
  volume,
}

/// 播放器手势引擎
///
/// 把手势层里的**纯计算**抽出来：横向分区判定、垂直滑动灵敏度换算、
/// 以及水平快进/快退的「浮点累积 + 毫秒精度 + 越界位移回写」算法。
///
/// 这些计算原先埋在两段 `onXxxDragUpdate` 闭包里，只能靠真机拖动验证；
/// 抽成无状态静态方法后可逐条覆盖边界：短片 / 长片、拖到片头片尾、反复回滑。
class PlayerGestureEngine {
  const PlayerGestureEngine._();

  /// 手势横向分区边界占比：左侧 35% 调亮度、右侧 35% 调音量、中间 30% 不响应
  static const double sideZoneRatio = 0.35;

  /// 垂直滑动灵敏度：滑过整屏约对应 1.5 倍量程
  static const double verticalSensitivity = 1.5;

  /// 长片判定阈值（秒）
  static const int longVideoThresholdSeconds = 300;

  /// 短片水平滑动档位（秒/屏）
  static const double shortVideoSecondsPerScreen = 60.0;

  /// 长片水平滑动档位（秒/屏）
  static const double longVideoSecondsPerScreen = 120.0;

  /// 时长未知时的兜底档位（秒）
  static const int unknownDurationFallbackSeconds = 120;

  /// 手势落在哪个调节区域
  ///
  /// 宽度为 0（尚未完成布局）时返回 [PlayerGestureZone.none]，避免除零与误判。
  static PlayerGestureZone zoneOf({
    required double localX,
    required double totalWidth,
  }) {
    if (totalWidth <= 0) return PlayerGestureZone.none;
    if (localX < totalWidth * sideZoneRatio) return PlayerGestureZone.brightness;
    if (localX > totalWidth * (1 - sideZoneRatio)) return PlayerGestureZone.volume;
    return PlayerGestureZone.none;
  }

  /// 垂直滑动的量程换算与限幅
  ///
  /// [deltaRatio] 为「滑动距离 / 区域高度」并已取反（向上滑动为正），
  /// 亮度与音量共用同一套灵敏度，仅 clamp 区间不同（亮度下限 0.15 以免全黑）。
  static double applyVerticalDrag({
    required double current,
    required double deltaRatio,
    required double min,
    required double max,
  }) =>
      (current + deltaRatio * verticalSensitivity).clamp(min, max);

  /// 水平滑动「每屏秒数」分档
  ///
  /// 长片用更大的档位，否则滑过整屏只能移动 60 秒，长视频里调整起来过于迟钝。
  static double seekSecondsPerScreen(Duration totalDuration) {
    final seconds = totalDuration.inSeconds;
    final base = seconds > 0 ? seconds : unknownDurationFallbackSeconds;
    return base > longVideoThresholdSeconds
        ? longVideoSecondsPerScreen
        : shortVideoSecondsPerScreen;
  }

  /// 累积水平滑动偏移并求目标位置
  ///
  /// 两处关键设计：
  /// 1. **浮点累积**：若对每帧增量先取整再累加，慢速滑动时单帧增量常不足 0.5 秒而被
  ///    截断为 0，形成「一顿一停、偶尔跳 1 秒」的顿挫感；
  /// 2. **越界回写**：把 clamp 后的实际位移回写到累积值，否则拖到片头片尾后继续滑动会
  ///    持续累积无效位移，回滑时出现一段「不响应」的空窗期。
  static ({double accumulatedSeconds, Duration target}) resolveSeekTarget({
    required Duration startPosition,
    required double accumulatedSeconds,
    required double deltaRatio,
    required Duration totalDuration,
  }) {
    final scaleSecs = seekSecondsPerScreen(totalDuration);
    var accumulated = accumulatedSeconds + deltaRatio * scaleSecs;

    final maxMs = totalDuration.inMilliseconds;
    final rawMs = startPosition.inMilliseconds + accumulated * 1000;
    final clampedMs = rawMs.clamp(0.0, maxMs.toDouble());

    // 越界位移回写：让累积值始终等于「实际生效的偏移」
    accumulated = (clampedMs - startPosition.inMilliseconds) / 1000;

    return (
      accumulatedSeconds: accumulated,
      target: Duration(milliseconds: clampedMs.round()),
    );
  }

  /// 水平滑动的目标秒数与方向（供浮层展示 `+15s` / `-8s`）
  static int displayDeltaSeconds(double accumulatedSeconds) =>
      accumulatedSeconds.round();
}
