/// 播完判定引擎
///
/// 判定「这一帧是否表示刚播完」，并保证**同一轮播放只上报一次**。
///
/// 闩锁是必需的：库在平台 completed 事件后会自行 `pause + seekTo(duration)`，
/// 此后 `isCompleted` / `position >= duration` **持续为真**，不闩锁就会逐帧重复回调，
/// 宿主侧表现为「自动跳集一次跳两集」。
/// 判据以 `isCompleted` 为主（离散，重新播放时自动清零），位置比较作兜底；
/// 状态回到「未播完」时闩锁自动释放，切换播放源 / 重建控制器需显式 [reset]。
class PlayerCompletionEngine {
  bool _reported = false;

  /// 提交一帧状态，返回**本次是否应触发播完回调**
  bool shouldReport({
    required bool isInitialized,
    required bool isCompleted,
    required Duration position,
    required Duration duration,
  }) {
    final completed = isInitialized &&
        (isCompleted ||
            (duration > Duration.zero && position >= duration));

    // 回到未播完 → 释放闩锁，允许下一轮播完再次上报
    if (!completed) {
      _reported = false;
      return false;
    }

    if (_reported) return false;
    _reported = true;
    return true;
  }

  /// 切换播放源 / 重建控制器后清空闩锁（新一轮播放与上一轮无关）
  void reset() => _reported = false;
}
