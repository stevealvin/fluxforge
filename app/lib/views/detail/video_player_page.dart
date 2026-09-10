import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/player/aura_player.dart';

/// 影视播放与剧集选集页面
/// 
/// 接入自研 AuraPlayer 核心引擎，支持分集切换、断点续播与防盗链穿透
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    this.title = '视频播放',
    this.playUrl,
    this.coverUrl,
    this.desc,
    this.episodes = const [],
    this.httpHeaders = const {},
  });

  /// 视频或影视标题
  final String title;

  /// 当前视频直链播放地址
  final String? playUrl;

  /// 封面海报地址
  final String? coverUrl;

  /// 剧情或内容简介
  final String? desc;

  /// 选集列表 (支持 [{'title': '第1集', 'url': 'https://...'}])
  final List<Map<String, dynamic>> episodes;

  /// 防盗链请求头
  final Map<String, String> httpHeaders;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  int _currentEpisodeIndex = 0;
  late String _currentPlayUrl;

  // 默认开源演示流 (当外部未传递播放源时作为降级体验体验 AuraPlayer)
  static const String _fallbackDemoUrl =
      'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4';

  @override
  void initState() {
    super.initState();
    _resolveInitialPlayUrl();
  }

  void _resolveInitialPlayUrl() {
    if (widget.episodes.isNotEmpty) {
      final firstEp = widget.episodes.first;
      _currentPlayUrl = firstEp['url']?.toString() ?? widget.playUrl ?? _fallbackDemoUrl;
    } else {
      _currentPlayUrl = widget.playUrl ?? _fallbackDemoUrl;
    }
  }

  /// 切换选集
  void _switchEpisode(int index) {
    if (index == _currentEpisodeIndex && _currentPlayUrl.isNotEmpty) return;
    setState(() {
      _currentEpisodeIndex = index;
      final ep = widget.episodes[index];
      _currentPlayUrl = ep['url']?.toString() ?? widget.playUrl ?? _fallbackDemoUrl;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentEpTitle = widget.episodes.isNotEmpty
        ? (widget.episodes[_currentEpisodeIndex]['title']?.toString() ?? '第${_currentEpisodeIndex + 1}集')
        : '';
    final displayTitle = currentEpTitle.isNotEmpty ? '${widget.title} - $currentEpTitle' : widget.title;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. 现代化 AuraPlayer 视频播放器视图 (16:9)
            AuraPlayer(
              key: ValueKey(_currentPlayUrl),
              playUrl: _currentPlayUrl,
              title: displayTitle,
              coverUrl: widget.coverUrl,
              httpHeaders: widget.httpHeaders,
              onBack: () => Navigator.maybePop(context),
            ),

            // 2. 详情信息与剧集分集滚动区域
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                children: [
                  // 标题与播放状态
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Aura 极光解码',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 简介
                  if (widget.desc != null && widget.desc!.isNotEmpty) ...[
                    Text(
                      widget.desc!,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 选集列表
                  if (widget.episodes.isNotEmpty) ...[
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
                          '共 ${widget.episodes.length} 集',
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
                      children: List.generate(widget.episodes.length, (index) {
                        final ep = widget.episodes[index];
                        final isSelected = index == _currentEpisodeIndex;
                        final title = ep['title']?.toString() ?? '${index + 1}';

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
                          onPressed: () => _switchEpisode(index),
                        );
                      }),
                    ),
                  ] else ...[
                    const SizedBox(height: 24),
                    const EmptyState(
                      icon: LucideIcons.playSquare,
                      title: '原生硬解就绪',
                      description: '支持 HLS (m3u8)、MP4 等主流流媒体协议极速解码',
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
