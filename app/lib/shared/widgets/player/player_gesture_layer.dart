import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/shared/widgets/player/player_gesture_engine.dart';

/// 播放器手势交互层（未锁定）
///
/// 只负责**手势接线与归一化换算**：把 `LayoutBuilder` 拿到的真实宽高换算成比例后
/// 交给语义化回调，页面侧只表达"手势意味着什么状态变化"。
///
/// 分区判定（左亮度 / 右音量）与快进快退算法见 [PlayerGestureEngine]，
/// 因此本组件不持有任何播放状态，也不依赖 `video_player`。
class PlayerGestureLayer extends StatelessWidget {
  const PlayerGestureLayer({
    super.key,
    required this.onTap,
    required this.onDoubleTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onHorizontalDragStart,
    required this.onHorizontalDragUpdate,
    required this.onHorizontalDragEnd,
  });

  /// 单击：显隐控制栏
  final VoidCallback onTap;

  /// 双击：暂停 / 播放
  final VoidCallback onDoubleTap;

  /// 长按：瞬时加速
  final VoidCallback onLongPressStart;

  /// 长按结束：恢复原速
  final VoidCallback onLongPressEnd;

  final VoidCallback onVerticalDragStart;

  /// 垂直滑动：已判定好的调节区域 + 归一化增量（向上滑动为正）
  final void Function(PlayerGestureZone zone, double deltaRatio) onVerticalDragUpdate;

  final VoidCallback onHorizontalDragStart;

  /// 水平滑动：归一化增量（向右滑动为正）
  final ValueChanged<double> onHorizontalDragUpdate;

  /// 水平滑动结束：执行真正的 seek
  final VoidCallback onHorizontalDragEnd;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onLongPressStart: (_) => onLongPressStart(),
          onLongPressEnd: (_) => onLongPressEnd(),
          onVerticalDragStart: (_) => onVerticalDragStart(),
          onVerticalDragUpdate: (details) => onVerticalDragUpdate(
            PlayerGestureEngine.zoneOf(
              localX: details.localPosition.dx,
              totalWidth: totalWidth,
            ),
            // 向上滑动为正；未完成布局时按 0 处理，避免除零产生 NaN 污染状态
            totalHeight <= 0 ? 0.0 : -details.primaryDelta! / totalHeight,
          ),
          onHorizontalDragStart: (_) => onHorizontalDragStart(),
          onHorizontalDragUpdate: (details) => onHorizontalDragUpdate(
            totalWidth <= 0 ? 0.0 : details.primaryDelta! / totalWidth,
          ),
          onHorizontalDragEnd: (_) => onHorizontalDragEnd(),
          child: const SizedBox.expand(),
        );
      },
    );
  }
}

/// 锁定状态下的极简防误触手势层
///
/// 仅捕获屏幕单击以唤醒 / 切换锁图标显隐，**完全拦截**滑动、双击、长按等误触。
class PlayerLockedGestureLayer extends StatelessWidget {
  const PlayerLockedGestureLayer({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: const SizedBox.expand(),
    );
  }
}
