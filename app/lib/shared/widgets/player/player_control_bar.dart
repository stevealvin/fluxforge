import 'package:flutter/foundation.dart' show ValueGetter, ValueListenable;
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/shared/widgets/player/player_control_buttons.dart';

/// 进度条构建器：由上层注入
///
/// 进度条需要缓冲比例、拖拽阻尼状态、seek 回调等播放器内部细节，
/// 交给上层装配比把十余个参数塞进控制栏更清晰 —— 控制栏只负责它在两种布局中的位置。
typedef PlayerProgressSliderBuilder = Widget Function({required bool compact});

/// 播放器控制栏
///
/// 全屏用宽版布局（时间组合 + 全宽进度条 + 三键行），小屏用紧凑布局（单行居中）；
/// 两者复用同一套控件，差异仅在排布。
class PlayerControlBar extends StatelessWidget {
  const PlayerControlBar({
    super.key,
    required this.isFullScreen,
    required this.padding,
    required this.isPlaying,
    required this.currentPosition,
    required this.duration,
    required this.playbackSpeed,
    required this.seekPreviewTick,
    required this.formatDuration,
    required this.progressSlider,
    required this.onTogglePlay,
    required this.onOpenSpeedDrawer,
    required this.onToggleFullScreen,
  });

  final bool isFullScreen;

  /// 已算好的内边距（含全屏避让与安全区处理，由上层按 MediaQuery 计算）
  final EdgeInsets padding;

  final bool isPlaying;

  /// 用 getter 而非值：时间文本要在手势预览的局部重建中拿到**最新**进度
  final ValueGetter<Duration> currentPosition;

  final Duration duration;
  final double playbackSpeed;

  /// 手势预览刷新信号（滑动寻道时时间文本与进度条同步跟手）
  final ValueListenable<int> seekPreviewTick;

  final String Function(Duration) formatDuration;
  final PlayerProgressSliderBuilder progressSlider;

  final VoidCallback onTogglePlay;
  final VoidCallback onOpenSpeedDrawer;
  final VoidCallback onToggleFullScreen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: padding,
      child: isFullScreen ? _buildWideLayout() : _buildCompactLayout(),
    );
  }

  /// 全屏商业级布局：
  /// - 顶行：左上方显示「当前进度 / 总进度」时间组合文本（05:23 / 45:10）；
  /// - 中行：全宽拉通进度条；
  /// - 底行：播放/暂停键、倍速选择、退出全屏按键（紧凑排布）。
  Widget _buildWideLayout() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            ValueListenableBuilder<int>(
              valueListenable: seekPreviewTick,
              builder: (context, _, _) =>
                  _timeText(formatDuration(currentPosition()), primary: true),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '/',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            _timeText(formatDuration(duration)),
          ],
        ),
        const SizedBox(height: 2),

        // 进度条：标准紧凑高度流式嵌入，无 Offset 偏移
        progressSlider(compact: false),
        const SizedBox(height: 2),

        // 控制按键行
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            PlayerPlayPauseButton(
              isPlaying: isPlaying,
              isFullScreen: isFullScreen,
              onTap: onTogglePlay,
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PlayerSpeedButton(
                  playbackSpeed: playbackSpeed,
                  onTap: onOpenSpeedDrawer,
                ),
                const SizedBox(width: 10),
                PlayerFullscreenButton(
                  isFullScreen: isFullScreen,
                  onTap: onToggleFullScreen,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// 小屏紧凑布局：播放、进度条、时间、全屏全部居中对齐在同一条水平中线上
  /// （移除倍速按键，留白更舒展）
  Widget _buildCompactLayout() {
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PlayerPlayPauseButton(
            isPlaying: isPlaying,
            isFullScreen: isFullScreen,
            compact: true,
            onTap: onTogglePlay,
          ),
          Expanded(child: progressSlider(compact: true)),
          const SizedBox(width: 6),
          // 小屏空间紧凑，起止时间合并为「当前/总长」等宽数字单段文本
          ValueListenableBuilder<int>(
            valueListenable: seekPreviewTick,
            builder: (context, _, _) => _timeText(
              '${formatDuration(currentPosition())}/${formatDuration(duration)}',
              primary: true,
              compact: true,
            ),
          ),
          const SizedBox(width: 4),
          PlayerFullscreenButton(
            isFullScreen: isFullScreen,
            compact: true,
            onTap: onToggleFullScreen,
          ),
        ],
      ),
    );
  }

  /// 等宽数字时间文本 (tabularFigures 保证秒数变化时宽度不抖动)
  Widget _timeText(String text, {bool primary = false, bool compact = false}) {
    return Text(
      text,
      style: TextStyle(
        color: primary ? Colors.white : Colors.white70,
        fontSize: compact ? 10 : 11,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }
}
