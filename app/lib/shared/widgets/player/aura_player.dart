import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:screen_brightness/screen_brightness.dart';
import 'package:video_player/video_player.dart';
import 'package:volume_controller/volume_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:fluxforge/shared/widgets/player/player_capsules.dart';
import 'package:fluxforge/shared/widgets/player/player_completion_engine.dart';
import 'package:fluxforge/shared/widgets/player/player_control_bar.dart';
import 'package:fluxforge/shared/widgets/player/player_fullscreen_route.dart';
import 'package:fluxforge/shared/widgets/player/player_gesture_engine.dart';
import 'package:fluxforge/shared/widgets/player/player_gesture_layer.dart';
import 'package:fluxforge/shared/widgets/player/player_overlays.dart';
import 'package:fluxforge/shared/widgets/player/player_settings_sheets.dart';
import 'package:fluxforge/shared/widgets/player/player_top_bar.dart';
import 'package:fluxforge/shared/widgets/player/player_video_surface.dart';
import 'package:fluxforge/shared/widgets/player/player_gesture_feedback_layer.dart';
import 'package:fluxforge/shared/widgets/player/player_preferences.dart';
import 'package:fluxforge/shared/widgets/player/player_progress_slider.dart';
import 'package:fluxforge/shared/widgets/player/player_refresh_engine.dart';

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
    this.active = true,
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

  /// 本实例是否处于活动状态（宿主被全屏路由遮挡期间传 `false`）
  ///
  /// 小屏实例不能卸载 —— 控制器由它创建并持有，卸载会连带销毁全屏正在使用的控制器。
  /// 置为不活动后：不重建、不驱动扫光、交还常亮、**不触发 [onEnded]**
  /// （两实例共用控制器，都回调会让宿主跳集跳两集）；
  /// 但保留 [onProgress] 上报，宿主的续播进度不能在全屏期间断档。
  final bool active;

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
  //
  // 数值与其**显示**已分离：这里只保留作用于「真实设备」的权威值，
  // 胶囊反馈（可见性 / 定时隐藏）由 PlayerGestureFeedbackLayer 自己持有。

  /// 系统音量（0.0 ~ 1.0）——经 `volume_controller` 直接作用于系统音量，
  /// 不再使用播放器实例音量（否则会与系统音量形成两个互相打架的音量维度）
  double _volume = 1.0;

  /// 屏幕亮度（0.0 ~ 1.0）——经 `screen_brightness` 作用于**应用级真实屏幕背光**
  /// （零权限，随应用生命周期自动重置；不再使用黑色遮罩压暗）
  double _brightness = 1.0;

  /// 用户是否已用手势调整过亮度：未调整过时不在生命周期回调里写回，避免无谓改屏
  bool _brightnessAdjusted = false;

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

  /// 位置刷新心跳（自增计数）
  ///
  /// 位置类 UI（快进胶囊、进度条、时间文本、迷你进度条）订阅它局部重建，
  /// 帧回调只递增心跳、不 setState；状态变化才整树重建（见 [_onControllerUpdate]）。
  /// 手势寻道与进度条拖拽同样递增它。
  final ValueNotifier<int> _positionTick = ValueNotifier<int>(0);

  /// 帧回调刷新策略：区分「状态变化（整树重建一次）」与「位置推进（心跳局部刷新）」
  final PlayerRefreshEngine _refreshEngine = PlayerRefreshEngine();

  /// 播完判定：以平台 completed 事件为主判据 + 每轮播放只上报一次的闩锁
  final PlayerCompletionEngine _completionEngine = PlayerCompletionEngine();

  /// 亮度 / 音量浮层的状态入口
  ///
  /// 数值由本页算好后推入（见 [_buildGestureLayer]）：浮层自己管可见性、定时隐藏
  /// 与内部刷新心跳，因此浮层显隐与逐帧数值更新都不再 setState 到本页 ——
  /// 原先每次显隐都会重建整棵播放器树。
  final GlobalKey<PlayerGestureFeedbackLayerState> _feedbackKey =
      GlobalKey<PlayerGestureFeedbackLayerState>();

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
      _controller!.addListener(_onControllerUpdate);
      // 休眠实例（宿主被全屏遮挡期间）不申请屏幕常亮，由全屏实例接管
      if (widget.active && _controller!.value.isPlaying) {
        _updateWakelock(true);
      }
      _startControlsTimer();
    } else {
      _initializePlayer();
    }

    _syncShimmerTicker();
    // 以当前系统音量 / 屏幕亮度作为手势起点，并关闭系统音量 UI（播放器自带胶囊反馈）
    unawaited(_syncSystemFeedbackState());
  }

  /// 读取当前系统音量与屏幕亮度作为手势起点
  ///
  /// 每次唤醒（退出全屏回到本实例）也会调用：休眠期间用户可能在另一实例上调整过，
  /// 重新读取可保证两个实例的起点一致，不会出现「退出全屏后音量跳回旧值」。
  Future<void> _syncSystemFeedbackState() async {
    try {
      // 手势滑动时由播放器自己的胶囊反馈，关闭系统音量 UI 避免双重提示
      VolumeController.instance.showSystemUI = false;
    } catch (e) {
      debugPrint('[AuraPlayer] 关闭系统音量 UI 失败: $e');
    }

    try {
      final volume = await VolumeController.instance.getVolume();
      if (!mounted) return;
      _volume = volume.clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('[AuraPlayer] 读取系统音量失败: $e');
    }

    try {
      // 应用亮度未设置过时返回负值，此时以系统亮度作为起点
      var brightness = await ScreenBrightness.instance.application;
      if (brightness < 0) brightness = await ScreenBrightness.instance.system;
      if (!mounted) return;
      _brightness = brightness.clamp(0.0, 1.0);
    } catch (e) {
      debugPrint('[AuraPlayer] 读取屏幕亮度失败: $e');
    }
  }

  /// 写入应用级屏幕亮度（失败仅记日志，不影响手势与胶囊反馈）
  void _applyScreenBrightness(double value) {
    ScreenBrightness.instance
        .setApplicationScreenBrightness(value)
        .catchError((Object e) {
      debugPrint('[AuraPlayer] 设置屏幕亮度失败: $e');
    });
  }

  /// 归还屏幕亮度给系统（退出播放器 / 组件销毁时）
  void _resetScreenBrightness() {
    ScreenBrightness.instance
        .resetApplicationScreenBrightness()
        .catchError((Object e) {
      debugPrint('[AuraPlayer] 重置屏幕亮度失败: $e');
    });
  }

  /// 写入系统音量（失败仅记日志）
  void _applySystemVolume(double value) {
    VolumeController.instance.setVolume(value).catchError((Object e) {
      debugPrint('[AuraPlayer] 设置系统音量失败: $e');
    });
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
    // 全屏路由进入 / 退出时切换活动状态（休眠 / 唤醒本实例）
    if (widget.active != oldWidget.active) {
      _onActiveChanged();
    }
  }

  /// 活动状态切换：休眠时让出常亮与 ticker，唤醒时按真实播放态重新断言
  ///
  /// 常亮是全局需求计数：休眠实例不交还，全屏内暂停后屏幕仍常亮；
  /// 唤醒时不重新断言，退出全屏后播放中屏幕会熄灭。
  void _onActiveChanged() {
    if (!widget.active) {
      _updateWakelock(false);
      if (_shimmerController.isAnimating) _shimmerController.stop();
      return;
    }
    _syncShimmerTicker();
    // 休眠期间用户可能在另一实例上调过音量 / 亮度，唤醒时重新同步起点
    unawaited(_syncSystemFeedbackState());
    final value = _controller?.value;
    _updateWakelock(
      value != null && value.isInitialized && value.isPlaying && !value.hasError,
    );
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
      // 应用亮度会随应用生命周期重置，回到前台补写回用户调整过的值
      if (_brightnessAdjusted) _applyScreenBrightness(_brightness);
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
    // 亮度 / 音量浮层的两个定时器已随状态下沉至 PlayerGestureFeedbackLayer，
    // 由该组件自己的 dispose 取消
    _resumeTipTimer?.cancel();
    _positionTick.dispose();

    // 退出全屏时恢复竖屏
    if (_isFullScreen) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }

    _controller?.removeListener(_onControllerUpdate);

    // 退出播放器时归还屏幕亮度（应用亮度虽会随应用生命周期重置，主动恢复更即时）
    if (_brightnessAdjusted) _resetScreenBrightness();

    // 仅当控制器是由本组件创建时才执行销毁，全屏模式下不销毁主页面控制器
    if (widget.controller == null) {
      _controller?.dispose();
    }
    super.dispose();
  }

  /// 初始化自建控制器
  ///
  /// 外部托管控制器不在此列：否则全屏界面的「重试加载」会接管并销毁宿主的控制器。
  Future<void> _initializePlayer() async {
    if (widget.controller != null) return;

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
    // 新控制器的状态与上一份快照无关，清空以保证首帧必定重建一次
    _refreshEngine.reset();
    _completionEngine.reset();
    _syncShimmerTicker();

    // 记录本次初始化所创建的控制器，供 catch 判断「这次初始化是否已被更新的一轮取代」
    VideoPlayerController? pending;
    try {
      final url = widget.playUrl.trim();
      // 本地已下载的视频走 file:// URI：Android 侧 ExoPlayer 直接支持，
      // 不引入 dart:io（避免破坏 web 构建路径，下载能力在 web 上本就不可用）
      final isLocal =
          !url.startsWith('http://') && !url.startsWith('https://');

      // 全程持局部引用：await 期间 playUrl 可能变化并触发新一轮初始化，
      // 若回头读 `_controller` 字段，会把监听挂到新控制器上（两份监听 → 结束回调两次），
      // 或用旧集的断点去 seek 新集。
      final controller = isLocal
          ? VideoPlayerController.contentUri(
              Uri.parse(url.startsWith('file://') ? url : 'file://$url'),
            )
          : VideoPlayerController.networkUrl(
              Uri.parse(url),
              httpHeaders: widget.httpHeaders,
            );
      pending = controller;
      _controller = controller;

      await controller.initialize();

      // 已被新一轮初始化取代（或已卸载）→ 丢弃结果。
      // 不再 dispose：新一轮入口已销毁过旧控制器，重销会二次释放。
      if (!mounted || !identical(controller, _controller)) return;

      controller.addListener(_onControllerUpdate);
      // 不再设置播放器实例音量：音量统一交由系统音量控制，避免两个音量维度互相打架
      controller.setPlaybackSpeed(_normalSpeed);
      controller.play();

      // 判断断点续播逻辑
      if (widget.initialPosition.inSeconds > 5 &&
          widget.initialPosition < controller.value.duration) {
        // 「直接跳转」策略：静默 seek 到上次进度，交由用户自行决定是否回退
        if (widget.autoResume) {
          await controller.seekTo(widget.initialPosition);
          if (!mounted || !identical(controller, _controller)) return;
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
      // 已被新一轮初始化取代 → 本次失败无需展示（旧控制器被主动销毁也走这里）
      if (pending != null && !identical(pending, _controller)) return;
      _updateWakelock(false);
      setState(() {
        _hasError = true;
        _errorMessage = '视频解析或加载失败: $e';
      });
      _syncShimmerTicker();
    }
  }

  /// 视频播放器帧状态监听（约 60 次/秒）
  ///
  /// 按「数据变化频率」分流：位置类走 [_positionTick] 局部重建；
  /// 状态类（播放/暂停、缓冲、倍速、总时长）与快照比对，仅真变化时 `setState`。
  void _onControllerUpdate() {
    if (!mounted || _controller == null) return;
    final value = _controller!.value;

    // 播放进度通知上层（不活动实例同样上报：宿主「继续观看」进度不能在全屏期间断档）
    if (value.isInitialized && !_isDraggingProgress && !_isSeeking) {
      widget.onProgress?.call(value.position, value.duration);
    }

    // 不活动实例（被全屏路由遮挡的宿主播放器）：只上报进度，其余全部跳过 ——
    // 不重建、不驱动扫光、不管常亮、不触发播完回调（播完由全屏实例唯一驱动）。
    if (!widget.active) return;

    // 同步常亮：播放中常亮，其余解除
    final isPlaying = value.isInitialized && value.isPlaying && !value.hasError;
    _updateWakelock(isPlaying);

    _syncShimmerTicker();

    // 播放结束判定 (支持单视频循环播放)
    //
    // 判据与「同一轮播放只上报一次」的闩锁见 [PlayerCompletionEngine]：
    // 库在收到平台完成事件后会自行 pause + seekTo(duration)，此后完成条件**持续为真**，
    // 不做闩锁就会逐帧重复回调，宿主侧表现为「自动跳集一次跳两集」。
    if (_completionEngine.shouldReport(
      isInitialized: value.isInitialized,
      isCompleted: value.isCompleted,
      position: value.position,
      duration: value.duration,
    )) {
      if (_isLooping) {
        _controller?.seekTo(Duration.zero);
        _controller?.play();
      } else {
        _updateWakelock(false);
        widget.onEnded?.call();
      }
    }

    // 状态类字段仅在其变化时整树重建：
    // 播放/暂停键（_effectiveIsPlaying）、缓冲转圈与扫光、倍速文本、总时长文本依赖它们。
    // 判断逻辑见 [PlayerRefreshEngine]（已由纯 Dart 单测锁定「状态不变则不重建」）。
    if (_refreshEngine.submit(
      isPlaying: value.isPlaying,
      isBuffering: value.isBuffering,
      playbackSpeed: value.playbackSpeed,
      duration: value.duration,
      isInitialized: value.isInitialized,
    )) {
      setState(() {});
    }

    // 位置类 UI 局部刷新；滑动寻道期间由手势回调递增，此处跳过避免重复
    if (!_isSeeking) _positionTick.value++;
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
  ///
  /// 横竖屏与系统 UI 模式切换、路由推入与退出恢复的编排见 [pushPlayerFullscreen]，
  /// 这里只表达「何时进入 / 退出」以及全屏实例的构造。
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

    // 2. 推入全屏路由（横屏 / 沉浸 / 退出后恢复竖屏由编排层统一处理）
    await pushPlayerFullscreen(
      context: context,
      builder: (fullscreenContext) => Scaffold(
        backgroundColor: Colors.black,
        body: AuraPlayer(
          playUrl: widget.playUrl,
          // 复用宿主控制器：全屏实例不持有其生命周期（见 [_initializePlayer] 的守卫）
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
      ),
      // 3. 退出全屏后的收尾（编排层已恢复竖屏，且保证宿主仍挂载）
      onExited: () {
        widget.onFullScreenChanged?.call(false);
        if (!mounted) return;
        setState(() {
          _isFullScreen = false;
        });
        _startControlsTimer();
        _updateWakelock(_controller?.value.isPlaying ?? false);
      },
    );
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

        // 2. 手势浮层：变暗遮罩 + 亮度 / 音量胶囊（自带状态）
        //    数值由本页推入，可见性与定时隐藏由它自己管 —— 滑动时不再 setState 到本页
        PlayerGestureFeedbackLayer(
          key: _feedbackKey,
          isFullScreen: _isFullScreen,
        ),

        // 3. 全局手势交互捕获层 (未锁定时支持滑动手势，锁定时仅响应单击呼出锁图标)
        if (_isInitialized)
          _isLocked ? _buildLockedGestureLayer() : _buildGestureLayer(),

        // 手势浮层：居中快进/快退毛玻璃胶囊
        //    仅该浮层随手势局部重建，拖动过程不触及整棵播放器树
        ValueListenableBuilder<int>(
          valueListenable: _positionTick,
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
          _brightness = PlayerGestureEngine.applyVerticalDrag(
            current: _brightness,
            deltaRatio: deltaRatio,
            min: 0.15,
            max: 1.0,
          );
          _brightnessAdjusted = true;
          // 直接作用于真实屏幕背光（应用级，零权限）
          _applyScreenBrightness(_brightness);
          // 显示交给浮层：首次出现只在浮层内建树，逐帧只递增它的心跳，
          // 本页不再为此 setState（原先浮层每次显隐都会重建整棵播放器树）
          _feedbackKey.currentState?.showBrightness(_brightness);
        } else if (zone == PlayerGestureZone.volume) {
          _volume = PlayerGestureEngine.applyVerticalDrag(
            current: _volume,
            deltaRatio: deltaRatio,
            min: 0.0,
            max: 1.0,
          );
          // 直接作用于系统音量
          _applySystemVolume(_volume);
          _feedbackKey.currentState?.showVolume(_volume);
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
        _positionTick.value++;
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
        _positionTick.value++;
      },
      onHorizontalDragEnd: () {
        if (_isSeeking && _controller != null) {
          setState(() {
            _isSeeking = false;
            _isSeekingTo = true;
          });
          _positionTick.value++;
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
      positionTick: _positionTick,
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
      positionTick: _positionTick,
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

  /// 极光翡翠流光进度条（视觉见 [PlayerProgressSlider]，这里只取值与接线）
  ///
  /// 整体订阅位置心跳：总时长 / 缓冲比例 / 缓冲态 / 播放位置都在心跳内重算，
  /// 因此播放期不必整树 `setState` 也能与播放帧同步。
  Widget _buildProgressSlider({bool compact = false}) {
    return ValueListenableBuilder<int>(
      valueListenable: _positionTick,
      builder: (context, _, _) => _buildProgressSliderBody(compact: compact),
    );
  }

  /// 进度条主体 (拆分为独立方法，便于随位置心跳局部重建)
  Widget _buildProgressSliderBody({required bool compact}) {
    final totalMs = _controller?.value.duration.inMilliseconds ?? 0;

    // 计算已加载缓冲比例
    double bufferedFraction = 0.0;
    if (_controller != null && totalMs > 0 && _controller!.value.buffered.isNotEmpty) {
      final lastBuffered = _controller!.value.buffered.last.end.inMilliseconds;
      bufferedFraction = (lastBuffered / totalMs).clamp(0.0, 1.0);
    }

    final isBuffering = !_isInitialized || (_controller?.value.isBuffering == true) || _isSeekingTo;

    final progressRatio = totalMs > 0
        ? (_currentPosition.inMilliseconds / totalMs).clamp(0.0, 1.0)
        : 0.0;

    return PlayerProgressSlider(
      compact: compact,
      progressRatio: progressRatio,
      bufferedFraction: bufferedFraction,
      isBuffering: isBuffering,
      isDragging: _isDraggingProgress,
      shimmerAnimation: _shimmerController,
      onChanged: (val) {
        // 拖拽起点：翻转拖拽标记需要整树重建一次（缩略块尺寸、播放意图判定依赖它）
        final startsDragging = !_isDraggingProgress;
        if (startsDragging) {
          _wasPlayingBeforeDrag = _controller?.value.isPlaying ?? false;
        }
        _dragProgressValue = val;
        if (startsDragging) {
          setState(() => _isDraggingProgress = true);
        } else {
          // 拖拽过程只递增位置心跳：进度条与时间文本局部重建，不再每帧重建整棵树
          _positionTick.value++;
        }
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
    );
  }

  /// 从右侧滑出全屏半透明倍速选择抽屉面板 (腾讯视频/B站全屏流媒体范式)
  void _showPlaybackSpeedDialog() {
    _controlsTimer?.cancel();
    showPlayerSpeedDrawer(
      context: context,
      currentSpeed: _controller?.value.playbackSpeed ?? 1.0,
      onSpeedSelected: (speed) {
        if (!mounted) return;
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
      onMirroredChanged: (val) {
        if (mounted) setState(() => _isMirrored = val);
      },
      onLoopingChanged: (val) {
        if (mounted) setState(() => _isLooping = val);
      },
      onVideoFitChanged: (val) {
        if (mounted) setState(() => _videoFit = val);
      },
      onPreferencesChanged: (next) {
        // 先本地生效（全屏路由不随宿主重建），再上抛宿主持久化
        if (mounted) setState(() => _preferences = next);
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



