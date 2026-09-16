import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_loading.dart';
import 'comic/comic_detail_view.dart';
import '../../models/media.dart';
import 'novel/novel_detail_view.dart';
import 'video/video_detail_view.dart';

/// 跨媒体统一详情调度容器页面 (MediaDetailPage)
class MediaDetailPage extends StatefulWidget {
  const MediaDetailPage({
    super.key,
    this.title = '',
    this.url = '',
    this.cover = '',
    this.rule,
    this.type,
    this.initialItem,
  });

  final String title;
  final String url;
  final String cover;
  final Rule? rule;
  final String? type;
  final Map<String, dynamic>? initialItem;

  @override
  State<MediaDetailPage> createState() => _MediaDetailPageState();
}

class _MediaDetailPageState extends State<MediaDetailPage> {
  bool _loading = true;
  String? _error;
  late MediaDetailData _data;
  Rule? _activeRule;

  @override
  void initState() {
    super.initState();
    _activeRule = widget.rule;
    _data = MediaDetailData(
      title: widget.title,
      url: widget.url,
      cover: widget.cover,
      mediaType: MediaType.fromString(widget.type ?? widget.rule?.type),
    );
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    if (_activeRule == null && ruleService.rules.isNotEmpty) {
      try {
        _activeRule = ruleService.rules.firstWhere(
          (r) => widget.url.isNotEmpty && r.baseUrl.isNotEmpty && widget.url.contains(Uri.parse(r.baseUrl).host),
          orElse: () => ruleService.rules.first,
        );
      } catch (_) {}
    }

    if (_activeRule == null) {
      if (widget.initialItem != null) {
        _parseSandboxResult(widget.initialItem!);
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _error = '未指定对应解析规则，无法调度沙箱执行';
        _loading = false;
      });
      return;
    }

    try {
      final itemParam = {
        'title': widget.title,
        'url': widget.url,
        'cover': widget.cover,
        if (widget.initialItem != null) ...widget.initialItem!,
      };

      final result = await RuleEngine.detail(
        _activeRule!,
        widget.url,
        item: itemParam,
      );

      _parseSandboxResult(result);
    } catch (e) {
      debugPrint('【媒体详情】沙箱调度失败: $e');
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

  void _parseSandboxResult(dynamic result) {
    if (result == null) return;

    String parsedTitle = widget.title;
    String parsedCover = widget.cover;
    String? parsedDesc;
    String? parsedAuthor;
    String? parsedRating;
    String? parsedUpdateTime;
    List<String> parsedTags = [];
    Map<String, String> parsedHeaders = {};
    List<String> parsedPreviews = [];
    List<MediaRelatedItem> parsedRelated = [];

    List<MediaGroup> videoGroups = [];
    List<MediaEpisode> items = [];
    List<String> imageList = [];
    List<MediaGroup> comicGroups = [];
    List<MediaEpisode> chapters = [];
    String? textContent;
    String? playUrl;

    if (result is Map) {
      parsedTitle = result['title']?.toString() ?? widget.title;
      parsedCover = result['cover']?.toString() ?? widget.cover;
      parsedDesc = result['desc']?.toString();
      parsedAuthor = result['author']?.toString();
      parsedRating = result['rating']?.toString();
      parsedUpdateTime = result['updateTime']?.toString();

      if (result['tags'] is List) {
        parsedTags = (result['tags'] as List)
            .map((e) => e.toString().trim())
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (result['headers'] is Map) {
        parsedHeaders = (result['headers'] as Map).map(
          (k, v) => MapEntry(k.toString(), v.toString()),
        );
      }

      // 智能识别并注入默认防盗链 Referer：若规则未显式声明，默认回退注入详情页 URL 或规则 baseUrl
      final hasReferer = parsedHeaders.keys.any((k) => k.toLowerCase() == 'referer');
      if (!hasReferer) {
        if (widget.url.isNotEmpty) {
          parsedHeaders['Referer'] = widget.url;
        } else if (_activeRule?.baseUrl.isNotEmpty ?? false) {
          parsedHeaders['Referer'] = _activeRule!.baseUrl;
        }
      }

      if (result['previews'] is List) {
        parsedPreviews = (result['previews'] as List)
            .map((e) => _normalizeUrl(e.toString()))
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (result['related'] is List) {
        for (final m in result['related']) {
          if (m is Map) {
            parsedRelated.add(MediaRelatedItem.fromMap(Map<String, dynamic>.from(m), rule: _activeRule));
          }
        }
      }

      if (result['groups'] is List) {
        for (final g in result['groups']) {
          if (g is Map) {
            final grp = MediaGroup.fromMap(Map<String, dynamic>.from(g));
            videoGroups.add(grp);
            comicGroups.add(grp);
          }
        }
      }

      if (result['items'] is List) {
        final rawItems = result['items'] as List;
        for (int i = 0; i < rawItems.length; i++) {
          final it = rawItems[i];
          if (it is Map) {
            final ep = MediaEpisode.fromMap(Map<String, dynamic>.from(it), fallbackIndex: i + 1);
            items.add(ep);
            chapters.add(ep);
          } else if (it is String) {
            final u = it.trim();
            if (u.isNotEmpty) {
              final ep = MediaEpisode(title: '第 ${i + 1} 话', url: u);
              items.add(ep);
              chapters.add(ep);
              imageList.add(_normalizeUrl(u));
            }
          }
        }
      }

      playUrl = result['playUrl']?.toString();
      textContent = result['content']?.toString();
    }

    MediaType determinedType = MediaType.fromString(widget.type ?? _activeRule?.type);
    if (determinedType == MediaType.unknown) {
      if (imageList.isNotEmpty || comicGroups.isNotEmpty) {
        determinedType = MediaType.comic;
      } else if (textContent != null && textContent.length > 80) {
        determinedType = MediaType.novel;
      } else if (playUrl != null || items.isNotEmpty || videoGroups.isNotEmpty) {
        determinedType = MediaType.video;
      } else {
        determinedType = MediaType.video;
      }
    }

    _data = MediaDetailData(
      title: parsedTitle,
      url: widget.url,
      cover: _normalizeUrl(parsedCover),
      desc: parsedDesc,
      author: parsedAuthor,
      rating: parsedRating,
      updateTime: parsedUpdateTime,
      tags: parsedTags,
      customHeaders: parsedHeaders,
      mediaType: determinedType,
      items: items,
      playUrl: playUrl,
      videoGroups: videoGroups,
      imageList: imageList,
      comicGroups: comicGroups,
      textContent: textContent,
      chapters: chapters,
      previews: parsedPreviews,
      related: parsedRelated,
    );
  }

  String _normalizeUrl(String raw) {
    final u = raw.trim();
    if (u.isEmpty) return '';
    if (u.startsWith('http://') || u.startsWith('https://')) return u;
    if (u.startsWith('//')) return 'https:$u';
    final base = _activeRule?.baseUrl ?? '';
    if (base.isEmpty) return u;
    try {
      final baseUri = Uri.parse(base);
      if (u.startsWith('/')) {
        return '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ":${baseUri.port}" : ""}$u';
      }
      return Uri.parse(base.endsWith('/') ? base : '$base/').resolve(u).toString();
    } catch (_) {
      return u;
    }
  }

  void _handleRelatedItemTap(MediaRelatedItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailPage(
          title: item.title,
          url: item.url,
          cover: item.cover,
          rule: item.rule ?? _activeRule,
          type: item.type,
        ),
      ),
    );
  }

  /// 自定义沉浸式流光顶栏 (纯净无缝吸顶设计，移除与视频画面之间的突兀底边框)
  Widget _buildTopBar(bool isDark) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(
        top: topPadding > 0 ? topPadding + 4 : 8,
        bottom: 8,
        left: 6,
        right: 12,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : AppColors.lightBg,
        // 彻底移除与下方视频播放器之间的分割线，实现纯净浑然一体的视觉过渡
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: isDark ? Colors.white : AppColors.lightTextPrimary,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Text(
              _data.title.isNotEmpty ? _data.title : widget.title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: Icon(
              Ionicons.refreshOutline,
              color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
              size: 18,
            ),
            onPressed: _loadDetail,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildTopBar(isDark),
            Expanded(child: _buildBody(isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading) {
      return const Center(child: AppLoading(message: '正在调度沙箱解析媒体元数据...'));
    }

    // 若沙箱解析发生异常，彻底清除默认数据兜底，直接展示错误详情与重试按钮
    if (_error != null) {
      return Center(
        child: AppEmptyState(
          icon: Ionicons.alertCircleOutline,
          title: '详情解析异常',
          description: _error!,
          actionText: '重试解析',
          onAction: _loadDetail,
        ),
      );
    }

    // 视频类型：顶部吸顶常驻播放器，下方独立滚动流 (享受商业级吸顶视听体验)
    if (_data.mediaType == MediaType.video || _data.mediaType == MediaType.unknown) {
      return VideoDetailView(
        data: _data,
        rule: _activeRule,
        fallbackTitle: widget.title,
        fallbackCover: widget.cover,
        onRelatedItemTap: _handleRelatedItemTap,
      );
    }

    Widget content;
    switch (_data.mediaType) {
      case MediaType.comic:
        content = ComicDetailView(
          data: _data,
          rule: _activeRule,
          fallbackTitle: widget.title,
          fallbackCover: widget.cover,
          onRelatedItemTap: _handleRelatedItemTap,
        );
        break;
      case MediaType.novel:
        content = NovelDetailView(
          data: _data,
          rule: _activeRule,
          fallbackTitle: widget.title,
          fallbackCover: widget.cover,
          onRelatedItemTap: _handleRelatedItemTap,
        );
        break;
      default:
        content = const SizedBox.shrink();
        break;
    }

    // 漫画与小说类型：整页自由长滑卷轴
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: content,
    );
  }
}
