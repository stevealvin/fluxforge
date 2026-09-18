import 'dart:ui' show ImageFilter;

import 'package:flutter/services.dart' show HapticFeedback;
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/player/player_preferences.dart';
import 'package:fluxforge/shared/widgets/player/player_settings_panel.dart';

/// 可选播放倍速档位（从快到慢）
const List<double> kPlayerSpeedOptions = [2.0, 1.5, 1.25, 1.0, 0.75, 0.5];

/// 从右侧滑出「播放倍速」抽屉
///
/// 命令式弹出：内部自带右滑入场动画、毛玻璃背景与倍速列表；
/// 选中某一档后先回调 [onSpeedSelected]，再自动关闭抽屉。
///
/// 做成函数而非 Widget 的原因：它本就是 `showGeneralDialog` 的封装，
/// 调用方只需关心"要选倍速"，不必再持有一份抽屉 UI 的构造代码。
Future<void> showPlayerSpeedDrawer({
  required BuildContext context,
  required double currentSpeed,
  required ValueChanged<double> onSpeedSelected,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'SpeedDrawer',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (dialogContext, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 210,
              height: double.infinity,
              color: Colors.black.withValues(alpha: 0.52),
              child: SafeArea(
                left: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '播放倍速',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pop(dialogContext),
                            child: const Icon(
                              Ionicons.closeOutline,
                              color: Colors.white60,
                              size: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: kPlayerSpeedOptions.length,
                        itemBuilder: (context, index) {
                          final speed = kPlayerSpeedOptions[index];
                          return PlayerSpeedOptionTile(
                            speed: speed,
                            isSelected: (currentSpeed - speed).abs() < 0.01,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              onSpeedSelected(speed);
                              Navigator.pop(dialogContext);
                            },
                          );
                        },
                      ),
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

/// 倍速抽屉中的单个档位选项
class PlayerSpeedOptionTile extends StatelessWidget {
  const PlayerSpeedOptionTile({
    super.key,
    required this.speed,
    required this.isSelected,
    required this.onTap,
  });

  final double speed;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = speed == 1.0 ? '1.0x (正常)' : '${speed}x';

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? AppColors.primary : Colors.white,
              ),
            ),
            if (isSelected)
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.6),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 从右侧滑出「播放设置」抽屉
///
/// 抽屉内容由 [PlayerMoreSettingsPanelBody] 承载（含局部回显状态），
/// 此处只负责弹出外壳：右滑入场动画 + 毛玻璃背景 + 遮罩。
///
/// 原先散在页面里的 `setDrawerState` 局部刷新已收进面板自身的 `State`，
/// 因此这里对外只暴露语义化回调，不泄漏任何 UI 刷新细节。
Future<void> showPlayerMoreSettingsDrawer({
  required BuildContext context,
  required bool isMirrored,
  required bool isLooping,
  required BoxFit videoFit,
  required PlayerPreferences preferences,
  required ValueChanged<bool> onMirroredChanged,
  required ValueChanged<bool> onLoopingChanged,
  required ValueChanged<BoxFit> onVideoFitChanged,
  required ValueChanged<PlayerPreferences>? onPreferencesChanged,
}) async {
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'MoreSettingsDrawer',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 240),
    transitionBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween<Offset>(begin: const Offset(1.0, 0.0), end: Offset.zero)
          .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
    pageBuilder: (dialogContext, _, _) => Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: ClipRRect(
          borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: 280,
              height: double.infinity,
              color: Colors.black.withValues(alpha: 0.55),
              child: SafeArea(
                left: false,
                child: PlayerMoreSettingsPanelBody(
                  isMirrored: isMirrored,
                  isLooping: isLooping,
                  videoFit: videoFit,
                  preferences: preferences,
                  onMirroredChanged: onMirroredChanged,
                  onLoopingChanged: onLoopingChanged,
                  onVideoFitChanged: onVideoFitChanged,
                  onPreferencesChanged: onPreferencesChanged,
                  onClose: () => Navigator.pop(dialogContext),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
