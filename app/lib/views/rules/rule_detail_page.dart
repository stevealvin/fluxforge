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

    // 1. 优先检查声明类型是否为图片/相册，或返回的是纯数组
    if (declaredType == 'image' ||
        declaredType == 'picture' ||
        declaredType == 'photo' ||
        declaredType == 'gallery') {
      _extractImages(result);
      _mediaType = MediaType.image;
      return;
    }

    // 2. 检查声明类型是否为小说/文本
    if (declaredType == 'novel' || declaredType == 'book' || declaredType == 'text') {
      _extractNovel(result);
      _mediaType = MediaType.novel;
      return;
    }

    // 3. 自适应数据结构推断 (当 declaredType 为空或通用时的智能兜底)
    if (result is List) {
      // 若列表中的元素是图片链接字符串，自动切为图片图集模式
      if (result.isNotEmpty && _looksLikeImageUrl(result.first.toString())) {
        _extractImages(result);
        _mediaType = MediaType.image;
        return;
      }
      // 否则作为多剧集视频列表处理
      _extractEpisodesFromList(result);
      _mediaType = MediaType.video;
      return;
    }

    if (result is Map) {
      // 检查是否包含显式图片字段
      if (result.containsKey('images') ||
          result.containsKey('photos') ||
          result.containsKey('pics') ||
          result.containsKey('picList')) {
        final rawImgs =
            result['images'] ?? result['photos'] ?? result['pics'] ?? result['picList'];
        if (rawImgs is List) {
          _extractImages(rawImgs);
          _mediaType = MediaType.image;
          return;
        }
      }

      // 检查是否包含文本/小说正文字段
      if (result.containsKey('content') || result.containsKey('chapters')) {
        _extractNovel(result);
        _mediaType = MediaType.novel;
        return;
      }

      // 检查视频播放地址或剧集
      final String? videoUrl = result['videoUrl']?.toString() ??
          result['playUrl']?.toString() ??
          result['url']?.toString();

      final rawList = result['list'] ?? result['episodes'];
      if (rawList is List) {
        _extractEpisodesFromList(rawList);
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

    // 默认回退为视频模式尝试渲染
    _mediaType = MediaType.video;
  }

  /// 从返回数据中提取图集列表
  void _extractImages(dynamic rawData) {
    final List<String> list = [];
    if (rawData is List) {
      for (final item in rawData) {
        if (item is String && item.isNotEmpty) {
          list.add(item);
        } else if (item is Map) {
          final url = item['src'] ??
              item['url'] ??
              item['cover'] ??
              item['image'] ??
              item['data-original'];
          if (url != null && url.toString().isNotEmpty) {
            list.add(url.toString());
          }
        }
      }
    } else if (rawData is Map) {
      final innerList = rawData['images'] ??
          rawData['photos'] ??
          rawData['pics'] ??
          rawData['picList'] ??
          rawData['list'];
      if (innerList is List) {
        for (final item in innerList) {
          if (item is String && item.isNotEmpty) {
            list.add(item);
          } else if (item is Map) {
            final url = item['src'] ??
                item['url'] ??
                item['cover'] ??
                item['image'] ??
                item['data-original'];
            if (url != null && url.toString().isNotEmpty) {
              list.add(url.toString());
            }
          }
        }
      }
    }
    _imageList = list;
  }

  /// 从返回数据中提取剧集列表
  void _extractEpisodesFromList(List rawList) {
    final List<Map<String, dynamic>> episodes = [];
    for (int i = 0; i < rawList.length; i++) {
      final item = rawList[i];
      if (item is Map) {
        episodes.add(Map<String, dynamic>.from(item));
      } else if (item is String) {
        episodes.add({
          'title': '第 ${i + 1} 集',
          'url': item,
        });
      }
    }
    _episodes = episodes;
  }

  /// 提取小说/文本内容
  void _extractNovel(dynamic rawData) {
    if (rawData is Map) {
      _textContent = rawData['content']?.toString();
      final chs = rawData['chapters'];
      if (chs is List) {
        _chapters = chs.map((e) => Map<String, dynamic>.from(e is Map ? e : {'title': e.toString()})).toList();
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
      ],
    );
  }
}
