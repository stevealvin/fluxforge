import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:video_player/video_player.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/shared/widgets/player/player_capsules.dart';
import 'package:fluxforge/shared/widgets/player/player_control_bar.dart';
import 'package:fluxforge/shared/widgets/player/player_gesture_engine.dart';
import 'package:fluxforge/shared/widgets/player/player_gesture_layer.dart';
import 'package:fluxforge/shared/widgets/player/player_overlays.dart';
import 'package:fluxforge/shared/widgets/player/player_settings_sheets.dart';
import 'package:fluxforge/shared/widgets/player/player_top_bar.dart';
import 'package:fluxforge/shared/widgets/player/player_video_surface.dart';
import 'package:fluxforge/shared/widgets/player/player_track_shape.dart';
import 'package:fluxforge/shared/widgets/player/player_preferences.dart';

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
    this.preferences = const PlayerPreferences(),
    this.onPreferencesChanged,
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

  /// 播放偏好（由宿主注入 —— 播放器自身不直连任何设置仓储，保证可复用性）
  final PlayerPreferences preferences;

  /// 偏好变更回调（用户在播放器内调整长按加速等设置时，通知宿主持久化）
  final ValueChanged<PlayerPreferences>? onPreferencesChanged;

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

  // 常亮需求计数（静态）：小屏/全屏是共享控制器的多实例，Wakelock 是全局单例，
  // 实例级去重会被旧实例 dispose 的 disable 误关常亮，故以全局计数收敛
  static int _wakelockDemandCount = 0;

  /// 本实例是否已计入常亮需求
  bool _wakelockDemanded = false;

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

  /// 浮点累积的滑动偏移秒数
  ///
  /// 若对每帧增量先取整再累加，慢速滑动时单帧增量（往往不足 0.5 秒）会被
  /// round 截断为 0，形成「一顿一停、偶尔跳 1 秒」的顿挫感；改为浮点累积、
  /// 仅在渲染时取整，滑动即可完全跟手。
  double _seekDeltaRawSeconds = 0.0;

  /// 手势预览刷新信号 (自增计数)
  ///
  /// 左右滑动寻道期间只更新该 notifier，让中央胶囊、进度条与时间文本局部重建，
  /// 不再调用 setState 重建整棵播放器树，从根本上消除滑动掉帧。
  final ValueNotifier<int> _seekPreviewTick = ValueNotifier<int>(0);

  // 长按瞬时加速 (倍率与开关均实时读取当前生效偏好)
  bool _isFastForwarding = false;
  double _normalSpeed = 1.0;

  /// 当前生效的播放偏好（本地副本）
  ///
  /// 面板改动必须本地立即生效：全屏是独立路由，宿主 rebuild 不会重建它，
  /// 若只读 [AuraPlayer.preferences]，会出现「全屏内改设置、退出全屏才生效」。
  late PlayerPreferences _preferences = widget.preferences;

  /// 长按瞬时加速是否启用
  bool get _longPressEnabled => _preferences.longPressBoostEnabled;

  /// 长按瞬时加速倍率 (可选 2.0 / 3.0 / 5.0)
  double get _longPressSpeed => _preferences.longPressSpeed;

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

  /// 播放中保持屏幕常亮，暂停/结束/退出时解除（多实例经全局计数收敛）
  void _updateWakelock(bool enable) {
    if (enable == _wakelockDemanded) return;
    _wakelockDemanded = enable;
    _wakelockDemandCount += enable ? 1 : -1;
    if (_wakelockDemandCount > 0) {
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

    // 缓冲动效动画控制器（仅缓冲期间运行，见 [_syncShimmerTicker]）
    // 周期 3000ms：条纹一个完整周期 32px，线速度与原 14px/1400ms 基本持平
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    );

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

    _syncShimmerTicker();
  }

  /// 按当前缓冲状态启停扫光动画
  ///
  /// 扫光只在「未加载空白轨道」上有视觉意义（见 `AuraSliderTrackShape.paint`），
  /// 若常驻 `repeat()`，播放器在详情页常驻（含暂停、控制栏隐藏）时会一直跑
  /// 60fps ticker 并持续重建进度条，白白耗电。
  void _syncShimmerTicker() {
    final buffering = !_hasError &&
        (!_isInitialized ||
            (_controller?.value.isBuffering ?? true) ||
            _isSeekingTo);
    if (buffering) {
      if (!_shimmerController.isAnimating) _shimmerController.repeat();
    } else if (_shimmerController.isAnimating) {
      _shimmerController.stop();
    }
  }

  @override
  void didUpdateWidget(covariant AuraPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 外部（设置页等）偏好变更经宿主回灌到本地副本
    if (widget.preferences != oldWidget.preferences) {
      _preferences = widget.preferences;
    }
    if (widget.controller == null &&
        (oldWidget.playUrl != widget.playUrl ||
            !mapEquals(oldWidget.httpHeaders, widget.httpHeaders))) {
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
    _seekPreviewTick.dispose();

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
      _syncShimmerTicker();
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
    _syncShimmerTicker();

    try {
      final url = widget.playUrl.trim();
      // 本地已下载的视频走 file:// URI：Android 侧 ExoPlayer 直接支持，
      // 不引入 dart:io（避免破坏 web 构建路径，下载能力在 web 上本就不可用）
      final isLocal =
          !url.startsWith('http://') && !url.startsWith('https://');
      if (isLocal) {
        final normalized = url.startsWith('file://') ? url : 'file://$url';
        _controller = VideoPlayerController.contentUri(Uri.parse(normalized));
      } else {
        _controller = VideoPlayerController.networkUrl(
          Uri.parse(url),
          httpHeaders: widget.httpHeaders,
        );
      }

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
      _syncShimmerTicker();

      _startControlsTimer();
    } catch (e) {
      if (!mounted) return;
      _updateWakelock(false);
      setState(() {
        _hasError = true;
        _errorMessage = '视频解析或加载失败: $e';
      });
      _syncShimmerTicker();
    }
  }

  /// 视频播放器帧状态监听
  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final value = _controller!.value;

    // 同步常亮：播放中常亮，其余解除
    final isPlaying = value.isInitialized && value.isPlaying && !value.hasError;
    _updateWakelock(isPlaying);

    _syncShimmerTicker();

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

    // 水平滑动寻道进行中：进度显示由 _seekPreviewTick 驱动局部刷新，
    // 此处跳过整树刷新，避免「播放帧回调 + 手势回调」双重重建导致掉帧
    if (_isSeeking) return;

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
              // 用本地副本而非 widget 参数：宿主尚未回灌时也要带上最新偏好
              preferences: _preferences,
              onPreferencesChanged: widget.onPreferencesChanged,
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
      _updateWakelock(_controller?.value.isPlaying ?? false);
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
        //    仅该浮层随手势局部重建，拖动过程不触及整棵播放器树
        ValueListenableBuilder<int>(
          valueListenable: _seekPreviewTick,
          builder: (context, _, _) {
            if (!_isSeeking) return const SizedBox.shrink();
            return _buildSeekingCapsule();
          },
        ),

        // 7. 手势浮层：长按加速中微胶囊（含当前倍数）
        if (_isFastForwarding) _buildFastForwardCapsule(),

        // 8. 断点续播提醒气泡
        if (_showResumeTip) _buildResumeTip(),

        // 9. 现代毛玻璃 UI 控制栏 (顶栏、底栏) — 常驻渲染，由内部动画驱动显隐
        if (_isInitialized) _buildControlOverlays(),

        // 11. 浮动锁屏按钮 (仅全屏模式出现、加宽左边距、支持单锁显隐)
        if (_isInitialized && _isFullScreen)
          PlayerLockButton(
            // 锁定态由 _showLockIcon 决定（点击屏幕唤醒，5.0 秒后自动隐去），
            // 未锁定态跟随控制栏 _showControls
            visible: _isLocked ? _showLockIcon : _showControls,
            isLocked: _isLocked,
            left: _fullscreenLeftPadding,
            onToggle: _onToggleLock,
          ),

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

  /// 视频渲染核心区域 (比例调节与镜像翻转，渲染见 [PlayerVideoSurface])
  Widget _buildVideoSurface() {
    return PlayerVideoSurface(
      isInitialized: _isInitialized,
      controller: _controller,
      fit: _videoFit,
      isMirrored: _isMirrored,
      coverUrl: widget.coverUrl,
    );
  }

  /// 锁定状态下的极简防误触手势层（点击切换锁图标显隐，见 [PlayerLockedGestureLayer]）
  Widget _buildLockedGestureLayer() {
    return PlayerLockedGestureLayer(
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
    );
  }

  /// 手势交互捕获层 (未锁定时)
  ///
  /// 接线与归一化换算见 [PlayerGestureLayer]，分区判定与滑动算法见 [PlayerGestureEngine]；
  /// 这里只表达「手势意味着什么状态变化」。
  Widget _buildGestureLayer() {
    return PlayerGestureLayer(
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
      onLongPressStart: () {
        if (!_longPressEnabled) return; // 用户已关闭长按加速
        HapticFeedback.lightImpact(); // 原生轻触觉震动反馈
        _normalSpeed = _controller?.value.playbackSpeed ?? 1.0;
        _controller?.setPlaybackSpeed(_longPressSpeed);
        setState(() {
          _isFastForwarding = true;
        });
      },
      onLongPressEnd: () {
        // 未真正进入加速态时无需恢复原速
        if (!_isFastForwarding) return;
        _controller?.setPlaybackSpeed(_normalSpeed);
        setState(() {
          _isFastForwarding = false;
        });
      },
      // 垂直与水平滑动手势判定
      onVerticalDragStart: () => _controlsTimer?.cancel(),
      // 垂直滑动：左 35% 亮度 / 右 35% 音量（分区已由手势层判定）
      onVerticalDragUpdate: (zone, deltaRatio) {
        if (zone == PlayerGestureZone.brightness) {
          setState(() {
            _brightness = PlayerGestureEngine.applyVerticalDrag(
              current: _brightness,
              deltaRatio: deltaRatio,
              min: 0.15,
              max: 1.0,
            );
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
        } else if (zone == PlayerGestureZone.volume) {
          setState(() {
            _volume = PlayerGestureEngine.applyVerticalDrag(
              current: _volume,
              deltaRatio: deltaRatio,
              min: 0.0,
              max: 1.0,
            );
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
      onHorizontalDragStart: () {
        if (_controller == null || !_controller!.value.isInitialized) return;
        _controlsTimer?.cancel();
        _wasPlayingBeforeDrag = _controller!.value.isPlaying;
        _seekDeltaRawSeconds = 0.0;
        setState(() {
          _isSeeking = true;
          _seekStartPos = _controller!.value.position;
          _seekTarget = _seekStartPos;
          _seekDeltaSeconds = 0;
        });
        _seekPreviewTick.value++;
      },
      onHorizontalDragUpdate: (deltaRatio) {
        if (!_isSeeking) return;
        final value = _controller?.value;
        if (value == null || !value.isInitialized) return;

        // 浮点累积 + 毫秒精度 + 越界位移回写，统一由引擎处理
        final resolved = PlayerGestureEngine.resolveSeekTarget(
          startPosition: _seekStartPos,
          accumulatedSeconds: _seekDeltaRawSeconds,
          deltaRatio: deltaRatio,
          totalDuration: value.duration,
        );
        _seekDeltaRawSeconds = resolved.accumulatedSeconds;
        _seekTarget = resolved.target;
        _seekDeltaSeconds =
            PlayerGestureEngine.displayDeltaSeconds(resolved.accumulatedSeconds);

        // 只刷新手势浮层与进度显示，不触发整树重建
        _seekPreviewTick.value++;
      },
      onHorizontalDragEnd: () {
        if (_isSeeking && _controller != null) {
          setState(() {
            _isSeeking = false;
            _isSeekingTo = true;
          });
          _seekPreviewTick.value++;
          _syncShimmerTicker();
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
                  _syncShimmerTicker();
                }
              });
            }
          });
          _startControlsTimer();
        }
      },
    );
  }

  /// 左侧垂直胶囊亮度指示条
  Widget _buildBrightnessCapsule() {
    return PlayerVerticalIndicatorCapsule(
      side: PlayerCapsuleSide.left,
      // 全屏下避让左侧控制区，偏移更大
      offset: _isFullScreen ? 68 : 16,
      icon: Ionicons.sunnyOutline,
      value: _brightness,
    );
  }

  /// 右侧垂直胶囊音量指示条
  Widget _buildVolumeCapsule() {
    return PlayerVerticalIndicatorCapsule(
      side: PlayerCapsuleSide.right,
      offset: 20,
      // 静音 / 低音量 / 高音量三态图标由页面按业务语义决定
      icon: _volume == 0
          ? Ionicons.volumeMuteOutline
          : (_volume > 0.5
              ? Ionicons.volumeHighOutline
              : Ionicons.volumeLowOutline),
      value: _volume,
    );
  }

  /// 居中微拟态快进/快退胶囊 (双行紧凑布局：上行方向+秒数，下行时间进度，主次分明)
  Widget _buildSeekingCapsule() {
    final totalDuration = _controller?.value.duration ?? Duration.zero;
    return PlayerSeekingCapsule(
      deltaSeconds: _seekDeltaSeconds,
      targetLabel:
          '${_formatDuration(_seekTarget)} / ${_formatDuration(totalDuration)}',
    );
  }

  /// 长按瞬时加速顶部微胶囊（毛玻璃翡翠图标 + 当前倍数）
  Widget _buildFastForwardCapsule() =>
      PlayerFastForwardCapsule(speed: _longPressSpeed);

  /// 断点续播提醒气泡（渲染见 [PlayerResumeTip]）
  Widget _buildResumeTip() {
    return PlayerResumeTip(
      formattedPosition: _formatDuration(widget.initialPosition),
      onContinue: () {
        _controller?.seekTo(widget.initialPosition);
        setState(() {
          _showResumeTip = false;
        });
      },
      onDismiss: () {
        setState(() {
          _showResumeTip = false;
        });
      },
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

  /// 小屏控制条隐藏时的常驻微型极光进度条
  ///
  /// 渲染守卫（全屏 / 未初始化 / 播放错误）留在页面侧，视觉与动画见 [PlayerBottomMiniProgress]。
  Widget _buildBottomMiniProgress() {
    if (_isFullScreen || !_isInitialized || _hasError) {
      return const SizedBox.shrink();
    }

    return PlayerBottomMiniProgress(
      visible: !_showControls,
      seekPreviewTick: _seekPreviewTick,
      currentPosition: () => _currentPosition,
      totalMilliseconds: _controller?.value.duration.inMilliseconds ?? 0,
    );
  }

  /// 现代毛玻璃控制顶栏与底栏 (带丝滑滑入滑出动画，见 [PlayerControlOverlays])
  Widget _buildControlOverlays() {
    // 顶部控制条仅在 全屏 / 有返回回调 / 有扩展操作 时参与渲染
    final showTopBar =
        _isFullScreen || widget.onBack != null || widget.extraActions != null;

    return PlayerControlOverlays(
      showControls: _showControls,
      topBar: showTopBar ? _buildTopBar() : null,
      bottomBar: _buildBottomBar(),
    );
  }

  /// 顶部控制条 (全屏加大左右呼吸安全边距，避开刘海与圆角；渲染见 [PlayerTopBar])
  Widget _buildTopBar() {
    final safePadding = MediaQuery.of(context).padding;
    return PlayerTopBar(
      title: widget.title,
      isFullScreen: _isFullScreen,
      showBackButton: _isFullScreen || widget.onBack != null,
      extraActions: widget.extraActions,
      padding: EdgeInsets.only(
        top: _isFullScreen
            ? (safePadding.top > 0 ? safePadding.top + 8 : 14)
            : 8,
        left: _isFullScreen ? _fullscreenLeftPadding : 12.0,
        right: _isFullScreen ? _fullscreenRightPadding : 12.0,
        bottom: 16,
      ),
      onBack: () {
        if (_isFullScreen) {
          _toggleFullScreen();
        } else if (widget.onBack != null) {
          widget.onBack!();
        } else {
          Navigator.maybePop(context);
        }
      },
      onOpenMoreSettings: _showMoreSettingsDrawer,
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
    return PlayerControlBar(
      isFullScreen: _isFullScreen,
      padding: EdgeInsets.only(
        left: _isFullScreen ? _fullscreenLeftPadding : 8.0,
        right: _isFullScreen ? _fullscreenRightPadding : 8.0,
        bottom: _isFullScreen
            ? (safePadding.bottom > 0 ? safePadding.bottom + 4.0 : 12.0)
            : 6.0,
        top: _isFullScreen ? 8 : 4,
      ),
      isPlaying: _effectiveIsPlaying,
      currentPosition: () => _currentPosition,
      duration: _controller?.value.duration ?? Duration.zero,
      playbackSpeed: _controller?.value.playbackSpeed ?? 1.0,
      seekPreviewTick: _seekPreviewTick,
      formatDuration: _formatDuration,
      progressSlider: ({required bool compact}) =>
          _buildProgressSlider(compact: compact),
      onTogglePlay: () {
        if (_effectiveIsPlaying) {
          _controller?.pause();
        } else {
          _controller?.play();
        }
        _startControlsTimer();
      },
      onOpenSpeedDrawer: _showPlaybackSpeedDialog,
      onToggleFullScreen: _toggleFullScreen,
    );
  }

  /// 极光翡翠流光进度条 (集成缓冲进度、统一粗细与加载流光扫光动画)
  Widget _buildProgressSlider({bool compact = false}) {
    final totalMs = _controller?.value.duration.inMilliseconds ?? 0;

    // 计算已加载缓冲比例
    double bufferedFraction = 0.0;
    if (_controller != null && totalMs > 0 && _controller!.value.buffered.isNotEmpty) {
      final lastBuffered = _controller!.value.buffered.last.end.inMilliseconds;
      bufferedFraction = (lastBuffered / totalMs).clamp(0.0, 1.0);
    }

    final isBuffering = !_isInitialized || (_controller?.value.isBuffering == true) || _isSeekingTo;

    // 订阅手势预览信号：滑动寻道时滑块实时跟手，且只重建进度条自身
    return ValueListenableBuilder<int>(
      valueListenable: _seekPreviewTick,
      builder: (context, _, _) => _buildProgressSliderBody(
        compact: compact,
        totalMs: totalMs,
        bufferedFraction: bufferedFraction,
        isBuffering: isBuffering,
      ),
    );
  }

  /// 进度条主体 (拆分为独立方法，便于随手势预览信号局部重建)
  Widget _buildProgressSliderBody({
    required bool compact,
    required int totalMs,
    required double bufferedFraction,
    required bool isBuffering,
  }) {
    final progressRatio = totalMs > 0
        ? (_currentPosition.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

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
                _syncShimmerTicker();
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
                        _syncShimmerTicker();
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

  /// 从右侧滑出全屏半透明倍速选择抽屉面板 (腾讯视频/B站全屏流媒体范式)
  void _showPlaybackSpeedDialog() {
    _controlsTimer?.cancel();
    showPlayerSpeedDrawer(
      context: context,
      currentSpeed: _controller?.value.playbackSpeed ?? 1.0,
      onSpeedSelected: (speed) {
        _controller?.setPlaybackSpeed(speed);
        _normalSpeed = speed;
        setState(() {});
        _startControlsTimer();
      },
    );
  }

  /// 从右侧滑出全屏半透明播放更多设置抽屉面板 (对标腾讯视频/B站全屏流媒体设置体系)
  void _showMoreSettingsDrawer() {
    _controlsTimer?.cancel();
    showPlayerMoreSettingsDrawer(
      context: context,
      isMirrored: _isMirrored,
      isLooping: _isLooping,
      videoFit: _videoFit,
      preferences: _preferences,
      onMirroredChanged: (val) => setState(() => _isMirrored = val),
      onLoopingChanged: (val) => setState(() => _isLooping = val),
      onVideoFitChanged: (val) => setState(() => _videoFit = val),
      onPreferencesChanged: (next) {
        // 先本地生效（全屏路由不随宿主重建），再上抛宿主持久化
        setState(() => _preferences = next);
        widget.onPreferencesChanged?.call(next);
      },
    );
  }

  /// 加载中或错误状态指示层（具体渲染见 [PlayerStateOverlay]）
  Widget _buildStateOverlay() => PlayerStateOverlay(
        hasError: _hasError,
        errorMessage: _errorMessage,
        onRetry: _initializePlayer,
      );
}



