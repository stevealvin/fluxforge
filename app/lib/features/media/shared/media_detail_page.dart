import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/shared/widgets/app_empty_state.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';
import 'package:fluxforge/features/media/comic/comic_detail_view.dart';
import 'package:fluxforge/domain/media/media.dart';
import 'package:fluxforge/features/media/novel/novel_detail_view.dart';
import 'package:fluxforge/features/media/shared/media_download_actions.dart';
import 'package:fluxforge/features/media/shared/media_download_sheet.dart';
import 'package:fluxforge/features/media/shared/media_favorite_actions.dart';
import 'package:fluxforge/features/media/shared/media_request_headers.dart';
import 'package:fluxforge/features/media/video/video_detail_view.dart';

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

    // 按 baseUrl 反查负责该地址的规则（判据见 Rule.matchesUrl）。
    // 匹配不到就保持 null 并如实报「未指定对应解析规则」—— 拿错规则会让 baseUrl 全错，
    // 解析结果只会更难排查。
    _activeRule ??= ruleService.matchByUrl(widget.url);

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
    if (result == null) {
      // 无数据必须显式上报：静默返回会让页面停在"只有封面和标题"的空壳上，
      // 用户既看不到数据、也看不到原因。
      _error = '详情解析未返回数据（规则可能未实现详情解析，或源站返回为空）';
      return;
    }

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

      // 防盗链兜底：Referer 取**规则 baseUrl（站点根）**，与发现页同口径，并补齐默认 UA。
      //
      // 为什么不是详情页 URL：图片 / 视频直链由 ExtendedImage / 播放器**直连**，不经规则
      // 引擎；图床校验 Referer 时只认站点根，而详情页 URL 是规则内部的页面/接口地址
      // （可能是深层路径甚至 API），会被判成盗链 → 403。实测该图床
      // `curl -H "Referer: <站点根>"` 能下载，正是发现页一直在用的那个值。
      parsedHeaders = MediaRequestHeaders.withDefaults(
        parsedHeaders,
        referer: MediaRequestHeaders.resolveReferer(
          ruleBaseUrl: _activeRule?.baseUrl,
          pageUrl: widget.url,
        ),
      );

      if (result['previews'] is List) {
        parsedPreviews = (result['previews'] as List)
            .map((e) => _normalizeUrl(e.toString()))
            .where((s) => s.isNotEmpty)
            .toList();
      }

      if (result['related'] is List) {
        for (final m in result['related']) {
          if (m is Map) {
            parsedRelated.add(
              MediaRelatedItem.fromMap(
                Map<String, dynamic>.from(m),
                rule: _activeRule,
              ),
            );
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
            final ep = MediaEpisode.fromMap(
              Map<String, dynamic>.from(it),
              fallbackIndex: i + 1,
            );
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

    MediaType determinedType = MediaType.fromString(
      widget.type ?? _activeRule?.type,
    );
    if (determinedType == MediaType.unknown) {
      if (imageList.isNotEmpty || comicGroups.isNotEmpty) {
        determinedType = MediaType.comic;
      } else if (textContent != null && textContent.length > 80) {
        determinedType = MediaType.novel;
      } else if (playUrl != null ||
          items.isNotEmpty ||
          videoGroups.isNotEmpty) {
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

    // 解析成功但没有任何可读内容 → 同样明确上报，
    // 便于区分"规则详情字段没写对"与"源站改版"。
    final hasReadableContent =
        _data.items.isNotEmpty ||
        _data.imageList.isNotEmpty ||
        _data.previews.isNotEmpty ||
        _data.comicGroups.any((g) => g.items.isNotEmpty) ||
        _data.videoGroups.any((g) => g.items.isNotEmpty) ||
        (_data.textContent?.trim().isNotEmpty ?? false) ||
        (_data.playUrl?.trim().isNotEmpty ?? false);
    if (!hasReadableContent) {
      _error = '已调度解析，但规则未返回章节 / 图片 / 正文（可检查规则的详情字段，或源站是否已改版）';
    }
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
      return Uri.parse(base.endsWith('/') ? base : '$base/')
          .resolve(u)
          .toString();
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

  /// 离线下载任务的唯一键（与动作层同源，保证「刚发起的任务查得到」）
  String get _downloadTaskKey =>
      MediaDownloadActions.taskKey(_data, widget.title, rule: _activeRule);

  /// 顶部栏下载入口：底部弹出下载面板（选集下载 + 全部下载）
  Future<void> _openDownloadSheet() {
    final units = MediaDownloadActions.unitsOf(_data);
    final urls = MediaDownloadActions.unitUrls(_data);
    return showMediaDownloadSheet(
      context,
      title: _data.title.isNotEmpty ? _data.title : widget.title,
      bookId: _downloadTaskKey,
      unitLabel: switch (_data.mediaType) {
        MediaType.novel => '章',
        MediaType.comic => '页',
        _ => '集',
      },
      tasks: downloadService.tasksNotifier,
      taskOf: () => downloadService.taskOf(_downloadTaskKey),
      onAction: (task) => MediaDownloadActions.handleTap(
        data: _data,
        rule: _activeRule,
        task: task,
        fallbackTitle: widget.title,
        fallbackCover: widget.cover,
      ),
      units: units,
      onDownloadSelection: (selection) =>
          MediaDownloadActions.downloadSelection(
            data: _data,
            rule: _activeRule,
            selection: selection,
            fallbackTitle: widget.title,
            fallbackCover: widget.cover,
          ),
      // 大小预估：只对能直接问到长度的直链有效（视频 mp4 等），
      // HLS 与「需再解析一层」的漫画章节返回 null —— 面板会显示「大小未知」
      probeUnitSizes: urls.isEmpty
          ? null
          : () => downloadService.probeUnitSizes(
              urls,
              headers: _data.customHeaders,
            ),
      onOpenDownloads: () => context.pushDownloads(),
    );
  }

  /// 收藏 / 取消收藏：写入侧唯一入口（见 [MediaFavoriteActions]）
  Future<void> _toggleFavorite() async {
    HapticFeedback.lightImpact();
    final message = await MediaFavoriteActions.toggle(
      data: _data,
      rule: _activeRule,
      fallbackTitle: widget.title,
      fallbackCover: widget.cover,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1600),
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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
          // 收藏入口：与「离线下载」并列，图标随收藏状态切换
          if (!_loading && _error == null)
            ValueListenableBuilder<List<FavoriteItem>>(
              valueListenable: favoriteService.favoritesNotifier,
              builder: (context, _, _) {
                final favorited = MediaFavoriteActions.isFavorited(
                  _data,
                  widget.title,
                  rule: _activeRule,
                );
                return IconButton(
                  tooltip: favorited ? '取消收藏' : '收藏并开启追更',
                  icon: Icon(
                    favorited ? Ionicons.bookmark : Ionicons.bookmarkOutline,
                    color: favorited
                        ? AppColors.primary
                        : (isDark
                              ? Colors.white70
                              : AppColors.lightTextSecondary),
                    size: 20,
                  ),
                  onPressed: _toggleFavorite,
                );
              },
            ),
          // 离线下载入口：顶部栏右上角，点击后底部弹出下载面板
          if (!_loading && _error == null)
            ValueListenableBuilder<List<DownloadTask>>(
              valueListenable: downloadService.tasksNotifier,
              builder: (context, _, _) {
                final task = downloadService.taskOf(_downloadTaskKey);
                final isActive = task != null && task.isActive;
                final isDone = task?.isFinished ?? false;
                return IconButton(
                  tooltip: isDone
                      ? '已下载全本，点击查看'
                      : (isActive ? '下载中，点击查看进度' : '离线下载'),
                  icon: Icon(
                    isDone
                        ? Ionicons.cloudDoneOutline
                        : Ionicons.cloudDownloadOutline,
                    color: isDone || isActive
                        ? AppColors.primary
                        : (isDark
                              ? Colors.white70
                              : AppColors.lightTextSecondary),
                    size: 20,
                  ),
                  onPressed: _openDownloadSheet,
                );
              },
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
    if (_data.mediaType == MediaType.video ||
        _data.mediaType == MediaType.unknown) {
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
