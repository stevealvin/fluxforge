import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/shared/widgets/player/aura_player.dart';
import 'package:fluxforge/shared/widgets/player/player_preferences.dart';
import 'package:fluxforge/features/media/shared/media_history_registrar.dart';
import 'package:fluxforge/features/media/shared/media_related_grid.dart';
import 'package:fluxforge/features/media/video/widgets/episode_picker_sheet.dart';
import 'package:fluxforge/features/media/video/widgets/video_episodes_section.dart';
import 'package:fluxforge/features/media/video/widgets/video_meta_section.dart';
import 'package:fluxforge/features/media/video/widgets/video_previews_section.dart';
import 'package:fluxforge/domain/media/media.dart';

/// 视频媒介业务专属详情视图
///
/// 遵循专业流媒体交互标准：吸顶常驻播放器、纯净平铺元数据、横向快速选集滑动条、全量剧集半屏抽屉与宽屏推荐
///
/// 页面只负责「播放生命周期 + 装配」：
/// - 播放状态（当前线路 / 集号 / 直链 / 全屏休眠）与消费记录由页面持有；
/// - 元数据、选集、剧照三个区块见 `widgets/`，它们是纯展示 + 语义化事件上抛；
/// - 全量选集面板见 [EpisodePickerSheet]。
class VideoDetailView extends StatefulWidget {
  const VideoDetailView({
    super.key,
    required this.data,
    this.rule,
    this.fallbackTitle = '',
    this.fallbackCover = '',
    this.onRelatedItemTap,
    this.onShareTap,
  });

  /// 结构化详情数据
  final MediaDetailData data;

  /// 所属解析规则
  final Rule? rule;

  /// 兜底标题
  final String fallbackTitle;

  /// 兜底封面
  final String fallbackCover;

  /// 相关推荐点击回调
  final void Function(MediaRelatedItem item)? onRelatedItemTap;

  /// 分享按钮点击回调
  final VoidCallback? onShareTap;

  @override
  State<VideoDetailView> createState() => _VideoDetailViewState();
}

class _VideoDetailViewState extends State<VideoDetailView> {
  /// 全局播放器受控 Key，业务代码通过该 Key 主动控制视频播放与暂停
  final GlobalKey<AuraPlayerState> _playerKey = GlobalKey<AuraPlayerState>();

  /// 供业务父组件主动暂停当前正在播放的视频
  void pauseVideo() {
    _playerKey.currentState?.pause();
  }

  int _selectedGroupIndex = 0;
  int _currentEpisodeIndex = 0;

  /// 是否处于全屏独占路由中
  ///
  /// 小屏播放器不能卸载（控制器由它持有），只能切为不活动状态，见 [AuraPlayer.active]。
  bool _isFullScreen = false;
  bool _isReversed = false;
  String? _activePlayUrl;

  /// 当前媒体的唯一消费标识 (优先详情页 URL，兜底标题)
  String get _mediaId {
    if (widget.data.url.isNotEmpty) return widget.data.url;
    if (widget.fallbackTitle.isNotEmpty) return widget.fallbackTitle;
    return _displayTitle;
  }

  /// 当前集数标题 (用于消费记录与「继续观看」展示)
  String get _currentEpisodeTitle {
    final episodes = _currentGroupEpisodes;
    if (episodes.isEmpty) return '';
    final idx = _currentEpisodeIndex.clamp(0, episodes.length - 1);
    return episodes[idx].title;
  }

  /// 计算本次播放的断点起播位置
  Duration get _resumePosition {
    // 1. 用户显式关闭续播 → 始终从头开始
    if (appService.settings.resumeBehavior == ResumeBehavior.disabled) {
      return Duration.zero;
    }
    final record = playHistoryService.getById(_mediaId);
    if (record == null) return Duration.zero;
    // 2. 非同一集不复用播放进度
    if (record.episodeIndex != _currentEpisodeIndex) return Duration.zero;
    if (record.positionSeconds <= 5) return Duration.zero;
    // 3. 已接近片尾（剩余不足 10 秒）视为看完，从头播放
    if (record.durationSeconds > 0 &&
        record.positionSeconds >= record.durationSeconds - 10) {
      return Duration.zero;
    }
    return Duration(seconds: record.positionSeconds);
  }

  /// 是否采用「直接跳转」静默续播策略
  bool get _autoResume =>
      appService.settings.resumeBehavior == ResumeBehavior.auto;

  /// 获取当前播放视频生效的完整请求头 (深度整合规则全局 headers、单集独占 headers 与智能 Referer 兜底)
  Map<String, String> get _activeHeaders {
    final headers = Map<String, String>.from(widget.data.customHeaders);
    final episodes = _currentGroupEpisodes;
    if (episodes.isNotEmpty &&
        _currentEpisodeIndex >= 0 &&
        _currentEpisodeIndex < episodes.length) {
      final ep = episodes[_currentEpisodeIndex];
      final epHeaders = ep.extra['headers'];
      if (epHeaders is Map) {
        epHeaders.forEach((k, v) {
          if (k != null && v != null) {
            headers[k.toString()] = v.toString();
          }
        });
      }
    }

    // 防盗链保护：若规则未声明 Referer，智能注入详情页 URL 或规则 baseUrl
    final hasReferer = headers.keys.any((k) => k.toLowerCase() == 'referer');
    if (!hasReferer) {
      if (widget.data.url.isNotEmpty) {
        headers['Referer'] = widget.data.url;
      } else if (widget.rule?.baseUrl.isNotEmpty ?? false) {
        headers['Referer'] = widget.rule!.baseUrl;
      }
    }
    return headers;
  }

  /// 剧照 / 预览图的请求头（防盗链 Referer 兜底，同播放器口径）
  Map<String, String> get _previewHeaders {
    final referer = widget.rule?.baseUrl ?? '';
    return {
      if (referer.isNotEmpty) 'Referer': referer,
      ...widget.data.customHeaders,
    };
  }

  @override
  void initState() {
    super.initState();
    _initInitialPlayState();
    _registerPlayRecord();
    // 设置变化时刷新注入给播放器的偏好（重建 widget 不会重初始化播放器内部 State）
    appService.settingsNotifier.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    appService.settingsNotifier.removeListener(_onSettingsChanged);
    // 离开播放页时强制落盘，确保「继续观看」进度不丢失
    playHistoryService.flush();
    super.dispose();
  }

  /// 全局播放偏好变更 → 重新注入给 AuraPlayer
  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// 登记 / 更新当前视频的消费记录
  ///
  /// 视频取**当前播放集**，但必须**沿用既有播放秒数** ——
  /// 否则每次进入详情页都会把「继续观看」的断点清零。
  /// 规则由 [MediaHistoryRegistrar] 统一承载，两个媒体不会再各写一版。
  void _registerPlayRecord() {
    MediaHistoryRegistrar.register(
      id: _mediaId,
      title: _displayTitle,
      cover: widget.data.cover.isNotEmpty ? widget.data.cover : widget.fallbackCover,
      mediaType: 'video',
      ruleId: widget.rule?.id?.toString() ?? '',
      episodeName: _currentEpisodeTitle,
      episodeIndex: _currentEpisodeIndex,
      totalEpisodes: _currentGroupEpisodes.length,
      preservePlaybackProgress: true,
    );
  }

  /// 播放进度实时回调 (内存即时更新，磁盘按服务内节流策略落盘)
  void _onPlayProgress(Duration position, Duration duration) {
    playHistoryService.updateProgress(
      id: _mediaId,
      positionSeconds: position.inSeconds,
      durationSeconds: duration.inSeconds,
    );
  }

  @override
  void didUpdateWidget(covariant VideoDetailView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data.playUrl != widget.data.playUrl ||
        oldWidget.data.items != widget.data.items) {
      _initInitialPlayState();
    }
  }

  void _initInitialPlayState() {
    _selectedGroupIndex = 0;
    _currentEpisodeIndex = 0;

    // 断点续播：若上次观看到第 N 集，进入详情页时自动定位回该集
    final record = playHistoryService.getById(_mediaId);
    final totalEpisodes = _currentGroupEpisodes.length;
    if (record != null &&
        record.episodeIndex > 0 &&
        record.episodeIndex < totalEpisodes) {
      _currentEpisodeIndex = record.episodeIndex;
    }

    if (widget.data.playUrl != null && widget.data.playUrl!.isNotEmpty) {
      _activePlayUrl = widget.data.playUrl;
    } else {
      final currentList = _currentGroupEpisodes;
      if (currentList.isNotEmpty) {
        final idx = _currentEpisodeIndex.clamp(0, currentList.length - 1);
        _activePlayUrl = currentList[idx].url;
      }
    }
  }

  List<MediaEpisode> get _currentGroupEpisodes {
    if (widget.data.videoGroups.isNotEmpty &&
        _selectedGroupIndex >= 0 &&
        _selectedGroupIndex < widget.data.videoGroups.length) {
      return widget.data.videoGroups[_selectedGroupIndex].items;
    }
    return widget.data.items;
  }

  void _playEpisode(int index) {
    final episodes = _currentGroupEpisodes;
    if (index < 0 || index >= episodes.length) return;
    HapticFeedback.lightImpact();
    setState(() {
      _currentEpisodeIndex = index;
      _activePlayUrl = episodes[index].url;
    });

    // 切换集数后同步消费记录（进度归零，避免跨集错误复用断点）
    playHistoryService.updateProgress(
      id: _mediaId,
      episodeName: episodes[index].title,
      episodeIndex: index,
      totalEpisodes: episodes.length,
      positionSeconds: 0,
      durationSeconds: 0,
      forceNotify: true,
    );
  }

  /// 切换播放线路：换线后从该线路第一集重新起播
  void _selectGroup(int index) {
    setState(() {
      _selectedGroupIndex = index;
      _currentEpisodeIndex = 0;
      final currentList = _currentGroupEpisodes;
      if (currentList.isNotEmpty) {
        _activePlayUrl = currentList.first.url;
      }
    });
  }

  String get _displayTitle {
    if (widget.data.title.isNotEmpty) return widget.data.title;
    return widget.fallbackTitle.isNotEmpty ? widget.fallbackTitle : '未知视频';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final episodes = _currentGroupEpisodes;

    final currentEpTitle = (episodes.isNotEmpty &&
            _currentEpisodeIndex >= 0 &&
            _currentEpisodeIndex < episodes.length)
        ? episodes[_currentEpisodeIndex].title
        : '';
    final fullPlayerTitle = currentEpTitle.isNotEmpty
        ? '$_displayTitle · $currentEpTitle'
        : _displayTitle;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. 顶部 16:9 吸顶常驻播放器 (无论下方如何滑动，播放画面始终吸顶可见)
        AspectRatio(
          aspectRatio: 16 / 9,
          child: Container(
            color: Colors.black,
            child: _activePlayUrl != null && _activePlayUrl!.isNotEmpty
                ? AuraPlayer(
                    key: _playerKey,
                    playUrl: _activePlayUrl!,
                    title: fullPlayerTitle,
                    coverUrl: widget.data.cover.isNotEmpty ? widget.data.cover : widget.fallbackCover,
                    httpHeaders: _activeHeaders,
                    initialPosition: _resumePosition,
                    autoResume: _autoResume,
                    // 全屏期间休眠本实例（不卸载：控制器由它持有）
                    active: !_isFullScreen,
                    onFullScreenChanged: (fullscreen) {
                      setState(() => _isFullScreen = fullscreen);
                    },
                    // 播放偏好由宿主注入（播放器已与设置仓储解耦，可复用于任意场景）
                    preferences: PlayerPreferences(
                      longPressBoostEnabled: appService.settings.enableLongPress2x,
                      longPressSpeed: appService.settings.longPressSpeed,
                    ),
                    onPreferencesChanged: (prefs) {
                      appService.updateSettings(appService.settings.copyWith(
                        enableLongPress2x: prefs.longPressBoostEnabled,
                        longPressSpeed: prefs.longPressSpeed,
                      ));
                    },
                    onProgress: _onPlayProgress,
                    onEnded: () {
                      if (_currentEpisodeIndex < episodes.length - 1) {
                        _playEpisode(_currentEpisodeIndex + 1);
                      }
                    },
                  )
                : const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Ionicons.filmOutline, color: Colors.white38, size: 36),
                        SizedBox(height: 8),
                        Text(
                          '暂无有效播放地址',
                          style: TextStyle(color: Colors.white60, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
          ),
        ),

        // 2. 下方独立滚动内容区 (包含纯净元数据、选集面板、剧照与推荐，滚动不遮挡播放画面)
        Expanded(
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // A. 视频元数据与剧情简介平铺呈现
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: VideoMetaSection(
                    isDark: isDark,
                    title: _displayTitle,
                    rating: widget.data.rating,
                    ruleName: widget.rule?.name,
                    tags: widget.data.tags,
                    author: widget.data.author,
                    desc: widget.data.desc,
                    onShareTap: widget.onShareTap,
                  ),
                ),
                const SizedBox(height: 14),

                // B. 商业级长视频选集模块 (多线路切换 + 单行横向滑动条 + 全部选集半屏抽屉)
                if (episodes.isNotEmpty) ...[
                  // 离线下载入口已上移至顶部栏右上角图标（底部弹出下载面板）
                  VideoEpisodesSection(
                    isDark: isDark,
                    episodes: episodes,
                    groups: widget.data.videoGroups,
                    selectedGroupIndex: _selectedGroupIndex,
                    currentEpisodeIndex: _currentEpisodeIndex,
                    isReversed: _isReversed,
                    onGroupSelected: _selectGroup,
                    onEpisodeTap: _playEpisode,
                    onToggleReverse: _toggleReversed,
                    onShowAll: () => EpisodePickerSheet.show(
                      context: context,
                      isDark: isDark,
                      episodes: episodes,
                      currentEpisodeIndex: _currentEpisodeIndex,
                      isReversed: _isReversed,
                      onEpisodeTap: _playEpisode,
                      onToggleReverse: _toggleReversed,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // C. 剧照与预览横向滑动流 (16:10 宽屏卡片)
                if (widget.data.previews.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: VideoPreviewsSection(
                      isDark: isDark,
                      previews: widget.data.previews,
                      headers: _previewHeaders,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // D. 相关推荐双列网格 (16:9 现代宽屏双列流)
                MediaRelatedGrid(
                  related: widget.data.related,
                  currentRule: widget.rule,
                  headers: widget.data.customHeaders,
                  isWide: true,
                  onItemTap: (item) {
                    _playerKey.currentState?.pause();
                    widget.onRelatedItemTap?.call(item);
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 正倒序切换（列表与选集面板共用同一份状态，避免两处各切一半）
  void _toggleReversed() {
    HapticFeedback.lightImpact();
    setState(() => _isReversed = !_isReversed);
  }

}
