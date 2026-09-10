import 'package:material_ui/material_ui.dart';

import '../gallery/gallery_viewer_page.dart';
import '../reader/novel_reader_page.dart';
import 'video_player_page.dart';

/// 跨媒体类型聚合详情路由分发页面
/// 
/// 根据 `type` (video, tv, image, novel, comic, gallery 等) 动态路由至对应的专用媒体播放与浏览界面
class MediaDetailPage extends StatelessWidget {
  const MediaDetailPage({
    super.key,
    required this.type,
    this.url,
    this.title = '详情',
    this.cover,
  });

  /// 媒体类型标识：'video' | 'tv' | 'image' | 'novel' | 'comic' | 'gallery'
  final String type;

  /// 内容直链或详情页链接
  final String? url;

  /// 媒体标题
  final String title;

  /// 封面海报
  final String? cover;

  @override
  Widget build(BuildContext context) {
    switch (type.toLowerCase()) {
      // 1. 视听流媒体类 -> AuraPlayer 驱动的 VideoPlayerPage
      case 'video':
      case 'tv':
      case 'movie':
      case 'anime':
        return VideoPlayerPage(
          title: title,
          coverUrl: cover,
          playUrl: url,
        );

      // 2. 小说阅读类 -> FluxReader 驱动的 NovelReaderPage
      case 'novel':
      case 'book':
      case 'story':
        return NovelReaderPage(
          bookTitle: title,
        );

      // 3. 漫画与高清画廊图集类 -> FluxGallery 驱动的 GalleryViewerPage
      case 'comic':
      case 'gallery':
      case 'manga':
      case 'image':
      case 'photo':
      case 'picture':
        return GalleryViewerPage(
          title: title,
          images: url != null && url!.isNotEmpty ? [url!] : const [],
        );

      default:
        return VideoPlayerPage(
          title: title,
          coverUrl: cover,
          playUrl: url,
        );
    }
  }
}
