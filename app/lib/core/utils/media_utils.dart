import 'package:flutter/widgets.dart';
import 'package:ionicons/ionicons.dart';

/// 媒体类型展示映射工具 (MediaDisplay)
///
/// 统一 video / novel / comic 三大媒体类型的语义图标与中文标签映射，
/// 消除收藏页、历史中心、继续观看横滑流等多处重复手写 switch 的问题。
class MediaDisplay {
  MediaDisplay._();

  /// 媒体类型语义图标
  static IconData typeIcon(String? mediaType) {
    switch ((mediaType ?? '').toLowerCase()) {
      case 'video':
      case 'tv':
      case 'movie':
      case 'anime':
      case 'film':
        return Ionicons.filmOutline;
      case 'novel':
      case 'book':
      case 'text':
      case 'story':
        return Ionicons.bookOutline;
      case 'comic':
      case 'manga':
      case 'image':
      case 'picture':
      case 'photo':
      case 'gallery':
        return Ionicons.imageOutline;
      default:
        return Ionicons.playCircleOutline;
    }
  }

  /// 媒体类型中文标签
  static String typeLabel(String? mediaType) {
    switch ((mediaType ?? '').toLowerCase()) {
      case 'video':
      case 'tv':
      case 'movie':
      case 'anime':
      case 'film':
        return '影视';
      case 'novel':
      case 'book':
      case 'text':
      case 'story':
        return '小说';
      case 'comic':
      case 'manga':
      case 'image':
      case 'picture':
      case 'photo':
      case 'gallery':
        return '漫画';
      default:
        return '媒体';
    }
  }
}
