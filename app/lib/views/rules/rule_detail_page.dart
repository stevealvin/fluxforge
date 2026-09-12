import 'dart:collection';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/player/aura_player.dart';
import '../detail/photo_gallery_page.dart';

/// 跨媒体类型标识枚举
enum MediaType {
  video,
  image,
  novel,
  unknown,
}

/// 规则项目详情与自适应多媒体播放/画廊页面
/// 
/// 自动根据规则元数据（rule.type）与沙箱返回数据结构进行媒体类型自适应识别，
/// 分别渲染专业视听播放器（AuraPlayer 极光引擎）、高清图集瀑布流网格或小说章节阅读器。
class RuleDetailPage extends StatefulWidget {
  const RuleDetailPage({
    super.key,
    required this.title,
    required this.url,
    required this.cover,
    this.rule,
  });

  /// 内容标题
  final String title;

  /// 详情或内容直链链接
  final String url;

  /// 封面海报
  final String cover;

  /// 关联的解析规则模型
  final Rule? rule;

  @override
  State<RuleDetailPage> createState() => _RuleDetailPageState();
}

class _RuleDetailPageState extends State<RuleDetailPage> {
  // 状态机变量
  bool _loading = true;
  String? _error;
  MediaType _mediaType = MediaType.unknown;

  // 扩展元数据 (标题/封面/简介/作者/评分/题材标签)
  String? _detailTitle;
  String? _detailCover;
  String? _detailDesc;
  String? _detailAuthor;
  String? _detailRating;
  List<String> _detailTags = [];

  // 视频相关数据
  String? _videoUrl;
  List<Map<String, dynamic>> _episodes = [];
  List<Map<String, dynamic>> _videoGroups = [];
  int _selectedVideoGroupIndex = 0;
  int _currentEpisodeIndex = 0;
  bool _isEpisodeReversed = false;
  bool _isDescExpanded = false;

  // 图片与漫画相关数据
  List<String> _imageList = [];
  List<Map<String, dynamic>> _comicGroups = [];
  int _selectedComicGroupIndex = 0;
  int _selectedComicChapterIndex = 0;
  bool _loadingChapter = false;
  bool _isContinuousReadingMode = false;

  // 文本/小说相关数据
  String? _textContent;
  List<Map<String, dynamic>> _chapters = [];

  // 扩展展示数据 (剧照/截图预览与相关推荐)
  List<String> _previews = [];
  List<Map<String, dynamic>> _related = [];
  Map<String, String> _customHeaders = {};

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  /// 加载并执行规则详情解析沙箱
  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
      _previews = [];
      _related = [];
      _comicGroups = [];
      _imageList = [];
      _videoUrl = null;
      _episodes = [];
      _videoGroups = [];
      _selectedVideoGroupIndex = 0;
      _currentEpisodeIndex = 0;
      _isEpisodeReversed = false;
      _isDescExpanded = false;
      _detailRating = null;
      _detailTags = [];
      _customHeaders = {};
    });

    if (widget.rule == null) {
      setState(() {
        _error = '未指定解析规则，无法调度沙箱执行';
        _loading = false;
      });
      return;
    }

    try {
      final itemParam = {
        'title': widget.title,
        'url': widget.url,
        'cover': widget.cover,
      };
      final result = await RuleEngine.detail(
        widget.rule!,
        widget.url,
        item: itemParam,
      );
      _parseResult(result);
    } catch (e) {
      debugPrint('【详情解析】沙箱执行失败: $e');
      setState(() {
        _error = '详情加载失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// 加载漫画章节/分卷下的图片清单 (执行沙箱 parse 动作)
  Future<void> _loadChapterImages(String chapterUrl, {String? groupName}) async {
    if (widget.rule == null || chapterUrl.isEmpty) return;
    setState(() {
      _loadingChapter = true;
    });

    try {
      final res = await RuleEngine.parse(
        widget.rule!,
        chapterUrl,
        groupName: groupName,
      );
      if (!mounted) return;
      if (res is Map && res['headers'] is Map) {
        _customHeaders = (res['headers'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }
      final images = _extractImageListFromAny(res);
      setState(() {
        if (images.isNotEmpty) {
          _imageList = images;
        } else {
          // 如果解析为空，保留封面或原图片作为兜底
          final fallback = <String>[];
          if (_detailCover != null && _detailCover!.isNotEmpty) {
            fallback.add(_normalizeUrl(_detailCover!));
          } else if (widget.cover.isNotEmpty) {
            fallback.add(_normalizeUrl(widget.cover));
          }
          _imageList = fallback;
        }
      });
    } catch (e) {
      debugPrint('【章节图片解析】沙箱 parse 调度失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loadingChapter = false;
        });
      }
    }
  }

  /// 规范化并解析 URL 为绝对路径
  String _normalizeUrl(String rawUrl) {
    var u = rawUrl.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    final base = widget.rule?.baseUrl ?? '';
    if (base.isEmpty) return u;
    try {
      final baseUri = Uri.parse(base);
      if (u.startsWith('/')) {
        return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ":${baseUri.port}" : ""}$u';
      } else {
        final baseDir = base.endsWith('/') ? base : '$base/';
        return Uri.parse(baseDir).resolve(u).toString();
      }
    } catch (_) {
      return u;
    }
  }

  /// 稳健智能提取各类数据结构中的图片 URL 列表
  List<String> _extractImageListFromAny(dynamic rawData) {
    if (rawData == null) return [];

    // 1. 字符串可能是直接图片地址或 JSON 字符串
    if (rawData is String) {
      final trimmed = rawData.trim();
      if (trimmed.isEmpty) return [];
      if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
        try {
          return _extractImageListFromAny(jsonDecode(trimmed));
        } catch (_) {}
      }
      if (_looksLikeImageUrl(trimmed) || trimmed.startsWith('http') || trimmed.startsWith('/')) {
        return [_normalizeUrl(trimmed)];
      }
      return [];
    }

    final List<String> list = [];

    // 2. 数组直接遍历
    if (rawData is List) {
      for (final item in rawData) {
        if (item is String) {
          final trimmed = item.trim();
          if (trimmed.isNotEmpty) {
            list.add(_normalizeUrl(trimmed));
          }
        } else if (item is Map) {
          final candidate = item['url'] ??
              item['src'] ??
              item['img'] ??
              item['image'] ??
              item['link'] ??
              item['href'] ??
              item['cover'] ??
              item['original'] ??
              item['raw'] ??
              item['path'];
          if (candidate != null) {
            final u = candidate.toString().trim();
            if (u.isNotEmpty) {
              list.add(_normalizeUrl(u));
            }
          }
        }
      }
      return LinkedHashSet<String>.from(list).toList();
    }

    // 3. Map 递归深入提取
    if (rawData is Map) {
      // 严格按照 RULE_SPECIFICATION.md v2.0 契约标准：
      // 全类型大一统字段为 items (图集/壁纸源直出 string[] 或 [{ url: string }])
      if (rawData['items'] != null) {
        final extracted = _extractImageListFromAny(rawData['items']);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }

      // 历史废弃字段或非标字段兜底容错 (如旧版规则未及时升级至 v2.0 items)
      const legacyCandidateKeys = [
        'images',
        'list',
        'photos',
        'pictures',
        'urls',
        'links',
        'gallery',
      ];

      for (final key in legacyCandidateKeys) {
        final val = rawData[key];
        if (val != null) {
          final extracted = _extractImageListFromAny(val);
          if (extracted.isNotEmpty) {
            return extracted;
          }
        }
      }

      // 嵌套 data 或 result 对象
      if (rawData['data'] != null) {
        final extracted = _extractImageListFromAny(rawData['data']);
        if (extracted.isNotEmpty) return extracted;
      }
      if (rawData['result'] != null) {
        final extracted = _extractImageListFromAny(rawData['result']);
        if (extracted.isNotEmpty) return extracted;
      }

      // 尝试从 content 正文中解析 <img> 标签或 Markdown 图片
      final contentStr = rawData['content']?.toString();
      if (contentStr != null && contentStr.isNotEmpty) {
        final imgRegex = RegExp(r'''<img[^>]+src=["']([^"']+)["']''', caseSensitive: false);
        for (final m in imgRegex.allMatches(contentStr)) {
          final u = m.group(1);
          if (u != null && u.trim().isNotEmpty) {
            list.add(_normalizeUrl(u.trim()));
          }
        }
        final mdRegex = RegExp(r'!\[.*?\]\((https?://[^\s\)]+)\)');
        for (final m in mdRegex.allMatches(contentStr)) {
          final u = m.group(1);
          if (u != null && u.trim().isNotEmpty) {
            list.add(_normalizeUrl(u.trim()));
          }
        }
        if (list.isNotEmpty) {
          return LinkedHashSet<String>.from(list).toList();
        }
      }

      // 单图直出字段
      final single = rawData['url'] ?? rawData['src'] ?? rawData['cover'] ?? rawData['img'];
      if (single != null) {
        final u = single.toString().trim();
        if (u.isNotEmpty && (_looksLikeImageUrl(u) || u.startsWith('http') || u.startsWith('/'))) {
          list.add(_normalizeUrl(u));
        }
      }
    }

    return LinkedHashSet<String>.from(list).toList();
  }

  /// 智能解析沙箱返回结果并推断媒体类型
  void _parseResult(dynamic result) {
    final declaredType = widget.rule?.type.toLowerCase() ?? '';

    // 提取通用元数据
    if (result is Map) {
      _detailTitle = result['title']?.toString();
      _detailCover = result['cover']?.toString();
      _detailDesc = result['desc']?.toString() ?? result['description']?.toString();
      _detailAuthor = result['author']?.toString();
      _detailRating = result['rating']?.toString();
      if (result['tags'] is List) {
        _detailTags = (result['tags'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

      // 防盗链 Header 提取 (RULE_SPECIFICATION.md 4.3 headers)
      if (result['headers'] is Map) {
        _customHeaders = (result['headers'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }

      if (result['previews'] is List) {
        _previews = (result['previews'] as List)
            .map((e) => _normalizeUrl(e.toString()))
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (result['related'] is List) {
        _related = (result['related'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }
    }

    // 检查是否有章节/分卷分组 (groups)
    final List<Map<String, dynamic>> extractedGroups = [];
    if (result is Map && result['groups'] is List) {
      for (final g in result['groups']) {
        if (g is Map) {
          final gName = g['name']?.toString() ?? '章节列表';
          final rawItems = g['items'] as List? ?? [];
          final epList = <Map<String, dynamic>>[];
          for (int i = 0; i < rawItems.length; i++) {
            final it = rawItems[i];
            if (it is Map) {
              epList.add({
                'title': it['title']?.toString() ?? '第 ${i + 1} 话',
                'url': it['url']?.toString() ?? it['link']?.toString() ?? '',
              });
            } else if (it is String) {
              epList.add({
                'title': '第 ${i + 1} 话',
                'url': it,
              });
            }
          }
          if (epList.isNotEmpty) {
            extractedGroups.add({
              'name': gName,
              'items': epList,
            });
          }
        }
      }
    }

    // 1. 图片/相册/画廊/漫画类型
    if (declaredType == 'image' ||
        declaredType == 'picture' ||
        declaredType == 'photo' ||
        declaredType == 'gallery' ||
        declaredType == 'comic' ||
        declaredType == 'manga') {
      _mediaType = MediaType.image;
      _comicGroups = extractedGroups;

      // 提取图片 (契约第一标准: detail.items)
      var directImages = _extractImageListFromAny(result);
      if (directImages.isEmpty && _previews.isNotEmpty) {
        // 如果 items 为空但有 previews 剧照/预览图，优雅降级作为画廊内容
        directImages = _previews;
      }

      if (directImages.isNotEmpty) {
        _imageList = directImages;
      } else if (_comicGroups.isNotEmpty) {
        // 如果没有直接图片列表，但有分卷/分集/章节分组 (如漫画连载)，自动请求并解析首个章节图片
        final firstGroup = _comicGroups.first;
        final firstItems = firstGroup['items'] as List<Map<String, dynamic>>? ?? [];
        if (firstItems.isNotEmpty) {
          final firstUrl = firstItems.first['url']?.toString() ?? '';
          _selectedComicGroupIndex = 0;
          _selectedComicChapterIndex = 0;
          if (firstUrl.isNotEmpty) {
            _loadChapterImages(firstUrl, groupName: firstGroup['name']?.toString());
          }
        }
      } else {
        // 兜底降级策略：使用 cover 或 url
        final fallback = <String>[];
        if (_detailCover != null && _detailCover!.isNotEmpty) {
          fallback.add(_normalizeUrl(_detailCover!));
        } else if (widget.cover.isNotEmpty) {
          fallback.add(_normalizeUrl(widget.cover));
        } else if (widget.url.isNotEmpty && _looksLikeImageUrl(widget.url)) {
          fallback.add(_normalizeUrl(widget.url));
        }
        _imageList = fallback;
      }
      return;
    }

    // 2. 小说/文本类型
    if (declaredType == 'novel' || declaredType == 'book' || declaredType == 'text') {
      _extractNovel(result);
      _mediaType = MediaType.novel;
      return;
    }

    // 3. 数组结果推断
    if (result is List) {
      if (result.isNotEmpty) {
        final first = result.first;
        final firstUrl = first is Map ? (first['url'] ?? first['src'] ?? '').toString() : first.toString();
        if (_looksLikeImageUrl(firstUrl)) {
          _imageList = _extractImageListFromAny(result);
          _mediaType = MediaType.image;
          return;
        }
      }
      _extractEpisodesFromList(result);
      _mediaType = MediaType.video;
      return;
    }

    // 4. Map 智能推断
    if (result is Map) {
      final rawItems = result['items'];

      // 检查 items 中的元素是否为图片 URL
      if (rawItems is List && rawItems.isNotEmpty) {
        final first = rawItems.first;
        final firstUrl = first is Map ? (first['url'] ?? first['src'] ?? '').toString() : first.toString();
        if (_looksLikeImageUrl(firstUrl)) {
          _imageList = _extractImageListFromAny(rawItems);
          _mediaType = MediaType.image;
          return;
        }
      }

      // 检查是否包含 images 字段且非空
      if (result['images'] is List && (result['images'] as List).isNotEmpty) {
        _imageList = _extractImageListFromAny(result['images']);
        _mediaType = MediaType.image;
        return;
      }

      // 检查小说正文
      if (result.containsKey('content') && (result['content'] is String) && (result['content'] as String).length > 100) {
        _extractNovel(result);
        _mediaType = MediaType.novel;
        return;
      }

      // 检查视频播放地址或剧集 items
      final String? videoUrl = result['playUrl']?.toString();

      if (extractedGroups.isNotEmpty) {
        _videoGroups = extractedGroups;
        _selectedVideoGroupIndex = 0;
        _episodes = extractedGroups.first['items'] as List<Map<String, dynamic>>? ?? [];
      } else if (rawItems is List) {
        _extractEpisodesFromList(rawItems);
      }

      if (videoUrl != null && videoUrl.isNotEmpty) {
        _videoUrl = videoUrl;
        _mediaType = MediaType.video;
        return;
      }

      if (_episodes.isNotEmpty) {
        _mediaType = MediaType.video;
        _playEpisode(0);
        return;
      }
    }

    // 默认作为视频模式处理
    _mediaType = MediaType.video;
  }

  /// 切换视频播放线路/分组 (如 "超清线路" / "备用线路")
  void _selectVideoGroup(int groupIndex) {
    if (groupIndex < 0 || groupIndex >= _videoGroups.length) return;
    setState(() {
      _selectedVideoGroupIndex = groupIndex;
      final group = _videoGroups[groupIndex];
      final items = group['items'] as List?;
      _episodes = items?.whereType<Map<String, dynamic>>().toList() ?? [];
      _currentEpisodeIndex = 0;
    });
    if (_episodes.isNotEmpty) {
      _playEpisode(0);
    }
  }

  /// 从返回数据中提取剧集列表 (统一读取 items 数组及 item.title / item.url)
  void _extractEpisodesFromList(List rawList) {
    final List<Map<String, dynamic>> episodes = [];
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map) {
        episodes.add({
          'title': item['title']?.toString() ?? '第 ${i + 1} 集',
          'url': item['url']?.toString() ?? '',
        });
      } else if (item is String) {
        episodes.add({
          'title': '第 ${i + 1} 集',
          'url': item,
        });
      }
    }
    _episodes = episodes;
  }

  /// 提取小说/文本内容 (统一读取 content 正文与 items 章节列表)
  void _extractNovel(dynamic rawData) {
    if (rawData is Map) {
      _textContent = rawData['content']?.toString();
      final chs = rawData['items'];
      if (chs is List) {
        _chapters = chs.map((e) {
          if (e is Map) {
            return {
              'title': e['title']?.toString() ?? '',
              'url': e['url']?.toString() ?? '',
            };
          }
          return {
            'title': e.toString(),
            'url': e.toString(),
          };
        }).toList();
      }
    } else if (rawData is String) {
      _textContent = rawData;
    }
  }

  /// 判断链接字符串是否可能是图片扩展名或路径
  bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('.gif') ||
        lower.contains('.avif') ||
        lower.contains('.heic') ||
        lower.contains('.jfif') ||
        lower.contains('.svg') ||
        lower.contains('/file/') ||
        lower.contains('/image/') ||
        lower.contains('/photo/') ||
        lower.contains('/pic/') ||
        lower.contains('/img/') ||
        lower.contains('/uploads/');
  }

  /// 判断地址是否为直接视频媒体直链
  bool _isDirectVideoUrl(String u) {
    final lower = u.toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.m3u8') ||
        lower.contains('.flv') ||
        lower.contains('.mov') ||
        lower.contains('.webm') ||
        lower.contains('.avi') ||
        lower.contains('.mkv') ||
        lower.contains('/mp4/') ||
        lower.contains('/m3u8/');
  }

  /// 选集播放调度 (智能直链嗅探与沙箱 parse 解析驱动 AuraPlayer)
  Future<void> _playEpisode(int index) async {
    if (index < 0 || index >= _episodes.length) return;
    final ep = _episodes[index];
    final rawUrl = ep['url']?.toString() ?? ep['videoUrl']?.toString() ?? '';
    if (rawUrl.isEmpty) return;

    setState(() {
      _currentEpisodeIndex = index;
    });

    // 若已经是直链流地址，直接驱动 AuraPlayer 播放
    if (_isDirectVideoUrl(rawUrl)) {
      setState(() {
        _videoUrl = rawUrl;
      });
      return;
    }

    // 否则调度沙箱 parse 动作嗅探直链 (遵循 RULE_SPECIFICATION.md 4.4 契约)
    if (widget.rule != null) {
      try {
        final parseResult = await RuleEngine.parse(widget.rule!, rawUrl);
        if (!mounted) return;
        if (parseResult is Map) {
          if (parseResult['headers'] is Map) {
            _customHeaders = {
              ..._customHeaders,
              ...(parseResult['headers'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              ),
            };
          }
          final resolvedPlayUrl = parseResult['playUrl']?.toString();
          if (resolvedPlayUrl != null && resolvedPlayUrl.isNotEmpty) {
            setState(() {
              _videoUrl = resolvedPlayUrl;
            });
            return;
          }
        }
      } catch (e) {
        debugPrint('【选集解析】沙箱 parse 解析视频直链失败: $e');
      }
    }

    // 降级使用原始地址
    setState(() {
      _videoUrl = rawUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayTitle = _detailTitle?.isNotEmpty == true ? _detailTitle! : widget.title;

    // 当处于视频媒体类型且已成功解析时，隐藏外层系统 AppBar，
    // 将顶栏导航与返回操作沉浸式交给置顶吸顶的 AuraPlayer 原生渲染，彻底消除双重标题和双返回键冲突。
    final bool hideScaffoldAppBar = !_loading && _error == null && _mediaType == MediaType.video;

    return Scaffold(
      appBar: hideScaffoldAppBar
          ? null
          : AppBar(
              title: Text(displayTitle),
              actions: [
                if (_mediaType == MediaType.image) ...[
                  if (_imageList.isNotEmpty)
                    IconButton(
                      tooltip: _isContinuousReadingMode ? '切换为网格画廊' : '切换为连续长卷',
                      icon: Icon(
                        _isContinuousReadingMode ? LucideIcons.layoutGrid : LucideIcons.rows3,
                        size: 20,
                      ),
                      onPressed: () {
                        setState(() {
                          _isContinuousReadingMode = !_isContinuousReadingMode;
                        });
                      },
                    ),
                  if (_imageList.isNotEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 16),
                        child: Text(
                          '共 ${_imageList.length} 张',
                          style: TextStyle(
                            fontSize: 13,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(
        child: LoadingIndicator(message: '正在调用沙箱解析多媒体内容...'),
      );
    }

    if (_error != null) {
      return Center(
        child: EmptyState(
          icon: LucideIcons.alertTriangle,
          title: '详情加载失败',
          description: _error,
          actionText: '重试加载',
          onAction: _loadDetail,
        ),
      );
    }

    // 根据检测出的媒体类型动态渲染专属视图
    switch (_mediaType) {
      case MediaType.image:
        return _buildGalleryView(isDark);
      case MediaType.novel:
        return _buildNovelView(isDark);
      case MediaType.video:
      default:
        return _buildVideoView(isDark);
    }
  }

  // ==================== 1. 图片/图集专属画廊视图 ====================
  Widget _buildGalleryView(bool isDark) {
    final referer = widget.rule?.baseUrl ?? '';
    final Map<String, String> imageHeaders = {
      if (referer.isNotEmpty) 'Referer': referer,
      ..._customHeaders,
    };
    final effectiveHeaders = imageHeaders.isNotEmpty ? imageHeaders : null;

    // 如果未解析到图片，并且没有章节选集，显示空状态
    if (_imageList.isEmpty && !_loadingChapter && _comicGroups.isEmpty) {
      return Center(
        child: EmptyState(
          icon: LucideIcons.imageOff,
          title: '未解析到图片内容',
          description: '目标图集可能已失效，或规则解析提取逻辑需要更新',
          actionText: '重新加载',
          onAction: _loadDetail,
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 图集/漫画元数据卡片 (简介、作者)
          if ((_detailDesc != null && _detailDesc!.isNotEmpty) ||
              (_detailAuthor != null && _detailAuthor!.isNotEmpty)) ...[
            AppCard(
              padding: const EdgeInsets.all(12),
              borderRadius: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_detailAuthor != null && _detailAuthor!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Icon(LucideIcons.user, size: 14, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(
                            _detailAuthor!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_detailDesc != null && _detailDesc!.isNotEmpty)
                    Text(
                      _detailDesc!,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 2. 漫画/分卷章节选集目录 (若有)
          _buildComicChaptersSection(isDark),

          // 3. 画廊头部与浏览模式切换按钮 (展厅网格 vs 垂直条漫)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(LucideIcons.images, size: 15, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      _isContinuousReadingMode ? '连续长卷浏览' : '画廊展厅模式',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      ),
                    ),
                    if (_imageList.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text(
                        '(${_imageList.length} 张)',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (_imageList.isNotEmpty)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: Icon(
                      _isContinuousReadingMode ? LucideIcons.layoutGrid : LucideIcons.columns,
                      size: 14,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      _isContinuousReadingMode ? '网格浏览' : '连续长卷',
                      style: const TextStyle(fontSize: 12, color: AppColors.primary),
                    ),
                    onPressed: () {
                      setState(() {
                        _isContinuousReadingMode = !_isContinuousReadingMode;
                      });
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // 4. 图片加载中状态
          if (_loadingChapter)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: LoadingIndicator(message: '正在解析章节图片流...'),
              ),
            )
          else if (_imageList.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Center(
                child: Text(
                  '当前章节暂无图片，请点击上方切换其他章节',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  ),
                ),
              ),
            )
          else if (_isContinuousReadingMode)
            // 连续垂直长卷流（漫画/连载长图模式）
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _imageList.length,
              separatorBuilder: (_, _) => const SizedBox(height: 6),
              itemBuilder: (context, index) {
                final imgUrl = _imageList[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openPhotoViewer(
                    index,
                    referer: referer,
                    headers: effectiveHeaders,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ExtendedImage.network(
                      imgUrl,
                      cache: true,
                      fit: BoxFit.fitWidth,
                      headers: effectiveHeaders,
                      loadStateChanged: (state) => _handleImageLoadState(state, isDark),
                    ),
                  ),
                );
              },
            )
          else
            // 3 列九宫格缩略图
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 0.68,
              ),
              itemCount: _imageList.length,
              itemBuilder: (context, index) {
                final imgUrl = _imageList[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => _openPhotoViewer(
                    index,
                    referer: referer,
                    headers: effectiveHeaders,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ExtendedImage.network(
                      imgUrl,
                      cache: true,
                      fit: BoxFit.cover,
                      headers: effectiveHeaders,
                      loadStateChanged: (state) => _handleImageLoadState(state, isDark),
                    ),
                  ),
                );
              },
            ),

          // 5. 相似推荐
          if (_related.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildRelatedSection(isDark),
          ],
        ],
      ),
    );
  }

  /// 构建漫画/图集分卷章节选择卡片
  Widget _buildComicChaptersSection(bool isDark) {
    if (_comicGroups.isEmpty) return const SizedBox.shrink();

    final currentGroup = _comicGroups[_selectedComicGroupIndex.clamp(0, _comicGroups.length - 1)];
    final items = currentGroup['items'] as List<Map<String, dynamic>>? ?? [];

    return AppCard(
      padding: const EdgeInsets.all(12),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '选集目录',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              Text(
                '共 ${items.length} 话',
                style: TextStyle(
                  fontSize: 11.5,
                  color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 分组选择 Tab (如 "章节列表" / "番外")
          if (_comicGroups.length > 1) ...[
            SizedBox(
              height: 32,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: _comicGroups.length,
                itemBuilder: (context, index) {
                  final g = _comicGroups[index];
                  final isSelected = index == _selectedComicGroupIndex;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(g['name']?.toString() ?? '第 ${index + 1} 组'),
                      selected: isSelected,
                      selectedColor: AppColors.primary,
                      labelStyle: TextStyle(
                        fontSize: 11.5,
                        color: isSelected
                            ? Colors.white
                            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      ),
                      onSelected: (val) {
                        if (val && _selectedComicGroupIndex != index) {
                          setState(() {
                            _selectedComicGroupIndex = index;
                            _selectedComicChapterIndex = 0;
                          });
                          final newGroup = _comicGroups[index];
                          final newItems = newGroup['items'] as List<Map<String, dynamic>>? ?? [];
                          if (newItems.isNotEmpty) {
                            _loadChapterImages(newItems.first['url'] ?? '', groupName: newGroup['name']);
                          }
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],

          // 章节 Chips 横向列表
          SizedBox(
            height: 36,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final chap = items[index];
                final isSelected = index == _selectedComicChapterIndex;
                final title = chap['title']?.toString() ?? '第 ${index + 1} 话';

                return ActionChip(
                  label: Text(title),
                  backgroundColor: isSelected
                      ? AppColors.primary
                      : (isDark ? AppColors.darkCard : AppColors.lightSurface),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                  ),
                  side: BorderSide(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  onPressed: () {
                    if (_selectedComicChapterIndex != index) {
                      setState(() {
                        _selectedComicChapterIndex = index;
                      });
                      _loadChapterImages(chap['url'] ?? '', groupName: currentGroup['name']);
                    }
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// 打开全屏画廊浏览器
  void _openPhotoViewer(
    int initialIndex, {
    List<String>? images,
    String referer = '',
    Map<String, String>? headers,
  }) {
    final list = images ?? _imageList;
    if (list.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PhotoViewPage(
          imageList: list,
          initialIndex: initialIndex,
          referer: referer,
          headers: headers,
        ),
      ),
    );
  }

  /// 统一处理图片加载状态占位与容错
  Widget? _handleImageLoadState(ExtendedImageState state, bool isDark) {
    switch (state.extendedImageLoadState) {
      case LoadState.loading:
        return Container(
          color: isDark ? AppColors.darkCard : Colors.black12,
          child: const Center(
            child: LoadingIndicator.compact(size: 20),
          ),
        );
      case LoadState.failed:
        return Container(
          color: isDark ? AppColors.darkCard : Colors.black12,
          child: const Center(
            child: Icon(Icons.broken_image_rounded, color: Colors.grey, size: 24),
          ),
        );
      case LoadState.completed:
        return null;
    }
  }

  // ==================== 2. 商业长视频与剧集播放视图 ====================
  Widget _buildVideoView(bool isDark) {
    final displayTitle = _detailTitle?.isNotEmpty == true ? _detailTitle! : widget.title;
    final String currentEpTitle = _episodes.isNotEmpty
        ? (_episodes[_currentEpisodeIndex.clamp(0, _episodes.length - 1)]['title']?.toString() ?? '')
        : '';
    final String fullPlayerTitle = currentEpTitle.isNotEmpty ? '$displayTitle · $currentEpTitle' : displayTitle;

    final referer = widget.rule?.baseUrl ?? '';
    final Map<String, String> videoHeaders = {
      if (referer.isNotEmpty) 'Referer': referer,
      ..._customHeaders,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶部 16:9 吸顶常驻播放器 (安全区顶置，页面滚动时永不离开视线)
        SafeArea(
          bottom: false,
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _videoUrl != null && _videoUrl!.isNotEmpty
                ? AuraPlayer(
                    key: ValueKey(_videoUrl),
                    playUrl: _videoUrl!,
                    title: fullPlayerTitle,
                    coverUrl: _detailCover ?? widget.cover,
                    httpHeaders: videoHeaders,
                    onBack: () => Navigator.maybePop(context),
                    onEnded: () {
                      if (_currentEpisodeIndex < _episodes.length - 1) {
                        _playEpisode(_currentEpisodeIndex + 1);
                      }
                    },
                  )
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: _detailCover ?? widget.cover,
                        fit: BoxFit.cover,
                        httpHeaders: videoHeaders.isNotEmpty ? videoHeaders : null,
                        errorWidget: (_, _, _) => Container(
                          color: Colors.black87,
                          child: const Center(
                            child: Icon(Icons.play_circle_outline, size: 48, color: Colors.white70),
                          ),
                        ),
                      ),
                      // 顶部沉浸式渐变与返回按钮 (未开始播放时也可从播放器顶栏顺畅退出)
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.black87, Colors.transparent],
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                                onPressed: () => Navigator.maybePop(context),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  displayTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_videoUrl == null && _error == null)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              _episodes.isNotEmpty
                                  ? '请从下方选择需要播放的剧集'
                                  : '暂未解析到可直接播放的视频流地址',
                              style: const TextStyle(color: Colors.white, fontSize: 13),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),

        // 2. 下方独立滚动内容区 (包含元数据卡片、商业选集面板、剧照流与相关推荐)
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A. 视频元数据与剧情简介卡片
                _buildVideoMetaCard(isDark, displayTitle),
                const SizedBox(height: 16),

                // B. 商业级长视频选集模块 (多线路切换、横向选集条、正倒序切换、全部选集底部抽屉)
                if (_episodes.isNotEmpty) ...[
                  _buildVideoEpisodesSection(isDark),
                  const SizedBox(height: 20),
                ],

                // C. 剧照与截图横向滑动流
                if (_previews.isNotEmpty) ...[
                  _buildPreviewsSection(isDark),
                  const SizedBox(height: 20),
                ],

                // D. 相关推荐列表
                if (_related.isNotEmpty) ...[
                  _buildRelatedSection(isDark),
                  const SizedBox(height: 12),
                ] else ...[
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 构建视频元数据与剧情简介卡片 (主标题、评分、规则源、题材标签、演职员与折叠简介)
  Widget _buildVideoMetaCard(bool isDark, String title) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 视频主大标题 (采用现代 SemiBold w600 字重，笔画干练利落，彻底告别粗黑沉重感)
        Text(
          title,
          style: TextStyle(
            fontSize: 17.5,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
        ),
        const SizedBox(height: 8),

        // 2. 状态/评分/标签流
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 评分徽标 (若沙箱返回 rating)
            if (_detailRating != null && _detailRating!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(LucideIcons.star, size: 12, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 4),
                    Text(
                      _detailRating!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),

            // 规则源名称标签
            if (widget.rule?.name != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.rule!.name,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),

            // 自定义分类标签 (tags)
            ..._detailTags.map(
              (tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 0.6,
                  ),
                ),
                child: Text(
                  tag,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),

            // 演职员 / 作者 / 导演
            if (_detailAuthor != null && _detailAuthor!.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    LucideIcons.user,
                    size: 13,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    _detailAuthor!,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),

        // 3. 剧情简介 (支持展开与折叠)
        if (_detailDesc != null && _detailDesc!.trim().isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              setState(() {
                _isDescExpanded = !_isDescExpanded;
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _isDescExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                  firstChild: Text(
                    _detailDesc!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  secondChild: Text(
                    _detailDesc!.trim(),
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _isDescExpanded ? '收起简介' : '展开简介',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _isDescExpanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                      size: 13,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 构建商业级长视频选集模块 (多线路切换、横向选集滑动条、正倒序、全部选集底部抽屉)
  Widget _buildVideoEpisodesSection(bool isDark) {
    final int count = _episodes.length;
    // 根据 _isEpisodeReversed 正序/倒序决定展示条目的真实索引序列
    final List<int> displayIndices = List.generate(
      count,
      (i) => _isEpisodeReversed ? (count - 1 - i) : i,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 多播放线路切换栏 (若沙箱返回多个 group)
        if (_videoGroups.length > 1) ...[
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _videoGroups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final g = _videoGroups[index];
                final isSelected = index == _selectedVideoGroupIndex;
                final gName = g['name']?.toString() ?? '线路 ${index + 1}';

                return ChoiceChip(
                  label: Text(gName),
                  selected: isSelected,
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected
                        ? Colors.white
                        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                  onSelected: (val) {
                    if (val && _selectedVideoGroupIndex != index) {
                      _selectVideoGroup(index);
                    }
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 2. 选集头部栏 (标题 + 集数提示 + 倒序按钮 + 全部选集弹窗)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 3.5,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '选集',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '更新至第 $count 集',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
            Row(
              children: [
                // 正序 / 倒序切换
                IconButton(
                  tooltip: _isEpisodeReversed ? '切换为正序' : '切换为倒序',
                  icon: Icon(
                    LucideIcons.arrowUpDown,
                    size: 16,
                    color: _isEpisodeReversed
                        ? AppColors.primary
                        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    setState(() {
                      _isEpisodeReversed = !_isEpisodeReversed;
                    });
                  },
                ),

                // 全部选集网格弹窗
                if (count > 5)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(LucideIcons.layoutGrid, size: 14, color: AppColors.primary),
                    label: const Text(
                      '全部',
                      style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () => _showAllEpisodesSheet(context, isDark),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 3. 商业级横向滑动选集条 (快速点击切换集数)
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final realIndex = displayIndices[i];
              final item = _episodes[realIndex];
              final isCurrent = realIndex == _currentEpisodeIndex;
              final rawTitle = item['title']?.toString().trim() ?? '${realIndex + 1}';

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _playEpisode(realIndex);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  constraints: const BoxConstraints(minWidth: 54),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: isCurrent
                        ? AppColors.primary
                        : (isDark ? AppColors.darkCard : AppColors.lightSurface),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isCurrent
                          ? AppColors.primary
                          : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      width: 0.8,
                    ),
                    boxShadow: isCurrent
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (isCurrent) ...[
                        const Icon(LucideIcons.play, size: 12, color: Colors.white),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        rawTitle,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                          color: isCurrent
                              ? Colors.white
                              : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 呼出全量剧集底部选集面板 (类似腾讯视频/B站的底部抽屉)
  void _showAllEpisodesSheet(BuildContext context, bool isDark) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final count = _episodes.length;
            final isReversed = _isEpisodeReversed;
            final List<int> indices = List.generate(
              count,
              (i) => isReversed ? (count - 1 - i) : i,
            );

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E293B) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  // 顶部把手
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white24 : Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),

                  // 标题栏
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Text(
                              '全部剧集',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '共 $count 集',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            // 正倒序切换
                            IconButton(
                              tooltip: isReversed ? '切换为正序' : '切换为倒序',
                              icon: Icon(
                                LucideIcons.arrowUpDown,
                                size: 16,
                                color: isReversed ? AppColors.primary : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                              ),
                              onPressed: () {
                                HapticFeedback.lightImpact();
                                setSheetState(() {
                                  _isEpisodeReversed = !_isEpisodeReversed;
                                });
                                setState(() {});
                              },
                            ),
                            // 关闭按钮
                            IconButton(
                              icon: Icon(
                                LucideIcons.x,
                                size: 18,
                                color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                              ),
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // 选集方块网格
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 1.3,
                      ),
                      itemCount: count,
                      itemBuilder: (context, i) {
                        final realIndex = indices[i];
                        final item = _episodes[realIndex];
                        final isCurrent = realIndex == _currentEpisodeIndex;
                        final rawTitle = item['title']?.toString().trim() ?? '${realIndex + 1}';

                        return InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            HapticFeedback.lightImpact();
                            Navigator.pop(sheetContext);
                            _playEpisode(realIndex);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            decoration: BoxDecoration(
                              color: isCurrent
                                  ? AppColors.primary
                                  : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isCurrent
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                                width: 0.8,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                rawTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.w500,
                                  color: isCurrent
                                      ? Colors.white
                                      : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ==================== 3. 文本与小说阅读视图 ====================
  Widget _buildNovelView(bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_textContent != null && _textContent!.isNotEmpty) ...[
          AppCard(
            borderRadius: 12,
            child: Text(
              _textContent!,
              style: TextStyle(
                fontSize: 15,
                height: 1.8,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        if (_chapters.isNotEmpty) ...[
          Text(
            '章节目录 (共 ${_chapters.length} 章)',
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _chapters.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            ),
            itemBuilder: (context, index) {
              final chapter = _chapters[index];
              return ListTile(
                title: Text(chapter['title']?.toString() ?? '第 ${index + 1} 章'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                onTap: () {
                  // 点击阅读章节
                },
              );
            },
          ),
        ],
        if (_related.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildRelatedSection(isDark),
        ],
      ],
    );
  }

  /// 剧照 / 截图 / 插图预览横向滑动流
  Widget _buildPreviewsSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 3.5,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '剧照与预览 (${_previews.length})',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 72,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _previews.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final imgUrl = _previews[index];
              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _openPhotoViewer(
                  index,
                  images: _previews,
                  referer: widget.rule?.baseUrl ?? '',
                  headers: _customHeaders.isNotEmpty ? _customHeaders : null,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                      width: 0.6,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(7.4),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: CachedNetworkImage(
                        imageUrl: imgUrl,
                        fit: BoxFit.cover,
                        httpHeaders: {
                          if (widget.rule?.baseUrl != null) 'Referer': widget.rule!.baseUrl,
                          ..._customHeaders,
                        },
                        placeholder: (_, _) => Container(
                          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                        ),
                        errorWidget: (_, _, _) => Container(
                          color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                          child: const Icon(Icons.broken_image_rounded, size: 18, color: Colors.grey),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 相关推荐模块 (宽屏 16:9 双列网格，随着主视口向下纵向滑动)
  Widget _buildRelatedSection(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 头部标题栏
        Row(
          children: [
            Container(
              width: 3.5,
              height: 14,
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '相关推荐',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${_related.length})',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 宽屏两列纵向网格 (采用 AppCard.flat 纯净平铺卡片，紧凑高宽比彻底消除卡片底部冗余空白)
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.34,
          ),
          itemCount: _related.length,
          itemBuilder: (context, index) {
            final item = _related[index];
            final title = item['title']?.toString() ?? '无标题';
            final cover = item['cover']?.toString() ?? '';
            final url = item['url']?.toString() ?? '';
            final badge = item['badge']?.toString().trim() ?? '';
            final desc = item['desc']?.toString().trim() ?? '';

            return AppCard.flat(
              padding: EdgeInsets.zero,
              borderRadius: 10,
              onTap: () {
                if (url.isNotEmpty && widget.rule != null) {
                  HapticFeedback.lightImpact();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RuleDetailPage(
                        rule: widget.rule!,
                        url: url,
                        title: title,
                        cover: cover,
                      ),
                    ),
                  );
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. 宽屏 16:9 封面 (顶部自动受 AppCard.flat 严格防溢出圆角约束)
                  AspectRatio(
                    aspectRatio: 16 / 9,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        cover.isNotEmpty
                            ? CachedNetworkImage(
                                imageUrl: cover,
                                fit: BoxFit.cover,
                                httpHeaders: {
                                  if (widget.rule?.baseUrl != null) 'Referer': widget.rule!.baseUrl,
                                  ..._customHeaders,
                                },
                                placeholder: (_, _) => Container(
                                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                ),
                                errorWidget: (_, _, _) => Container(
                                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                  child: const Icon(Icons.broken_image_rounded, size: 20, color: Colors.grey),
                                ),
                              )
                            : Container(
                                color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                child: const Icon(Icons.movie_outlined, size: 22, color: Colors.grey),
                              ),
                        // 底部渐变暗部 (保证角标与底部边界清晰)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: 24,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.6),
                                ],
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                              ),
                            ),
                          ),
                        ),
                        // 角标 (若有)
                        if (badge.isNotEmpty)
                          Positioned(
                            right: 6,
                            bottom: 4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.75),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                badge,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  // 2. 底部文字信息区 (平铺底色上规整内边距，提升阅读对比度)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                        if (desc.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
