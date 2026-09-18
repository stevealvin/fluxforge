import 'package:flutter/services.dart' show HapticFeedback;
import 'package:material_ui/material_ui.dart';

/// 播放 / 暂停按钮
///
/// 全屏下内容靠左紧贴（与进度条左边缘像素级对齐），非全屏用标准 `IconButton`。
/// 触感反馈内聚在此：点击即震，调用方只关心"切换播放状态"这件事。
class PlayerPlayPauseButton extends StatelessWidget {
  const PlayerPlayPauseButton({
    super.key,
    required this.isPlaying,
    required this.isFullScreen,
    required this.onTap,
    this.compact = false,
  });

  final bool isPlaying;
  final bool isFullScreen;
  final VoidCallback onTap;
  final bool compact;

  void _handleTap() {
    HapticFeedback.lightImpact();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    // 现代流媒体标准圆润实心矢量图标（紧凑 25，常规/全屏 28）
    final icon = Icon(
      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      color: Colors.white,
      size: compact ? 25 : 28,
    );

    if (isFullScreen) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Container(
          width: 42,
          height: 42,
          alignment: Alignment.centerLeft,
          child: icon,
        ),
      );
    }

    return IconButton(
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 34 : 42,
        height: compact ? 34 : 42,
      ),
      onPressed: _handleTap,
    );
  }
}

/// 倍速选择按钮（纯净无背景无边框悬浮字，带微立体文字投影）
class PlayerSpeedButton extends StatelessWidget {
  const PlayerSpeedButton({
    super.key,
    required this.playbackSpeed,
    required this.onTap,
  });

  final double playbackSpeed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // 1.0x 正常速度时直接显示“倍速”，非 1.0x 时显示当前倍率 (如 1.5x / 2x)
    final speedText = playbackSpeed == 1.0
        ? '倍速'
        : (playbackSpeed % 1 == 0
            ? '${playbackSpeed.toInt()}x'
            : '${playbackSpeed}x');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          speedText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black87,
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 全屏 / 退出全屏按钮
///
/// 全屏下内容靠右紧贴（与进度条右边缘像素级对齐），非全屏用标准 `IconButton`。
class PlayerFullscreenButton extends StatelessWidget {
  const PlayerFullscreenButton({
    super.key,
    required this.isFullScreen,
    required this.onTap,
    this.compact = false,
  });

  final bool isFullScreen;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // 现代流媒体标准圆角全屏切换图标，四角圆润规整
    final icon = Icon(
      isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      color: Colors.white,
      size: compact ? 22 : 24,
    );

    if (isFullScreen) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.centerRight,
          child: icon,
        ),
      );
    }

    return IconButton(
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 32 : 38,
        height: compact ? 32 : 38,
      ),
      onPressed: onTap,
    );
  }
}
