import 'dart:async';

import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/shared/widgets/player/player_capsules.dart';

/// 手势浮层：亮度 / 音量的数值反馈层（**自带状态**）
///
/// 原先这组状态（两个值 + 两个可见性 + 两个定时器 + 变暗遮罩）散在
/// `AuraPlayerState` 里，浮层每次显隐都要 `setState` 重建整棵播放器树。
/// 这里整组收拢，并把职责切成两半：
///
/// - **宿主保留**「改变外部世界」的那半：把音量写进播放器控制器、持久化偏好；
/// - **本层负责**「显示什么」：数值、可见性、定时自动隐藏、变暗遮罩、三态音量图标。
///
/// 调用方通过 `GlobalKey<PlayerGestureFeedbackLayerState>` 推入数值
/// （[showBrightness] / [showVolume]），因此**拖动的逐帧更新既不触发本层的整树重建，
/// 也不再触达宿主页面**：首次显示是结构变化（本层内建树一次），此后逐帧只递增内部心跳。
class PlayerGestureFeedbackLayer extends StatefulWidget {
  const PlayerGestureFeedbackLayer({
    super.key,
    required this.isFullScreen,
  });

  /// 浮层自动隐藏延时（每次数值更新都会重新计时）
  static const Duration hideDelay = Duration(seconds: 1);

  /// 全屏时左侧胶囊需避让控制区，偏移更大
  final bool isFullScreen;

  @override
  State<PlayerGestureFeedbackLayer> createState() =>
      PlayerGestureFeedbackLayerState();
}

/// 公开 State：宿主通过 `GlobalKey<PlayerGestureFeedbackLayerState>` 推送数值
class PlayerGestureFeedbackLayerState extends State<PlayerGestureFeedbackLayer> {
  /// 浮层内部刷新心跳（数值变化时递增，只有浮层自身重建）
  final ValueNotifier<int> _tick = ValueNotifier<int>(0);

  double _brightness = 1.0;
  bool _showBrightness = false;
  Timer? _brightnessTimer;

  double _volume = 1.0;
  bool _showVolume = false;
  Timer? _volumeTimer;

  /// 显示亮度反馈（数值由宿主计算后推入）
  void showBrightness(double value) {
    _brightness = value;
    if (!_showBrightness) {
      setState(() => _showBrightness = true);
    } else {
      _tick.value++;
    }
    _brightnessTimer?.cancel();
    _brightnessTimer = Timer(
      PlayerGestureFeedbackLayer.hideDelay,
      () {
        if (mounted) setState(() => _showBrightness = false);
      },
    );
  }

  /// 显示音量反馈（数值由宿主计算后推入）
  void showVolume(double value) {
    _volume = value;
    if (!_showVolume) {
      setState(() => _showVolume = true);
    } else {
      _tick.value++;
    }
    _volumeTimer?.cancel();
    _volumeTimer = Timer(
      PlayerGestureFeedbackLayer.hideDelay,
      () {
        if (mounted) setState(() => _showVolume = false);
      },
    );
  }

  @override
  void dispose() {
    _brightnessTimer?.cancel();
    _volumeTimer?.cancel();
    _tick.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // 1. 应用内微调暗度遮罩（无权限亮度调节：按当前亮度压暗画面）
        IgnorePointer(
          child: ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (context, _, _) => Container(
              color: Colors.black.withValues(alpha: (1.0 - _brightness) * 0.75),
            ),
          ),
        ),

        // 2. 左侧亮度胶囊（全屏下避让左侧控制区）
        if (_showBrightness)
          ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (context, _, _) => PlayerVerticalIndicatorCapsule(
              side: PlayerCapsuleSide.left,
              offset: widget.isFullScreen ? 68 : 16,
              icon: Ionicons.sunnyOutline,
              value: _brightness,
            ),
          ),

        // 3. 右侧音量胶囊（静音 / 低音量 / 高音量三态图标）
        if (_showVolume)
          ValueListenableBuilder<int>(
            valueListenable: _tick,
            builder: (context, _, _) => PlayerVerticalIndicatorCapsule(
              side: PlayerCapsuleSide.right,
              offset: 20,
              icon: _volume == 0
                  ? Ionicons.volumeMuteOutline
                  : (_volume > 0.5
                      ? Ionicons.volumeHighOutline
                      : Ionicons.volumeLowOutline),
              value: _volume,
            ),
          ),
      ],
    );
  }
}
