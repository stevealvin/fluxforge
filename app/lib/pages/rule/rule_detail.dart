import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:chewie/chewie.dart';
import '../../model/rule.dart';
import 'package:video_player/video_player.dart';

import '../../common/rule_engine.dart';

/// 规则项目详情与播放页
class RuleDetailPage extends StatefulWidget {
  const RuleDetailPage({
    super.key,
    required this.title,
    required this.href,
    required this.cover,
    required this.rule,
  });

  final String title;
  final String href;
  final String cover;
  final Rule rule;

  @override
  State<RuleDetailPage> createState() => _RuleDetailPageState();
}

class _RuleDetailPageState extends State<RuleDetailPage> {
  VideoPlayerController? _videoPlayerController;
  ChewieController? _chewieController;

  List _list = [];
  bool _loading = false;
  String? _videoUrl;
  String? _error;

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await RuleEngine.detail(widget.rule, widget.href);
      if (result is Map) {
        final rawList = result['list'] ?? result['episodes'] ?? [];
        final String? url = result['videoUrl']?.toString() ??
            result['playUrl']?.toString() ??
            result['url']?.toString();

        setState(() {
          _list = rawList is List ? rawList : [];
          _videoUrl = url;
        });

        if (url != null && url.isNotEmpty) {
          await _initPlayer(url);
        }
      }
    } catch (e) {
      debugPrint('Detail load error: $e');
      setState(() {
        _error = '加载详情失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _initPlayer(String url) async {
    try {
      _videoPlayerController?.dispose();
      _chewieController?.dispose();

      final controller = VideoPlayerController.networkUrl(
        Uri.parse(url),
        httpHeaders: {
          'referer': widget.rule.baseUrl,
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
              playbackSpeedButtonText: '播放速度',
              cancelButtonText: '取消',
            ),
          );
        });
      }
    } catch (e) {
      debugPrint('Player init error: $e');
    }
  }

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

  Widget _buildList() {
    if (_list.isEmpty) {
      return const SizedBox.shrink();
    }

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _list.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
      ),
      itemBuilder: (BuildContext context, int index) {
        final item = _list[index];
        final coverUrl = item['cover']?.toString() ?? widget.cover;
        final title = item['title']?.toString() ?? '第 ${index + 1} 集';

        return Card(
          clipBehavior: Clip.hardEdge,
          elevation: 0,
          child: InkWell(
            onTap: () {
              final playUrl = item['url']?.toString() ?? item['videoUrl']?.toString();
              if (playUrl != null && playUrl.isNotEmpty) {
                _initPlayer(playUrl);
              }
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.zero,
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      httpHeaders: {
                        'referer': widget.rule.baseUrl,
                        'user-agent':
                            'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
                      },
                      errorWidget: (_, _, _) => Container(
                        color: Colors.grey.withValues(alpha: 0.2),
                        child: const Icon(Icons.broken_image, color: Colors.grey),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(6),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                                  'referer': widget.rule.baseUrl,
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
                                  color: Colors.black45,
                                  child: const Center(
                                    child: Text(
                                      '未获取到直接播放流，请选择下方选集',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildList(),
                  ),
                ],
              ),
            ),
    );
  }
}
