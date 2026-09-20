import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

/// 推入播放器全屏独占沉浸路由，退出后恢复竖屏
///
/// 抽出的是与播放逻辑无关的编排：横竖屏、系统 UI 模式、路由推入与退出恢复。
/// 全屏内容由 [builder] 决定，故本文件不依赖播放器类型（避免互相 import）；
/// [onExited] 在恢复竖屏后回调，调用方已卸载时不回调。
Future<void> pushPlayerFullscreen({
  required BuildContext context,
  required WidgetBuilder builder,
  required VoidCallback onExited,
}) async {
  // 1. 横屏 + 全屏沉浸（隐藏状态栏与导航栏）
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  if (!context.mounted) return;

  // 2. 走 rootNavigator 独立路由，全屏铺满并覆盖宿主所有 AppBar / BottomBar / Scaffold
  await Navigator.of(context, rootNavigator: true).push(
    PageRouteBuilder<void>(
      opaque: true,
      fullscreenDialog: true,
      pageBuilder: (fullscreenContext, animation, secondaryAnimation) =>
          builder(fullscreenContext),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(opacity: animation, child: child),
    ),
  );

  // 3. 退出全屏后恢复竖屏与 edgeToEdge
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  if (!context.mounted) return;
  onExited();
}
