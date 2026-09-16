import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:extended_image/extended_image.dart';

import '../../../core/theme/app_colors.dart';
import '../../../models/rule.dart';
import '../../../services/app_service.dart';
import '../../../services/di.dart';
import '../../../services/play_history_service.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/player/aura_player.dart';
import '../common/media_related_grid.dart';
import '../../../models/media.dart';

/// 视频媒介业务专属详情视图
/// 
/// 遵循专业流媒体交互标准：吸顶常驻播放器、纯净平铺元数据、横向快速选集滑动条、全量剧集半屏抽屉与宽屏推荐
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
  bool _isReversed = false;
  bool _isDescExpanded = false;
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

  @override
  void initState() {
    super.initState();
    _initInitialPlayState();
    _registerPlayRecord();
  }

  @override
  void dispose() {
    // 离开播放页时强制落盘，确保「继续观看」进度不丢失
    playHistoryService.flush();
    super.dispose();
  }

  /// 登记 / 更新当前视频的消费记录 (保留既有播放进度)
  void _registerPlayRecord() {
    if (_mediaId.isEmpty) return;
    final existing = playHistoryService.getById(_mediaId);
    playHistoryService.upsert(
      PlayRecord(
        id: _mediaId,
        title: _displayTitle,
        cover: widget.data.cover.isNotEmpty ? widget.data.cover : widget.fallbackCover,
        mediaType: 'video',
        ruleId: widget.rule?.id?.toString() ?? '',
        episodeName: _currentEpisodeTitle,
        episodeIndex: _currentEpisodeIndex,
        totalEpisodes: _currentGroupEpisodes.length,
        positionSeconds: existing?.positionSeconds ?? 0,
        durationSeconds: existing?.durationSeconds ?? 0,
        updatedAt: DateTime.now(),
      ),
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
                  child: _buildVideoMetaContent(isDark),
                ),
                const SizedBox(height: 14),

                // B. 商业级长视频选集模块 (多线路切换 + 单行横向滑动条 + 全部选集半屏抽屉)
                if (episodes.isNotEmpty) ...[
                  _buildVideoEpisodesSection(isDark, episodes),
                  const SizedBox(height: 16),
                ],

                // C. 剧照与预览横向滑动流 (16:10 宽屏卡片)
                if (widget.data.previews.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: _buildPreviewsSection(isDark),
                  ),
                  const SizedBox(height: 16),
                ],

                // D. 相关推荐双列网格 (16:9 现代宽屏双列流)
                MediaRelatedGrid(
                  related: widget.data.related,
                  currentRule: widget.rule,
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

  /// 构建纯净平铺的视频元数据区 (主大标题、评分胶囊、规则源标签、分类题材、作者与平滑展开简介)
  Widget _buildVideoMetaContent(bool isDark) {
    final desc = widget.data.desc?.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 标题行与分享操作
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                _displayTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (widget.onShareTap != null) ...[
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(
                  Ionicons.shareSocialOutline,
                  size: 17,
                  color: isDark ? Colors.white70 : AppColors.lightTextSecondary,
                ),
                onPressed: widget.onShareTap,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // 状态、评分、规则源、题材标签与作者流
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            // 评分徽标 (琥珀黄金色胶囊)
            if (widget.data.rating != null && widget.data.rating!.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.star_rounded, size: 13, color: Color(0xFFF59E0B)),
                    const SizedBox(width: 3),
                    Text(
                      widget.data.rating!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFF59E0B),
                      ),
                    ),
                  ],
                ),
              ),

            // 规则源标识
            if (widget.rule != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: isDark ? 0.2 : 0.12),
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

            // 分类题材标签 (微光实体药丸)
            ...widget.data.tags.map(
              (tag) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 0.8,
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

            // 演职员 / 作者
            if (widget.data.author != null && widget.data.author!.isNotEmpty)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Ionicons.personOutline,
                    size: 11,
                    color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.data.author!,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                ],
              ),
          ],
        ),

        // 剧情简介：平铺直接呈现，无多余边框大卡片，带流畅展开折叠动效
        if (desc != null && desc.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
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
                    desc,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.5,
                      color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                    ),
                  ),
                  secondChild: Text(
                    desc,
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
                    const SizedBox(width: 3),
                    Icon(
                      _isDescExpanded ? Ionicons.chevronUpOutline : Ionicons.chevronDownOutline,
                      size: 11,
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

  /// 构建商业级长视频选集模块 (多线路切换 + 单行横向滑动条 + 全部选集半屏抽屉)
  Widget _buildVideoEpisodesSection(bool isDark, List<MediaEpisode> episodes) {
    final int count = episodes.length;
    final displayIndices = List.generate(
      count,
      (i) => _isReversed ? (count - 1 - i) : i,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 多播放线路切换栏 (若沙箱返回多个 group)
        if (widget.data.videoGroups.length > 1) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: SizedBox(
              height: 32,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.data.videoGroups.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final g = widget.data.videoGroups[index];
                  final isSelected = index == _selectedGroupIndex;

                  return ChoiceChip(
                    label: Text(g.name),
                    selected: isSelected,
                    selectedColor: AppColors.primary,
                    backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
                    side: BorderSide(
                      color: isSelected
                          ? AppColors.primary
                          : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      width: 0.8,
                    ),
                    labelStyle: TextStyle(
                      fontSize: 11.5,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? Colors.white
                          : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    ),
                    onSelected: (val) {
                      if (val && _selectedGroupIndex != index) {
                        HapticFeedback.selectionClick();
                        setState(() {
                          _selectedGroupIndex = index;
                          _currentEpisodeIndex = 0;
                          final currentList = _currentGroupEpisodes;
                          if (currentList.isNotEmpty) {
                            _activePlayUrl = currentList.first.url;
                          }
                        });
                      }
                    },
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // 2. 选集控制头部栏 (标题 + 集数统计 + 正倒序 + 全部选集抽屉按钮)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
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
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
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
                  // 正序 / 倒序切换按钮
                  IconButton(
                    tooltip: _isReversed ? '切换为正序' : '切换为倒序',
                    icon: Icon(
                      Ionicons.swapVerticalOutline,
                      size: 14,
                      color: _isReversed
                          ? AppColors.primary
                          : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        _isReversed = !_isReversed;
                      });
                    },
                  ),

                  // 全部选集网格弹窗抽屉按钮 (超过 5 集时展示)
                  if (count > 5)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                      icon: const Icon(Ionicons.gridOutline, size: 13, color: AppColors.primary),
                      label: const Text(
                        '全部',
                        style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                      onPressed: () => _showAllEpisodesSheet(context, isDark, episodes),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. 商业级单行横向快速选集滑动条 (高度 46px，即点即播，选中态翠绿高光微阴影)
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            itemCount: count,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final realIndex = displayIndices[i];
              final item = episodes[realIndex];
              final isCurrent = realIndex == _currentEpisodeIndex;

              return InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => _playEpisode(realIndex),
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
                        const Icon(Ionicons.playOutline, size: 10, color: Colors.white),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 12.5,
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

  /// 呼出全量剧集底部选集面板 (类似腾讯视频/B站的底部半屏选集抽屉)
  void _showAllEpisodesSheet(BuildContext context, bool isDark, List<MediaEpisode> episodes) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final count = episodes.length;
            final isReversed = _isReversed;
            final List<int> indices = List.generate(
              count,
              (i) => isReversed ? (count - 1 - i) : i,
            );

            return Container(
              height: MediaQuery.of(context).size.height * 0.65,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkCard : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                border: Border(
                  top: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                    width: 0.8,
                  ),
                ),
              ),
              child: Column(
                children: [
                  // 顶部药丸把手
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
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '共 $count 集',
                              style: TextStyle(
                                fontSize: 12,
                                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                              ),
                            ),
                          ],
                        ),
                        // 抽屉内正倒序切换
                        IconButton(
                          tooltip: isReversed ? '切换为正序' : '切换为倒序',
                          icon: Icon(
                            Ionicons.swapVerticalOutline,
                            size: 15,
                            color: isReversed
                                ? AppColors.primary
                                : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                          ),
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            setState(() {
                              _isReversed = !_isReversed;
                            });
                            setSheetState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // 选集 4 列紧凑网格
                  Expanded(
                    child: GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 4,
                        mainAxisSpacing: 10,
                        crossAxisSpacing: 10,
                        childAspectRatio: 2.1,
                      ),
                      itemCount: count,
                      itemBuilder: (context, idx) {
                        final realIndex = indices[idx];
                        final ep = episodes[realIndex];
                        final isCurrent = realIndex == _currentEpisodeIndex;

                        return AppCard(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          borderRadius: 8,
                          showBorder: true,
                          borderColor: isCurrent
                              ? AppColors.primary
                              : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                          color: isCurrent
                              ? AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.15)
                              : (isDark ? const Color(0xFF0F1420) : AppColors.lightSurface),
                          onTap: () {
                            Navigator.pop(sheetContext);
                            _playEpisode(realIndex);
                          },
                          child: Center(
                            child: Text(
                              ep.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                color: isCurrent
                                    ? AppColors.primary
                                    : (isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary),
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

  /// 构建剧照与预览横向滑动视图 (16:10 宽屏卡片)
  Widget _buildPreviewsSection(bool isDark) {
    final referer = widget.rule?.baseUrl ?? '';
    final headers = {
      if (referer.isNotEmpty) 'Referer': referer,
      ...widget.data.customHeaders,
    };

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
              '剧照与预览',
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${widget.data.previews.length})',
              style: TextStyle(
                fontSize: 12,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 76,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: widget.data.previews.length,
            separatorBuilder: (context, index) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final imgUrl = widget.data.previews[index];
              return Container(
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                  borderRadius: BorderRadius.circular(8),
                ),
                clipBehavior: Clip.antiAlias,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ExtendedImage.network(
                    imgUrl,
                    fit: BoxFit.cover,
                    headers: headers.isNotEmpty ? headers : null,
                    loadStateChanged: (state) {
                      if (state.extendedImageLoadState == LoadState.failed) {
                        return Center(
                          child: Icon(
                            Icons.broken_image_rounded,
                            color: isDark ? AppColors.darkTextTertiary : AppColors.lightTextTertiary,
                            size: 20,
                          ),
                        );
                      }
                      return null;
                    },
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
