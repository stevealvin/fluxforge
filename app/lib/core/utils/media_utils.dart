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

/// 图片直链的 Referer 兜底：**只在缺失时**补上图片自身的站点根
///
/// 实测（同一图床，逐项打真实响应码）：不带 Referer → **403**；
/// 带任意 Referer（站点根 / CDN 自身 / 换任何 UA）→ **200** —— 即站点只校验
/// 「有没有 Referer」，UA 不参与判定。
///
/// 而页面级 Referer 未必总取得出（规则没有 baseUrl、或从下载管理 / 历史 /
/// 继续观看等**非详情页**上下文发起加载），所以这里用图片自身的站点根兜底，
/// 保证请求至少带一个 Referer。
///
/// 三条约定：
/// - **不覆盖**调用方已给的 Referer（大小写不敏感）；
/// - 只在 [headers] 里没有 Referer 且地址是绝对 URL 时才补；
/// - 返回新 Map（纯函数，不改动入参）；无需补时原样返回入参（含 `null`）。
Map<String, String>? ensureRefererHeader(
  String url,
  Map<String, String>? headers,
) {
  final hasReferer =
      headers != null && headers.keys.any((k) => k.toLowerCase() == 'referer');
  if (hasReferer) return headers;

  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return headers;

  return {...?headers, 'Referer': '${uri.scheme}://${uri.host}'};
}

/// 把详情 / parse 解析出的地址补全为绝对地址
///
/// 规则里的相对路径（`/static/upload/xxx.jpg`、`chapter/53996`、`//cdn.xx/a.jpg`）
/// 必须先补全，否则会被当成站内相对路径直接请求失败。
///
/// 详情解析与漫画章节的图片解析都用这**同一套口径**，避免两处补全规则分叉。
String resolveMediaUrl(String raw, {String baseUrl = ''}) {
  final u = raw.trim();
  if (u.isEmpty) return '';
  if (u.startsWith('http://') || u.startsWith('https://')) return u;
  if (u.startsWith('//')) return 'https:$u';

  final base = baseUrl.trim();
  if (base.isEmpty) return u;

  try {
    final baseUri = Uri.parse(base);
    if (u.startsWith('/')) {
      return '${baseUri.scheme}://${baseUri.host}'
          '${baseUri.hasPort ? ":${baseUri.port}" : ""}$u';
    }
    return Uri.parse(base.endsWith('/') ? base : '$base/')
        .resolve(u)
        .toString();
  } catch (_) {
    return u;
  }
}
