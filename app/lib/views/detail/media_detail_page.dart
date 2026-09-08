import 'package:material_ui/material_ui.dart';

import 'photo_gallery_page.dart';
import 'video_player_page.dart';

/// 跨媒体类型聚合详情路由分发页面
/// 
/// 根据 `type` (video, tv, image, novel 等) 动态路由至对应的专用媒体播放与浏览界面
class MediaDetailPage extends StatelessWidget {
  const MediaDetailPage({
    super.key,
    required this.type,
    this.href,
    this.title = '详情',
    this.cover,
  });

  /// 媒体类型标识：'video' | 'tv' | 'image' | 'novel'
  final String type;

  /// 内容直链或详情页链接
  final String? href;

  /// 媒体标题
  final String title;

  /// 封面海报
  final String? cover;

  @override
  Widget build(BuildContext context) {
    switch (type) {
      case 'video':
      case 'tv':
      case 'movie':
        return VideoPlayerPage(
          title: title,
          coverUrl: cover,
        );

      case 'image':
      case 'photo':
      case 'gallery':
        return PhotoDetailPage(
          href: href ?? '',
          title: title,
        );

      default:
        return VideoPlayerPage(
          title: title,
          coverUrl: cover,
        );
    }
  }
}
