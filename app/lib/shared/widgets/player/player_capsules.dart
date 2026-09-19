import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';

/// 垂直指示胶囊所在的一侧
enum PlayerCapsuleSide { left, right }

/// 垂直指示胶囊（亮度 / 音量共用一套外观）
///
/// 两者结构完全一致，仅「图标、数值、贴边方向、水平偏移」不同：
/// 亮度贴左（全屏下避让左侧控制区因而偏移更大），音量贴右。
///
/// 注：图标由调用方按业务语义算好后传入（如音量为 0 时的静音图标），
/// 组件本身不感知音量 / 亮度的取值规则。
class PlayerVerticalIndicatorCapsule extends StatelessWidget {
  const PlayerVerticalIndicatorCapsule({
    super.key,
    required this.icon,
    required this.value,
    required this.side,
    required this.offset,
  });

  final IconData icon;

  /// 0.0 ~ 1.0，同时用于竖条长度与百分比文案
  final double value;

  final PlayerCapsuleSide side;

  /// 贴边距离
  final double offset;

  @override
  Widget build(BuildContext context) {
    final body = Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            width: 38,
            height: 140,
            padding: const EdgeInsets.symmetric(vertical: 12),
            color: Colors.black.withValues(alpha: 0.65),
            child: Column(
              children: [
                Icon(icon, color: Colors.white, size: 18),
                const Spacer(),
                Expanded(
                  flex: 6,
                  child: RotatedBox(
                    quarterTurns: -1,
                    child: LinearProgressIndicator(
                      value: value,
                      backgroundColor: Colors.white24,
                      valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${(value * 100).round()}%',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return side == PlayerCapsuleSide.left
        ? Positioned(left: offset, top: 0, bottom: 0, child: body)
        : Positioned(right: offset, top: 0, bottom: 0, child: body);
  }
}

/// 居中微拟态快进/快退胶囊（双行紧凑布局：上行方向+秒数，下行时间进度，主次分明）
class PlayerSeekingCapsule extends StatelessWidget {
  const PlayerSeekingCapsule({
    super.key,
    required this.deltaSeconds,
    required this.targetLabel,
  });

  /// 相对起点的偏移秒数：正数为快进、负数为快退
  final int deltaSeconds;

  /// 已格式化的「目标时间 / 视频总时长」
  final String targetLabel;

  @override
  Widget build(BuildContext context) {
    final isForward = deltaSeconds >= 0;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              // 取消外围边框线，进一步提升半透明通透感
              color: Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：方向圆角图标 + 快进/快退秒数（统一纯白）
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isForward
                          ? Ionicons.playForwardOutline
                          : Ionicons.playBackOutline,
                      color: Colors.white,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${isForward ? '+' : ''}${deltaSeconds}s',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // 第二行：目标时间 / 视频总时长
                Text(
                  targetLabel,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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

/// 长按瞬时加速顶部微胶囊（高斯毛玻璃翡翠快进图标 + 当前倍数）
class PlayerFastForwardCapsule extends StatelessWidget {
  const PlayerFastForwardCapsule({super.key, required this.speed});

  /// 长按瞬时加速倍率（如 2.0 / 3.0 / 5.0，展示为 2x / 3x / 5x）
  final double speed;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 48,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.black.withValues(alpha: 0.42),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Ionicons.playForwardOutline,
                    color: Colors.white,
                    size: 20,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '${_formatSpeed(speed)}X',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 倍数文案：整数倍不带小数点（2X），非整数保留一位（2.5X）
  static String _formatSpeed(double speed) {
    if (speed % 1 == 0) return speed.toInt().toString();
    return speed.toStringAsFixed(1);
  }
}
