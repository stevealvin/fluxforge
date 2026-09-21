import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueGetter, ValueListenable;
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

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
        child: AppLoading(message: '流媒体资源极速载入中...'),
      ),
    );
  }
}

/// 控制条显隐动画：微位移与淡出同步播放，曲线统一自然
/// 仅供同文件内的迷你进度条使用，故不对外暴露
class _PlayerAnimatedBar extends StatelessWidget {
  const _PlayerAnimatedBar({
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
            child: _PlayerAnimatedBar(
              visible: showControls,
              slideOffset: const Offset(0, -0.5),
              child: topBar!,
            ),
          ),

        // 底部控制条：隐藏时向下轻滑并淡出
        Align(
          alignment: Alignment.bottomCenter,
          child: _PlayerAnimatedBar(
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
    required this.positionTick,
    required this.currentPosition,
    required this.totalMilliseconds,
  });

  /// 控制条收起时才显示（收起时无缝淡入）
  final bool visible;

  /// 位置刷新心跳：播放 / 滑动寻道 / 拖拽进度条时进度实时跟手，且不触发整树重建
  final ValueListenable<int> positionTick;

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
            valueListenable: positionTick,
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

/// 全屏浮动锁屏按钮
///
/// 外层为 [Positioned]，需置于 `Stack` 内使用；垂直居中，左边缘与底栏进度条对齐。
/// 「是否参与渲染」（仅全屏）与「当前是否应显示」由调用方决定后传入（见上层守卫），
/// 组件内部只负责 240ms 淡出 + 缩放动画与点击回调。
class PlayerLockButton extends StatelessWidget {
  const PlayerLockButton({
    super.key,
    required this.visible,
    required this.isLocked,
    required this.left,
    required this.onToggle,
  });

  /// 当前是否应显示（未锁定态跟随控制栏、锁定态由锁图标独立计时器决定）
  final bool visible;

  /// 是否已上锁（决定展示闭合 / 开启两种锁图标）
  final bool isLocked;

  /// 与底栏进度条对齐的左边缘基准位置
  final double left;

  /// 切换锁定 / 解锁
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      top: 0,
      bottom: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: visible ? 1.0 : 0.82,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.centerLeft, // 图标左边缘与基准线严格同轴对齐
                  child: Icon(
                    isLocked ? Ionicons.lockClosedOutline : Ionicons.lockOpenOutline,
                    color: Colors.white, // 关闭锁定状态去掉颜色，保持纯白通透质感
                    size: 24,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
