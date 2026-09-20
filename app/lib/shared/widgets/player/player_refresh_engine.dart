/// 播放器帧回调刷新策略引擎
///
/// 帧回调每秒约 60 次，其中绝大多数只有播放位置在变；若每帧 `setState`，
/// 整棵播放器树会被逐帧重建。本引擎把一帧数据分成两类：
/// - **位置类** → 调用方递增位置心跳，仅订阅该心跳的 UI 局部重建；
/// - **状态类**（播放/暂停、缓冲、倍速、总时长、初始化完成）→ 与上次快照比对，
///   仅在真正变化时告知调用方整树重建一次。
///
/// 独立成类的原因：这是纯数据比对，可用单测锁定「状态不变时反复提交必须返回 false」。
class PlayerRefreshEngine {
  bool? _isPlaying;
  bool? _isBuffering;
  double? _playbackSpeed;
  Duration? _duration;
  bool? _isInitialized;

  /// 提交一帧状态，返回**是否需要整树重建**
  ///
  /// 首次调用恒返回 `true`：快照为空，需要一次重建把初始状态铺到 UI 上
  /// （也保证 `aspectRatio` 等依赖控制器实时值的布局能拿到初值）。
  bool submit({
    required bool isPlaying,
    required bool isBuffering,
    required double playbackSpeed,
    required Duration duration,
    required bool isInitialized,
  }) {
    final changed = isPlaying != _isPlaying ||
        isBuffering != _isBuffering ||
        playbackSpeed != _playbackSpeed ||
        duration != _duration ||
        isInitialized != _isInitialized;

    if (!changed) return false;

    _isPlaying = isPlaying;
    _isBuffering = isBuffering;
    _playbackSpeed = playbackSpeed;
    _duration = duration;
    _isInitialized = isInitialized;
    return true;
  }

  /// 清空快照
  ///
  /// 切换播放源 / 重建控制器后调用：此时上一份快照来自**另一个**媒体，
  /// 若沿用会掩盖新控制器首帧的状态变化，导致首帧不重建。
  void reset() {
    _isPlaying = null;
    _isBuffering = null;
    _playbackSpeed = null;
    _duration = null;
    _isInitialized = null;
  }
}
