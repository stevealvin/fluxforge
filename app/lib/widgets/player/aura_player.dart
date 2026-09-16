import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../services/di.dart';
import '../../widgets/app_loading.dart';

/// 现代视频播放器核心引擎 (AuraPlayer)
/// 
/// 彻底解耦第三方重量级播放器与外部路由，底层基于官方原生 video_player 解码驱动
/// 纯粹的受控与自闭环基础 UI 组件：集成音量/亮度手势免权限调节、长按2.0x震动倍速、微胶囊状态条与极光流光进度条
class AuraPlayer extends StatefulWidget {
  const AuraPlayer({
    super.key,
    required this.playUrl,
    this.controller,
    this.isFullScreenMode = false,
    this.httpHeaders = const {},
    this.title = '',
    this.coverUrl,
    this.initialPosition = Duration.zero,
    this.autoResume = false,
    this.onProgress,
    this.onEnded,
    this.onBack,
    this.extraActions,
    this.autoPauseOnCovered = true,
    this.onFullScreenChanged,
  });

  /// 播放源地址
  final String playUrl;

  /// 外部复用或托管的视频控制器 (若为 null 则内部自主管理生命周期)
  final VideoPlayerController? controller;

  /// 是否运行于全屏独占沉浸路由模式下
  final bool isFullScreenMode;

  /// 自定义防盗链与鉴权请求头 (如 Referer, User-Agent)
  final Map<String, String> httpHeaders;

  /// 视频主标题
  final String title;

  /// 视频封面海报图 URL
  final String? coverUrl;

  /// 起播跳转定位
  final Duration initialPosition;

  /// 是否自动静默跳转至 [initialPosition]（对应断点续播「直接跳转」策略）
  ///
  /// - `false`（默认）：仅弹出「上次看到 XX:XX [继续]」胶囊，由用户确认后再跳转；
  /// - `true`：初始化完成后直接 seek 到断点位置，仅保留提示胶囊告知用户。
  final bool autoResume;

  /// 播放进度实时回调 (当前位置, 总时长)
  final void Function(Duration position, Duration duration)? onProgress;

  /// 播放完毕自然结束回调
  final VoidCallback? onEnded;

  /// 顶部返回按钮回调
  final VoidCallback? onBack;

  /// 全屏状态变更回调
  final void Function(bool isFullScreen)? onFullScreenChanged;

  /// 顶部/底部扩展操作插槽
  final List<Widget>? extraActions;

  /// 退至后台或失去焦点时是否自动暂停 (默认 true)
  final bool autoPauseOnCovered;

  @override
  State<AuraPlayer> createState() => AuraPlayerState();
}

/// 导出公开的状态类，供业务代码通过 `GlobalKey<AuraPlayerState>` 执行主动暂停/播放等受控交互
class AuraPlayerState extends State<AuraPlayer>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  /// 主动暂停当前视频播放并解除屏幕常亮 (供业务层按需调用，例如点击相关推荐视频时)
  void pause() {
    if (_controller != null && _controller!.value.isPlaying) {
      _controller!.pause();
      _updateWakelock(false);
    }
  }

  /// 主动恢复当前视频播放并恢复屏幕常亮
  void play() {
    if (_controller != null && !_controller!.value.isPlaying) {
      _controller!.play();
      _updateWakelock(true);
    }
  }

  /// 获取底层视频控制器 (只读访问)
  VideoPlayerController? get controller => _controller;

  /// 当前是否正在播放
  bool get isPlaying => _controller?.value.isPlaying ?? false;

  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _hasError = false;
  String _errorMessage = '';

  // 屏幕常亮状态管理（仅在有效播放中保持常亮）
  bool _isWakelockEnabled = false;

  // 控制条显隐与自动隐藏定时器
  bool _showControls = true;
  Timer? _controlsTimer;

  // 锁屏状态管理 (支持单独唤醒与3.5秒自动淡出)
  bool _isLocked = false;
  bool _showLockIcon = true;
  Timer? _lockIconTimer;

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

  // 长按瞬时加速 (倍率与开关均实时读取全局播放偏好)
  bool _isFastForwarding = false;
  double _normalSpeed = 1.0;

  /// 长按瞬时加速是否启用
  bool get _longPressEnabled => appService.settings.enableLongPress2x;

  /// 长按瞬时加速倍率 (可选 2.0 / 3.0 / 5.0)
  double get _longPressSpeed => appService.settings.longPressSpeed;

  // 断点续播提示胶囊
  bool _showResumeTip = false;
  Timer? _resumeTipTimer;

  // 拖动进度条临时状态与防跳变播放意向记忆
  bool _isDraggingProgress = false;
  double _dragProgressValue = 0.0;
  bool _wasPlayingBeforeDrag = true;
  bool _isSeekingTo = false;
  Timer? _seekToDebounceTimer;

  // 画面比例自适应、镜像翻转与循环播放偏好
  BoxFit _videoFit = BoxFit.contain; // 默认原比例包含
  bool _isMirrored = false; // 是否水平镜像翻转
  bool _isLooping = false; // 是否单视频无缝循环播放

  // 加载与缓冲状态极光流光扫光动画控制器
  late AnimationController _shimmerController;

  /// 综合判定播放意图与真实状态：
  /// 在用户拖拽进度条、手势滑屏寻道、或寻道后的网络缓冲等待阶段，
  /// 始终优先保持拖拽前的播放意图，坚决防止播放/暂停按钮发生误显或跳变。
  bool get _effectiveIsPlaying {
    if (_controller == null || !_controller!.value.isInitialized) return false;
    if (_isDraggingProgress || _isSeeking || _isSeekingTo) {
      return _wasPlayingBeforeDrag;
    }
    if (_controller!.value.isBuffering && _wasPlayingBeforeDrag) {
      return true;
    }
    return _controller!.value.isPlaying;
  }

  /// 动态更新屏幕常亮状态
  void _updateWakelock(bool enable) {
    if (_isWakelockEnabled == enable) return;
    _isWakelockEnabled = enable;
    if (enable) {
      WakelockPlus.enable().catchError((e) {
        debugPrint('[AuraPlayer] 开启屏幕常亮异常: $e');
      });
    } else {
      WakelockPlus.disable().catchError((e) {
        debugPrint('[AuraPlayer] 解除屏幕常亮异常: $e');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isFullScreen = widget.isFullScreenMode;

    // 初始化流光进度条循环扫光动画控制器 (周期 1400ms，平滑线性流动)
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();

    if (widget.controller != null) {
      _controller = widget.controller;
      _isInitialized = _controller!.value.isInitialized;
      _volume = _controller!.value.volume;
      _controller!.addListener(_onControllerUpdate);
      if (_controller!.value.isPlaying) {
        _updateWakelock(true);
      }
      _startControlsTimer();
    } else {
      _initializePlayer();
    }
  }

  @override
  void didUpdateWidget(covariant AuraPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null && oldWidget.playUrl != widget.playUrl) {
      _initializePlayer();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // 进入后台、锁屏或失焦时自动暂停播放并解除屏幕常亮，防止后台偷跑电量与网络流量
      if (widget.autoPauseOnCovered && (_controller?.value.isPlaying ?? false)) {
        _controller?.pause();
      }
      _updateWakelock(false);
    } else if (state == AppLifecycleState.resumed) {
      // 重新切回前台时，若视频仍在播放则恢复屏幕常亮
      final value = _controller?.value;
      if (value != null && value.isInitialized && value.isPlaying && !value.hasError) {
        _updateWakelock(true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _shimmerController.dispose();
    _seekToDebounceTimer?.cancel();
    _updateWakelock(false);
    _controlsTimer?.cancel();
    _lockIconTimer?.cancel();
    _volumeCapsuleTimer?.cancel();
    _brightnessCapsuleTimer?.cancel();
    _resumeTipTimer?.cancel();
    
    // 退出全屏时恢复竖屏
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    _controller?.removeListener(_onControllerUpdate);
    
    // 仅当控制器是由本组件创建时才执行销毁，全屏模式下不销毁主页面控制器
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  /// 初始化原生播放器控制器
  Future<void> _initializePlayer() async {
    if (widget.playUrl.trim().isEmpty) {
      _updateWakelock(false);
      setState(() {
        _hasError = true;
        _errorMessage = '播放地址为空';
      });
      return;
    }

    _controlsTimer?.cancel();
    _controller?.removeListener(_onControllerUpdate);
    _controller?.dispose();
    _updateWakelock(false);

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
        // 「直接跳转」策略：静默 seek 到上次进度，交由用户自行决定是否回退
        if (widget.autoResume) {
          await _controller!.seekTo(widget.initialPosition);
          if (!mounted) return;
        }
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
      _updateWakelock(false);
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

    // 动态同步屏幕常亮状态：仅在视频有效播放时保持屏幕常亮
    final isPlaying = value.isInitialized && value.isPlaying && !value.hasError;
    _updateWakelock(isPlaying);

    // 播放进度通知上层
    if (value.isInitialized && !_isDraggingProgress && !_isSeeking) {
      widget.onProgress?.call(value.position, value.duration);
    }

    // 播放结束判定 (支持单视频循环播放)
    if (value.isInitialized &&
        value.position >= value.duration &&
        value.duration > Duration.zero) {
      if (_isLooping) {
        _controller?.seekTo(Duration.zero);
        _controller?.play();
      } else {
        _updateWakelock(false);
        widget.onEnded?.call();
      }
    }

    // 触发刷新时间显示
    setState(() {});
  }

  /// 启动无操作 5.0 秒后自动隐藏控制栏的计时器 (时长延长，操作从容舒展)
  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(milliseconds: 5000), () {
      if (mounted && _showControls && !_isDraggingProgress && !_isSeeking) {
        setState(() {
          _showControls = false;
        });
      }
    });
  }

  /// 启动锁定状态下锁图标无操作 5.0 秒后自动隐藏的计时器
  void _startLockIconTimer() {
    _lockIconTimer?.cancel();
    _lockIconTimer = Timer(const Duration(milliseconds: 5000), () {
      if (mounted && _showLockIcon) {
        setState(() {
          _showLockIcon = false;
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

  /// 切换横竖屏全屏模式 (自闭环驱动独立全屏路由)
  Future<void> _toggleFullScreen() async {
    // 1. 如果当前已在全屏路由模式中，触发退出全屏路由
    if (widget.isFullScreenMode) {
      if (widget.onBack != null) {
        widget.onBack!();
      } else {
        Navigator.of(context).pop();
      }
      return;
    }

    if (_controller == null || !_controller!.value.isInitialized) return;

    widget.onFullScreenChanged?.call(true);

    // 2. 设置横屏与全屏沉浸模式
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    if (!mounted) return;

    // 3. 通过 rootNavigator 独立路由推入全屏播放界面，直接全屏铺满覆盖宿主所有的 AppBar/BottomBar/Scaffold
    await Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: true,
        fullscreenDialog: true,
        pageBuilder: (fullscreenContext, animation, secondaryAnimation) {
          return Scaffold(
            backgroundColor: Colors.black,
            body: AuraPlayer(
              playUrl: widget.playUrl,
              controller: _controller,
              title: widget.title,
              coverUrl: widget.coverUrl,
              httpHeaders: widget.httpHeaders,
              isFullScreenMode: true,
              onBack: () => Navigator.of(fullscreenContext).pop(),
              onEnded: widget.onEnded,
              extraActions: widget.extraActions,
            ),
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );

    // 4. 退出全屏路由后，自动恢复竖屏与 edgeToEdge
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    widget.onFullScreenChanged?.call(false);

    if (mounted) {
      setState(() {
        _isFullScreen = false;
        _volume = _controller?.value.volume ?? _volume;
      });
      _startControlsTimer();
      // 从全屏无缝平滑切回竖屏后，若视频仍处于播放状态，维持屏幕常亮
      if (_controller?.value.isPlaying ?? false) {
        _updateWakelock(true);
      }
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
    final stackContent = Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.hardEdge,
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

        // 3. 全局手势交互捕获层 (未锁定时支持滑动手势，锁定时仅响应单击呼出锁图标)
        if (_isInitialized)
          _isLocked ? _buildLockedGestureLayer() : _buildGestureLayer(),

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

        // 9. 小屏专属居中大播放/暂停按键 (带平滑缩放与淡入淡出动效)
        _buildCenterPlayButton(),

        // 10. 现代毛玻璃 UI 控制栏 (顶栏、底栏) — 常驻渲染，由内部动画驱动显隐
        if (_isInitialized) _buildControlOverlays(),

        // 11. 浮动锁屏按钮 (仅全屏模式出现、加宽左边距、支持单锁显隐)
        if (_isInitialized) _buildLockButton(),

        // 12. 小屏底边常驻微型流光进度条 (控制条隐藏时无缝接替)
        _buildBottomMiniProgress(),

        // 13. 加载中或错误状态指示层
        if (!_isInitialized || _hasError) _buildStateOverlay(),
      ],
    );

    if (widget.isFullScreenMode) {
      return PopScope(
        canPop: true,
        child: Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: stackContent,
        ),
      );
    }

    return ClipRect(
      child: Container(
        color: Colors.black,
        child: AspectRatio(
          aspectRatio: (_controller?.value.isInitialized == true &&
                  _controller!.value.aspectRatio > 0
              ? _controller!.value.aspectRatio
              : 16 / 9),
          child: stackContent,
        ),
      ),
    );
  }

  /// 视频渲染核心区域 (支持 Contain/Cover/Fill 比例调节与水平镜像翻转)
  Widget _buildVideoSurface() {
    if (_isInitialized && _controller != null) {
      final videoWidth = _controller!.value.size.width;
      final videoHeight = _controller!.value.size.height;
      final aspectRatio = _controller!.value.aspectRatio > 0
          ? _controller!.value.aspectRatio
          : 16 / 9;

      Widget videoWidget;
      if (_videoFit == BoxFit.cover) {
        videoWidget = SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: videoWidth > 0 ? videoWidth : 16,
              height: videoHeight > 0 ? videoHeight : 9,
              child: VideoPlayer(_controller!),
            ),
          ),
        );
      } else if (_videoFit == BoxFit.fill) {
        videoWidget = SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.fill,
            child: SizedBox(
              width: videoWidth > 0 ? videoWidth : 16,
              height: videoHeight > 0 ? videoHeight : 9,
              child: VideoPlayer(_controller!),
            ),
          ),
        );
      } else {
        videoWidget = Center(
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: VideoPlayer(_controller!),
          ),
        );
      }

      // 水平镜像翻转处理 (便于舞蹈、健身、跟练视频学习)
      if (_isMirrored) {
        videoWidget = Transform(
          alignment: Alignment.center,
          transform: Matrix4.rotationY(math.pi),
          child: videoWidget,
        );
      }

      return videoWidget;
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

  /// 锁定状态下的极简防误触手势层：仅捕获屏幕单击以唤醒/切换锁图标显隐，完全拦截滑动/双击/长按等误触
  Widget _buildLockedGestureLayer() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          _showLockIcon = !_showLockIcon;
        });
        if (_showLockIcon) {
          _startLockIconTimer();
        } else {
          _lockIconTimer?.cancel();
        }
      },
      child: const SizedBox.expand(),
    );
  }

  /// 手势交互捕获层 (未锁定时)
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
          // 长按：瞬时加速 (倍率可在「设置 → 播放与视听偏好」中配置)
          onLongPressStart: (_) {
            if (!_longPressEnabled) return; // 用户已关闭长按加速
            HapticFeedback.lightImpact(); // 原生轻触觉震动反馈
            _normalSpeed = _controller?.value.playbackSpeed ?? 1.0;
            _controller?.setPlaybackSpeed(_longPressSpeed);
            setState(() {
              _isFastForwarding = true;
            });
          },
          onLongPressEnd: (_) {
            // 未真正进入加速态时无需恢复原速
            if (!_isFastForwarding) return;
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
            _wasPlayingBeforeDrag = _controller!.value.isPlaying;
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
              setState(() {
                _isSeeking = false;
                _isSeekingTo = true;
              });
              _controller!.seekTo(_seekTarget).then((_) {
                if (mounted) {
                  if (_wasPlayingBeforeDrag) {
                    _controller?.play();
                  }
                  _seekToDebounceTimer?.cancel();
                  _seekToDebounceTimer = Timer(const Duration(milliseconds: 350), () {
                    if (mounted) {
                      setState(() {
                        _isSeekingTo = false;
                      });
                    }
                  });
                }
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
      left: _isFullScreen ? 68 : 16,
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
                  Icon(_brightness > 0.5 ? Ionicons.sunnyOutline : Ionicons.sunnyOutline,
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
                  Icon(_volume == 0
                        ? Ionicons.volumeMuteOutline
                        : (_volume > 0.5 ? Ionicons.volumeHighOutline : Ionicons.volumeLowOutline),
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

  /// 居中微拟态快进/快退胶囊 (双行紧凑布局：上行方向+秒数，下行时间进度，主次分明)
  Widget _buildSeekingCapsule() {
    final isForward = _seekDeltaSeconds >= 0;
    final totalDuration = _controller?.value.duration ?? Duration.zero;
    // 快进 = 翡翠绿，快退 = 琥珀金 (与 WebView 端 HUD 配色保持一致)
    final accentColor = isForward ? const Color(0xFF10B981) : const Color(0xFFF59E0B);

    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
            decoration: BoxDecoration(
              // 取消外围边框线，进一步提升半透明通透感 (alpha: 0.45)
              color: Colors.black.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：方向圆角图标 + 快进/快退秒数
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isForward ? Ionicons.playForwardOutline : Ionicons.playBackOutline,
                      color: accentColor,
                      size: 18,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '${isForward ? '+' : ''}${_seekDeltaSeconds}s',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                // 第二行：目标时间 / 视频总时长
                Text(
                  '${_formatDuration(_seekTarget)} / ${_formatDuration(totalDuration)}',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


  /// 长按瞬时加速顶部微胶囊 (纯净无文字版，仅展示高斯毛玻璃翡翠快进图标，视线无遮挡)
  Widget _buildFastForwardCapsule() {
    return Positioned(
      top: 48,
      child: Center(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: Colors.black.withValues(alpha: 0.55),
              child: const Icon(Ionicons.playForwardOutline,
                color: AppColors.primary,
                size: 20,
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
                  child: const Icon(Ionicons.closeOutline, color: Colors.white54, size: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 切换全屏锁定/解锁状态
  void _onToggleLock() {
    HapticFeedback.lightImpact();
    setState(() {
      _isLocked = !_isLocked;
      if (_isLocked) {
        // 上锁：立即向外滑出隐藏顶部栏与底部栏，仅保留锁图标，并开启锁图标 3.5 秒独立倒计时
        _showControls = false;
        _showLockIcon = true;
        _controlsTimer?.cancel();
        _startLockIconTimer();
      } else {
        // 解锁：恢复全部控制栏显示，取消锁图标独立计时，统一交给控制栏 3.5 秒计时器管理
        _showControls = true;
        _showLockIcon = true;
        _lockIconTimer?.cancel();
        _startControlsTimer();
      }
    });
  }

  /// 全屏模式下的左侧呼吸内边距 (安全避开刘海/挖孔与屏幕圆角，至少 40px)
  double get _fullscreenLeftPadding {
    final safeLeft = MediaQuery.of(context).padding.left;
    return safeLeft > 0 ? safeLeft + 24.0 : 40.0;
  }

  /// 全屏模式下的右侧呼吸内边距 (安全避开刘海/挖孔与屏幕圆角，至少 40px)
  double get _fullscreenRightPadding {
    final safeRight = MediaQuery.of(context).padding.right;
    return safeRight > 0 ? safeRight + 24.0 : 40.0;
  }

  /// 浮动锁屏按钮 (仅全屏模式出现、垂直居中、左边缘与底栏进度条及播放键严丝合缝对齐)
  Widget _buildLockButton() {
    // 锁定图标仅在全屏状态下出现
    if (!_isFullScreen) {
      return const SizedBox.shrink();
    }

    // 判断锁图标当前是否应该显示：
    // - 锁定态下由 _showLockIcon 决定 (点击屏幕唤醒，5.0 秒后自动隐去)
    // - 未锁定态下跟随控制栏 _showControls 决定
    final bool shouldShow = _isLocked ? _showLockIcon : _showControls;
    final double leftPosition = _fullscreenLeftPadding;

    return Positioned(
      left: leftPosition,
      top: 0,
      bottom: 0,
      child: Center(
        child: IgnorePointer(
          ignoring: !shouldShow,
          child: AnimatedOpacity(
            opacity: shouldShow ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            child: AnimatedScale(
              scale: shouldShow ? 1.0 : 0.82,
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onToggleLock,
                child: Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.centerLeft, // 图标左边缘与基准线严格同轴对齐
                  child: Icon(_isLocked ? Ionicons.lockClosedOutline : Ionicons.lockOpenOutline,
                    color: Colors.white, // 关闭锁定状态去掉颜色，保持纯白通透质感
                    size: 24,
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 8,
                        offset: Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 居中大播放/暂停按键 (无底色、无边线纯净悬浮形态，圆润极简 LucideIcons，带微立体投影与弹性缩放动效)
  Widget _buildCenterPlayButton() {
    if (!_isInitialized || _hasError) {
      return const SizedBox.shrink();
    }

    // 采用防跳变综合播放判定：拖拽/寻道缓冲期间保持意向，绝不误显暂停按键
    final isPlaying = _effectiveIsPlaying;

    // 全屏模式下播放中保持画面干净；仅在暂停状态 (且呼出控制栏时) 呈现纯净大播放按键
    if (_isFullScreen && isPlaying) {
      return const SizedBox.shrink();
    }

    return Center(
      child: IgnorePointer(
        ignoring: !_showControls,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          child: AnimatedScale(
            scale: _showControls ? 1.0 : 0.72,
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutBack,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.lightImpact();
                if (isPlaying) {
                  _controller?.pause();
                } else {
                  _controller?.play();
                }
                _startControlsTimer();
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 34, // 适度缩小居中图标尺寸，避免遮挡视频画面
                    shadows: const [
                      Shadow(
                        color: Colors.black87,
                        blurRadius: 10,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 小屏控制条隐藏时的常驻微型极光进度条 (高度 2px，纯净观影且随时掌握播放进度)
  Widget _buildBottomMiniProgress() {
    if (_isFullScreen || !_isInitialized || _hasError) {
      return const SizedBox.shrink();
    }

    final totalMs = _controller?.value.duration.inMilliseconds ?? 0;
    final progressRatio = totalMs > 0
        ? (_currentPosition.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    // 当控制条呼出时隐藏，收起时无缝淡入
    final shouldShow = !_showControls;

    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: shouldShow ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: LinearProgressIndicator(
            value: progressRatio,
            minHeight: 2.0,
            backgroundColor: Colors.white12,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ),
    );
  }

  /// 现代毛玻璃控制顶栏与底栏 (带丝滑滑入滑出动画)
  Widget _buildControlOverlays() {
    // 顶部控制条仅在 全屏 / 有返回回调 / 有扩展操作 时参与渲染
    final showTopBar = _isFullScreen || widget.onBack != null || widget.extraActions != null;

    return Stack(
      children: [
        // 顶部控制条：隐藏时向上轻滑并淡出
        if (showTopBar)
          Align(
            alignment: Alignment.topCenter,
            child: _buildAnimatedBar(
              slideOffset: const Offset(0, -0.5),
              child: _buildTopBar(),
            ),
          ),

        // 底部控制条：隐藏时向下轻滑并淡出
        Align(
          alignment: Alignment.bottomCenter,
          child: _buildAnimatedBar(
            slideOffset: const Offset(0, 0.5),
            child: _buildBottomBar(),
          ),
        ),
      ],
    );
  }

  /// 通用控制条显隐动画：微位移与淡出同步播放，曲线统一自然
  Widget _buildAnimatedBar({
    required Offset slideOffset,
    required Widget child,
  }) {
    return IgnorePointer(
      ignoring: !_showControls,
      child: AnimatedSlide(
        offset: _showControls ? Offset.zero : slideOffset,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: _showControls ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          child: child,
        ),
      ),
    );
  }

  /// 顶部控制条 (全屏状态加大左右呼吸安全边距，避开刘海与圆角，右上角增加更多设置)
  Widget _buildTopBar() {
    final safePadding = MediaQuery.of(context).padding;
    final double leftPadding = _isFullScreen ? _fullscreenLeftPadding : 12.0;
    final double rightPadding = _isFullScreen ? _fullscreenRightPadding : 12.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        top: _isFullScreen ? (safePadding.top > 0 ? safePadding.top + 8 : 14) : 8,
        left: leftPadding,
        right: rightPadding,
        bottom: 16,
      ),
      child: Row(
        children: [
          if (_isFullScreen || widget.onBack != null)
            IconButton(
              icon: const Icon(Ionicons.chevronBackOutline, color: Colors.white, size: 22),
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
          // 右上角更多设置图标
          _buildMoreSettingsButton(),
        ],
      ),
    );
  }

  /// 顶部右上角「更多设置」按钮 (极简 LucideIcons 三点，全屏下右边缘与进度条/全屏键严格右对齐)
  Widget _buildMoreSettingsButton() {
    final icon = const Icon(Ionicons.ellipsisHorizontalOutline,
      color: Colors.white,
      size: 22,
    );

    if (_isFullScreen) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          _showMoreSettingsDrawer();
        },
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.centerRight,
          child: icon,
        ),
      );
    }

    return IconButton(
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 36, height: 36),
      onPressed: () {
        HapticFeedback.lightImpact();
        _showMoreSettingsDrawer();
      },
    );
  }

  /// 当前播放位置 (拖拽或滑动手势中优先取临时目标值，保证进度条跟手不回弹)
  Duration get _currentPosition {
    if (_isDraggingProgress) {
      final totalMs = _controller?.value.duration.inMilliseconds ?? 1;
      return Duration(milliseconds: (_dragProgressValue * totalMs).round());
    }
    if (_isSeeking) {
      return _seekTarget;
    }
    return _controller?.value.position ?? Duration.zero;
  }

  /// 底部控制条
  ///
  /// 采用两套布局分支：
  /// - 全屏（大屏）：左右边距与锁图标严格对齐（_fullscreenLeftPadding / _fullscreenRightPadding）；
  ///   进度条整体下沉贴地，时间移至进度条上方左侧（05:23 / 45:10），进度条全宽拉通；
  /// - 小屏（非全屏）：进度条与播放/时间/倍速/全屏垂直居中精准对齐在 38px 高度中线上，
  ///   消除多余外边距与垂直错位，彻底避免挤压溢出。
  Widget _buildBottomBar() {
    final safePadding = MediaQuery.of(context).padding;
    final double leftPadding = _isFullScreen ? _fullscreenLeftPadding : 8.0;
    final double rightPadding = _isFullScreen ? _fullscreenRightPadding : 8.0;
    final double bottomPadding = _isFullScreen
        ? (safePadding.bottom > 0 ? safePadding.bottom + 4.0 : 12.0)
        : 6.0;

    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      padding: EdgeInsets.only(
        left: leftPadding,
        right: rightPadding,
        bottom: bottomPadding,
        top: _isFullScreen ? 8 : 4,
      ),
      child: _isFullScreen ? _buildWideControlLayout() : _buildCompactControlLayout(),
    );
  }

  /// 全屏商业级布局：
  /// - 顶行：左上方显示「当前进度 / 总进度」时间组合文本（05:23 / 45:10）；
  /// - 中行：全宽拉通进度条（下沉微移 8px，紧贴下方操作按键图标，消除视觉空隙）；
  /// - 底行：播放/暂停键、倍速选择、退出全屏按键（紧凑排布）。
  Widget _buildWideControlLayout() {
    final duration = _controller?.value.duration ?? Duration.zero;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 进度条上方左侧：当前进度与总进度 (正常流式排布)
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildTimeText(_formatDuration(_currentPosition), primary: true),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                '/',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            _buildTimeText(_formatDuration(duration)),
          ],
        ),
        const SizedBox(height: 2),

        // 2. 进度条：标准紧凑高度流式嵌入，完全消除 Offset 偏移，布局真实直观
        _buildProgressSlider(),
        const SizedBox(height: 2),

        // 3. 控制按键行（播放/暂停、倍速、全屏，正常流式排列）
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _buildPlayPauseButton(),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildSpeedButton(),
                const SizedBox(width: 10),
                _buildFullscreenButton(),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// 小屏紧凑布局：播放、进度条、时间、全屏全部居中对齐在同一条水平中线上 (移除倍速按键，留白更舒展)
  Widget _buildCompactControlLayout() {
    final duration = _controller?.value.duration ?? Duration.zero;
    return SizedBox(
      height: 38,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildPlayPauseButton(compact: true),
          Expanded(child: _buildProgressSlider(compact: true)),
          const SizedBox(width: 6),
          // 小屏空间紧凑，起止时间合并为「当前/总长」等宽数字单段文本
          _buildTimeText(
            '${_formatDuration(_currentPosition)}/${_formatDuration(duration)}',
            primary: true,
            compact: true,
          ),
          const SizedBox(width: 4),
          _buildFullscreenButton(compact: true),
        ],
      ),
    );
  }

  /// 等宽数字时间文本 (tabularFigures 保证秒数变化时宽度不抖动)
  Widget _buildTimeText(String text, {bool primary = false, bool compact = false}) {
    return Text(
      text,
      style: TextStyle(
        color: primary ? Colors.white : Colors.white70,
        fontSize: compact ? 10 : 11,
        fontFeatures: const [FontFeature.tabularFigures()],
        fontWeight: primary ? FontWeight.w600 : FontWeight.w400,
      ),
    );
  }

  /// 极光翡翠流光进度条 (集成缓冲进度、统一粗细与加载流光扫光动画)
  Widget _buildProgressSlider({bool compact = false}) {
    final totalMs = _controller?.value.duration.inMilliseconds ?? 0;
    final progressRatio = totalMs > 0
        ? (_currentPosition.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    // 计算已加载缓冲比例
    double bufferedFraction = 0.0;
    if (_controller != null && totalMs > 0 && _controller!.value.buffered.isNotEmpty) {
      final lastBuffered = _controller!.value.buffered.last.end.inMilliseconds;
      bufferedFraction = (lastBuffered / totalMs).clamp(0.0, 1.0);
    }

    final isBuffering = !_isInitialized || (_controller?.value.isBuffering == true) || _isSeekingTo;

    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, child) {
        return SizedBox(
          height: compact ? 18 : 22,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackShape: AuraSliderTrackShape(
                bufferedFraction: bufferedFraction,
                isBuffering: isBuffering,
                shimmerProgress: _shimmerController.value,
              ),
              trackHeight: compact ? 2.5 : 3.5,
              thumbShape: RoundSliderThumbShape(
                enabledThumbRadius: _isDraggingProgress
                    ? (compact ? 6.0 : 7.0)
                    : (compact ? 4.5 : 5.5),
              ),
              overlayShape: RoundSliderOverlayShape(overlayRadius: compact ? 10 : 12),
              activeTrackColor: AppColors.primary,
              inactiveTrackColor: Colors.white24,
              thumbColor: AppColors.primary,
              overlayColor: AppColors.primary.withValues(alpha: 0.2),
            ),
          child: Slider(
            value: progressRatio,
            onChanged: (val) {
              if (!_isDraggingProgress) {
                _wasPlayingBeforeDrag = _controller?.value.isPlaying ?? false;
              }
              setState(() {
                _isDraggingProgress = true;
                _dragProgressValue = val;
              });
              _controlsTimer?.cancel();
            },
            onChangeEnd: (val) {
              if (_controller != null && totalMs > 0) {
                setState(() {
                  _isSeekingTo = true;
                });
                _controller!.seekTo(Duration(milliseconds: (val * totalMs).round())).then((_) {
                  if (mounted) {
                    if (_wasPlayingBeforeDrag) {
                      _controller?.play();
                    }
                    _seekToDebounceTimer?.cancel();
                    _seekToDebounceTimer = Timer(const Duration(milliseconds: 350), () {
                      if (mounted) {
                        setState(() {
                          _isSeekingTo = false;
                        });
                      }
                    });
                  }
                });
              }
              setState(() {
                _isDraggingProgress = false;
              });
              _startControlsTimer();
            },
          ),
        ),
      );
    },
  );
  }

  /// 播放 / 暂停按钮 (全屏下图标左边缘与进度条左边缘严格像素级对齐，防跳变播放状态判定)
  Widget _buildPlayPauseButton({bool compact = false}) {
    final isPlaying = _effectiveIsPlaying;
    // 采用现代流媒体标准圆润实心矢量图标，提升复杂画面背景下的辨识度与触觉质感
    final icon = Icon(
      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
      color: Colors.white,
      size: compact ? 22 : 24,
    );

    // 全屏模式下内容靠左紧贴，消除外围边距错位
    if (_isFullScreen) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (isPlaying) {
            _controller?.pause();
          } else {
            _controller?.play();
          }
          _startControlsTimer();
        },
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.centerLeft,
          child: icon,
        ),
      );
    }

    return IconButton(
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 32 : 38,
        height: compact ? 32 : 38,
      ),
      onPressed: () {
        if (isPlaying) {
          _controller?.pause();
        } else {
          _controller?.play();
        }
        _startControlsTimer();
      },
    );
  }

  /// 倍速选择按钮 (纯净无背景无边框悬浮字，带微立体文字投影与触觉反馈)
  Widget _buildSpeedButton() {
    final speed = _controller?.value.playbackSpeed ?? 1.0;
    // 1.0x 正常速度时直接显示“倍速”，非 1.0x 时显示当前倍率 (如 1.5x / 2x)
    final speedText = speed == 1.0
        ? '倍速'
        : (speed % 1 == 0 ? '${speed.toInt()}x' : '${speed}x');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        _showPlaybackSpeedDialog();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Text(
          speedText,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                color: Colors.black87,
                blurRadius: 6,
                offset: Offset(0, 1),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 全屏 / 退出全屏按钮 (全屏下图标右边缘与进度条右边缘严格像素级对齐)
  Widget _buildFullscreenButton({bool compact = false}) {
    // 采用现代流媒体标准圆角全屏切换图标，四角圆润规整，视觉平衡感更强
    final icon = Icon(
      _isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded,
      color: Colors.white,
      size: compact ? 22 : 24,
    );

    // 全屏模式下内容靠右紧贴，消除外围边距错位
    if (_isFullScreen) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleFullScreen,
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.centerRight,
          child: icon,
        ),
      );
    }

    return IconButton(
      icon: icon,
      padding: EdgeInsets.zero,
      constraints: BoxConstraints.tightFor(
        width: compact ? 32 : 38,
        height: compact ? 32 : 38,
      ),
      onPressed: _toggleFullScreen,
    );
  }

  /// 从右侧滑出全屏半透明倍速选择抽屉面板 (腾讯视频/B站全屏流媒体范式)
  void _showPlaybackSpeedDialog() {
    _controlsTimer?.cancel();
    final speeds = [2.0, 1.5, 1.25, 1.0, 0.75, 0.5];
    final currentSpeed = _controller?.value.playbackSpeed ?? 1.0;

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'SpeedDrawer',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: 210,
                  height: double.infinity,
                  color: Colors.black.withValues(alpha: 0.52),
                  child: SafeArea(
                    left: false,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 顶部标题栏
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '播放倍速',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              GestureDetector(
                                onTap: () => Navigator.pop(dialogContext),
                                child: const Icon(Ionicons.closeOutline, color: Colors.white60, size: 18),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: Colors.white.withValues(alpha: 0.08),
                        ),

                        // 倍速选项列表 (垂直排布)
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: speeds.length,
                            itemBuilder: (context, index) {
                              final speed = speeds[index];
                              final isSelected = (currentSpeed - speed).abs() < 0.01;
                              final label = speed == 1.0 ? '1.0x (正常)' : '${speed}x';

                              return InkWell(
                                onTap: () {
                                  HapticFeedback.lightImpact();
                                  _controller?.setPlaybackSpeed(speed);
                                  _normalSpeed = speed;
                                  setState(() {});
                                  Navigator.pop(dialogContext);
                                  _startControlsTimer();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        label,
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                          color: isSelected ? AppColors.primary : Colors.white,
                                        ),
                                      ),
                                      if (isSelected)
                                        Container(
                                          width: 6,
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary,
                                            shape: BoxShape.circle,
                                            boxShadow: [
                                              BoxShadow(
                                                color: AppColors.primary.withValues(alpha: 0.6),
                                                blurRadius: 6,
                                                spreadRadius: 1,
                                              ),
                                            ],
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
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 从右侧滑出全屏半透明播放更多设置抽屉面板 (对标腾讯视频/B站全屏流媒体设置体系)
  void _showMoreSettingsDrawer() {
    _controlsTimer?.cancel();

    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'MoreSettingsDrawer',
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
            ),
          ),
          child: child,
        );
      },
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: ClipRRect(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: Container(
                  width: 280,
                  height: double.infinity,
                  color: Colors.black.withValues(alpha: 0.55),
                  child: SafeArea(
                    left: false,
                    child: StatefulBuilder(
                      builder: (context, setDrawerState) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // 顶部标题栏
                            Padding(
                              padding: const EdgeInsets.fromLTRB(20, 20, 16, 14),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    '播放设置',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: () => Navigator.pop(dialogContext),
                                    child: const Icon(Ionicons.closeOutline, color: Colors.white60, size: 20),
                                  ),
                                ],
                              ),
                            ),
                            Divider(height: 1, color: Colors.white.withValues(alpha: 0.08)),

                            // 设置列表项滚动区
                            Expanded(
                              child: ListView(
                                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                children: [
                                  // 1. 画面比例
                                  const Text(
                                    '画面比例',
                                    style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _buildFitChip('适应', BoxFit.contain, setDrawerState),
                                      const SizedBox(width: 8),
                                      _buildFitChip('铺满', BoxFit.cover, setDrawerState),
                                      const SizedBox(width: 8),
                                      _buildFitChip('拉伸', BoxFit.fill, setDrawerState),
                                    ],
                                  ),

                                  const SizedBox(height: 20),
                                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                                  const SizedBox(height: 16),

                                  // 2. 画面视效与播放循环
                                  const Text(
                                    '播放视效与控制',
                                    style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 8),

                                  // 镜像翻转开关 (舞蹈/跟练神器)
                                  _buildSettingSwitchRow(
                                    title: '画面水平镜像',
                                    subtitle: '适合舞蹈、跟练与教程视频左右镜像观看',
                                    value: _isMirrored,
                                    onChanged: (val) {
                                      HapticFeedback.lightImpact();
                                      setState(() {
                                        _isMirrored = val;
                                      });
                                      setDrawerState(() {});
                                    },
                                  ),

                                  // 循环播放开关
                                  _buildSettingSwitchRow(
                                    title: '单视频循环播放',
                                    subtitle: '播放结束时自动从头接力播放',
                                    value: _isLooping,
                                    onChanged: (val) {
                                      HapticFeedback.lightImpact();
                                      setState(() {
                                        _isLooping = val;
                                      });
                                      setDrawerState(() {});
                                    },
                                  ),

                                  const SizedBox(height: 14),
                                  Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
                                  const SizedBox(height: 16),

                                  // 3. 长按瞬时加速
                                  const Text(
                                    '长按加速配置',
                                    style: TextStyle(color: Colors.white60, fontSize: 12, fontWeight: FontWeight.w500),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildSettingSwitchRow(
                                    title: '长按瞬时快进',
                                    subtitle: '长按画面任意处即可按设定倍速快速播放',
                                    value: appService.settings.enableLongPress2x,
                                    onChanged: (val) {
                                      HapticFeedback.lightImpact();
                                      appService.updateSettings(appService.settings.copyWith(enableLongPress2x: val));
                                      setDrawerState(() {});
                                    },
                                  ),
                                  if (appService.settings.enableLongPress2x) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        _buildSpeedChip(2.0, setDrawerState),
                                        const SizedBox(width: 8),
                                        _buildSpeedChip(3.0, setDrawerState),
                                        const SizedBox(width: 8),
                                        _buildSpeedChip(5.0, setDrawerState),
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 辅助构建画面比例选择胶囊
  Widget _buildFitChip(String label, BoxFit fit, StateSetter setDrawerState) {
    final isSelected = _videoFit == fit;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          setState(() {
            _videoFit = fit;
          });
          setDrawerState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  /// 辅助构建长按加速倍率选择胶囊
  Widget _buildSpeedChip(double speed, StateSetter setDrawerState) {
    final isSelected = appService.settings.longPressSpeed == speed;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          appService.updateSettings(appService.settings.copyWith(longPressSpeed: speed));
          setDrawerState(() {});
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            '${speed.toInt()}x 快进',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected ? Colors.white : Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  /// 辅助构建设置开关行
  Widget _buildSettingSwitchRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 10.5),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.78,
            child: Switch(
              value: value,
              activeThumbColor: AppColors.primary,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.35),
              inactiveThumbColor: Colors.white60,
              inactiveTrackColor: Colors.white12,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
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
              const Icon(Ionicons.warningOutline, color: Colors.amber, size: 36),
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
                icon: const Icon(Ionicons.refreshOutline, size: 16),
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

/// 自定义纯净流光进度条轨道形状
///
/// 1. 彻底消除 Flutter 原生 `Slider` 默认左右强制 24px 的内缩留白边距；
/// 2. 严密统一未加载(背景轨)、已加载(缓冲轨)、已播放(翡翠轨)的高度与圆角，彻底消除粗细断层感；
/// 3. 支持网络缓冲/加载中的动态羽化流光光斑扫光动画。
class AuraSliderTrackShape extends RoundedRectSliderTrackShape {
  const AuraSliderTrackShape({
    this.bufferedFraction = 0.0,
    this.isBuffering = false,
    this.shimmerProgress = 0.0,
  });

  /// 已加载缓冲比例 (0.0 ~ 1.0)
  final double bufferedFraction;

  /// 是否处于缓冲加载中
  final bool isBuffering;

  /// 流光扫光动画进度 (0.0 ~ 1.0)
  final double shimmerProgress;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight ?? 3.5;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    if (sliderTheme.trackHeight == null || sliderTheme.trackHeight! <= 0) {
      return;
    }

    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );

    final double trackHeight = trackRect.height;
    final Radius trackRadius = Radius.circular(trackHeight / 2);
    final RRect fullRRect = RRect.fromRectAndRadius(trackRect, trackRadius);

    final Canvas canvas = context.canvas;

    // 1. 底层：未加载背景轨道（高度严格等于 trackHeight，圆角严格统一）
    final Paint inactivePaint = Paint()
      ..color = sliderTheme.inactiveTrackColor ?? Colors.white24
      ..style = PaintingStyle.fill;
    canvas.drawRRect(fullRRect, inactivePaint);

    // 2. 中层：已加载缓冲轨道（Buffered Track，与未加载保持完全一致粗细）
    if (bufferedFraction > 0.0) {
      final double bufferedWidth = (trackRect.width * bufferedFraction.clamp(0.0, 1.0));
      final Rect bufferedRect = Rect.fromLTWH(
        trackRect.left,
        trackRect.top,
        bufferedWidth,
        trackHeight,
      );
      final Paint bufferedPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;

      canvas.save();
      canvas.clipRRect(fullRRect);
      canvas.drawRect(bufferedRect, bufferedPaint);
      canvas.restore();
    }

    // 3. 顶层：已播放极光翡翠轨道 (Active Track，高度与未加载完全一样粗)
    final double activeWidth = (thumbCenter.dx - trackRect.left).clamp(0.0, trackRect.width);
    final Rect activeRect = Rect.fromLTWH(
      trackRect.left,
      trackRect.top,
      activeWidth,
      trackHeight,
    );
    final Paint activePaint = Paint()
      ..color = sliderTheme.activeTrackColor ?? AppColors.primary
      ..style = PaintingStyle.fill;

    canvas.save();
    canvas.clipRRect(fullRRect);
    canvas.drawRect(activeRect, activePaint);
    canvas.restore();

    // 4. 加载/缓冲状态动效：严格仅在【未加载区域 (Unloaded Area)】流动呈现
    if (isBuffering) {
      final double bufferedWidth = (trackRect.width * bufferedFraction.clamp(0.0, 1.0));
      final double loadedRight = math.max(activeRect.right, trackRect.left + bufferedWidth);
      final double unloadedLeft = loadedRight;
      final double unloadedWidth = trackRect.right - unloadedLeft;

      // 仅当存在未加载的空白轨道时执行未加载专属动画
      if (unloadedWidth > 4.0) {
        final Rect unloadedRect = Rect.fromLTWH(unloadedLeft, trackRect.top, unloadedWidth, trackHeight);

        canvas.save();
        canvas.clipRRect(fullRRect); // 约束在圆角轨道内
        canvas.clipRect(unloadedRect); // 严格约束仅在未加载空白区域内

        // A. 未加载区域柔和呼吸底色 (Breathing Pulse)
        final double pulseOpacity = 0.12 + 0.10 * (0.5 + 0.5 * math.sin(shimmerProgress * 2 * math.pi));
        final Paint pulsePaint = Paint()
          ..color = Colors.white.withValues(alpha: pulseOpacity)
          ..style = PaintingStyle.fill;
        canvas.drawRect(unloadedRect, pulsePaint);

        // B. 未加载区域专属流光光斑 (Shimmer Sweep，从缓冲端点向右掠过)
        final double shimmerWidth = math.max(unloadedWidth * 0.45, 36.0);
        final double shimmerLeft = unloadedLeft - shimmerWidth + (unloadedWidth + shimmerWidth * 2) * shimmerProgress;
        final Rect shimmerRect = Rect.fromLTWH(shimmerLeft, trackRect.top, shimmerWidth, trackHeight);

        final Paint shimmerPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              Colors.transparent,
              Colors.white.withValues(alpha: 0.60),
              Colors.transparent,
            ],
          ).createShader(shimmerRect);

        canvas.drawRect(shimmerRect, shimmerPaint);

        // C. 已缓冲端点向右微光波纹 (Buffer Head Glow)
        final double headGlowWidth = 14.0;
        final Rect headGlowRect = Rect.fromLTWH(unloadedLeft, trackRect.top, headGlowWidth, trackHeight);
        final Paint headGlowPaint = Paint()
          ..shader = LinearGradient(
            colors: [
              AppColors.primary.withValues(alpha: 0.70),
              Colors.transparent,
            ],
          ).createShader(headGlowRect);
        canvas.drawRect(headGlowRect, headGlowPaint);

        canvas.restore();
      }
    }
  }
}

