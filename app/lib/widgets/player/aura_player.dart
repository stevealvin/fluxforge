import 'dart:async';
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:video_player/video_player.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/loading_indicator.dart';

/// 现代视频播放器核心引擎 (AuraPlayer)
/// 
/// 彻底解耦第三方重量级播放器，底层基于官方原生 video_player 解码驱动
/// 集成应用内音量/亮度手势免权限调节、长按2.0x震动倍速、微胶囊状态条与极光流光进度条
class AuraPlayer extends StatefulWidget {
  const AuraPlayer({
    super.key,
    required this.playUrl,
    this.httpHeaders = const {},
    this.title = '',
    this.coverUrl,
    this.initialPosition = Duration.zero,
    this.onProgress,
    this.onEnded,
    this.onBack,
    this.extraActions,
  });

  /// 视频播放直链 (mp4, m3u8 等)
  final String playUrl;

  /// 防盗链请求头 (Referer, User-Agent 等)
  final Map<String, String> httpHeaders;

  /// 视频/剧集标题
  final String title;

  /// 封面海报地址
  final String? coverUrl;

  /// 断点续播初始跳转位置
  final Duration initialPosition;

  /// 播放进度回调
  final void Function(Duration current, Duration total)? onProgress;

  /// 播放结束回调
  final VoidCallback? onEnded;

  /// 顶部返回按钮回调
  final VoidCallback? onBack;

  /// 顶部/底部扩展操作插槽
  final List<Widget>? extraActions;

  @override
  State<AuraPlayer> createState() => _AuraPlayerState();
}

class _AuraPlayerState extends State<AuraPlayer> with SingleTickerProviderStateMixin {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 控制条显隐与自动隐藏定时器
  bool _showControls = true;
  Timer? _controlsTimer;

  // 锁屏状态
  bool _isLocked = false;

  // 全屏状态
  bool _isFullScreen = false;

  // 应用内免权限音量调节 (0.0 ~ 1.0)
  double _volume = 1.0;
  bool _showVolumeCapsule = false;
  Timer? _volumeCapsuleTimer;

  // 应用内无侵入遮罩亮度调节 (0.0 最暗 ~ 1.0 最亮，内部通过 0.0~0.75 纯黑遮罩实现)
  double _brightness = 1.0;
  bool _showBrightnessCapsule = false;
  Timer? _brightnessCapsuleTimer;

  // 水平快进/快退手势
  bool _isSeeking = false;
  Duration _seekTarget = Duration.zero;
  Duration _seekStartPos = Duration.zero;
  int _seekDeltaSeconds = 0;

  // 长按 2.0x 瞬时倍速
  bool _isFastForwarding = false;
  double _normalSpeed = 1.0;

  // 断点续播提示胶囊
  bool _showResumeTip = false;
  Timer? _resumeTipTimer;

  // 拖动进度条临时状态
  bool _isDraggingProgress = false;
  double _dragProgressValue = 0.0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  @override
  void didUpdateWidget(covariant AuraPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playUrl != widget.playUrl) {
      _initializePlayer();
    }
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _volumeCapsuleTimer?.cancel();
    _brightnessCapsuleTimer?.cancel();
    _resumeTipTimer?.cancel();
    
    // 退出全屏时恢复竖屏
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    super.dispose();
  }

  /// 初始化原生播放器控制器
  Future<void> _initializePlayer() async {
    if (widget.playUrl.trim().isEmpty) {
      setState(() {
        _hasError = true;
        _errorMessage = '播放地址为空';
      });
      return;
    }

    _controlsTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();

    setState(() {
      _isInitialized = false;
      _hasError = false;
      _errorMessage = '';
    });

    try {
      final uri = Uri.parse(widget.playUrl);
      _controller = VideoPlayerController.networkUrl(
        uri,
        httpHeaders: widget.httpHeaders,
      );

      await _controller!.initialize();

      if (!mounted) return;

      _controller!.addListener(_onControllerUpdate);
      _controller!.setVolume(_volume);
      _controller!.setPlaybackSpeed(_normalSpeed);
      _controller!.play();

      // 判断断点续播逻辑
      if (widget.initialPosition.inSeconds > 5 &&
          widget.initialPosition < _controller!.value.duration) {
        setState(() {
          _showResumeTip = true;
        });
        _resumeTipTimer = Timer(const Duration(seconds: 5), () {
          if (mounted) {
            setState(() {
              _showResumeTip = false;
            });
          }
        });
      }

      setState(() {
        _isInitialized = true;
      });

      _startControlsTimer();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _hasError = true;
        _errorMessage = '视频解析或加载失败: $e';
      });
    }
  }

  /// 视频播放器帧状态监听
  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final value = _controller!.value;

    // 播放进度通知上层
    if (value.isInitialized && !_isDraggingProgress && !_isSeeking) {
      widget.onProgress?.call(value.position, value.duration);
    }

    // 播放结束判定
    if (value.isInitialized &&
        value.position >= value.duration &&
        value.duration > Duration.zero) {
      widget.onEnded?.call();
    }

    // 触发刷新时间显示
    setState(() {});
  }

  /// 启动无操作 3.5 秒后自动隐藏控制栏的计时器
  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && _showControls && !_isDraggingProgress && !_isSeeking) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// 切换控制栏显示/隐藏
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
    if (_showControls) {
      _startControlsTimer();
    } else {
      _controlsTimer?.cancel();
    }
  }

  /// 切换横竖屏全屏模式
  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });

    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }

  /// 格式化 Duration 为 00:00 样式文本
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final hours = d.inHours.toString().padLeft(2, '0');
      final minutes = (d.inMinutes % 60).toString().padLeft(2, '0');
      final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    }
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isFullScreen,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isFullScreen) {
          _toggleFullScreen();
        }
      },
      child: Container(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: _isFullScreen
              ? MediaQuery.of(context).size.aspectRatio
              : (_controller?.value.isInitialized == true &&
                      _controller!.value.aspectRatio > 0
                  ? _controller!.value.aspectRatio
                  : 16 / 9),
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // 1. 核心视频画面渲染层
              _buildVideoSurface(),

              // 2. 屏幕应用内微调暗度遮罩 (实现无权限亮度调节)
              IgnorePointer(
                child: Container(
                  color: Colors.black.withValues(alpha: (1.0 - _brightness) * 0.75),
                ),
              ),

              // 3. 全局手势交互捕获层 (左右滑动调节亮度/音量、居中拖拽快进、长按2.0x、双击暂停)
              if (_isInitialized && !_isLocked) _buildGestureLayer(),

              // 4. 手势浮层：左侧亮度微胶囊
              if (_showBrightnessCapsule) _buildBrightnessCapsule(),

              // 5. 手势浮层：右侧音量微胶囊
              if (_showVolumeCapsule) _buildVolumeCapsule(),

              // 6. 手势浮层：居中快进/快退毛玻璃胶囊
              if (_isSeeking) _buildSeekingCapsule(),

              // 7. 手势浮层：长按 2.0x 快速播放中微胶囊
              if (_isFastForwarding) _buildFastForwardCapsule(),

              // 8. 断点续播提醒气泡
              if (_showResumeTip) _buildResumeTip(),

              // 9. 现代毛玻璃 UI 控制栏 (顶栏、底栏、锁屏)
              if (_showControls && _isInitialized) _buildControlOverlays(),

              // 10. 锁屏浮动小按钮 (始终在控制层或者单锁显隐)
              if (_isInitialized) _buildLockButton(),

              // 11. 加载中或错误状态指示层
              if (!_isInitialized || _hasError) _buildStateOverlay(),
            ],
          ),
        ),
      ),
    );
  }

  /// 视频渲染核心区域
  Widget _buildVideoSurface() {
    if (_isInitialized && _controller != null) {
      return Center(
        child: AspectRatio(
          aspectRatio: _controller!.value.aspectRatio > 0
              ? _controller!.value.aspectRatio
              : 16 / 9,
          child: VideoPlayer(_controller!),
        ),
      );
    }

    // 未就绪时若有封面则显示海报封面
    if (widget.coverUrl != null && widget.coverUrl!.isNotEmpty) {
      return Image.network(
        widget.coverUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
      );
    }

    return const SizedBox.shrink();
  }

  /// 手势交互捕获层
  Widget _buildGestureLayer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final totalHeight = constraints.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 单击：显隐控制栏
          onTap: _toggleControls,
          // 双击：暂停/播放
          onDoubleTap: () {
            if (_controller == null || !_controller!.value.isInitialized) return;
            if (_controller!.value.isPlaying) {
              _controller!.pause();
            } else {
              _controller!.play();
            }
            _startControlsTimer();
          },
          // 长按：2.0X 瞬时倍速
          onLongPressStart: (_) {
            HapticFeedback.lightImpact(); // 原生轻触觉震动反馈
            _normalSpeed = _controller?.value.playbackSpeed ?? 1.0;
            _controller?.setPlaybackSpeed(2.0);
            setState(() {
              _isFastForwarding = true;
            });
          },
          onLongPressEnd: (_) {
            _controller?.setPlaybackSpeed(_normalSpeed);
            setState(() {
              _isFastForwarding = false;
            });
          },
          // 垂直与水平滑动手势判定
          onVerticalDragStart: (details) {
            _controlsTimer?.cancel();
          },
          onVerticalDragUpdate: (details) {
            final positionX = details.localPosition.dx;
            final deltaY = -details.primaryDelta! / totalHeight;

            // 左侧 1/3：调节屏幕亮度
            if (positionX < totalWidth * 0.35) {
              setState(() {
                _brightness = (_brightness + deltaY * 1.5).clamp(0.15, 1.0);
                _showBrightnessCapsule = true;
              });
              _brightnessCapsuleTimer?.cancel();
              _brightnessCapsuleTimer = Timer(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() {
                    _showBrightnessCapsule = false;
                  });
                }
              });
            }
            // 右侧 1/3：调节应用内免权限音量
            else if (positionX > totalWidth * 0.65) {
              setState(() {
                _volume = (_volume + deltaY * 1.5).clamp(0.0, 1.0);
                _controller?.setVolume(_volume);
                _showVolumeCapsule = true;
              });
              _volumeCapsuleTimer?.cancel();
              _volumeCapsuleTimer = Timer(const Duration(seconds: 1), () {
                if (mounted) {
                  setState(() {
                    _showVolumeCapsule = false;
                  });
                }
              });
            }
          },
          onHorizontalDragStart: (details) {
            if (_controller == null || !_controller!.value.isInitialized) return;
            _controlsTimer?.cancel();
            setState(() {
              _isSeeking = true;
              _seekStartPos = _controller!.value.position;
              _seekTarget = _seekStartPos;
              _seekDeltaSeconds = 0;
            });
          },
          onHorizontalDragUpdate: (details) {
            if (!_isSeeking || _controller == null) return;
            final deltaX = details.primaryDelta! / totalWidth;
            final durationSecs = _controller!.value.duration.inSeconds;
            final scaleSecs = durationSecs > 0 ? durationSecs : 120;
            final int addedSecs = (deltaX * (scaleSecs > 300 ? 120 : 60)).round();

            setState(() {
              _seekDeltaSeconds += addedSecs;
              final targetMillis = (_seekStartPos.inMilliseconds + _seekDeltaSeconds * 1000)
                  .clamp(0, _controller!.value.duration.inMilliseconds);
              _seekTarget = Duration(milliseconds: targetMillis);
            });
          },
          onHorizontalDragEnd: (_) {
            if (_isSeeking && _controller != null) {
              _controller!.seekTo(_seekTarget);
              setState(() {
                _isSeeking = false;
              });
              _startControlsTimer();
            }
          },
          child: const SizedBox.expand(),
        );
      },
    );
  }

  /// 左侧垂直胶囊亮度指示条
  Widget _buildBrightnessCapsule() {
    return Positioned(
      left: 20,
      top: 0,
      bottom: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 38,
              height: 140,
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.black.withValues(alpha: 0.65),
              child: Column(
                children: [
                  Icon(
                    _brightness > 0.5 ? LucideIcons.sun : LucideIcons.sunDim,
                    color: Colors.white,
                    size: 18,
                  ),
                  const Spacer(),
                  Expanded(
                    flex: 6,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: LinearProgressIndicator(
                        value: _brightness,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(_brightness * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 右侧垂直胶囊音量指示条
  Widget _buildVolumeCapsule() {
    return Positioned(
      right: 20,
      top: 0,
      bottom: 0,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              width: 38,
              height: 140,
              padding: const EdgeInsets.symmetric(vertical: 12),
              color: Colors.black.withValues(alpha: 0.65),
              child: Column(
                children: [
                  Icon(
                    _volume == 0 ? LucideIcons.volumeX : (_volume > 0.5 ? LucideIcons.volume2 : LucideIcons.volume1),
                    color: Colors.white,
                    size: 18,
                  ),
                  const Spacer(),
                  Expanded(
                    flex: 6,
                    child: RotatedBox(
                      quarterTurns: -1,
                      child: LinearProgressIndicator(
                        value: _volume,
                        backgroundColor: Colors.white24,
                        valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${(_volume * 100).round()}%',
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 居中微拟态快进/快退胶囊
  Widget _buildSeekingCapsule() {
    final isForward = _seekDeltaSeconds >= 0;
    final totalDuration = _controller?.value.duration ?? Duration.zero;

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            color: Colors.black.withValues(alpha: 0.7),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isForward ? LucideIcons.fastForward : LucideIcons.rewind,
                  color: AppColors.primary,
                  size: 28,
                ),
                const SizedBox(height: 6),
                Text(
                  '${isForward ? '+' : ''}$_seekDeltaSeconds秒',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatDuration(_seekTarget)} / ${_formatDuration(totalDuration)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 长按 2.0x 顶部微胶囊
  Widget _buildFastForwardCapsule() {
    return Positioned(
      top: 48,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: Colors.black.withValues(alpha: 0.75),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.fastForward, color: AppColors.primary, size: 16),
                  SizedBox(width: 6),
                  Text(
                    '2.0X 快速播放中',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 断点续播提醒气泡
  Widget _buildResumeTip() {
    return Positioned(
      bottom: 72,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Colors.black.withValues(alpha: 0.75),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '上次看到 ${_formatDuration(widget.initialPosition)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () {
                    _controller?.seekTo(widget.initialPosition);
                    setState(() {
                      _showResumeTip = false;
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '跳转继续',
                      style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    setState(() {
                      _showResumeTip = false;
                    });
                  },
                  child: const Icon(LucideIcons.x, color: Colors.white54, size: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 浮动锁屏按钮
  Widget _buildLockButton() {
    if (!_showControls && !_isLocked) {
      return const SizedBox.shrink();
    }

    return Positioned(
      left: 16,
      top: _isFullScreen ? 0 : null,
      bottom: _isFullScreen ? 0 : 48,
      child: Center(
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            setState(() {
              _isLocked = !_isLocked;
              if (_isLocked) {
                _showControls = false;
              } else {
                _showControls = true;
                _startControlsTimer();
              }
            });
          },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Container(
                padding: const EdgeInsets.all(10),
                color: Colors.black.withValues(alpha: 0.6),
                child: Icon(
                  _isLocked ? LucideIcons.lock : LucideIcons.unlock,
                  color: _isLocked ? AppColors.primary : Colors.white70,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 现代毛玻璃控制顶栏与底栏
  Widget _buildControlOverlays() {
    if (_isLocked) return const SizedBox.shrink();

    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // 顶部控制条 (返回、标题、扩展插槽)
        _buildTopBar(),

        // 底部控制条 (播放/暂停、流光进度条、时长、倍速、全屏)
        _buildBottomBar(),
      ],
    );
  }

  /// 顶部控制条
  Widget _buildTopBar() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: _isFullScreen ? 12 : 8,
        left: 12,
        right: 12,
        bottom: 16,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
            onPressed: () {
              if (_isFullScreen) {
                _toggleFullScreen();
              } else if (widget.onBack != null) {
                widget.onBack!();
              } else {
                Navigator.maybePop(context);
              }
            },
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (widget.extraActions != null) ...widget.extraActions!,
        ],
      ),
    );
  }

  /// 底部控制条
  Widget _buildBottomBar() {
    final value = _controller?.value;
    final isPlaying = value?.isPlaying ?? false;
    final position = _isDraggingProgress
        ? Duration(milliseconds: (_dragProgressValue * (value?.duration.inMilliseconds ?? 1)).round())
        : (value?.position ?? Duration.zero);
    final duration = value?.duration ?? Duration.zero;

    final progressRatio = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        bottom: _isFullScreen ? 24 : 12,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 极光翡翠流光进度条 (Slider 改造)
          Row(
            children: [
              Text(
                _formatDuration(position),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: RoundSliderThumbShape(
                      enabledThumbRadius: _isDraggingProgress ? 7 : 5,
                    ),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: AppColors.primary,
                    overlayColor: AppColors.primary.withValues(alpha: 0.2),
                  ),
                  child: Slider(
                    value: progressRatio,
                    onChanged: (val) {
                      setState(() {
                        _isDraggingProgress = true;
                        _dragProgressValue = val;
                      });
                      _controlsTimer?.cancel();
                    },
                    onChangeEnd: (val) {
                      if (_controller != null && duration.inMilliseconds > 0) {
                        final targetMillis = (val * duration.inMilliseconds).round();
                        _controller!.seekTo(Duration(milliseconds: targetMillis));
                      }
                      setState(() {
                        _isDraggingProgress = false;
                      });
                      _startControlsTimer();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatDuration(duration),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),

          const SizedBox(height: 4),

          // 核心控制按钮行
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 播放/暂停
              IconButton(
                icon: Icon(
                  isPlaying ? LucideIcons.pause : LucideIcons.play,
                  color: Colors.white,
                  size: 22,
                ),
                onPressed: () {
                  if (isPlaying) {
                    _controller?.pause();
                  } else {
                    _controller?.play();
                  }
                  _startControlsTimer();
                },
              ),

              Row(
                children: [
                  // 倍速选择药丸
                  GestureDetector(
                    onTap: _showPlaybackSpeedDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${_controller?.value.playbackSpeed ?? 1.0}x',
                        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // 全屏/退出全屏
                  IconButton(
                    icon: Icon(
                      _isFullScreen ? LucideIcons.minimize : LucideIcons.maximize,
                      color: Colors.white,
                      size: 20,
                    ),
                    onPressed: _toggleFullScreen,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 弹出倍速选择弹窗
  void _showPlaybackSpeedDialog() {
    _controlsTimer?.cancel();
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    final currentSpeed = _controller?.value.playbackSpeed ?? 1.0;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8, bottom: 12),
                  child: Text(
                    '播放速度',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: speeds.map((speed) {
                    final isSelected = (currentSpeed - speed).abs() < 0.01;
                    return ActionChip(
                      label: Text('${speed}x'),
                      backgroundColor: isSelected ? AppColors.primary : AppColors.darkCard,
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : AppColors.darkTextSecondary,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      side: BorderSide(
                        color: isSelected ? AppColors.primary : AppColors.darkBorder,
                      ),
                      onPressed: () {
                        _controller?.setPlaybackSpeed(speed);
                        _normalSpeed = speed;
                        Navigator.pop(ctx);
                        _startControlsTimer();
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 加载中或错误状态指示层
  Widget _buildStateOverlay() {
    if (_hasError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.alertTriangle, color: Colors.amber, size: 36),
              const SizedBox(height: 12),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                onPressed: _initializePlayer,
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('重试播放'),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.black54,
      child: const Center(
        child: LoadingIndicator(message: '流媒体资源极速载入中...'),
      ),
    );
  }
}
