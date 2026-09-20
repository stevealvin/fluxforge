import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/player/player_track_shape.dart';

/// 极光翡翠流光进度条（缓冲进度 + 加载扫光 + 拖拽阻尼）
///
/// 纯展示：进度比例 / 缓冲态 / 拖拽态由上层算好传入，本组件不读控制器；
/// 拖拽只上抛「值变化」与「落点」，扫光动画在组件内部订阅。
class PlayerProgressSlider extends StatelessWidget {
  const PlayerProgressSlider({
    super.key,
    required this.progressRatio,
    required this.bufferedFraction,
    required this.isBuffering,
    required this.isDragging,
    required this.compact,
    required this.shimmerAnimation,
    required this.onChanged,
    required this.onChangeEnd,
  });

  /// 播放进度比例（0.0 ~ 1.0）
  final double progressRatio;

  /// 已缓冲比例（0.0 ~ 1.0）
  final double bufferedFraction;

  /// 是否处于缓冲 / 未就绪（驱动轨道流光扫光）
  final bool isBuffering;

  /// 是否正在拖拽（缩略块放大反馈）
  final bool isDragging;

  /// 紧凑尺寸（小屏控制栏用；全屏用宽版）
  final bool compact;

  /// 扫光动画（仅缓冲期间运行，见上层 `_syncShimmerTicker`）
  final Animation<double> shimmerAnimation;

  /// 拖拽过程中值变化（含拖拽起点）
  final ValueChanged<double> onChanged;

  /// 拖拽结束落点（上层据此 seek）
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: shimmerAnimation,
      builder: (context, child) {
        return SizedBox(
          height: compact ? 18 : 22,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: AuraSliderTrackShape(
                bufferedFraction: bufferedFraction,
                isBuffering: isBuffering,
                shimmerProgress: shimmerAnimation.value,
              ),
              trackHeight: compact ? 2.5 : 3.5,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: isDragging
                    ? (compact ? 6.0 : 7.0)
                    : (compact ? 4.5 : 5.5),
              ),
              overlayShape: RoundSliderOverlayShape(overlayRadius: compact ? 10 : 12),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
            ),
            child: Slider(
              value: progressRatio,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        );
      },
    );
  }
}
