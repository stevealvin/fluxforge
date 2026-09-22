import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/domain/text/novel_text.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/chapter_cache.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/chapter_content_pipeline.dart';
import 'package:fluxforge/features/media/novel/reader/controllers/reader_preferences.dart';
import 'package:fluxforge/features/media/novel/reader/engines/catalog_navigator.dart';
import 'package:fluxforge/features/media/novel/reader/engines/horizontal_window.dart';
import 'package:fluxforge/features/media/novel/reader/engines/page_estimate_engine.dart';
import 'package:fluxforge/features/media/novel/reader/engines/pagination_engine.dart';
import 'package:fluxforge/features/media/novel/reader/engines/reader_progress.dart';
import 'package:fluxforge/features/media/novel/reader/engines/vertical_flow_engine.dart';
import 'package:fluxforge/features/media/novel/reader/models/chapter_metrics.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_bottom_bar.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_chapter_bridge.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_horizontal_page_view.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_settings_panel.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_status_views.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_catalog_drawer.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_tap_zones.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_top_bar.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_vertical_scroll_view.dart';

/// 纯净小说阅读引擎 (FluxReader)
///
/// 支持按需异步调度沙箱 parse 抓取正文、智能排版切片分页、
/// SelectionArea 长按划词自由选区复制（横向 / 纵向统一）、后台预取与跨章无缝续读、
/// 四大经典护眼底色、字号行距无级微调，以及左侧目录抽屉（自动定位当前章 + 缓存状态标识）

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({
    super.key,
    this.bookTitle = '小说阅读',
    this.initialChapterIndex = 0,
    this.chapters = const [],
    this.rule,
    this.customHeaders = const {},
    this.onChapterChanged,
    this.offlineBookId,
    this.parseRule,
    this.offlineStore,
  });

  final String bookTitle;
  final int initialChapterIndex;
  final List<NovelChapter> chapters;
  final Rule? rule;
  final Map<String, String> customHeaders;

  /// 章节切换回调 (章节索引, 章节标题)
  /// 供上层记录阅读进度，实现「继续阅读」章节级续读
  final void Function(int index, String title)? onChapterChanged;

  /// 离线下载用的书籍唯一标识（与详情页 `_mediaId` 一致）
  /// 传入后阅读器会优先读取沙盒中的离线章节，实现断网阅读
  final String? offlineBookId;

  /// 正文抓取函数（缺省走沙箱 [RuleEngine]）
  ///
  /// 仅供「正文延迟到达」这类纯时序场景注入可控实现（测试用）；
  /// 正常调用方无需传入 —— 阅读器的三级来源与预取策略都不依赖它。
  final Future<Object?> Function(Rule rule, String url)? parseRule;

  /// 离线章节存取实现（缺省接全局下载服务，见 [GlobalOfflineChapterStore]）
  ///
  /// 仅供测试注入内存替身：得以在无沙盒 / 无网络环境下构造「该章已离线下载」
  /// 这一前置条件，验证「已下载的邻居章进入窗口即被预载、不再停在就绪占位页」。
  final OfflineChapterStore? offlineStore;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage>
    with WidgetsBindingObserver {
  // 章节与数据
  late List<NovelChapter> _chapters;
  late int _currentChapterIndex;

  // 正文异步加载状态与缓存
  //
  // 不再有「正在加载」布尔量：未就绪状态由渲染层就地表达（横向桥接页 / 纵向块内占位），
  // 只保留失败原因用于块内重试入口。
  String? _contentError;

  /// 正文缓存的保留半径（章）：略大于渲染窗口，作为回看缓冲
  ///
  /// 顺读时它基本不被访问，挡的是回看 / 跳章时的重新分页开销
  /// （实测单章分页 ~71ms，而重新读盘仅 ~0.3ms），取 ±15 保持内存恒定。
  static const int _cacheWindowRadius = 15;

  /// 章节正文会话缓存（阅读期加速层，退出阅读器即释放）
  ///
  /// 与「离线下载」（沙盒落盘、断网可读）是两层机制，详见 [ChapterCache]；
  /// 分页切片（[_chapterPageStarts]）与该缓存同生共死，见 [_applyCacheEviction]。
  final ChapterCache _contentCache = ChapterCache(
    capacity: _cacheWindowRadius * 2 + 1,
  );

  /// 章节正文获取管道（三级来源 + 后台预取 / 落盘调度）
  ///
  /// 依赖 `widget.rule` / `widget.offlineBookId` 与已就绪的章节列表，
  /// 因此在 [_setupChapters] 中构造。
  late final ChapterContentPipeline _pipeline;

  // 排版与阅读样式设置
  double _fontSize = 18.0;
  double _lineHeight = 1.6;
  ReaderTheme _readerTheme = ReaderTheme.parchment;
  PageTurnMode _pageMode = PageTurnMode.horizontal;

  // 控制面板状态
  bool _showControls = false;
  bool _showSettingsPanel = false;

  // 横向翻页控制
  PageController? _pageController;

  /// 章内当前阅读位置（**唯一真相**，对应 legado 的 `durChapterPos`）
  ///
  /// 页号、扁平下标、进度全部由它派生：分页表变化（补分片 / 重排 / 跨章平移窗口）时
  /// 位置本身不变，因此**不需要「落点意图」这类补偿机制** —— 这正是 legado 的做法。
  int _chapterCharOffset = 0;

  /// 「本章最后」哨兵（对应 legado `moveToPrevChapter` 里的 `Int.MAX_VALUE`）
  ///
  /// 「从下一章回退到上一章末页」在目标章尚未分片时无从得知末页起始偏移，
  /// 先记为章末哨兵，分片就绪后由 [_normalizeChapterOffset] 收敛到真实末页。
  static const int _chapterEndPosition = 1 << 30;

  /// 章内当前页号（**派生值**，唯一真相见 [_chapterCharOffset]）
  ///
  /// 读处一律走这里，避免"位置与页号各存一份"再次漂移。
  int get _currentPageIndex =>
      ReaderProgress.pageIndexFromCharOffset(_pageStarts, _chapterCharOffset);

  /// 当前章的**页起始字符偏移表**（页数 = 长度；不再存文本副本）
  List<int> _pageStarts = [];

  /// 各章分片缓存：横向滑窗（当前章 ± 1）跨章连续渲染的数据源
  final Map<int, List<int>> _chapterPageStarts = {};

  // 上下滚动控制器
  final ScrollController _scrollController = ScrollController();

  // ==================== 后台预取与跨章连续阅读状态 ====================

  /// 正在后台预取中的章节索引集合（防止同一章重复发起请求）
  final Set<int> _prefetching = {};

  /// 正在离线下载到沙盒的章节索引集合（目录内展示下载中状态）
  final Set<int> _downloadingChapters = {};

  // 「落到上一章末页」不再需要独立意图标记：它由位置本身表达（见 [_chapterEndPosition]）

  /// 纵向连续阅读的章节序列（升序连续；首端可被向上前插）
  final List<int> _verticalSequence = [];

  /// 纵向长卷的坐标锚点（进入纵向模式时所在的章，本轮纵向阅读内保持不变）
  ///
  /// 作为 `CustomScrollView.center` 的落点：锚点之上插入内容不会改变锚点及以下的
  /// 布局坐标，因此向上加载历史章节时**无需任何偏移补偿**，从机制上杜绝前插跳变。
  int _verticalAnchorIndex = -1;

  /// 锚点 sliver 的稳定 Key
  ///
  /// 必须由页面持有跨帧复用：它是 Viewport 的坐标基准，每帧重建会导致锚点失效、
  /// 滚动位置被重置。
  final GlobalKey _verticalCenterKey = GlobalKey();

  /// 纵向模式正在追加中的章节索引集合
  final Set<int> _verticalAppending = {};

  /// 纵向模式各章节块定位 Key（用于识别当前正在阅读的章节）
  final Map<int, GlobalKey> _verticalBlockKeys = {};

  /// 屏中线同步的降频计数（章号最多滞后 3 帧，滚动停止时补一次）
  int _verticalSyncFrame = 0;

  /// 屏中线同步降频间隔（帧）
  static const int _verticalSyncFrameInterval = 4;

  /// 纵向续载失败的章节索引（避免滚动过程中对失败章节反复发起请求）
  final Set<int> _verticalFailed = {};

  /// 排版参数调整（字号/行距）前的阅读位置锚点（-1 表示未锚定）
  int _typographyAnchorOffset = -1;

  /// 纵向模式下上一次同步的章内进度（用于节流刷新进度条，避免每帧 setState）
  double _lastVerticalProgress = -1;

  // ==================== 章节目录（左侧抽屉）状态 ====================

  /// Scaffold 句柄：用于从左侧滑出章节目录抽屉
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  /// 目录列表滚动控制器（每次打开时重建并预置偏移，实现自动定位当前章节）
  ScrollController? _catalogScrollController;

  /// 目录排序是否倒序（倒序 = 最新章节在前，便于追更时快速定位最新章）
  bool _isCatalogReversed = false;

  // ==================== 翻页窗口与真实页面映射 ====================

  /// 当前章节是否存在上一章
  bool get _hasPrevChapter => _currentChapterIndex > 0;

  /// 当前章节是否存在下一章
  bool get _hasNextChapter => _currentChapterIndex < _chapters.length - 1;

  @override
  void initState() {
    super.initState();
    // 载入历史标定（幂等）：让"估算页数"越用越准，并跨会话保留
    PageEstimateCalibrationStore.instance.load();
    // 监听系统内存告警，收到后主动释放不在屏上的章节正文
    WidgetsBinding.instance.addObserver(this);
    _currentChapterIndex = widget.initialChapterIndex;
    _setupChapters();
    _loadUserPreferences();
    _recalculatePages();
    _pageController = PageController(
      initialPage: _flatIndexOf(_currentChapterIndex, _currentPageIndex),
    );

    // 初始进入立即按需调度沙箱加载章节内容
    _loadChapterContent(_currentChapterIndex);

    // 纵向滚动监听：触底自动续载下一章 + 同步当前阅读章节
    _scrollController.addListener(_onVerticalScroll);

    // 通知上层记录初始阅读章节
    if (_chapters.isNotEmpty) {
      widget.onChapterChanged?.call(
        _currentChapterIndex,
        _chapters[_currentChapterIndex].title,
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController?.dispose();
    _scrollController.dispose();
    _catalogScrollController?.dispose();
    super.dispose();
  }

  /// 系统内存告警（Android `onTrimMemory` / iOS `didReceiveMemoryWarning`）
  ///
  /// 长会话下章节内存镜像是唯一会持续增长的部分，收到告警即主动让路：
  /// 释放不在屏上的章节正文，避免整页被系统回收（重读一次本地文件即可恢复）。
  @override
  void didHaveMemoryPressure() {
    super.didHaveMemoryPressure();
    _releaseCacheOnMemoryPressure();
  }

  /// 准备章节数据并初始化缓存
  ///
  /// 注意：此处严禁注入任何示例/演示章节；无章节时由 build 统一渲染空态提示，
  /// 避免用户把伪造正文误认为真实内容。
  void _setupChapters() {
    _chapters = widget.chapters.isNotEmpty
        ? List<NovelChapter>.from(widget.chapters)
        : <NovelChapter>[];

    _contentCache.seedFromChapters(_chapters);
    _evictChapterCacheIfNeeded();

    _pipeline = ChapterContentPipeline(
      bookTitle: widget.bookTitle,
      offlineBookId: widget.offlineBookId,
      rule: widget.rule,
      chapters: _chapters,
      cache: _contentCache,
      prefetching: _prefetching,
      cacheWriter: _cacheChapterContent,
      parseRule: widget.parseRule,
      offlineStore: widget.offlineStore,
      onPersisted: (index) {
        // 该章此前若在纵向续载中失败过，落盘成功后解除熔断标记
        _verticalFailed.remove(index);
        // 刷新目录里的下载状态图标与底部栏「已下载」计数
        if (mounted) setState(() {});
      },
    );
  }

  /// 切换控制栏显示/收起状态
  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
      if (!_showControls) _showSettingsPanel = false;
    });
  }

  /// 异步按需加载指定章节正文
  ///
  /// 四条来源按「代价从低到高」依次尝试，命中即返回：
  /// 1. **内存镜像**（阅读期加速层）—— 零等待；
  /// 2. **沙盒离线文件** —— 一次本地 IO，刻意不进 loading 态（否则「已下载却闪加载」）；
  /// 3. **章节自带正文**（无目标 URL 时）—— 详情页直传，落盘后仍可读；
  /// 4. **沙箱抓取** —— 最后兜底，失败进入错误态并给出重试。
  ///
  /// 四条路径的就绪收尾统一走 [_settleChapterContent]：原先「状态收尾 + 落点处理」
  /// 这段在四处各写一遍，其中「落点重置」这条规则因此有了四份实现（改一处必漏三处）。
  Future<void> _loadChapterContent(
    int index, {
    bool forceReload = false,
  }) async {
    if (index < 0 || index >= _chapters.length) return;

    // 1. 内存镜像：命中即刻渲染
    final cached = _contentCache[index];
    if (!forceReload && cached != null && cached.isNotEmpty) {
      _settleChapterContent(index, cached);
      return;
    }

    // 2. 沙盒离线正文。守卫说明：isOfflineDownloaded 是同步判定，且未配置书籍标识时
    //    直接返回 false，因此未下载的章节走这条路是零开销的，不给正常路径增加成本。
    if (!forceReload && _pipeline.isOfflineDownloaded(index)) {
      final offline = await _pipeline.readOffline(index);
      // 读盘期间用户可能已切走，此时必须丢弃本次结果，避免覆盖当前章
      if (!mounted || _currentChapterIndex != index) return;
      if (offline != null && offline.isNotEmpty) {
        _cacheChapterContent(index, offline);
        _settleChapterContent(index, offline);
        return;
      }
      // 离线文件读不到（损坏 / 被外部清理）时不报错，继续降级到自带正文 / 网络抓取
    }

    // 3. 无目标 URL：只能用章节自带正文
    final currentCh = _chapters[index];
    final chapterUrl = currentCh.url?.trim() ?? '';
    if (chapterUrl.isEmpty) {
      if (currentCh.content.isNotEmpty) {
        // 章节自带正文同样属于「已加载」→ 一并落盘，退出后仍可读
        _mountLoadedContent(index, currentCh.content);
        _settleChapterContent(index, currentCh.content);
      }
      return;
    }

    // 4. 沙箱抓取（最后兜底）
    setState(() => _contentError = null);

    try {
      final rule = widget.rule;
      if (rule == null) {
        throw Exception('未绑定解析规则，无法调度沙箱抓取章节内容');
      }

      final cleanContent = _cleanNovelContent(
        _extractContentText(await _parseChapter(rule, chapterUrl)),
      );
      if (cleanContent.isEmpty) {
        throw Exception('目标站点响应完成，但未提取到正文文本内容');
      }

      // 建立内存镜像并落盘 —— 抓到即属于「已下载」，退出阅读器后依然可读
      _mountLoadedContent(index, cleanContent);
      if (mounted && _currentChapterIndex == index) {
        _settleChapterContent(index, cleanContent);
      }
    } catch (e) {
      if (mounted && _currentChapterIndex == index) {
        setState(() {
          _contentError = '正文加载失败: $e';
        });
      }
    }
  }

  /// 执行一次正文抓取：缺省走沙箱 [RuleEngine]，[NovelReaderPage.parseRule] 可注入替代实现
  Future<Object?> _parseChapter(Rule rule, String url) {
    final injected = widget.parseRule;
    return injected != null ? injected(rule, url) : RuleEngine.parse(rule, url);
  }

  /// 从沙箱返回结果取正文字符串（`content` / `text` / `data` 三种既有约定）
  String _extractContentText(Object? res) {
    if (res is Map) {
      return res['content']?.toString() ??
          res['text']?.toString() ??
          res['data']?.toString() ??
          '';
    }
    return res is String ? res : '';
  }

  /// 正文就绪后的统一收尾：同步章节模型 → 重算分页 → 应用落点 → 对齐控制器 → 准备邻居
  void _settleChapterContent(int index, String content) {
    setState(() {
      _chapters[index] = _chapters[index].copyWith(content: content);
      _contentError = null;
      _recalculatePages();
      // 覆盖「本章此刻无正文」这一早退分支：_recalculatePages 不会消费落点
      _normalizeChapterOffset();
    });
    _syncPageController();
    // 正文就绪即代表阅读顺畅，立即静默准备相邻章节（实现连续翻页零等待）：
    // 落盘走 downloadAdjacent，进内存镜像走预载 —— 二者互补，
    // 因为已下载的章会被 downloadAdjacent 直接跳过，只有预载能把它们变成可渲染分片
    _pipeline.downloadAdjacent(_currentChapterIndex);
    _preloadNeighborContent();
  }

  // ==================== 后台预取、跨章连续与阅读位置保持 ====================

  /// 是否处于「正文加载失败且无可用内容」状态
  ///
  /// 该状态下必须撤除三区点击热层：热层为全屏 `Positioned.fill`，
  /// 会遮挡错误页的「重试加载」按钮，导致点击被抢走而误解为呼出菜单。
  bool get _isContentErrorState =>
      _contentError != null &&
      _chapters.isNotEmpty &&
      _chapters[_currentChapterIndex].content.isEmpty;

  /// 目标章正文是否已可立即渲染
  ///
  /// 严格口径：只有**内容真实可用**才算就绪。
  /// 已离线下载的章节同样视为就绪：正文在沙盒文件里，读取只是一次本地 IO，
  /// 切过去不会出现任何联网等待。
  bool _isChapterContentAvailable(int index) {
    if (index < 0 || index >= _chapters.length) return false;
    if (_chapters[index].content.isNotEmpty) return true;
    final cached = _contentCache[index];
    if (cached != null && cached.isNotEmpty) return true;
    return _pipeline.isOfflineDownloaded(index);
  }

  /// 纵向滚动监听：触底续载下一章 + 同步当前阅读章节
  void _onVerticalScroll() {
    if (_pageMode != PageTurnMode.verticalScroll) return;
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    // 续载意图由引擎统一判定：距底不足阈值 → 追加下一章；距顶不足阈值 → 前插上一章
    // （内容不足一屏时两者同时成立，保证短章节也能向两个方向持续回溯）
    final intent = VerticalFlowEngine.resolveIntent(
      pixels: position.pixels,
      maxScrollExtent: position.maxScrollExtent,
    );
    if (intent == VerticalLoadIntent.appendNext ||
        intent == VerticalLoadIntent.both) {
      _appendNextVerticalChapter();
    }
    if (intent == VerticalLoadIntent.prependPrev ||
        intent == VerticalLoadIntent.both) {
      _prependPrevVerticalChapter();
    }

    // 屏中线同步（findRenderObject）降频到每 N 帧一次，滚动停止时再由
    // [_onVerticalScrollEnd] 精确补一次；窗口裁剪同样跟着降频执行。
    if (++_verticalSyncFrame >= _verticalSyncFrameInterval) {
      _verticalSyncFrame = 0;
      _syncVerticalCurrentChapter();
      // 锚点漂移过大时先重设锚点，否则「锚点与当前章之间」的中间区段无法被窗口裁掉
      _reanchorVerticalFlowIfNeeded();
      _trimVerticalWindow();
    }

    // 控制栏展开时节流刷新章内进度条（避免滚动过程中每帧 setState）
    if (_showControls) {
      final progress = _chapterProgress;
      if ((progress - _lastVerticalProgress).abs() > 0.005) {
        _lastVerticalProgress = progress;
        setState(() {});
      }
    }
  }

  /// 纵向模式：静默加载并把下一章正文追加到同一滚动流（无缝连续阅读）
  Future<void> _appendNextVerticalChapter() async {
    final next = VerticalFlowEngine.nextAppendTarget(
      sequence: _verticalSequence,
      appending: _verticalAppending,
      failed: _verticalFailed,
      chapterCount: _chapters.length,
    );
    if (next == null) return;

    _verticalAppending.add(next);
    final content = await _pipeline.ensureContent(next);
    _verticalAppending.remove(next);

    if (!mounted) return;
    // 加载失败则标记并停止重试，避免滚动过程中反复发起无效请求
    if (content == null) {
      _verticalFailed.add(next);
      return;
    }

    _chapters[next] = _chapters[next].copyWith(content: content);
    setState(() {
      _verticalSequence.add(next);
      _verticalBlockKeys.putIfAbsent(next, () => GlobalKey());
    });

    // 继续向后下载，保证连续下拉时永不卡顿
    if (next + 1 < _chapters.length) {
      unawaited(_pipeline.downloadOffline(next + 1));
    }
  }

  /// 纵向长卷：向上前插上一章正文
  ///
  /// 已加载长卷滚到顶部后需要继续向上阅读（中段章节尤其明显），
  /// 这里在「距顶不足阈值」时静默前插上一章。
  ///
  /// **无需任何滚动偏移补偿**：长卷以 [_verticalAnchorIndex] 作为
  /// `CustomScrollView.center`，向上方向的坐标独立于锚点，
  /// 前插内容不会移动用户当前看到的正文位置。
  /// （旧实现靠 `postFrame` 量高度再 `jumpTo`，必然产生一帧错位画面。）
  Future<void> _prependPrevVerticalChapter() async {
    final prev = VerticalFlowEngine.prevPrependTarget(
      sequence: _verticalSequence,
      appending: _verticalAppending,
      failed: _verticalFailed,
    );
    if (prev == null) return;

    _verticalAppending.add(prev);
    final content = await _pipeline.ensureContent(prev);
    _verticalAppending.remove(prev);

    if (!mounted) return;
    if (content == null) {
      _verticalFailed.add(prev);
      return;
    }

    _chapters[prev] = _chapters[prev].copyWith(content: content);
    setState(() {
      _verticalSequence.insert(0, prev);
      _verticalBlockKeys.putIfAbsent(prev, () => GlobalKey());
    });

    // 上方仍有章节则继续下载，滚动时即可无缝衔接
    if (prev - 1 >= 0) {
      unawaited(_pipeline.downloadOffline(prev - 1));
    }
  }

  /// 用户点击「下一章加载失败 · 点击重试」：解除熔断后重新续载
  ///
  /// 熔断的存在意义是「滚动过程中不反复发起无效请求」；用户显式点击重试
  /// 说明网络或规则源可能已恢复，故先解除标记再发起一次。
  /// 仍失败则给出明确提示 —— 不再像原先那样静默停住。
  Future<void> _retryAppendNextChapter() async {
    if (_verticalSequence.isEmpty) return;
    final next = _verticalSequence.last + 1;
    if (next >= _chapters.length) return;

    setState(() => _verticalFailed.remove(next));
    await _appendNextVerticalChapter();

    if (mounted && _verticalFailed.contains(next)) {
      _showReaderSnack('「${_chapters[next].title}」仍加载失败，请检查网络或规则源');
    }
  }

  /// 用户点击「上一章加载失败 · 点击重试」：解除熔断后重新前插
  Future<void> _retryPrependPrevChapter() async {
    if (_verticalSequence.isEmpty) return;
    final prev = _verticalSequence.first - 1;
    if (prev < 0) return;

    setState(() => _verticalFailed.remove(prev));
    await _prependPrevVerticalChapter();

    if (mounted && _verticalFailed.contains(prev)) {
      _showReaderSnack('「${_chapters[prev].title}」仍加载失败，请检查网络或规则源');
    }
  }

  /// 纵向模式：依据屏幕中线定位当前正在阅读的章节并同步阅读进度
  void _syncVerticalCurrentChapter() {
    if (_verticalBlockKeys.isEmpty || !mounted) return;

    final screenMid = MediaQuery.of(context).size.height / 2;
    // 仅检查当前章相邻的 3 个章节块，避免长序列导致逐帧全量遍历
    final candidates = <int>[
      _currentChapterIndex - 1,
      _currentChapterIndex,
      _currentChapterIndex + 1,
    ];

    for (final index in candidates) {
      final ctx = _verticalBlockKeys[index]?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) continue;

      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      if (top <= screenMid && bottom >= screenMid) {
        if (_currentChapterIndex != index) {
          setState(() => _currentChapterIndex = index);
          widget.onChapterChanged?.call(index, _chapters[index].title);
        }
        return;
      }
    }
  }

  /// 滚动停止：补齐一次精确的屏中线同步与窗口裁剪
  ///
  /// 延到帧末执行：`ScrollEndNotification` 可能在布局阶段派发（那时 setState 会抛异常），
  /// 且裁剪本身会改变内容尺寸、可能再派发一次结束通知。
  void _onVerticalScrollEnd() {
    if (_pageMode != PageTurnMode.verticalScroll) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _pageMode != PageTurnMode.verticalScroll) return;
      _verticalSyncFrame = 0;
      _syncVerticalCurrentChapter();
      _reanchorVerticalFlowIfNeeded();
      _trimVerticalWindow();
    });
  }

  /// 锚点漂移过大时重设锚点（原因见 [VerticalFlowEngine.needsReanchor]）
  ///
  /// 锚点是 Viewport 坐标原点，变更后 `pixels` 含义随之改变，
  /// 故须跳转到当前章内的阅读位置（`pixels - 章块顶部偏移`，见 [ChapterMetrics.top]）；
  /// 跳转与 setState 在同一同步块内完成，本帧尚未布局，因此无中间态。
  void _reanchorVerticalFlowIfNeeded() {
    if (_pageMode != PageTurnMode.verticalScroll) return;
    if (!_scrollController.hasClients) return;

    if (!VerticalFlowEngine.needsReanchor(
      currentChapterIndex: _currentChapterIndex,
      anchorChapterIndex: _verticalAnchorIndex,
    )) {
      return;
    }

    // 当前章块几何不可测（尚未布局）→ 下一帧再试，绝不盲目跳转
    final metrics = _verticalChapterMetrics();
    if (metrics == null) return;

    final inChapterOffset = (_scrollController.offset - metrics.top).clamp(
      0.0,
      double.infinity,
    );

    setState(() => _verticalAnchorIndex = _currentChapterIndex);
    _scrollController.jumpTo(inChapterOffset);
  }

  /// 长卷窗口化：摘除远离当前章的章节（锚点章节永不摘除，见引擎）
  ///
  /// 序列收缩后保护集合随之变小，正文缓存才真正受容量上限约束。
  void _trimVerticalWindow() {
    if (_pageMode != PageTurnMode.verticalScroll) return;

    final trim = VerticalFlowEngine.resolveWindowTrim(
      sequence: _verticalSequence,
      currentChapterIndex: _currentChapterIndex,
      anchorChapterIndex: _verticalAnchorIndex,
    );
    if (trim.isEmpty) return;

    final dropped = trim.all;
    setState(() {
      _verticalSequence.removeWhere(dropped.contains);
      // 一并释放各块的定位 Key，避免反复进出窗口时 Key 表持续增长
      _verticalBlockKeys.removeWhere((index, _) => dropped.contains(index));
    });

    // 序列变小 → 保护集合变小 → 按容量上限回收不在窗口内的正文
    _evictChapterCacheIfNeeded();
  }

  /// 写入会话缓存，并按容量上限回收最久未使用的章节
  void _cacheChapterContent(int index, String content) {
    _contentCache[index] = content;
    _evictChapterCacheIfNeeded();
    // 内容就绪是「可以分片」的唯一信号：立刻排队给窗口内各章补齐切片。
    //
    // 否则会留下「正文早已到达、翻页时仍是占位页」的窗口期 —— 而未分片章在扁平
    // 序列里只占 1 页，补分片时窗口内页索引会整体平移（见 [_onHorizontalPagesChanged]），
    // 曾是「进入后直接往前翻落到上一章章首」的直接成因。
    if ((index - _currentChapterIndex).abs() <= 1) _scheduleNeighborSlices();
  }

  /// 加载到正文后的统一收尾：建立内存镜像 + 尽力落盘
  ///
  /// **核心语义：只要加载到了正文，这一章就属于「已下载」** ——
  /// 内存镜像只是本次阅读的渲染载体（配合 LRU 避免重复读盘），
  /// 真正的「缓存」落在沙盒，退出后依然可读。
  ///
  /// 已在沙盒中的章节会被 [ChapterContentPipeline.persistOffline] 同步短路，
  /// 因此重复调用不产生额外磁盘 IO；落盘不可用（未绑定书籍标识 / 解析规则）时静默跳过，
  /// 正文仍保留在内存镜像中供本次阅读使用。
  void _mountLoadedContent(int index, String content) {
    _cacheChapterContent(index, content);
    unawaited(_pipeline.persistOffline(index, content));
  }

  /// 缓存保护集合：这些章节在任何淘汰路径下都不回收
  ///
  /// 长卷正在渲染的章节（回收会出空白块）、当前章、预取 / 下载中章节，
  /// 以及**无远程地址的章节**（详情页直传正文，回收即永久丢失）。
  Set<int> _cacheProtectSet() => <int>{
    ..._verticalSequence,
    _currentChapterIndex,
    ..._prefetching,
    ..._downloadingChapters,
    for (int i = 0; i < _chapters.length; i++)
      if ((_chapters[i].url ?? '').isEmpty) i,
  };

  /// 按容量上限回收内存缓存（常规路径：控制会话内存增长）
  void _evictChapterCacheIfNeeded() {
    _applyCacheEviction(
      _contentCache.evictOverflow(protect: _cacheProtectSet()),
    );
  }

  /// 内存告警下的主动释放：不做数量判断，保护集合之外一律释放
  ///
  /// 正文已统一「加载到即落盘」，重读不会丢内容，代价只是一次本地 IO。
  void _releaseCacheOnMemoryPressure() {
    final evicted = _contentCache.evictAllExcept(_cacheProtectSet());
    _applyCacheEviction(evicted);
    // 控制栏「已缓存章节数」等展示需要跟随刷新
    if (evicted.isNotEmpty && mounted) setState(() {});
  }

  /// 淘汰收尾：清空章节模型中的正文引用与分页切片
  ///
  /// 必须清 `_chapters[i].content`，否则 String 仍被 [NovelChapter] 持有、内存不释放。
  /// 切片与正文是同一段文本的两份表示，必须同生共死（命中正文即命中切片）。
  void _applyCacheEviction(Set<int> evicted) {
    if (evicted.isEmpty) return;
    for (final index in evicted) {
      _chapters[index] = _chapters[index].copyWith(content: '');
      _chapterPageStarts.remove(index);
      // 分片随正文一同消失 → 允许该章再次预载（否则重入窗口后永远停在占位页）
      _preloadRequested.remove(index);
    }
  }

  /// 当前阅读位置在本章正文中的字符偏移量
  ///
  /// 用于翻页模式切换、字号/行距调整后精确还原阅读位置，杜绝「从头开始」。
  int get _currentCharOffset {
    if (_chapters.isEmpty) return 0;
    final content = _chapters[_currentChapterIndex].content;
    if (content.isEmpty) return 0;

    // 横向：页 = 偏移，当前页起始偏移即答案（O(1)，无需再累加各页长度）
    if (_pageMode == PageTurnMode.horizontal) {
      return _currentPageIndex < _pageStarts.length
          ? _pageStarts[_currentPageIndex]
          : 0;
    }

    // 纵向：按当前章块内的阅读比例换算为字符偏移，保证切换模式 / 改排版后不跳回开头
    return (_chapterProgress * content.length).round();
  }

  /// 在下一帧布局完成后，把阅读位置还原到指定字符偏移处
  void _restoreReadingPosition(int charOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 横向：位置直接落库（页号是派生值，无需"反查页号 → 再赋值页号"）
      if (_pageMode == PageTurnMode.horizontal) {
        if (_pageStarts.isEmpty) return;

        final contentLength = _chapters[_currentChapterIndex].content.length;
        final target = charOffset.clamp(0, contentLength);
        if (target != _chapterCharOffset) {
          setState(() => _chapterCharOffset = target);
        }
        // 准确定位 PageController 到包含桥接页偏移的真实目标页（杜绝误跳章首桥接页触发误切章）
        _syncPageController();
        return;
      }

      // 纵向：按字符偏移在当前章块内换算为滚动距离
      final contentLength = _chapters[_currentChapterIndex].content.length;
      if (contentLength <= 0 || !_scrollController.hasClients) return;
      final metrics = _verticalChapterMetrics();
      if (metrics == null) return;
      final target = ReaderProgress.verticalOffsetFromRatio(
        ratio: ReaderProgress.ratioFromCharOffset(charOffset, contentLength),
        metrics: metrics,
      );
      _scrollController.jumpTo(
        target.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    });
  }

  /// 统一入口：切换翻页模式（保持当前阅读位置，不再从头开始）
  void _togglePageMode() {
    final offset = _currentCharOffset;
    final nextMode = _pageMode == PageTurnMode.horizontal
        ? PageTurnMode.verticalScroll
        : PageTurnMode.horizontal;

    setState(() {
      _pageMode = nextMode;
      if (nextMode == PageTurnMode.verticalScroll) {
        // 进入纵向模式：以当前章为锚点重建连续阅读序列
        _resetVerticalFlow(_currentChapterIndex);
      } else {
        // 回到横向模式：复位页码并清空纵向序列
        _chapterCharOffset = 0;
        _verticalSequence.clear();
        _verticalBlockKeys.clear();
      }
    });

    ReaderPreferences.savePageMode(nextMode);

    // 布局完成后恢复阅读位置
    _restoreReadingPosition(offset);
  }

  /// 应用排版参数变更（字号加减等）：变更前后保持阅读位置，避免重新排版后跳回开头
  void _applyTypographyChange(VoidCallback mutate) {
    final offset = _currentCharOffset;
    setState(() {
      mutate();
      _recalculatePages(invalidateAll: true);
    });
    _restoreReadingPosition(offset);
  }

  /// 手动下载下一章（供底部「已下载 N 章」按钮调用，给出明确反馈）
  ///
  /// 与底部按钮的下载图标语义对齐：具备离线条件时**真正落盘**（复用已抓取的正文，
  /// 不产生额外网络请求），落盘后断网也能读；
  /// 未绑定书籍标识 / 解析规则时退化为本次阅读内的内存预取。
  Future<void> _downloadNextManually() async {
    final next = _currentChapterIndex + 1;
    if (next >= _chapters.length) {
      _showReaderSnack('已是最后一章，无需下载');
      return;
    }

    // 1. 已离线落盘：明确告知可断网阅读
    if (_pipeline.isOfflineDownloaded(next)) {
      _showReaderSnack('下一章《${_chapters[next].title}》已下载，断网也能读');
      return;
    }

    // 2. 具备离线条件：真正下载到沙盒（downloadOffline 内部会复用已抓取正文）
    if (_pipeline.canDownloadOffline) {
      _showReaderSnack('正在下载下一章《${_chapters[next].title}》...');
      final ok = await _pipeline.downloadOffline(next);
      if (!mounted) return;
      _showReaderSnack(
        ok ? '下载完成，当前已下载 ${_pipeline.downloadedCount} 章' : '下载失败，请检查网络或解析规则',
      );
      return;
    }

    // 3. 无离线条件（未绑定书籍标识 / 规则）：只能建立本次阅读内的内存镜像
    if (_contentCache.containsKey(next)) {
      _showReaderSnack('下一章《${_chapters[next].title}》已就绪，可无缝续读');
      return;
    }
    _showReaderSnack('正在加载下一章《${_chapters[next].title}》...');
    final content = await _pipeline.ensureContent(next);
    if (!mounted) return;
    _showReaderSnack(
      content == null || content.isEmpty
          ? '加载失败，请检查网络或解析规则'
          : '加载完成，本次阅读内可无缝续读（未绑定书籍标识，无法离线留存）',
    );
  }

  /// 统一轻提示（避免打断阅读沉浸）
  void _showReaderSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontSize: 12)),
        duration: const Duration(milliseconds: 1600),
      ),
    );
  }

  // ==================== 阅读区三区点击交互 ====================

  /// 点击左侧 1/3 区域：上一页（横向翻页 / 纵向滚屏）
  void _goToPreviousPage() {
    // 纵向长卷：向上滚动一屏；到顶时自动切回上一章
    if (_pageMode == PageTurnMode.verticalScroll) {
      if (!_scrollController.hasClients) return;
      if (_scrollController.offset <= 10 && _currentChapterIndex > 0) {
        _switchChapter(_currentChapterIndex - 1);
        return;
      }
      final viewport = _scrollController.position.viewportDimension;
      final target = (_scrollController.offset - viewport * 0.92).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // 横向翻页：滑窗内自然翻页，跨章动画与章内一致
    final controller = _pageController;
    if (controller == null || !controller.hasClients) {
      // 控制器未挂载：退化为直接切章
      if (_currentChapterIndex > 0) {
        _switchChapter(_currentChapterIndex - 1, toLastPage: true);
      } else {
        _showReaderSnack('已是全书第一页');
      }
      return;
    }
    final raw = controller.page?.round() ?? 0;
    if (raw <= 0) {
      _showReaderSnack('已是全书第一页');
      return;
    }
    controller.previousPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// 点击右侧 1/3 区域：下一页（横向翻页 / 纵向滚屏）
  void _goToNextPage() {
    // 纵向长卷：向下滚动一屏（触底会自动续载下一章）
    if (_pageMode == PageTurnMode.verticalScroll) {
      if (!_scrollController.hasClients) return;
      final viewport = _scrollController.position.viewportDimension;
      final target = (_scrollController.offset + viewport * 0.92).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // 横向翻页：滑窗内自然翻页，章末继续翻直接进入下一章
    final controller = _pageController;
    if (controller == null || !controller.hasClients) {
      // 控制器未挂载：退化为直接切章
      if (_currentChapterIndex < _chapters.length - 1) {
        _switchChapter(_currentChapterIndex + 1);
      } else {
        _showReaderSnack('已是最后一章');
      }
      return;
    }
    final raw = controller.page?.round() ?? 0;
    if (raw >= _horizontalTotalPages - 1) {
      _showReaderSnack('已是最后一章');
      return;
    }
    controller.nextPage(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  /// 阅读区三区点击热层（具体布局见 [ReaderTapZones]）
  Widget _buildTapZones() {
    return ReaderTapZones(
      onPreviousPage: _goToPreviousPage,
      onToggleControls: _toggleControls,
      onNextPage: _goToNextPage,
    );
  }

  // ==================== 章内进度（底部控制栏进度条） ====================

  /// 纵向长卷中「当前章」的实测几何信息（章块顶部偏移 / 高度 / 章内可滚动距离）
  ///
  /// 关键：不能拿整条长卷的 `maxScrollExtent` 当分母 —— 长卷每追加一章，分母就会
  /// 变大，同一个物理偏移对应的比例会自行回退，加载的章节越多偏差越大。
  /// 这里改用当前章块自身的几何区间，与「本章进度」语义严格一致。
  ChapterMetrics? _verticalChapterMetrics() {
    if (!_scrollController.hasClients) return null;

    final box =
        _verticalBlockKeys[_currentChapterIndex]?.currentContext
                ?.findRenderObject()
            as RenderBox?;
    if (box == null || !box.hasSize) return null;

    final viewport = RenderAbstractViewport.maybeOf(box);
    if (viewport == null) return null;

    final top = viewport.getOffsetToReveal(box, 0.0).offset;
    final height = box.size.height;
    if (height <= 0) return null;

    final viewportHeight = _scrollController.position.viewportDimension;
    return ChapterMetrics(
      top: top,
      height: height,
      scrollable: (height - viewportHeight).clamp(0.0, double.infinity),
    );
  }

  /// 当前章节内的阅读进度（0.0 ~ 1.0）
  ///
  /// - 横向翻页模式：按「当前页码 / 本章总页数」计算；
  /// - 纵向长卷模式：按「当前章块内的滚动比例」计算（0% = 章首对齐，100% = 章末读尽）。
  double get _chapterProgress {
    if (_pageMode == PageTurnMode.horizontal) {
      return ReaderProgress.horizontalProgress(
        _currentPageIndex,
        _pageStarts.length,
      );
    }

    final metrics = _verticalChapterMetrics();
    if (metrics == null) return 0.0;
    return ReaderProgress.verticalProgress(
      currentOffset: _scrollController.offset,
      metrics: metrics,
    );
  }

  /// 章内进度文案（横向显示页码，纵向显示百分比）
  ///
  /// 本章尚未分片时用**估算页数**给出量级（"本章 约 N 页"），而不是显示无信息的
  /// `--` —— 这正是 legado 保留估算层的用处：不排版也能说出量级。
  String get _chapterProgressLabel {
    if (_pageMode == PageTurnMode.horizontal) {
      if (_pageStarts.isEmpty) {
        final estimate = _estimatedPageCount;
        if (estimate != null) return '本章 约 $estimate 页';
      }
      return ReaderProgress.horizontalLabel(
        _currentPageIndex,
        _pageStarts.length,
      );
    }
    return ReaderProgress.verticalLabel(_chapterProgress);
  }

  /// 拖动章内进度条进行章内跳转
  void _seekChapterProgress(double ratio) {
    // 横向：按比例换算目标页码并直接跳转（无动画，保证拖动跟手）
    if (_pageMode == PageTurnMode.horizontal) {
      if (_pageStarts.isEmpty) return;
      final target = ReaderProgress.charOffsetFromPage(
        _pageStarts,
        ReaderProgress.pageIndexFromRatio(ratio, _pageStarts.length),
      );
      if (target == _chapterCharOffset) return;
      setState(() => _chapterCharOffset = target);
      // 准确定位到包含桥接页偏移的真实目标页（拖到 0% 时绝不误切回上一章，拉到 100% 精确达至末页）
      _syncPageController();
      return;
    }

    // 纵向：在当前章块内按比例定位（而非整条长卷，避免跨章误跳）
    if (!_scrollController.hasClients) return;
    final metrics = _verticalChapterMetrics();
    if (metrics == null) return;
    final target = ReaderProgress.verticalOffsetFromRatio(
      ratio: ratio,
      metrics: metrics,
    );
    _scrollController.jumpTo(
      target.clamp(0.0, _scrollController.position.maxScrollExtent),
    );
  }

  /// 智能清洗与规范化小说正文排版
  ///
  /// 统一委托到 `core/utils/novel_text.dart`，与离线下载服务复用同一套清洗逻辑，
  /// 保证「在线抓取」与「离线下载」得到的正文排版完全一致。
  String _cleanNovelContent(String raw) => cleanNovelContent(raw);

  /// 读取用户阅读偏好（逐项应用已保存的值，未持久化的项保持默认）
  Future<void> _loadUserPreferences() async {
    final saved = await ReaderPreferences.load();
    if (!mounted || saved.isEmpty) return;

    // 提升为局部变量以获得非空提升（字段不可提升）
    final fontSize = saved.fontSize;
    final lineHeight = saved.lineHeight;
    final theme = saved.theme;
    final pageMode = saved.pageMode;

    setState(() {
      if (fontSize != null) _fontSize = fontSize;
      if (lineHeight != null) _lineHeight = lineHeight;
      if (theme != null) _readerTheme = theme;
      if (pageMode != null) {
        _pageMode = pageMode;
        // 冷启动直接落到纵向模式时必须同步初始化长卷序列与锚点：
        // 此前只在「手动切换模式」时才初始化，导致上次退出时是纵向模式的用户
        // 再次进入会看到整屏空白（长卷序列为空 → 不渲染任何章节块）
        if (pageMode == PageTurnMode.verticalScroll) {
          _resetVerticalFlow(_currentChapterIndex);
        }
      }
    });
  }

  /// 以指定章节为锚点重建纵向长卷序列
  ///
  /// 锚点即 `CustomScrollView.center` 的落点，向上方向可无限前插而不影响坐标。
  /// 进入纵向模式、纵向内换章、冷启动恢复纵向模式三条路径共用此方法，
  /// 避免三处各自维护序列与锚点导致状态不一致。
  void _resetVerticalFlow(int index) {
    _verticalSequence
      ..clear()
      ..add(index);
    _verticalBlockKeys
      ..clear()
      ..putIfAbsent(index, () => GlobalKey());
    _verticalAnchorIndex = index;
  }

  double _lastRenderWidth = 0;
  double _lastRenderHeight = 0;

  // ==================== 横向滑窗：跨章连续渲染映射 ====================

  /// 滑窗章号序列：当前章 ± 1（存在才含）
  List<int> get _horizontalWindow {
    final window = <int>[];
    if (_hasPrevChapter) window.add(_currentChapterIndex - 1);
    window.add(_currentChapterIndex);
    if (_hasNextChapter) window.add(_currentChapterIndex + 1);
    return window;
  }

  /// 滑窗扁平总页数（口径见 [HorizontalWindow]）
  int get _horizontalTotalPages =>
      HorizontalWindow.totalPages(_horizontalWindow, _chapterPageStarts);

  /// 全局扁平页索引 → (章号, 章内页码)；越界兜底为窗口最后一章第 0 页
  (int, int) _resolveFlatPage(int rawIndex) => HorizontalWindow.resolveFlat(
    _horizontalWindow,
    _chapterPageStarts,
    rawIndex,
  );

  /// (章号, 章内页码) → 全局扁平页索引（章不在窗口内时兜底 0）
  int _flatIndexOf(int chapter, int pageInChapter) =>
      HorizontalWindow.flatIndexOf(
        _horizontalWindow,
        _chapterPageStarts,
        chapter,
        pageInChapter,
      );

  /// 横向模式是否应渲染滑窗 `PageView`
  ///
  /// **横向模式下恒为真**（滑窗必含当前章）：「本章未就绪 / 失败」一律交给窗内占位页
  /// 原地表达，绝不整屏切换视图。原因有两条：
  /// 1. 整屏切换会销毁 `PageView`，丢掉翻页动画与控制器位置；
  /// 2. 原先的判据是「窗口内任一章已分片」，与全屏加载态的判据（当前章正文是否为空）
  ///    **不同源** —— 于是跳到未下载章时会先闪一次全屏「正在抓取并排版章节正文...」，
  ///    等帧末邻居补分片后窗口变可读，又切成桥接页「正在加载本章」，同一动作出现两条提示。
  bool get _shouldRenderHorizontalWindow =>
      _pageMode == PageTurnMode.horizontal && _horizontalWindow.isNotEmpty;

  /// 按当前视口与排版参数切分正文，产出**每页起始字符偏移**（纯计算，不落任何状态）
  List<int> _sliceContent(String content) {
    if (content.isEmpty) return const [];
    if (_lastRenderWidth <= 0 || _lastRenderHeight <= 0) return const [0];
    return PaginationEngine.sliceIntoPageStarts(
      text: content,
      maxWidth: _lastRenderWidth,
      maxHeight: _lastRenderHeight,
      textStyle: TextStyle(
        fontSize: _fontSize,
        height: _lineHeight,
        letterSpacing: 0.5,
      ),
    );
  }

  /// 确保某章已分片（正文在内存即同步分片，否则留待占位页）
  void _ensureChapterSliced(int chapter) {
    if (chapter < 0 || chapter >= _chapters.length) return;
    final existing = _chapterPageStarts[chapter];
    if (existing != null && existing.isNotEmpty) return;
    final content = _contentCache[chapter] ?? _chapters[chapter].content;
    if (content.isEmpty) return;
    _chapterPageStarts[chapter] = _sliceContent(content);
  }

  /// 确保滑窗内全部章已分片（在正文就绪后调用，保证跨章翻页零占位）
  void _ensureNeighborSlices() {
    _ensureChapterSliced(_currentChapterIndex - 1);
    _ensureChapterSliced(_currentChapterIndex);
    _ensureChapterSliced(_currentChapterIndex + 1);
  }

  /// 邻居分片是否已排入帧末任务（合并同一帧内的重复请求）
  bool _neighborSlicesScheduled = false;

  /// 邻居章分片推迟到帧末：分页约 71ms/章，三章同帧补齐会卡住切章那一帧；
  /// 而邻居只需在翻到之前就绪（读一页至少几百毫秒）。
  void _scheduleNeighborSlices() {
    if (_neighborSlicesScheduled) return;
    _neighborSlicesScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _neighborSlicesScheduled = false;
      if (!mounted || _pageMode != PageTurnMode.horizontal) return;
      final before = _horizontalTotalPages;
      _ensureNeighborSlices();
      // 占位页 → 真实页数：既要重建，也要按「章 + 章内页」重新锚定（见下）
      if (_horizontalTotalPages != before) _onHorizontalPagesChanged();
    });
  }

  /// 静默预载某章正文进内存镜像（不落盘 / 不碰落点 / 不动控制器 / 不改进度）
  ///
  /// 与 [ChapterContentPipeline.ensureContent] 配合：命中沙盒即把正文写进内存镜像
  /// （见其 `cacheWriter` 分支），而内存镜像的写入会触发帧末分片
  /// （见 [_cacheChapterContent] → [_scheduleNeighborSlices]）。
  ///
  /// 这一步专治「已下载却仍停在占位页」：已离线下载的章会被
  /// [ChapterContentPipeline.downloadAdjacent] 直接跳过，正文因此从未进入内存，
  /// 也就永远分不了片 —— 而桥接页的就绪判定含离线来源，于是长期显示
  /// 「正文已就绪，即将无缝续读」。预载补上的正是「离线 → 内存 → 分片」这条通路。
  void _preloadChapterContent(int chapter) {
    if (chapter < 0 || chapter >= _chapters.length) return;
    if (_chapterPageStarts[chapter]?.isNotEmpty == true) return;
    // 正在下载 / 预取中的章由下载流程负责，避免同一章被并发抓取两次
    if (_prefetching.contains(chapter)) return;
    if (!_preloadRequested.add(chapter)) return;
    unawaited(_pipeline.ensureContent(chapter));
  }

  /// 预载滑窗内的邻居章（当前章 ± 1）
  ///
  /// 对齐 Legado 的「当前章加载成功后接力预载前后各一章」（`loadInitialContent`），
  /// 使窗口内的章在用户翻到之前就已分片，跨章落地即为真实正文页、零占位。
  void _preloadNeighborContent() {
    _preloadChapterContent(_currentChapterIndex - 1);
    _preloadChapterContent(_currentChapterIndex + 1);
  }

  /// 滑窗页数变化后的统一收口：重建 + 以「章 + 章内页」重新锚定当前页
  ///
  /// 未分片章在扁平序列里只占 1 页（见 [HorizontalWindow]）：它一旦补上分片，
  /// 窗口内**排在它之后**的所有页索引都会平移（真实页数 - 1），而 `PageView` 只能
  /// 按索引定位 —— 不重新锚定的话，「当前页」会静默漂到另一页。往前翻时补的正是
  /// 上一章（当前页索引整体后移），于是精确地漂成上一章章首。
  void _onHorizontalPagesChanged() {
    if (!mounted || _pageMode != PageTurnMode.horizontal) return;
    setState(() {});
    // 拖拽途中只重建、不定位：jumpToPage 会打断正按着的手势（见 [_dragResyncPending]）
    if (_horizontalDragging) {
      _dragResyncPending = true;
      return;
    }
    _syncPageController();
  }

  /// 是否正在程序化定位（`jumpToPage`）—— 期间的页码通知一律屏蔽
  ///
  /// `PageView` 在跳转过程中会吐出基于**旧布局**的过渡通知，其页码可能落在
  /// 任意一个 (章, 页) 上（实测：跳向末页时曾收到落在章内的中间页码）。
  /// 若把这类通知当作真实翻页处理，就会覆盖刚刚算好的落点 ——
  /// 「往前翻又滑回上一章章首附近」正是由此产生。
  ///
  /// 屏蔽窗口只有一帧：`jumpToPage` 是同步的、通知在当帧派发，
  /// 故定位后在**下一帧末**解除，不会长期屏蔽用户的真实翻页。
  bool _suppressPageChanged = false;

  /// 是否正处于横向翻页的拖拽手势中
  ///
  /// `PageView.onPageChanged` **不是等松手才触发**：页码按四舍五入变化，拖过半页那一刻
  /// 就会回调。此时若立即走跨章分支，会同步平移滑窗 —— 窗口一变，同一扁平下标指向的
  /// 内容随之改变（手指下那页会突然换成另一章），再叠加 [_translateHorizontalWindow]
  /// 的 `jumpToPage`，用户看到的就是「慢慢滑到一半被强制跳到下一章」。
  ///
  /// 因此跨章一律等手势结束（[ScrollEndNotification]）再落地；章内翻页不受影响。
  bool _horizontalDragging = false;

  /// 拖拽期间最后经过的落点，按 **(章, 章内页)** 记录
  ///
  /// 不用扁平下标：拖拽途中邻居补分片会改变窗口总页数，下标含义会整体平移，
  /// 而 (章, 章内页) 是稳定语义。
  ///
  /// **章内落点同样要覆盖**（不能只在跨章时写）：用户「跨出去又滑回来」后，
  /// 若这里仍留着最初那次跨章意图，松手就会把界面扯回上一章末页。
  (int, int)? _pendingHorizontalLanding;

  /// 拖拽期间被冻结的「重新锚定」请求
  ///
  /// 邻居分片到位会改变窗口总页数，此时需按 (章, 章内页) 重新定位 —— 但拖拽途中
  /// `jumpToPage` 会打断用户正按着的手势（位置被强行改写，后续位移继续叠加 →
  /// 落点错乱 + 画面突变）。故挂起到松手后一次性补做。
  bool _dragResyncPending = false;

  /// 已发起过静默预载的章节（防重复读盘 / 重复抓取；分片作废或缓存淘汰时移除）
  final Set<int> _preloadRequested = <int>{};

  /// 程序化定位到某个扁平页索引（跳转期间屏蔽过渡通知）
  void _jumpToFlatIndex(PageController controller, int targetRaw) {
    if (controller.page?.round() == targetRaw) return;
    _suppressPageChanged = true;
    // 程序化定位优先级更高，丢弃尚未落地的拖拽意图（此刻下标含义已被改写）
    _pendingHorizontalLanding = null;
    controller.jumpToPage(targetRaw);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _suppressPageChanged = false;
    });
  }

  /// 文本分页算法已抽取至 `PaginationEngine.sliceIntoPages`（纯函数，可独立单测）

  /// 计算当前章分页；[invalidateAll] 置真时（视口/排版变化）所有章分片一并作废
  ///
  /// 只做三件事：量尺寸 → 切当前章 → 定落点，各自成方法；
  /// 避免「分页 + 落点 + 邻居调度」混在一个 90 行的函数里。
  void _recalculatePages({
    double? width,
    double? height,
    bool invalidateAll = false,
  }) {
    // 空章节保护：避免无章节时越界访问
    if (_chapters.isEmpty) {
      _chapterPageStarts.clear();
      _pageStarts = [];
      _chapterCharOffset = 0;
      return;
    }

    final currentContent =
        _contentCache[_currentChapterIndex] ??
        _chapters[_currentChapterIndex].content;
    if (currentContent.isEmpty) {
      _chapterPageStarts.remove(_currentChapterIndex);
      _pageStarts = [];
      _chapterCharOffset = 0;
      return;
    }

    final targetWidth = width ?? _lastRenderWidth;
    final targetHeight = height ?? _lastRenderHeight;

    // 若尚未测量到真实视口尺寸，进行基础兜底（此时不写分片表，待真实尺寸到达再切）
    if (targetWidth <= 0 || targetHeight <= 0) {
      _pageStarts = const [0];
      _chapterCharOffset = 0;
      return;
    }

    _lastRenderWidth = targetWidth;
    _lastRenderHeight = targetHeight;
    _sliceCurrentChapter(currentContent, invalidateAll: invalidateAll);
    _normalizeChapterOffset();

    // 邻居分片推迟到帧末：当前章同步分片保证本帧可渲染，邻居只需在翻到之前就绪
    _scheduleNeighborSlices();
  }

  /// 切分当前章正文并写入分片表（[invalidateAll] 时连邻居分片一并作废）
  void _sliceCurrentChapter(String content, {required bool invalidateAll}) {
    if (invalidateAll) {
      _chapterPageStarts.clear();
      // 分片作废 → 允许重新预载（否则排版参数变化后邻居再无预载机会）
      _preloadRequested.clear();
    }
    final starts = _sliceContent(content);
    _chapterPageStarts[_currentChapterIndex] = starts;
    _pageStarts = starts;
    _recordPageEstimate(content, starts.length);
  }

  /// 当前排版参数下的估算输入（版心取实测视口，与分页同源）
  ChapterPageEstimateInput _pageEstimateInput(String content) {
    return ChapterPageEstimateInput(
      contentLength: content.length,
      contentWidthPx: _lastRenderWidth,
      contentHeightPx: _lastRenderHeight,
      textSizePx: _fontSize,
      // TextStyle 的 height 是倍数，换算成物理行高才能进估算公式
      textHeightPx: _fontSize * _lineHeight,
      lineSpacingPx: 0,
      paragraphSpacingPx: 0,
      // 与分页时构造的 TextStyle 同源（分页用 letterSpacing: 0.5）
      letterSpacingPx: 0.5,
    );
  }

  /// 当前章的**估算页数**（仅在真实分页不可用时用于提示）
  int? get _estimatedPageCount {
    if (_chapters.isEmpty) return null;
    final content =
        _contentCache[_currentChapterIndex] ??
        _chapters[_currentChapterIndex].content;
    if (content.isEmpty || _lastRenderWidth <= 0 || _lastRenderHeight <= 0) {
      return null;
    }
    final input = _pageEstimateInput(content);
    return PageEstimateCalibrationStore.instance
        .get(input.calibrationBucket)
        .apply(PageEstimateEngine.estimateContinuous(input));
  }

  /// 把「估算页数 → 真实页数」喂给标定存储：每切一章学习一次，越用越准
  ///
  /// 估算只影响展示（页码提示），不参与任何落点 / 分页判断，
  /// 因此这里失败最多是"估算不准一点"，不会影响阅读正确性。
  void _recordPageEstimate(String content, int realPageCount) {
    if (content.isEmpty || realPageCount <= 0) return;
    if (_lastRenderWidth <= 0 || _lastRenderHeight <= 0) return;
    final input = _pageEstimateInput(content);
    PageEstimateCalibrationStore.instance.record(
      bucket: input.calibrationBucket,
      estimatedPages: PageEstimateEngine.estimateContinuous(input),
      realPages: realPageCount,
    );
  }

  /// 把章内位置收敛到合法区间（横向）
  ///
  /// 需要收敛的只有一种情形：**末页哨兵**。分片未就绪时保持哨兵态（派生页号自然
  /// 落在现有页表的末页），分片就绪后收敛到真实末页起始偏移。
  /// 普通位置无需夹取 —— 页号是派生值，越界由 [ReaderProgress.pageIndexFromCharOffset]
  /// 自身 clamp。**同一条规则只有这一处实现。**
  void _normalizeChapterOffset() {
    if (_chapterCharOffset < _chapterEndPosition) return;
    if (_pageStarts.isEmpty) return;
    _chapterCharOffset = _pageStarts.last;
  }

  /// 切换章节 (toLastPage: 是否直接定位到该章最后一页，用于从下一章倒序回溯)
  ///
  /// 落点用**位置**表达：正向跳章 = 章首；倒序回溯 = 章末哨兵（分片就绪后自动收敛到末页）。
  /// 位置一旦落定，后续补分片 / 重排都不需要"补做落点"。
  void _switchChapter(int index, {bool toLastPage = false}) {
    if (index < 0 || index >= _chapters.length) return;

    setState(() {
      _currentChapterIndex = index;
      _chapterCharOffset = toLastPage ? _chapterEndPosition : 0;
      _recalculatePages();

      // 纵向模式下以目标章为锚点重建连续阅读序列（避免残留旧章内容造成错位）
      if (_pageMode == PageTurnMode.verticalScroll) {
        _resetVerticalFlow(index);
      }
    });

    // 通知上层同步阅读进度
    widget.onChapterChanged?.call(index, _chapters[index].title);

    // 触发异步加载目标章节
    _loadChapterContent(index);

    // 跳章后处理前后相邻章节（不依赖正文加载时序）：
    // 具备离线条件时直接下载前后各一章，否则退化为纯内存临时预取
    _pipeline.handleChapterJumped(_currentChapterIndex);

    if (_pageMode == PageTurnMode.horizontal) {
      _syncPageController();
    } else if (_pageMode == PageTurnMode.verticalScroll &&
        _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// 定位到当前章的当前页（目录跳章 / 正文就绪后）
  void _syncPageController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageMode != PageTurnMode.horizontal) return;
      // 拖拽途中不做程序化定位：既会打断用户正按着的手势，也会让索引补偿
      // 与手指位移互相叠加（落点错乱）。挂起到松手后统一补做。
      if (_horizontalDragging) {
        _dragResyncPending = true;
        return;
      }

      final targetRaw = _flatIndexOf(
        _currentChapterIndex,
        _currentPageIndex.clamp(0, math.max(0, _pageStarts.length - 1)),
      );

      final controller = _pageController;
      if (controller != null && controller.hasClients) {
        _jumpToFlatIndex(controller, targetRaw);
      } else {
        _pageController?.dispose();
        _pageController = PageController(initialPage: targetRaw);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // 空章节保护：未传入任何可读章节时展示空态，杜绝越界与伪造正文
    if (_chapters.isEmpty) {
      return ReaderEmptyScaffold(readerTheme: _readerTheme);
    }

    final chapter = _chapters[_currentChapterIndex];

    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: _readerTheme.bg,
      // 章节目录改为左侧滑出抽屉：保留阅读上下文，不再以底部弹层打断阅读
      drawer: _buildCatalogDrawer(),
      // 禁用边缘滑出，避免与横向翻页 / 左滑手势冲突，统一由顶栏目录按钮唤醒
      drawerEnableOpenDragGesture: false,
      body: SafeArea(
        child: Stack(
          children: [
            // 1. 核心阅读排版视口 (支持长按划词自由选区复制与点击控制栏)
            GestureDetector(
              key: const ValueKey('reader_gesture_area'),
              behavior: HitTestBehavior.opaque,
              onTap: _toggleControls,
              child: _buildReaderBody(),
            ),

            // 2. 阅读区三区点击热层 (左 1/3 上一页 / 中 1/3 呼出菜单 / 右 1/3 下一页)
            //
            // 正文加载失败时撤除热层，确保错误页的「重试加载」按钮可正常点击；
            // 该状态下重试入口即为按钮本身，不再需要点击呼出控制栏。
            if (!_isContentErrorState) Positioned.fill(child: _buildTapZones()),

            // 3. 顶部微拟态控制栏 (返回、书名、刷新、目录)
            if (_showControls) _buildTopBar(chapter),

            // 4. 底部微拟态控制面板 (目录、缓存、翻页模式、排版、进度条)
            if (_showControls) _buildBottomControls(chapter),

            // 5. 排版设置扩展抽屉 (字号、行距、护眼底色、翻页模式)
            if (_showSettingsPanel) _buildSettingsDrawer(),
          ],
        ),
      ),
    );
  }

  /// 构建阅读器主体
  ///
  /// 两种翻页模式**各只有一条渲染路径**，「正文未就绪 / 抓取失败」都在原位表达：
  /// - 横向 → 滑窗 `PageView`，未就绪章由窗内桥接页占位（见 [_buildChapterBridge]）；
  /// - 纵向 → 连续长卷，未就绪 / 失败由章节块内占位表达（见 [ReaderVerticalScrollView]）。
  ///
  /// 全屏加载 / 错误视图不再参与分流：它们会丢掉阅读框架（顶部栏、目录、进度），
  /// 横向还会销毁 `PageView`（丢翻页动画与控制器位置），并且让同一状态出现两套表达
  /// —— 曾表现为「先闪全屏『正在抓取并排版章节正文...』，再切成窗内『正在加载本章』」。
  Widget _buildReaderBody() {
    if (_shouldRenderHorizontalWindow) {
      return _buildHorizontalPageView();
    }
    return _buildVerticalScrollView();
  }

  /// 横向平滑翻页视口
  /// 物理视口实测完成：尺寸变化（初次渲染 / 横竖屏旋转）或尚未分页时触发亚像素级精准重算
  void _onViewportResolved(double width, double height) {
    final content =
        _contentCache[_currentChapterIndex] ??
        _chapters[_currentChapterIndex].content;
    if (PaginationEngine.needsRepaginate(
      currentWidth: _lastRenderWidth,
      currentHeight: _lastRenderHeight,
      nextWidth: width,
      nextHeight: height,
      pageCount: _pageStarts.length,
      // 只有一页 ⟺ 该页就是整篇正文（页是正文的划分，故等价）
      firstPageIsWholeContent: _pageStarts.length == 1,
      contentLength: content.length,
    )) {
      _recalculatePages(width: width, height: height, invalidateAll: true);
    }
  }

  /// PageView 页码反解为 (章, 章内页)；跨章时平移滑窗（视觉零跳变）
  void _onHorizontalPageChanged(int rawIndex) {
    _scheduleNeighborSlices();

    // 程序化定位的过渡通知：页码基于旧布局，必须整条丢弃（见 [_suppressPageChanged]）
    if (_suppressPageChanged) return;

    final landing = _resolveFlatPage(rawIndex);

    // 拖拽期间：只记录**最后经过的落点**，一律等松手再落地。
    //
    // 章内落点同样要覆盖，不能只在跨章时写：否则「跨出去又滑回来」后这里仍留着
    // 最初那次跨章意图，松手就把界面扯回上一章末页 —— 用户明明滑回了当前章第一页。
    if (_horizontalDragging) {
      _pendingHorizontalLanding = landing;
      // 手指已明确指向某章：立刻静默预载该章正文（不切章、不碰落点），
      // 让「不松手停在占位页」的这段时间里内容已进内存并完成分片
      _preloadChapterContent(landing.$1);
      return;
    }

    // 程序化定位（[_syncPageController] / [_translateHorizontalWindow] 的 jumpToPage）
    // 同样会回打本回调：落点与当前状态一致时无需任何处理，否则会重复触发章节加载，
    // 并把「未就绪落末页」的意图误置给下一次重建。
    if (rawIndex == _flatIndexOf(_currentChapterIndex, _currentPageIndex)) {
      return;
    }

    _applyHorizontalLanding(landing);
  }

  /// 横向滚动开始（拖拽 / 吸附动画都会派发，成对出现）
  void _onHorizontalScrollStart() {
    _horizontalDragging = true;
  }

  /// 横向滚动结束（吸附完成）：此刻才允许跨章落地
  ///
  /// 用户拖动期间手指下那页始终是同一次布局的结果；松手后才做「切章 + 平移滑窗 +
  /// 索引补偿」，于是跳转发生在动画结束之后，而不是滑到一半就被扯走。
  void _onHorizontalScrollEnd() {
    _horizontalDragging = false;
    final pending = _pendingHorizontalLanding;
    _pendingHorizontalLanding = null;
    final needsResync = _dragResyncPending;
    _dragResyncPending = false;

    // 落地：消费的是「松手前最后经过的落点」，与手指最终停留位置一致
    if (pending != null) _applyHorizontalLanding(pending);
    // 拖拽期间被冻结的重新锚定在此补做（分片到位导致窗口页索引平移）
    if (needsResync) _syncPageController();
  }

  /// 落地一次横向翻页（章内即时同步；跨章切换章节并平移滑窗）
  void _applyHorizontalLanding((int, int) landing) {
    if (!mounted) return;

    final (chapter, pageInChapter) = landing;
    if (chapter < 0 || chapter >= _chapters.length) return;

    final wasChapter = _currentChapterIndex;
    final targetStarts = _chapterPageStarts[chapter] ?? const <int>[];

    // 跨章回退且目标章尚未分片：落点用**章末哨兵**
    // （legado: `durChapterPos = readerPagination(prev)?.lastPageStart ?: Int.MAX_VALUE`）
    // 未分片章在窗口里只占 1 页，解析结果恒为章内第 0 页；不能用「正文是否可用」判断 ——
    // 正文已预取到内存、但尚未分片的窗口期里那个判据会漏判，从而落到上一章章首。
    final toChapterEnd = chapter < wasChapter && targetStarts.isEmpty;
    final targetOffset = toChapterEnd
        ? _chapterEndPosition
        : ReaderProgress.charOffsetFromPage(targetStarts, pageInChapter);

    // 落点与当前位置一致（程序化定位回打 / 拖回原位）时无需处理
    if (chapter == wasChapter && targetOffset == _chapterCharOffset) return;

    // 章内翻页：仅同步位置
    if (chapter == wasChapter) {
      setState(() => _chapterCharOffset = targetOffset);
      // 章内两端：提前分片相邻章 + 双向预取下载 + 静默预载正文进内存
      if (_currentPageIndex <= 1 ||
          _currentPageIndex >= _pageStarts.length - 2) {
        _ensureChapterSliced(_currentChapterIndex - 1);
        _ensureChapterSliced(_currentChapterIndex + 1);
        _pipeline.downloadAdjacent(_currentChapterIndex);
        _preloadNeighborContent();
      }
      return;
    }

    // 跨章：位置与分片表一起换；末页哨兵由 [_normalizeChapterOffset] 在分片就绪后收敛
    setState(() {
      _currentChapterIndex = chapter;
      _pageStarts = targetStarts;
      _chapterCharOffset = targetOffset;
    });

    widget.onChapterChanged?.call(chapter, _chapters[chapter].title);
    _loadChapterContent(chapter);
    _pipeline.handleChapterJumped(chapter);
    _translateHorizontalWindow();
    // 窗口平移后另一侧邻居新入窗：静默预载补齐，使下一次跨章落地同样零占位
    _preloadNeighborContent();
  }

  /// 跨章平移滑窗：jump 到新窗口中同一内容的索引（前后渲染相同，视觉零跳变）
  void _translateHorizontalWindow() {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final targetRaw = _flatIndexOf(
      _currentChapterIndex,
      _currentPageIndex.clamp(0, math.max(0, _pageStarts.length - 1)),
    );
    _jumpToFlatIndex(controller, targetRaw);
  }

  /// 滑窗内「尚未分片」章的占位页（加载中 / 已就绪待分片 / 失败 + 重试）
  ///
  /// 横向模式不再整屏切换加载 / 错误视图，跨章未就绪一律由这里表达 ——
  /// 这是「占位页原地顶替、翻页动画不中断」得以成立的前提。
  Widget _buildChapterBridge(BuildContext context, int chapter) {
    final isCurrent = chapter == _currentChapterIndex;
    // 失败态只对当前章有意义：相邻章的抓取失败在真正切过去时才会被记录
    final error = isCurrent ? _contentError : null;

    return ReaderChapterBridge(
      chapterTitle: (chapter >= 0 && chapter < _chapters.length)
          ? _chapters[chapter].title
          : '',
      readerTheme: _readerTheme,
      isReady: _isChapterContentAvailable(chapter),
      heading: error != null
          ? '本章正文加载失败'
          : isCurrent
          ? '正在加载本章'
          : (chapter < _currentChapterIndex ? '正在加载上一章' : '正在进入下一章'),
      readyHint: '正文已就绪，即将无缝续读',
      loadingHint: '正在加载正文...',
      errorMessage: error,
      onRetry: error != null
          ? () => _loadChapterContent(chapter, forceReload: true)
          : null,
    );
  }

  Widget _buildHorizontalPageView() {
    // 拖拽态由 PageView 的滚动通知驱动：跨章落地必须等手势结束（见 [_onHorizontalScrollEnd]）
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        // 只认横向主滚动，避免把外层其它可滚动组件的通知当成本页翻页
        if (notification.metrics.axis != Axis.horizontal) return false;
        if (notification is ScrollStartNotification) {
          _onHorizontalScrollStart();
        } else if (notification is ScrollEndNotification) {
          _onHorizontalScrollEnd();
        }
        return false;
      },
      child: ReaderHorizontalPageView(
        bookTitle: widget.bookTitle,
        windowChapters: _horizontalWindow,
        windowPageStarts: _chapterPageStarts,
        contentOf: (i) => (i >= 0 && i < _chapters.length)
            ? (_contentCache[i] ?? _chapters[i].content)
            : '',
        chapterTitleOf: (i) =>
            (i >= 0 && i < _chapters.length) ? _chapters[i].title : '',
        chapterCount: _chapters.length,
        currentChapterIndex: _currentChapterIndex,
        currentPageIndex: _currentPageIndex,
        pageController: _pageController,
        readerTheme: _readerTheme,
        bodyTextStyle: TextStyle(
          fontSize: _fontSize,
          height: _lineHeight,
          color: _readerTheme.text,
          letterSpacing: 0.5,
        ),
        onViewportResolved: _onViewportResolved,
        onPageChanged: _onHorizontalPageChanged,
        bridgeBuilder: _buildChapterBridge,
      ),
    );
  }

  /// 上下连续无缝长篇滚动视口
  ///
  /// 支持滚动接近底部时静默续载下一章并追加到同一滚动流，实现真正的无缝长卷阅读；
  /// 同时依据屏幕中线自动同步当前阅读章节，保证进度记录与目录高亮准确。
  ///
  /// 滚动停止由 [ReaderVerticalScrollView.onScrollEnd] 回调上来：屏中线同步已降频，
  /// 停止时补一次精确同步并触发窗口裁剪（见 [_onVerticalScrollEnd]）。
  Widget _buildVerticalScrollView() {
    // 兜底：确保连续阅读序列至少包含当前章
    if (_verticalSequence.isEmpty) {
      _verticalSequence.add(_currentChapterIndex);
    }
    _verticalBlockKeys.putIfAbsent(_currentChapterIndex, () => GlobalKey());

    return ReaderVerticalScrollView(
      sequence: _verticalSequence,
      // 锚点让「向上前插」天然不影响滚动坐标，无需任何偏移补偿
      anchorIndex: _verticalAnchorIndex,
      centerKey: _verticalCenterKey,
      chapters: _chapters,
      blockKeys: _verticalBlockKeys,
      controller: _scrollController,
      readerTheme: _readerTheme,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      // 正文解析沿用「内存缓存优先，落回章节自带正文」的顺序
      contentOf: (index) => _contentCache[index] ?? _chapters[index].content,
      hasMore: VerticalFlowEngine.hasMoreBelow(
        sequence: _verticalSequence,
        failed: _verticalFailed,
        chapterCount: _chapters.length,
      ),
      // 「加载失败」必须与「确实没有下一章」分开传：合并成一个 false
      // 会把失败误报成「已是最后一章」（见 VerticalFlowEngine.failedBelow）
      failedAbove: VerticalFlowEngine.failedAbove(
        sequence: _verticalSequence,
        failed: _verticalFailed,
      ),
      failedBelow: VerticalFlowEngine.failedBelow(
        sequence: _verticalSequence,
        failed: _verticalFailed,
        chapterCount: _chapters.length,
      ),
      onRetryAbove: _retryPrependPrevChapter,
      onRetryBelow: _retryAppendNextChapter,
      // 当前章失败同样在块内重试（不再整屏切错误页）
      currentFailed: _isContentErrorState,
      onRetryCurrent: () =>
          _loadChapterContent(_currentChapterIndex, forceReload: true),
      onScrollEnd: _onVerticalScrollEnd,
    );
  }

  /// 顶部控制栏（刷新章节 / 查看目录，具体布局见 [ReaderTopBar]）
  Widget _buildTopBar(NovelChapter chapter) {
    return ReaderTopBar(
      bookTitle: widget.bookTitle,
      readerTheme: _readerTheme,
      onBack: () => Navigator.maybePop(context),
      onRefresh: () =>
          _loadChapterContent(_currentChapterIndex, forceReload: true),
      onOpenCatalog: _showCatalogDrawer,
    );
  }

  /// 底部控制面板（具体布局见 [ReaderBottomBar]）
  Widget _buildBottomControls(NovelChapter chapter) {
    return ReaderBottomBar(
      readerTheme: _readerTheme,
      progress: _chapterProgress,
      progressLabel: _chapterProgressLabel,
      canGoPrev: _currentChapterIndex > 0,
      canGoNext: _currentChapterIndex < _chapters.length - 1,
      // 与目录顶部「已下载 N 章」共用同一沙盒口径，杜绝同一屏出现两套计数
      downloadedChapterCount: _pipeline.downloadedCount,
      isHorizontalMode: _pageMode == PageTurnMode.horizontal,
      pageModeLabel: _pageMode.label,
      onSeek: _seekChapterProgress,
      onPrevChapter: () => _switchChapter(_currentChapterIndex - 1),
      onNextChapter: () => _switchChapter(_currentChapterIndex + 1),
      onOpenCatalog: _showCatalogDrawer,
      onDownloadNext: _downloadNextManually,
      onTogglePageMode: _togglePageMode,
      onToggleSettingsPanel: () =>
          setState(() => _showSettingsPanel = !_showSettingsPanel),
    );
  }

  /// 排版设置扩展面板 (底色、字号、行距、翻页模式)
  ///
  /// 控件布局与渲染见 [ReaderSettingsPanel]；这里只负责把页面状态转换为组件参数，
  /// 并把交互回调接回页面逻辑（含偏好持久化与阅读位置锚定）。
  Widget _buildSettingsDrawer() {
    return ReaderSettingsPanel(
      readerTheme: _readerTheme,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      pageMode: _pageMode,
      onThemeSelected: (th) {
        setState(() => _readerTheme = th);
        ReaderPreferences.saveTheme(th);
      },
      onPageModeSelected: (_) => _togglePageMode(),
      onDecreaseFont: () {
        if (_fontSize <= 12) return;
        _applyTypographyChange(() => _fontSize -= 1);
        ReaderPreferences.saveFontSize(_fontSize);
      },
      onIncreaseFont: () {
        if (_fontSize >= 32) return;
        _applyTypographyChange(() => _fontSize += 1);
        ReaderPreferences.saveFontSize(_fontSize);
      },
      onLineHeightChangeStart: () =>
          _typographyAnchorOffset = _currentCharOffset,
      onLineHeightChanged: (val) {
        setState(() {
          _lineHeight = val;
          _recalculatePages(invalidateAll: true);
        });
        ReaderPreferences.saveLineHeight(val);
      },
      onLineHeightChangeEnd: () {
        if (_typographyAnchorOffset >= 0) {
          _restoreReadingPosition(_typographyAnchorOffset);
          _typographyAnchorOffset = -1;
        }
      },
    );
  }

  /// 当前章在目录中的显示行号（倒序时镜像翻转）
  int get _catalogDisplayIndex => CatalogNavigator.displayIndex(
    chapterIndex: _currentChapterIndex,
    chapterCount: _chapters.length,
    reversed: _isCatalogReversed,
  );

  /// 按当前章计算目录应停靠的滚动偏移
  double _catalogOffsetForCurrentChapter() => CatalogNavigator.offsetFor(
    displayIndex: _catalogDisplayIndex,
    chapterCount: _chapters.length,
  );

  /// 打开章节目录（左侧抽屉）
  ///
  /// 每次打开前重建滚动控制器并预置偏移量，使目录一打开就自动定位到当前正在阅读的章节。
  void _showCatalogDrawer() {
    final double targetOffset = _catalogOffsetForCurrentChapter();
    _catalogScrollController?.dispose();
    _catalogScrollController = ScrollController(
      initialScrollOffset: targetOffset,
    );
    setState(() {});

    _scaffoldKey.currentState?.openDrawer();
  }

  /// 切换章节目录排序（正序 ⇄ 倒序）
  ///
  /// 目录已展开时不能重建滚动控制器（旧控制器仍被列表占用，dispose 后会抛异常），
  /// 因此改为在列表重建完成后的下一帧，用同一控制器滚动到当前章的新行号位置。
  void _toggleCatalogOrder() {
    setState(() => _isCatalogReversed = !_isCatalogReversed);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = _catalogScrollController;
      if (!mounted || controller == null || !controller.hasClients) return;
      final target = _catalogOffsetForCurrentChapter().clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(target);
    });
  }

  /// 章节目录（左侧抽屉面板）
  ///
  /// 具体布局与状态图标的渲染见 [ReaderCatalogDrawer]，
  /// 这里只负责把页面状态转换为组件参数、并把交互回调接回页面逻辑。
  Widget _buildCatalogDrawer() {
    return ReaderCatalogDrawer(
      bookTitle: widget.bookTitle,
      chapters: _chapters,
      readerTheme: _readerTheme,
      currentChapterIndex: _currentChapterIndex,
      isReversed: _isCatalogReversed,
      downloadedCount: _pipeline.downloadedCount,
      scrollController: _catalogScrollController,
      itemHeight: CatalogNavigator.itemHeight,
      isChapterDownloaded: _pipeline.isOfflineDownloaded,
      isChapterDownloading: _downloadingChapters.contains,
      onToggleOrder: _toggleCatalogOrder,
      onSelectChapter: _switchChapter,
      onDownloadChapter: _downloadChapterFromCatalog,
      onClose: () => Navigator.pop(context),
    );
  }

  /// 从目录下载指定章节到本地沙盒
  ///
  /// 与详情页「全本下载」共用同一套离线数据（落盘位置与任务记录完全一致）：
  /// 下载完成后断网可读，下载管理页看到的进度也是同一份；同时回填内存缓存，
  /// 本次阅读内切到该章依然瞬时打开。
  Future<void> _downloadChapterFromCatalog(int index) async {
    if (_downloadingChapters.contains(index)) return;
    if (_pipeline.isOfflineDownloaded(index)) return;

    if (!_pipeline.canDownloadOffline) {
      _showReaderSnack('当前入口未绑定书籍标识或解析规则，无法离线下载');
      return;
    }

    setState(() => _downloadingChapters.add(index));
    // 复用阅读期已抓取的正文：已缓存章节零网络请求，未缓存才调度一次抓取
    final ok = await _pipeline.downloadOffline(index);
    if (!mounted) return;
    setState(() => _downloadingChapters.remove(index));

    if (!ok) {
      _showReaderSnack('《${_chapters[index].title}》下载失败，请检查网络或解析规则');
      return;
    }
    _showReaderSnack('《${_chapters[index].title}》已下载到本地，断网可读');
  }
}
