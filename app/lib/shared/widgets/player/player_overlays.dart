import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueGetter, ValueListenable;
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 长按加速倍率选择胶囊
///
/// 注意：返回的是 [Expanded]，需直接置于 `Row` 中作为子项使用
/// （原实现如此，以保证多个档位等宽平分）。
class PlayerSpeedChip extends StatelessWidget {
  const PlayerSpeedChip({
    super.key,
    required this.speed,
    required this.isSelected,
    required this.onTap,
  });

  /// 长按加速倍率（如 2.0 / 3.0）
  final double speed;

  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '${speed.toInt()}x 快进',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

/// 加载中 / 错误状态指示层
///
/// 失败态给出可操作的「重试播放」入口，加载态仅展示极简载入提示，
/// 两者共用同一层遮罩，避免播放器与覆盖层之间出现状态空窗。
class PlayerStateOverlay extends StatelessWidget {
  const PlayerStateOverlay({
    super.key,
    required this.hasError,
    required this.errorMessage,
    required this.onRetry,
  });

  final bool hasError;

  /// 失败原因（仅在 [hasError] 为 true 时展示）
  final String errorMessage;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Ionicons.warningOutline, color: Colors.amber, size: 36),
              const SizedBox(height: 12),
              Text(
                errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: onRetry,
                icon: const Icon(Ionicons.refreshOutline, size: 16),
                label: const Text('重试播放'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black54,
      child: const Center(
        child: LoadingIndicator(message: '流媒体资源极速载入中...'),
      ),
    );
  }
}

/// 播放设置抽屉中的单行开关
///
/// 纯展示 + 回调上抛：开关自身不持有状态，取消 / 选中的判定与持久化由调用方处理。
class PlayerSettingSwitchRow extends StatelessWidget {
  const PlayerSettingSwitchRow({
    super.key,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.78,
            child: Switch(
              value: value,
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.35),
              inactiveThumbColor: Colors.white60,
              inactiveTrackColor: Colors.white12,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// 播放设置抽屉中的画面比例胶囊
///
/// 注意：与原实现一致，返回 [Expanded]，需直接置于 `Row` 中作为子项使用。
class PlayerFitChip extends StatelessWidget {
  const PlayerFitChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.primary
                : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }
}

/// 控制条显隐动画：微位移与淡出同步播放，曲线统一自然
class PlayerAnimatedBar extends StatelessWidget {
  const PlayerAnimatedBar({
    super.key,
    required this.visible,
    required this.slideOffset,
    required this.child,
  });

  /// 是否展开（收起时同时淡出并位移，且不拦截点击）
  final bool visible;

  /// 收起时的位移方向：顶栏 `(0, -0.5)`、底栏 `(0, 0.5)`
  final Offset slideOffset;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        offset: visible ? Offset.zero : slideOffset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }
}

/// 控制层浮层：承载顶部 / 底部两条控制栏的显隐动画
class PlayerControlOverlays extends StatelessWidget {
  const PlayerControlOverlays({
    super.key,
    required this.showControls,
    required this.topBar,
    required this.bottomBar,
  });

  final bool showControls;

  /// 顶部控制条；为 null 表示本条不参与渲染（非全屏且无返回回调与扩展操作时）
  final Widget? topBar;

  final Widget bottomBar;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 顶部控制条：隐藏时向上轻滑并淡出
        if (topBar != null)
          Align(
            alignment: Alignment.topCenter,
            child: PlayerAnimatedBar(
              visible: showControls,
              slideOffset: const Offset(0, -0.5),
              child: topBar!,
            ),
          ),

        // 底部控制条：隐藏时向下轻滑并淡出
        Align(
          alignment: Alignment.bottomCenter,
          child: PlayerAnimatedBar(
            visible: showControls,
            slideOffset: const Offset(0, 0.5),
            child: bottomBar,
          ),
        ),
      ],
    );
  }
}

/// 小屏控制条隐藏时的常驻微型极光进度条（高度 2px）
///
/// 外层为 [Positioned]，需置于 `Stack` 内使用；
/// 是否渲染由调用方按"全屏 / 未初始化 / 播放错误"等状态决定（见上层守卫）。
class PlayerBottomMiniProgress extends StatelessWidget {
  const PlayerBottomMiniProgress({
    super.key,
    required this.visible,
    required this.seekPreviewTick,
    required this.currentPosition,
    required this.totalMilliseconds,
  });

  /// 控制条收起时才显示（收起时无缝淡入）
  final bool visible;

  /// 手势预览信号：滑动寻道时进度实时跟手，且不触发整树重建
  final ValueListenable<int> seekPreviewTick;

  /// 用 getter 而非值，保证局部重建时拿到最新进度
  final ValueGetter<Duration> currentPosition;

  final int totalMilliseconds;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: ValueListenableBuilder<int>(
            valueListenable: seekPreviewTick,
            builder: (context, _, _) {
              final progressRatio = totalMilliseconds > 0
                  ? (currentPosition().inMilliseconds / totalMilliseconds)
                      .clamp(0.0, 1.0)
                  : 0.0;
              return LinearProgressIndicator(
                value: progressRatio,
                minHeight: 2.0,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// 断点续播提醒气泡
///
/// 外层为 [Positioned]，需置于 `Stack` 内使用。
/// 「上次看到 X」的文案与两个动作（跳转继续 / 关闭）由调用方通过回调接入。
class PlayerResumeTip extends StatelessWidget {
  const PlayerResumeTip({
    super.key,
    required this.formattedPosition,
    required this.onContinue,
    required this.onDismiss,
  });

  /// 已格式化的上次播放位置（如 `01:23:45`）
  final String formattedPosition;

  /// 跳转到上次位置
  final VoidCallback onContinue;

  /// 关闭提示
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 72,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.black.withValues(alpha: 0.75),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '上次看到 $formattedPosition',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: onContinue,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '跳转继续',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: onDismiss,
                  child: const Icon(
                    Ionicons.closeOutline,
                    color: Colors.white54,
                    size: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
