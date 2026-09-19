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
import 'package:fluxforge/features/media/novel/reader/engines/pagination_engine.dart';
import 'package:fluxforge/features/media/novel/reader/engines/reader_progress.dart';
import 'package:fluxforge/features/media/novel/reader/engines/vertical_flow_engine.dart';
import 'package:fluxforge/features/media/novel/reader/models/chapter_metrics.dart';
import 'package:fluxforge/features/media/novel/reader/models/novel_chapter.dart';
import 'package:fluxforge/features/media/novel/reader/models/page_turn_mode.dart';
import 'package:fluxforge/features/media/novel/reader/models/reader_theme.dart';
import 'package:fluxforge/features/media/novel/reader/widgets/reader_bottom_bar.dart';
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
/// SelectableText 长按划词自由选区复制、后台预取与跨章无缝续读、
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

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  // 章节与数据
  late List<NovelChapter> _chapters;
  late int _currentChapterIndex;

  // 正文异步沙箱加载状态与缓存
  bool _isLoadingContent = false;
  String? _contentError;
  /// 章节正文会话缓存（阅读期加速层，退出阅读器即释放）
  ///
  /// 与「离线下载」（沙盒持久化、断网可读）是两层不同机制，详见 [ChapterCache]；
  /// 内置访问序 LRU，超出容量时淘汰最久未使用的章节。
  final ChapterCache _contentCache = ChapterCache();

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
  int _currentPageIndex = 0;
  List<String> _pageSlices = [];

  /// 各章分片缓存：横向滑窗（当前章 ± 1）跨章连续渲染的数据源
  final Map<int, List<String>> _chapterSlices = {};

  // 上下滚动控制器
  final ScrollController _scrollController = ScrollController();

  // ==================== 后台预取与跨章连续阅读状态 ====================

  /// 正在后台预取中的章节索引集合（防止同一章重复发起请求）
  final Set<int> _prefetching = {};

  /// 正在离线下载到沙盒的章节索引集合（目录内展示下载中状态）
  final Set<int> _downloadingChapters = {};

  /// 切换章节时是否直接定位到最后一页（用于从下一章倒序回溯到上一章）
  bool _openAtLastPage = false;

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
    _pageController?.dispose();
    _scrollController.dispose();
    _catalogScrollController?.dispose();
    super.dispose();
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
  Future<void> _loadChapterContent(int index, {bool forceReload = false}) async {
    if (index < 0 || index >= _chapters.length) return;

    // 1. 如果已有本地缓存且非强制刷新，直接挂载并重新切片（命中缓存即刻渲染，零等待）
    if (!forceReload && _contentCache.containsKey(index) && _contentCache[index]!.isNotEmpty) {
      final cached = _contentCache[index]!;
      setState(() {
        _chapters[index] = _chapters[index].copyWith(content: cached);
        _isLoadingContent = false;
        _contentError = null;
        _recalculatePages();
        if (_openAtLastPage) {
          _currentPageIndex = _pageSlices.isNotEmpty ? _pageSlices.length - 1 : 0;
          _openAtLastPage = false;
        }
      });
      _syncPageController();
      // 命中内存镜像即代表阅读顺畅，立即静默下载前后相邻章节
      _pipeline.downloadAdjacent(_currentChapterIndex);
      return;
    }

    // 2. 沙盒离线正文：本地文件 IO，耗时极短，因此**刻意不进入 loading 态** ——
    //    否则会出现「明明已下载却仍闪一下加载」的反差。
    //    守卫说明：isOfflineDownloaded 是同步判定且未配置书籍标识时直接返回 false，
    //    因此未下载的章节走这条路是零开销的，不会给正常路径增加任何成本。
    if (!forceReload && _pipeline.isOfflineDownloaded(index)) {
      final offline = await _pipeline.readOffline(index);
      // 读盘期间用户可能已切走，此时必须丢弃本次结果，避免覆盖当前章
      if (!mounted || _currentChapterIndex != index) return;
      if (offline != null && offline.isNotEmpty) {
        _cacheChapterContent(index, offline);
        setState(() {
          _chapters[index] = _chapters[index].copyWith(content: offline);
          _isLoadingContent = false;
          _contentError = null;
          _recalculatePages();
          if (_openAtLastPage) {
            _currentPageIndex = _pageSlices.isNotEmpty ? _pageSlices.length - 1 : 0;
            _openAtLastPage = false;
          }
        });
        _syncPageController();
        _pipeline.downloadAdjacent(_currentChapterIndex);
        return;
      }
      // 离线文件读不到（损坏 / 被外部清理）时不报错，继续降级到自带正文 / 网络抓取
    }

    final currentCh = _chapters[index];
    final chapterUrl = currentCh.url?.trim() ?? '';

    // 若无目标 URL 且已有正文，直接使用
    if (chapterUrl.isEmpty) {
      if (currentCh.content.isNotEmpty) {
        // 章节自带正文同样属于「已加载」→ 一并落盘，退出后仍可读
        _mountLoadedContent(index, currentCh.content);
        _recalculatePages();
        if (_openAtLastPage) {
          _currentPageIndex = _pageSlices.isNotEmpty ? _pageSlices.length - 1 : 0;
          _openAtLastPage = false;
        }
        _syncPageController();
      }
      return;
    }

    // 2. 调度沙箱执行 parse 动作
    setState(() {
      _isLoadingContent = true;
      _contentError = null;
    });

    try {
      if (widget.rule == null) {
        throw Exception('未绑定解析规则，无法调度沙箱抓取章节内容');
      }

      final res = await RuleEngine.parse(widget.rule!, chapterUrl);
      String rawContent = '';

      if (res is Map) {
        rawContent = res['content']?.toString() ??
            res['text']?.toString() ??
            res['data']?.toString() ??
            '';
      } else if (res is String) {
        rawContent = res;
      }

      final cleanContent = _cleanNovelContent(rawContent);

      if (cleanContent.isEmpty) {
        throw Exception('目标站点响应完成，但未提取到正文文本内容');
      }

      // 建立内存镜像并落盘 —— 抓到即属于「已下载」，退出阅读器后依然可读
      _mountLoadedContent(index, cleanContent);
      if (mounted && _currentChapterIndex == index) {
        setState(() {
          _chapters[index] = _chapters[index].copyWith(content: cleanContent);
          _isLoadingContent = false;
          _contentError = null;
          _recalculatePages();
          if (_openAtLastPage) {
            _currentPageIndex = _pageSlices.isNotEmpty ? _pageSlices.length - 1 : 0;
            _openAtLastPage = false;
          }
        });
        _syncPageController();
      }
      // 当前章加载就绪后，立即静默下载相邻章节（实现连续翻页零等待）
      _pipeline.downloadAdjacent(_currentChapterIndex);
    } catch (e) {
      if (mounted && _currentChapterIndex == index) {
        setState(() {
          _isLoadingContent = false;
          _contentError = '正文加载失败: $e';
        });
      }
    }
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
    _syncVerticalCurrentChapter();

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

  /// 写入会话缓存，并按容量上限回收最久未使用的章节
  void _cacheChapterContent(int index, String content) {
    _contentCache[index] = content;
    _evictChapterCacheIfNeeded();
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

  /// 按容量上限回收内存缓存
  ///
  /// 保护集合覆盖「纵向长卷正在渲染的章节」「当前章」「预取 / 下载中的章节」，
  /// 以及**没有远程地址的章节**（如详情页直传的单章正文）——
  /// 后者一旦被淘汰，正文将永久无法重新获取。
  void _evictChapterCacheIfNeeded() {
    final protect = <int>{
      ..._verticalSequence,
      _currentChapterIndex,
      ..._prefetching,
      ..._downloadingChapters,
      for (int i = 0; i < _chapters.length; i++)
        if ((_chapters[i].url ?? '').isEmpty) i,
    };

    final evicted = _contentCache.evictOverflow(protect: protect);
    if (evicted.isEmpty) return;

    // 同步清空章节模型中的正文引用：否则 String 仍被 _chapters 持有，内存不会真正释放
    for (final index in evicted) {
      _chapters[index] = _chapters[index].copyWith(content: '');
    }
  }

  /// 当前阅读位置在本章正文中的字符偏移量
  ///
  /// 用于翻页模式切换、字号/行距调整后精确还原阅读位置，杜绝「从头开始」。
  int get _currentCharOffset {
    if (_chapters.isEmpty) return 0;
    final content = _chapters[_currentChapterIndex].content;
    if (content.isEmpty) return 0;

    // 横向：累加当前页之前各页的字符长度
    if (_pageMode == PageTurnMode.horizontal) {
      return ReaderProgress.charOffsetFromPage(_pageSlices, _currentPageIndex);
    }

    // 纵向：按当前章块内的阅读比例换算为字符偏移，保证切换模式 / 改排版后不跳回开头
    return (_chapterProgress * content.length).round();
  }

  /// 在下一帧布局完成后，把阅读位置还原到指定字符偏移处
  void _restoreReadingPosition(int charOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 横向：依据偏移量反查所在页码并直接跳转
      if (_pageMode == PageTurnMode.horizontal) {
        if (_pageSlices.isEmpty) return;

        final target =
            ReaderProgress.pageIndexFromCharOffset(_pageSlices, charOffset);

        if (_currentPageIndex != target) {
          setState(() => _currentPageIndex = target);
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
        _currentPageIndex = 0;
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
        ok
            ? '下载完成，当前已下载 ${_pipeline.downloadedCount} 章'
            : '下载失败，请检查网络或解析规则',
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
      final target = (_scrollController.offset - viewport * 0.92)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
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
      final target = (_scrollController.offset + viewport * 0.92)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
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

    final box = _verticalBlockKeys[_currentChapterIndex]
        ?.currentContext
        ?.findRenderObject() as RenderBox?;
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
        _pageSlices.length,
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
  String get _chapterProgressLabel {
    if (_pageMode == PageTurnMode.horizontal) {
      return ReaderProgress.horizontalLabel(
        _currentPageIndex,
        _pageSlices.length,
      );
    }
    return ReaderProgress.verticalLabel(_chapterProgress);
  }

  /// 拖动章内进度条进行章内跳转
  void _seekChapterProgress(double ratio) {
    // 横向：按比例换算目标页码并直接跳转（无动画，保证拖动跟手）
    if (_pageMode == PageTurnMode.horizontal) {
      if (_pageSlices.isEmpty) return;
      final target =
          ReaderProgress.pageIndexFromRatio(ratio, _pageSlices.length);
      if (target == _currentPageIndex) return;
      setState(() => _currentPageIndex = target);
      // 准确定位到包含桥接页偏移的真实目标页（拖到 0% 时绝不误切回上一章，拉到 100% 精确达至末页）
      _syncPageController();
      return;
    }

    // 纵向：在当前章块内按比例定位（而非整条长卷，避免跨章误跳）
    if (!_scrollController.hasClients) return;
    final metrics = _verticalChapterMetrics();
    if (metrics == null) return;
    final target =
        ReaderProgress.verticalOffsetFromRatio(ratio: ratio, metrics: metrics);
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

  /// 窗口内某章的渲染页数：未分片章恒占 1 页（加载占位页）
  int _windowPageCountOf(int chapter) {
    final slices = _chapterSlices[chapter];
    return (slices != null && slices.isNotEmpty) ? slices.length : 1;
  }

  /// 滑窗扁平总页数
  int get _horizontalTotalPages =>
      _horizontalWindow.fold(0, (sum, c) => sum + _windowPageCountOf(c));

  /// 全局扁平页索引 → (章号, 章内页码)；越界兜底为窗口最后一章第 0 页
  (int, int) _resolveFlatPage(int rawIndex) {
    var remaining = rawIndex;
    for (final chapter in _horizontalWindow) {
      final count = _windowPageCountOf(chapter);
      if (remaining < count) return (chapter, remaining);
      remaining -= count;
    }
    return (_horizontalWindow.last, 0);
  }

  /// (章号, 章内页码) → 全局扁平页索引（章不在窗口内时兜底 0）
  int _flatIndexOf(int chapter, int pageInChapter) {
    var base = 0;
    for (final c in _horizontalWindow) {
      if (c == chapter) return base + pageInChapter;
      base += _windowPageCountOf(c);
    }
    return 0;
  }

  /// 按当前视口与排版参数切片正文（纯计算，不落任何状态）
  List<String> _sliceContent(String content) {
    if (content.isEmpty) return const [];
    if (_lastRenderWidth <= 0 || _lastRenderHeight <= 0) return [content];
    return PaginationEngine.sliceIntoPages(
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
    final existing = _chapterSlices[chapter];
    if (existing != null && existing.isNotEmpty) return;
    final content = _contentCache[chapter] ?? _chapters[chapter].content;
    if (content.isEmpty) return;
    _chapterSlices[chapter] = _sliceContent(content);
  }

  /// 确保滑窗内全部章已分片（在正文就绪后调用，保证跨章翻页零占位）
  void _ensureNeighborSlices() {
    _ensureChapterSliced(_currentChapterIndex - 1);
    _ensureChapterSliced(_currentChapterIndex);
    _ensureChapterSliced(_currentChapterIndex + 1);
  }

  /// 文本分页算法已抽取至 `PaginationEngine.sliceIntoPages`（纯函数，可独立单测）

  /// 计算当前章分页；[invalidateAll] 置真时（视口/排版变化）所有章分片一并作废
  void _recalculatePages({
    double? width,
    double? height,
    bool invalidateAll = false,
  }) {
    // 空章节保护：避免无章节时越界访问
    if (_chapters.isEmpty) {
      _chapterSlices.clear();
      _pageSlices = [];
      _currentPageIndex = 0;
      return;
    }

    final currentContent = _contentCache[_currentChapterIndex] ??
        _chapters[_currentChapterIndex].content;
    if (currentContent.isEmpty) {
      _chapterSlices.remove(_currentChapterIndex);
      _pageSlices = [];
      _currentPageIndex = 0;
      return;
    }

    final targetWidth = width ?? _lastRenderWidth;
    final targetHeight = height ?? _lastRenderHeight;

    // 若尚未测量到真实视口尺寸，进行基础兜底
    if (targetWidth <= 0 || targetHeight <= 0) {
      _pageSlices = [currentContent];
      _currentPageIndex = 0;
      return;
    }

    _lastRenderWidth = targetWidth;
    _lastRenderHeight = targetHeight;

    if (invalidateAll) _chapterSlices.clear();
    _chapterSlices[_currentChapterIndex] = _sliceContent(currentContent);
    _pageSlices = _chapterSlices[_currentChapterIndex]!;

    if (_openAtLastPage && _pageSlices.isNotEmpty) {
      _currentPageIndex = _pageSlices.length - 1;
      _openAtLastPage = false;
    } else {
      _currentPageIndex = _currentPageIndex.clamp(0, math.max(0, _pageSlices.length - 1));
    }

    // 顺带补齐滑窗邻居分片，保证跨章翻页不出现占位页
    _ensureNeighborSlices();
  }

  /// 切换章节 (toLastPage: 是否直接定位到该章最后一页，用于从下一章倒序回溯)
  void _switchChapter(int index, {bool toLastPage = false}) {
    if (index < 0 || index >= _chapters.length) return;
    _openAtLastPage = toLastPage;

    setState(() {
      _currentChapterIndex = index;
      _recalculatePages();

      if (toLastPage && _pageSlices.isNotEmpty) {
        _currentPageIndex = _pageSlices.length - 1;
        _openAtLastPage = false;
      } else if (!toLastPage) {
        _currentPageIndex = 0;
      }

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
    } else if (_pageMode == PageTurnMode.verticalScroll && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// 定位到当前章的当前页（目录跳章 / 正文就绪后）
  void _syncPageController() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_pageMode != PageTurnMode.horizontal) return;

      final targetRaw = _flatIndexOf(
        _currentChapterIndex,
        _currentPageIndex.clamp(0, math.max(0, _pageSlices.length - 1)),
      );

      final controller = _pageController;
      if (controller != null && controller.hasClients) {
        if (controller.page?.round() != targetRaw) {
          controller.jumpToPage(targetRaw);
        }
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

  /// 构建阅读器主体（状态分流：加载中 / 加载失败 / 正文排版）
  Widget _buildReaderBody() {
    final chapter = _chapters[_currentChapterIndex];

    // 状态 A：正文加载中且无可用内容
    if (_isLoadingContent && chapter.content.isEmpty) {
      return ReaderLoadingView(readerTheme: _readerTheme);
    }

    // 状态 B：正文加载失败且无可用内容
    if (_isContentErrorState) {
      return ReaderErrorView(
        readerTheme: _readerTheme,
        message: _contentError!,
        onRetry: () =>
            _loadChapterContent(_currentChapterIndex, forceReload: true),
      );
    }

    // 状态 C：正文就绪，根据模式渲染平滑横翻或长篇纵滚
    return _pageMode == PageTurnMode.horizontal
        ? _buildHorizontalPageView()
        : _buildVerticalScrollView();
  }

  /// 横向平滑翻页视口
  /// 物理视口实测完成：尺寸变化（初次渲染 / 横竖屏旋转）或尚未分页时触发亚像素级精准重算
  void _onViewportResolved(double width, double height) {
    final content = _contentCache[_currentChapterIndex] ??
        _chapters[_currentChapterIndex].content;
    if ((_lastRenderWidth - width).abs() > 1.0 ||
        (_lastRenderHeight - height).abs() > 1.0 ||
        _pageSlices.isEmpty ||
        (_pageSlices.length == 1 &&
            _pageSlices.first == content &&
            content.length > 300)) {
      _recalculatePages(width: width, height: height, invalidateAll: true);
    }
  }

  /// PageView 页码反解为 (章, 章内页)；跨章时平移滑窗（视觉零跳变）
  void _onHorizontalPageChanged(int rawIndex) {
    _ensureNeighborSlices();

    final (chapter, pageInChapter) = _resolveFlatPage(rawIndex);
    final wasChapter = _currentChapterIndex;

    // 章内翻页：仅同步页码
    if (chapter == wasChapter) {
      setState(() {
        _currentPageIndex = pageInChapter.clamp(0, math.max(0, _pageSlices.length - 1));
      });
      // 章内两端：提前分片相邻章 + 双向预取下载
      if (_currentPageIndex <= 1 || _currentPageIndex >= _pageSlices.length - 2) {
        _ensureChapterSliced(_currentChapterIndex - 1);
        _ensureChapterSliced(_currentChapterIndex + 1);
        _pipeline.downloadAdjacent(_currentChapterIndex);
      }
      return;
    }

    // 跨章：目标章在当前章之前且未就绪时，加载完成后落其最后一页
    if (chapter < wasChapter && !_isChapterContentAvailable(chapter)) {
      _openAtLastPage = true;
    }

    setState(() {
      _currentChapterIndex = chapter;
      _pageSlices = _chapterSlices[chapter] ?? const [];
      _currentPageIndex =
          pageInChapter.clamp(0, math.max(0, _pageSlices.length - 1));
    });

    widget.onChapterChanged?.call(chapter, _chapters[chapter].title);
    _loadChapterContent(chapter);
    _pipeline.handleChapterJumped(chapter);
    _translateHorizontalWindow();
  }

  /// 跨章平移滑窗：jump 到新窗口中同一内容的索引（前后渲染相同，视觉零跳变）
  void _translateHorizontalWindow() {
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final targetRaw = _flatIndexOf(
      _currentChapterIndex,
      _currentPageIndex.clamp(0, math.max(0, _pageSlices.length - 1)),
    );
    if (controller.page?.round() == targetRaw) return;
    controller.jumpToPage(targetRaw);
  }

  Widget _buildHorizontalPageView() {
    return ReaderHorizontalPageView(
      bookTitle: widget.bookTitle,
      windowChapters: _horizontalWindow,
      windowSlices: _chapterSlices,
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
    );
  }

  /// 上下连续无缝长篇滚动视口
  ///
  /// 支持滚动接近底部时静默续载下一章并追加到同一滚动流，实现真正的无缝长卷阅读；
  /// 同时依据屏幕中线自动同步当前阅读章节，保证进度记录与目录高亮准确。
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
    );
  }

  /// 顶部控制栏（刷新章节 / 查看目录，具体布局见 [ReaderTopBar]）
  Widget _buildTopBar(NovelChapter chapter) {
    return ReaderTopBar(
      bookTitle: widget.bookTitle,
      readerTheme: _readerTheme,
      onBack: () => Navigator.maybePop(context),
      onRefresh: () => _loadChapterContent(_currentChapterIndex, forceReload: true),
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
      onLineHeightChangeStart: () => _typographyAnchorOffset = _currentCharOffset,
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
    _catalogScrollController = ScrollController(initialScrollOffset: targetOffset);
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
      final target = _catalogOffsetForCurrentChapter()
          .clamp(0.0, controller.position.maxScrollExtent);
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
