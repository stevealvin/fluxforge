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
    // 快进 = 翡翠绿，快退 = 琥珀金（与 WebView 端 HUD 配色保持一致）
    final accentColor =
        isForward ? const Color(0xFF10B981) : const Color(0xFFF59E0B);

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              // 取消外围边框线，进一步提升半透明通透感 (alpha: 0.45)
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：方向圆角图标 + 快进/快退秒数
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isForward
                          ? Ionicons.playForwardOutline
                          : Ionicons.playBackOutline,
                      color: accentColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${isForward ? '+' : ''}${deltaSeconds}s',
                      style: TextStyle(
                        color: accentColor,
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

/// 长按瞬时加速顶部微胶囊（纯净无文字版，仅展示高斯毛玻璃翡翠快进图标，视线无遮挡）
class PlayerFastForwardCapsule extends StatelessWidget {
  const PlayerFastForwardCapsule({super.key});

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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.black.withValues(alpha: 0.55),
              child: const Icon(
                Ionicons.playForwardOutline,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
