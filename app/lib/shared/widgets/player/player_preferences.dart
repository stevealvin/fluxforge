/// 播放器偏好（纯值对象，零业务依赖）
///
/// 设计意图：让 `AuraPlayer` 成为一个**可以放进 `shared/` 的通用组件** ——
/// 它不再直接读写全局设置仓储（`appService.settings`），而是由宿主通过参数注入偏好、
/// 通过回调回写变更。这样播放器层与设置存储层彻底解耦，可被任意业务场景复用。
class PlayerPreferences {
  const PlayerPreferences({
    this.longPressBoostEnabled = true,
    this.longPressSpeed = 2.0,
  });

  /// 长按屏幕瞬时加速是否启用
  final bool longPressBoostEnabled;

  /// 长按瞬时加速倍率（2.0 / 3.0 / 5.0）
  final double longPressSpeed;

  PlayerPreferences copyWith({
    bool? longPressBoostEnabled,
    double? longPressSpeed,
  }) {
    return PlayerPreferences(
      longPressBoostEnabled: longPressBoostEnabled ?? this.longPressBoostEnabled,
      longPressSpeed: longPressSpeed ?? this.longPressSpeed,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PlayerPreferences &&
        other.longPressBoostEnabled == longPressBoostEnabled &&
        other.longPressSpeed == longPressSpeed;
  }

  @override
  int get hashCode => Object.hash(longPressBoostEnabled, longPressSpeed);
}
