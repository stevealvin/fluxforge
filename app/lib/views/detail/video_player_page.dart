import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/empty_state.dart';

/// 影视播放与剧集选集页面
class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({
    super.key,
    this.title = '视频播放',
    this.playUrl,
    this.coverUrl,
    this.description,
    this.episodes = const [],
  });

  /// 视频或影视标题
  final String title;

  /// 当前视频直链播放地址
  final String? playUrl;

  /// 封面海报地址
  final String? coverUrl;

  /// 剧情或内容简介
  final String? description;

  /// 选集列表
  final List<Map<String, dynamic>> episodes;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  int _currentEpisodeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        elevation: 0,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 播放器容器区域 (16:9)
          _buildPlayerSurface(isDark),

          // 详情信息与剧集分集
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 标题与基本信息
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 8),

                // 简介
                if (widget.description != null && widget.description!.isNotEmpty) ...[
                  Text(
                    widget.description!,
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
                      final name = ep['name']?.toString() ?? '${index + 1}';

                      return ActionChip(
                        label: Text(name),
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
                          setState(() {
                            _currentEpisodeIndex = index;
                          });
                        },
                      );
                    }),
                  ),
                ] else ...[
                  const SizedBox(height: 32),
                  const EmptyState(
                    icon: LucideIcons.playSquare,
                    title: '播放源准备就绪',
                    description: '支持 HLS (m3u8)、MP4 等主流流媒体协议极速解码',
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 视频播放器渲染视口
  Widget _buildPlayerSurface(bool isDark) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(
              Icons.play_circle_fill_rounded,
              size: 64,
              color: AppColors.primary,
            ),
            Positioned(
              bottom: 12,
              left: 16,
              right: 16,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const Text(
                    '00:00 / --:--',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
