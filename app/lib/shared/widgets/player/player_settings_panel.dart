import 'package:flutter/services.dart' show HapticFeedback;
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/player/player_preferences.dart';

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
            '${speed.toInt()}X 快进',
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

/// 播放设置抽屉的内容体
///
/// 持有各设置的**展示副本**：改动后先更新自身（立即回显），再上抛回调。
/// 这样页面就不必再把 `setDrawerState` 这类局部刷新细节穿进业务逻辑 ——
/// 抽屉是模态的，页面状态不会被外部改动，因此无需双向同步。
class PlayerMoreSettingsPanelBody extends StatefulWidget {
  const PlayerMoreSettingsPanelBody({
    super.key,
    required this.isMirrored,
    required this.isLooping,
    required this.videoFit,
    required this.preferences,
    required this.onMirroredChanged,
    required this.onLoopingChanged,
    required this.onVideoFitChanged,
    required this.onPreferencesChanged,
    required this.onClose,
  });

  final bool isMirrored;
  final bool isLooping;
  final BoxFit videoFit;
  final PlayerPreferences preferences;
  final ValueChanged<bool> onMirroredChanged;
  final ValueChanged<bool> onLoopingChanged;
  final ValueChanged<BoxFit> onVideoFitChanged;
  final ValueChanged<PlayerPreferences>? onPreferencesChanged;

  /// 关闭抽屉（由弹出方注入 `Navigator.pop`）
  final VoidCallback onClose;

  @override
  State<PlayerMoreSettingsPanelBody> createState() =>
      _PlayerMoreSettingsPanelBodyState();
}

class _PlayerMoreSettingsPanelBodyState
    extends State<PlayerMoreSettingsPanelBody> {
  late bool _isMirrored = widget.isMirrored;
  late bool _isLooping = widget.isLooping;
  late BoxFit _videoFit = widget.videoFit;
  late PlayerPreferences _preferences = widget.preferences;

  /// 局部回显 + 上抛（带触感反馈）
  ///
  /// `setState` 是同步的，因此先更新自身再上抛，回调方能拿到最新值。
  void _apply(VoidCallback localUpdate, VoidCallback notify) {
    HapticFeedback.lightImpact();
    setState(localUpdate);
    notify();
  }

  /// 偏好类改动的统一入口（先用 `copyWith` 算出新值，避免重复构造）
  void _applyPreferences(PlayerPreferences next) {
    HapticFeedback.lightImpact();
    setState(() => _preferences = next);
    widget.onPreferencesChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部标题栏
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 16, 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '播放设置',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              GestureDetector(
                onTap: widget.onClose,
                child: const Icon(
                  Ionicons.closeOutline,
                  color: Colors.white60,
                  size: 20,
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),

        // 设置列表项滚动区
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            children: [
              // 1. 画面比例
              const _PanelSectionTitle('画面比例'),
              const SizedBox(height: 10),
              Row(
                children: [
                  PlayerFitChip(
                    label: '适应',
                    isSelected: _videoFit == BoxFit.contain,
                    onTap: () => _apply(
                      () => _videoFit = BoxFit.contain,
                      () => widget.onVideoFitChanged(BoxFit.contain),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PlayerFitChip(
                    label: '铺满',
                    isSelected: _videoFit == BoxFit.cover,
                    onTap: () => _apply(
                      () => _videoFit = BoxFit.cover,
                      () => widget.onVideoFitChanged(BoxFit.cover),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PlayerFitChip(
                    label: '拉伸',
                    isSelected: _videoFit == BoxFit.fill,
                    onTap: () => _apply(
                      () => _videoFit = BoxFit.fill,
                      () => widget.onVideoFitChanged(BoxFit.fill),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              const SizedBox(height: 16),

              // 2. 画面视效与播放循环
              const _PanelSectionTitle('播放视效与控制'),
              const SizedBox(height: 8),

              // 镜像翻转开关 (舞蹈/跟练神器)
              PlayerSettingSwitchRow(
                title: '画面水平镜像',
                subtitle: '适合舞蹈、跟练与教程视频左右镜像观看',
                value: _isMirrored,
                onChanged: (val) => _apply(
                  () => _isMirrored = val,
                  () => widget.onMirroredChanged(val),
                ),
              ),

              // 循环播放开关
              PlayerSettingSwitchRow(
                title: '单视频循环播放',
                subtitle: '播放结束时自动从头接力播放',
                value: _isLooping,
                onChanged: (val) => _apply(
                  () => _isLooping = val,
                  () => widget.onLoopingChanged(val),
                ),
              ),

              const SizedBox(height: 14),
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
              const SizedBox(height: 16),

              // 3. 长按瞬时加速
              const _PanelSectionTitle('长按加速配置'),
              const SizedBox(height: 8),
              PlayerSettingSwitchRow(
                title: '长按瞬时快进',
                subtitle: '长按画面任意处即可按设定倍速快速播放',
                value: _preferences.longPressBoostEnabled,
                onChanged: (val) => _applyPreferences(
                  _preferences.copyWith(longPressBoostEnabled: val),
                ),
              ),
              if (_preferences.longPressBoostEnabled) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    PlayerSpeedChip(
                      speed: 2.0,
                      isSelected: _preferences.longPressSpeed == 2.0,
                      onTap: () => _applyPreferences(
                        _preferences.copyWith(longPressSpeed: 2.0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PlayerSpeedChip(
                      speed: 3.0,
                      isSelected: _preferences.longPressSpeed == 3.0,
                      onTap: () => _applyPreferences(
                        _preferences.copyWith(longPressSpeed: 3.0),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PlayerSpeedChip(
                      speed: 5.0,
                      isSelected: _preferences.longPressSpeed == 5.0,
                      onTap: () => _applyPreferences(
                        _preferences.copyWith(longPressSpeed: 5.0),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// 抽屉内的小节标题
class _PanelSectionTitle extends StatelessWidget {
  const _PanelSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          color: Colors.white60,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      );
}
