import 'package:flutter/services.dart' show HapticFeedback;
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

/// 顶部控制条
///
/// 全屏状态加大左右呼吸安全边距（避开刘海与圆角），右侧可插入扩展操作与「更多设置」按钮。
/// 内边距由上层算好后整体传入 —— 与 `PlayerControlBar` 保持同一约定，
/// 组件本身不感知 `MediaQuery` 与全屏避让规则。
class PlayerTopBar extends StatelessWidget {
  const PlayerTopBar({
    super.key,
    required this.title,
    required this.padding,
    required this.isFullScreen,
    required this.showBackButton,
    required this.onBack,
    required this.extraActions,
    required this.onOpenMoreSettings,
  });

  final String title;

  /// 已算好的内边距（含顶部安全区与左右避让，由上层按 MediaQuery 计算）
  final EdgeInsets padding;

  final bool isFullScreen;

  /// 是否渲染返回键（全屏恒显示；非全屏仅在提供了返回回调时显示）
  final bool showBackButton;

  final VoidCallback onBack;

  /// 扩展操作区（如收藏、分享），为 null 时不渲染
  final List<Widget>? extraActions;

  final VoidCallback onOpenMoreSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: padding,
      child: Row(
        children: [
          if (showBackButton)
            IconButton(
              icon: const Icon(
                Ionicons.chevronBackOutline,
                color: Colors.white,
                size: 22,
              ),
              onPressed: onBack,
            ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          ...?extraActions,
          // 右上角更多设置图标
          PlayerMoreSettingsButton(
            isFullScreen: isFullScreen,
            onTap: onOpenMoreSettings,
          ),
        ],
      ),
    );
  }
}

/// 顶部右上角「更多设置」按钮
///
/// 全屏下右边缘与进度条 / 全屏键严格右对齐（靠右固定尺寸容器），
/// 非全屏用标准 `IconButton`。触感反馈内聚在此。
class PlayerMoreSettingsButton extends StatelessWidget {
  const PlayerMoreSettingsButton({
    super.key,
    required this.isFullScreen,
    required this.onTap,
  });

  final bool isFullScreen;
  final VoidCallback onTap;

  void _handleTap() {
    HapticFeedback.lightImpact();
    onTap();
  }

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(
      Ionicons.ellipsisHorizontalOutline,
      color: Colors.white,
      size: 22,
    );

    if (isFullScreen) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.centerRight,
          child: icon,
        ),
      );
    }

    return IconButton(
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      onPressed: _handleTap,
    );
  }
}
