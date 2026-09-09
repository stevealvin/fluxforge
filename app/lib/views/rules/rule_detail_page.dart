import 'package:cached_network_image/cached_network_image.dart';
import 'package:chewie/chewie.dart';
import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
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
/// 分别渲染专业视频播放器（Chewie/VideoPlayer）、高清图集瀑布流网格或小说章节阅读器。
class RuleDetailPage extends StatefulWidget {
  const RuleDetailPage({
    super.key,
    required this.title,
    required this.href,
    required this.cover,
    this.rule,
  });

  /// 内容标题
  final String title;

  /// 详情或内容直链链接
  final String href;

  /// 封面海报
  final String cover;

  /// 关联的解析规则模型
  final Rule? rule;

  @override
  State<RuleDetailPage> createState() => _RuleDetailPageState();
}

class _RuleDetailPageState extends State<RuleDetailPage> {
  // 视频播放器控制器
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  // 状态机变量
  bool _loading = true;
  String? _error;
  MediaType _mediaType = MediaType.unknown;

  // 视频相关数据
  String? _videoUrl;
  List<Map<String, dynamic>> _episodes = [];
  int _currentEpisodeIndex = 0;

  // 图片相关数据
  List<String> _imageList = [];

  // 文本/小说相关数据
  String? _textContent;
  List<Map<String, dynamic>> _chapters = [];

  // 扩展展示数据 (剧照/截图预览与相关推荐)
  List<String> _previews = [];
  List<Map<String, dynamic>> _related = [];

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  @override
  void dispose() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    super.dispose();
  }

  /// 加载并执行规则详情解析沙箱
  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
      _previews = [];
      _related = [];
    });

    if (widget.rule == null) {
      setState(() {
        _error = '未指定解析规则，无法调度沙箱执行';
        _loading = false;
      });
      return;
    }

    try {
      final result = await RuleEngine.detail(widget.rule!, widget.href);
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

  /// 智能解析沙箱返回结果并推断媒体类型
  void _parseResult(dynamic result) {
    final declaredType = widget.rule?.type.toLowerCase() ?? '';

    // 1. 图片/相册类型
    if (declaredType == 'image' ||
        declaredType == 'picture' ||
        declaredType == 'photo' ||
        declaredType == 'gallery') {
      _extractImages(result);
      _mediaType = MediaType.image;
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
      if (result.isNotEmpty && _looksLikeImageUrl(result.first.toString())) {
        _extractImages(result);
        _mediaType = MediaType.image;
        return;
      }
      _extractEpisodesFromList(result);
      _mediaType = MediaType.video;
      return;
    }

    if (result is Map) {
      // 提取预览图与推荐列表
      if (result['previews'] is List) {
        _previews = (result['previews'] as List)
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty)
            .toList();
      }
      if (result['related'] is List) {
        _related = (result['related'] as List)
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
      }

      // 统一提取 items
      final rawItems = result['items'];

      // 检查 items 中的元素是否为图片 URL
      if (rawItems is List &&
          rawItems.isNotEmpty &&
          _looksLikeImageUrl(rawItems.first is Map
              ? (rawItems.first['url'] ?? '').toString()
              : rawItems.first.toString())) {
        _extractImages(rawItems);
        _mediaType = MediaType.image;
        return;
      }

      // 检查小说正文
      if (result.containsKey('content')) {
        _extractNovel(result);
        _mediaType = MediaType.novel;
        return;
      }

      // 检查视频播放地址或剧集 items
      final String? videoUrl = result['playUrl']?.toString();

      if (rawItems is List) {
        _extractEpisodesFromList(rawItems);
      }

      if (videoUrl != null && videoUrl.isNotEmpty) {
        _videoUrl = videoUrl;
        _mediaType = MediaType.video;
        _initVideoPlayer(videoUrl);
        return;
      }

      if (_episodes.isNotEmpty) {
        _mediaType = MediaType.video;
        final firstUrl = _episodes.first['url']?.toString();
        if (firstUrl != null && firstUrl.isNotEmpty) {
          _videoUrl = firstUrl;
          _initVideoPlayer(firstUrl);
        }
        return;
      }
    }

    // 默认作为视频模式处理
    _mediaType = MediaType.video;
  }

  /// 从返回数据中提取图集列表 (统一读取 items 数组及 item.url)
  void _extractImages(dynamic rawData) {
    final List<String> list = [];
    final List? itemsList = rawData is List
        ? rawData
        : (rawData is Map && rawData['items'] is List ? rawData['items'] as List : null);

    if (itemsList != null) {
      for (final item in itemsList) {
        if (item is String && item.isNotEmpty) {
          list.add(item);
        } else if (item is Map) {
          final url = item['url'];
          if (url != null && url.toString().isNotEmpty) {
            list.add(url.toString());
          }
        }
      }
    }
    _imageList = list;
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

  /// 判断链接字符串是否可能是图片扩展名
  bool _looksLikeImageUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('.jpg') ||
        lower.contains('.jpeg') ||
        lower.contains('.png') ||
        lower.contains('.webp') ||
        lower.contains('.gif');
  }

  /// 初始化高性能视频播放器
  Future<void> _initVideoPlayer(String url) async {
    try {
      _videoPlayerController?.dispose();
      _chewieController?.dispose();

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'referer': widget.rule?.baseUrl ?? '',
          'user-agent':
              'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
        },
      );
      await controller.initialize();

      if (mounted) {
        setState(() {
          _videoPlayerController = controller;
          _chewieController = ChewieController(
            videoPlayerController: controller,
            autoPlay: true,
            looping: false,
            optionsTranslation: OptionsTranslation(
              playbackSpeedButtonText: '播放倍速',
              cancelButtonText: '取消',
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('【视频播放器】初始化失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_mediaType == MediaType.image && _imageList.isNotEmpty)
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
    if (_imageList.isEmpty) {
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

    final referer = widget.rule?.baseUrl ?? '';

    return GridView.builder(
      padding: const EdgeInsets.all(8),
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
          onTap: () {
            // 点击打开全屏沉浸式缩放手势画廊
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PhotoViewPage(
                  imageList: _imageList,
                  initialIndex: index,
                  referer: referer,
                ),
              ),
            );
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ExtendedImage.network(
              imgUrl,
              cache: true,
              fit: BoxFit.cover,
              headers: referer.isNotEmpty ? {'Referer': referer} : null,
              loadStateChanged: (state) {
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
                      child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                    );
                  case LoadState.completed:
                    return null;
                }
              },
            ),
          ),
        );
      },
    );
  }

  // ==================== 2. 视频与剧集播放视图 ====================
  Widget _buildVideoView(bool isDark) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部 16:9 播放视口
          AspectRatio(
            aspectRatio: 16 / 9,
            child: _chewieController != null &&
                    _chewieController!.videoPlayerController.value.isInitialized
                ? Chewie(controller: _chewieController!)
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedNetworkImage(
                        imageUrl: widget.cover,
                        fit: BoxFit.cover,
                        httpHeaders: {
                          'referer': widget.rule?.baseUrl ?? '',
                          'user-agent':
                              'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
                        },
                        errorWidget: (_, _, _) => Container(
                          color: Colors.black87,
                          child: const Center(
                            child: Icon(Icons.play_circle_outline, size: 48, color: Colors.white70),
                          ),
                        ),
                      ),
                      if (_videoUrl == null && _error == null)
                        Container(
                          color: Colors.black54,
                          child: Center(
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

          // 下方选集列表
          if (_episodes.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '选集列表',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                      Text(
                        '共 ${_episodes.length} 集',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List.generate(_episodes.length, (index) {
                      final item = _episodes[index];
                      final isSelected = index == _currentEpisodeIndex;
                      final epTitle = item['title']?.toString() ?? '第 ${index + 1} 集';
                      final playUrl = item['url']?.toString() ?? item['videoUrl']?.toString();

                      return ActionChip(
                        label: Text(epTitle),
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
                          if (playUrl != null && playUrl.isNotEmpty) {
                            setState(() {
                              _currentEpisodeIndex = index;
                              _videoUrl = playUrl;
                            });
                            _initVideoPlayer(playUrl);
                          }
                        },
                      );
                    }),
                  ),
                ],
              ),
            ),
          ],

          // 剧照 / 预览图流
          if (_previews.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildPreviewsSection(isDark),
            ),
          ],

          // 相关推荐
          if (_related.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: _buildRelatedSection(isDark),
            ),
          ],
        ],
      ),
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
              fontSize: 16,
              fontWeight: FontWeight.bold,
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
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 110,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _previews.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final imgUrl = _previews[index];
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: AspectRatio(
                  aspectRatio: 16 / 10,
                  child: CachedNetworkImage(
                    imageUrl: imgUrl,
                    fit: BoxFit.cover,
                    httpHeaders: {
                      if (widget.rule?.baseUrl != null) 'Referer': widget.rule!.baseUrl,
                    },
                    placeholder: (_, _) => Container(
                      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                    ),
                    errorWidget: (_, _, _) => Container(
                      color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                      child: const Icon(Icons.broken_image_rounded, size: 20, color: Colors.grey),
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

  /// 相关推荐卡片横向滑动流
  Widget _buildRelatedSection(bool isDark) {
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
              '相关推荐 (${_related.length})',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 155,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _related.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final item = _related[index];
              final title = item['title']?.toString() ?? '无标题';
              final cover = item['cover']?.toString() ?? '';
              final url = item['url']?.toString() ?? '';

              return GestureDetector(
                onTap: () {
                  if (url.isNotEmpty && widget.rule != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RuleDetailPage(
                          rule: widget.rule!,
                          href: url,
                          title: title,
                          cover: cover,
                        ),
                      ),
                    );
                  }
                },
                child: SizedBox(
                  width: 95,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: AspectRatio(
                          aspectRatio: 3 / 4,
                          child: cover.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: cover,
                                  fit: BoxFit.cover,
                                  httpHeaders: {
                                    if (widget.rule?.baseUrl != null) 'Referer': widget.rule!.baseUrl,
                                  },
                                  errorWidget: (_, _, _) => Container(
                                    color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                    child: const Icon(Icons.broken_image_rounded, size: 20, color: Colors.grey),
                                  ),
                                )
                              : Container(
                                  color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
                                  child: const Icon(Icons.movie_outlined, size: 20, color: Colors.grey),
                                ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
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
}
