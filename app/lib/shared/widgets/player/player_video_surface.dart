import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';

/// 视频渲染核心区域（支持 Contain / Cover / Fill 比例调节与水平镜像翻转）
///
/// 纯展示组件：接收播放控制器与画面参数，不持有任何状态。
///
/// 三种比例的差异：
/// - `cover` / `fill`：用 `SizedBox.expand + FittedBox` 撑满父容器，避免出现黑边；
/// - `contain`（默认）：用 `AspectRatio` 保持视频原始比例居中。
///
/// 未就绪时退化为封面海报；封面也缺失时返回空容器（由外层底色兜底）。
class PlayerVideoSurface extends StatelessWidget {
  const PlayerVideoSurface({
    super.key,
    required this.isInitialized,
    required this.controller,
    required this.fit,
    required this.isMirrored,
    this.coverUrl,
  });

  final bool isInitialized;
  final VideoPlayerController? controller;
  final BoxFit fit;

  /// 水平镜像翻转（便于舞蹈 / 健身 / 跟练视频学习）
  final bool isMirrored;

  /// 未就绪时展示的海报封面
  final String? coverUrl;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    if (!isInitialized || ctrl == null) {
      // 未就绪时若有封面则显示海报封面
      if (coverUrl != null && coverUrl!.isNotEmpty) {
        return Image.network(
          coverUrl!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
        );
      }
      return const SizedBox.shrink();
    }

    final videoWidth = ctrl.value.size.width;
    final videoHeight = ctrl.value.size.height;
    final aspectRatio = ctrl.value.aspectRatio > 0 ? ctrl.value.aspectRatio : 16 / 9;

    Widget videoWidget;
    if (fit == BoxFit.cover) {
      videoWidget = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: SizedBox(
            width: videoWidth > 0 ? videoWidth : 16,
            height: videoHeight > 0 ? videoHeight : 9,
            child: VideoPlayer(ctrl),
          ),
        ),
      );
    } else if (fit == BoxFit.fill) {
      videoWidget = SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fill,
          child: SizedBox(
            width: videoWidth > 0 ? videoWidth : 16,
            height: videoHeight > 0 ? videoHeight : 9,
            child: VideoPlayer(ctrl),
          ),
        ),
      );
    } else {
      videoWidget = Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: VideoPlayer(ctrl),
        ),
      );
    }

    if (isMirrored) {
      videoWidget = Transform(
        alignment: Alignment.center,
        transform: Matrix4.rotationY(math.pi),
        child: videoWidget,
      );
    }

    return videoWidget;
  }
}
