import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import '../../../../core/storage/app_storage.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../models/rule.dart';
import '../../../../services/rule_engine.dart';

/// 护眼阅读配色方案枚举与配置
enum ReaderTheme {
  parchment(
    name: '羊皮复古',
    bg: Color(0xFFF6F1E7),
    text: Color(0xFF3B2F1D),
    subText: Color(0xFF7A6B58),
  ),
  bamboo(
    name: '豆沙护眼',
    bg: Color(0xFFE4EDE1),
    text: Color(0xFF1D2E1A),
    subText: Color(0xFF536B50),
  ),
  night(
    name: '极夜深邃',
    bg: Color(0xFF0F141C),
    text: Color(0xFFA0ABC0),
    subText: Color(0xFF586377),
  ),
  porcelain(
    name: '纯净白瓷',
    bg: Color(0xFFFFFFFF),
    text: Color(0xFF1A202C),
    subText: Color(0xFF718096),
  );

  const ReaderTheme({
    required this.name,
    required this.bg,
    required this.text,
    required this.subText,
  });

  final String name;
  final Color bg;
  final Color text;
  final Color subText;
}

/// 翻页模式
enum PageTurnMode {
  horizontal('平滑横翻'),
  verticalScroll('上下滚动');

  const PageTurnMode(this.label);
  final String label;
}

/// 小说章节模型
class NovelChapter {
  final String title;
  final String content;
  final String? url;

  const NovelChapter({
    required this.title,
    this.content = '',
    this.url,
  });

  NovelChapter copyWith({
    String? title,
    String? content,
    String? url,
  }) {
    return NovelChapter(
      title: title ?? this.title,
      content: content ?? this.content,
      url: url ?? this.url,
    );
  }
}

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
  });

  final String bookTitle;
  final int initialChapterIndex;
  final List<NovelChapter> chapters;
  final Rule? rule;
  final Map<String, String> customHeaders;

  /// 章节切换回调 (章节索引, 章节标题)
  /// 供上层记录阅读进度，实现「继续阅读」章节级续读
  final void Function(int index, String title)? onChapterChanged;

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
  final Map<int, String> _contentCache = {};

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

  // 上下滚动控制器
  final ScrollController _scrollController = ScrollController();

  // ==================== 后台预取与跨章连续阅读状态 ====================

  /// 正在后台预取中的章节索引集合（防止同一章重复发起请求）
  final Set<int> _prefetching = {};

  /// 横向模式防抖标记：正在执行章末/章首自动续章
  bool _advancingChapter = false;

  /// 切换章节时是否直接定位到最后一页（用于从下一章倒序回溯到上一章）
  bool _openAtLastPage = false;

  /// 纵向连续阅读的章节序列（首个元素为进入纵向模式时的章节）
  final List<int> _verticalSequence = [];

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

  /// 目录列表固定行高（固定行高才能用 initialScrollOffset 精确跳转到指定章节）
  static const double _catalogItemHeight = 56.0;

  // ==================== 翻页桥接页与真实页面映射 ====================

  /// 当前章节是否存在上一章
  bool get _hasPrevChapter => _currentChapterIndex > 0;

  /// 当前章节是否存在下一章
  bool get _hasNextChapter => _currentChapterIndex < _chapters.length - 1;

  /// 章首上一章衔接页占用页数（存在上一章时占用第 0 页）
  int get _prevBridgeCount => _hasPrevChapter ? 1 : 0;

  /// 章末下一章衔接页占用页数
  int get _nextBridgeCount => _hasNextChapter ? 1 : 0;

  /// PageView 包含衔接页的总页数
  int get _totalPageCount => _prevBridgeCount + _pageSlices.length + _nextBridgeCount;

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _setupChapters();
    _loadUserPreferences();
    _recalculatePages();
    _pageController = PageController(initialPage: _prevBridgeCount + _currentPageIndex);

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

    for (int i = 0; i < _chapters.length; i++) {
      if (_chapters[i].content.isNotEmpty) {
        _contentCache[i] = _chapters[i].content;
      }
    }
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
      // 命中缓存即代表阅读顺畅，立即静默双向预取前后相邻章节
      _maybePrefetchAdjacent();
      return;
    }

    final currentCh = _chapters[index];
    final chapterUrl = currentCh.url?.trim() ?? '';

    // 若无目标 URL 且已有正文，直接使用
    if (chapterUrl.isEmpty) {
      if (currentCh.content.isNotEmpty) {
        _contentCache[index] = currentCh.content;
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

      // 写入缓存并挂载更新
      _contentCache[index] = cleanContent;
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
      // 当前章加载就绪后，立即静默双向预取相邻章节（实现连续翻页零等待）
      _maybePrefetchAdjacent();
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

  /// 确保指定章节正文可用：优先命中缓存，否则调度沙箱抓取并写入缓存
  ///
  /// 返回清洗后的正文文本；失败返回 null（由调用方决定是否降级展示）。
  /// 该方法为「纯数据获取」，不触碰当前 UI 状态，因此可安全用于后台预取与纵向续载。
  Future<String?> _ensureChapterContent(int index) async {
    if (index < 0 || index >= _chapters.length) return null;

    final cached = _contentCache[index];
    if (cached != null && cached.isNotEmpty) return cached;

    final url = _chapters[index].url?.trim() ?? '';
    // 无远程地址时退化为本地已有正文
    if (url.isEmpty) {
      final local = _chapters[index].content;
      if (local.isNotEmpty) {
        _contentCache[index] = local;
        return local;
      }
      return null;
    }

    if (widget.rule == null) return null;

    try {
      final res = await RuleEngine.parse(widget.rule!, url);
      final String raw = res is Map
          ? (res['content']?.toString() ?? res['text']?.toString() ?? '')
          : (res is String ? res : '');
      final clean = _cleanNovelContent(raw);
      if (clean.isEmpty) return null;
      _contentCache[index] = clean;
      return clean;
    } catch (_) {
      // 后台预取失败静默忽略：用户真正切到该章时会走正常加载与错误提示流程
      return null;
    }
  }

  /// 静默预取指定章节正文（不改变当前显示，仅写入缓存以实现切章秒开）
  Future<void> _prefetchChapter(int index) async {
    if (index < 0 || index >= _chapters.length) return;
    if (_contentCache.containsKey(index)) return;
    if (_prefetching.contains(index)) return;

    _prefetching.add(index);
    final content = await _ensureChapterContent(index);
    _prefetching.remove(index);

    // 预取成功仅刷新控制栏的「已缓存章节数」展示，不干扰当前阅读内容
    if (content != null && mounted) {
      setState(() {});
    }
  }

  /// 触发相邻章节双向预取（向前/向后均提前预载，实现顺读与回溯零卡顿）
  void _maybePrefetchAdjacent() {
    // 优先预取下一章
    final next = _currentChapterIndex + 1;
    if (next < _chapters.length && !_contentCache.containsKey(next)) {
      _prefetchChapter(next);
    }
    // 同步预取上一章
    final prev = _currentChapterIndex - 1;
    if (prev >= 0 && !_contentCache.containsKey(prev)) {
      _prefetchChapter(prev);
    }
  }

  /// 横向模式：滑入章首衔接页后自动回退到上一章最后一页（带防抖与轻微延迟）
  void _autoAdvanceToPreviousChapter() {
    if (_advancingChapter) return;
    if (_currentChapterIndex <= 0) return;

    _advancingChapter = true;
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) {
        _advancingChapter = false;
        return;
      }
      _advancingChapter = false;
      _switchChapter(_currentChapterIndex - 1, toLastPage: true);
    });
  }

  /// 横向模式：滑入章末衔接页后自动续读下一章（带防抖与轻微延迟，避免误触）
  void _autoAdvanceToNextChapter() {
    if (_advancingChapter) return;
    if (_currentChapterIndex >= _chapters.length - 1) return;

    _advancingChapter = true;
    Future.delayed(const Duration(milliseconds: 260), () {
      if (!mounted) {
        _advancingChapter = false;
        return;
      }
      _advancingChapter = false;
      _switchChapter(_currentChapterIndex + 1);
    });
  }

  /// 纵向滚动监听：触底续载下一章 + 同步当前阅读章节
  void _onVerticalScroll() {
    if (_pageMode != PageTurnMode.verticalScroll) return;
    if (!_scrollController.hasClients) return;

    final position = _scrollController.position;
    // 距离底部不足 480px 时静默续载下一章（实现无缝长卷，用户无感知）
    if (position.maxScrollExtent - position.pixels < 480) {
      _appendNextVerticalChapter();
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
    if (_verticalSequence.isEmpty) return;

    final next = _verticalSequence.last + 1;
    if (next >= _chapters.length) return;
    if (_verticalAppending.contains(next)) return;
    if (_verticalFailed.contains(next)) return;

    _verticalAppending.add(next);
    final content = await _ensureChapterContent(next);
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

    // 继续向后预取，保证连续下拉时永不卡顿
    if (next + 1 < _chapters.length) {
      _prefetchChapter(next + 1);
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

  /// 已缓存的章节数量（用于控制栏缓存状态展示）
  int get _cachedChapterCount =>
      _contentCache.entries.where((e) => e.value.isNotEmpty).length;

  /// 当前阅读位置在本章正文中的字符偏移量
  ///
  /// 用于翻页模式切换、字号/行距调整后精确还原阅读位置，杜绝「从头开始」。
  int get _currentCharOffset {
    if (_chapters.isEmpty) return 0;
    final content = _chapters[_currentChapterIndex].content;
    if (content.isEmpty) return 0;

    // 横向：累加当前页之前各页的字符长度
    if (_pageMode == PageTurnMode.horizontal) {
      if (_pageSlices.isEmpty) return 0;
      int offset = 0;
      for (int i = 0; i < _currentPageIndex && i < _pageSlices.length; i++) {
        offset += _pageSlices[i].length;
      }
      return offset;
    }

    // 纵向：按滚动比例近似换算为字符偏移，足以保证切换后不跳回开头
    if (!_scrollController.hasClients) return 0;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return 0;
    final ratio = (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
    return (ratio * content.length).round();
  }

  /// 在下一帧布局完成后，把阅读位置还原到指定字符偏移处
  void _restoreReadingPosition(int charOffset) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      // 横向：依据偏移量反查所在页码并直接跳转
      if (_pageMode == PageTurnMode.horizontal) {
        if (_pageSlices.isEmpty) return;

        int target = 0;
        int acc = 0;
        for (int i = 0; i < _pageSlices.length; i++) {
          if (acc + _pageSlices[i].length > charOffset) {
            target = i;
            break;
          }
          acc += _pageSlices[i].length;
          target = i;
        }
        target = target.clamp(0, _pageSlices.length - 1);

        if (_currentPageIndex != target) {
          setState(() => _currentPageIndex = target);
        }
        final controller = _pageController;
        if (controller != null &&
            controller.hasClients &&
            controller.page?.round() != target) {
          controller.jumpToPage(target);
        }
        return;
      }

      // 纵向：按字符偏移换算为滚动距离
      final contentLength = _chapters[_currentChapterIndex].content.length;
      if (contentLength <= 0 || !_scrollController.hasClients) return;
      final ratio = (charOffset / contentLength).clamp(0.0, 1.0);
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      _scrollController.jumpTo((ratio * maxExtent).clamp(0.0, maxExtent));
    });
  }

  /// 统一入口：切换翻页模式（保持当前阅读位置，不再从头开始）
  void _togglePageMode() {
    final offset = _currentCharOffset;
    final nextMode = _pageMode == PageTurnMode.horizontal
        ? PageTurnMode.verticalScroll
        : PageTurnMode.horizontal;

    HapticFeedback.selectionClick();
    setState(() {
      _pageMode = nextMode;
      if (nextMode == PageTurnMode.verticalScroll) {
        // 进入纵向模式：以当前章为起点重建连续阅读序列
        _verticalSequence
          ..clear()
          ..add(_currentChapterIndex);
        _verticalBlockKeys
          ..clear()
          ..putIfAbsent(_currentChapterIndex, () => GlobalKey());
        _advancingChapter = false;
      } else {
        // 回到横向模式：复位页码并清空纵向序列
        _currentPageIndex = 0;
        _verticalSequence.clear();
        _verticalBlockKeys.clear();
      }
    });

    _savePreference(
      'novel_page_mode',
      nextMode == PageTurnMode.verticalScroll ? 'vertical' : 'horizontal',
    );

    // 布局完成后恢复阅读位置
    _restoreReadingPosition(offset);
  }

  /// 应用排版参数变更（字号加减等）：变更前后保持阅读位置，避免重新排版后跳回开头
  void _applyTypographyChange(VoidCallback mutate) {
    final offset = _currentCharOffset;
    setState(() {
      mutate();
      _recalculatePages();
    });
    _restoreReadingPosition(offset);
  }

  /// 手动触发下一章预取（供底部「已缓存 N 章」按钮调用，给出明确反馈）
  Future<void> _prefetchNextManually() async {
    final next = _currentChapterIndex + 1;
    if (next >= _chapters.length) {
      _showReaderSnack('已是最后一章，无需预取');
      return;
    }

    HapticFeedback.lightImpact();
    if (_contentCache.containsKey(next)) {
      _showReaderSnack('下一章《${_chapters[next].title}》已缓存，可无缝续读');
      return;
    }

    _showReaderSnack('正在预取下一章《${_chapters[next].title}》...');
    await _prefetchChapter(next);
    if (!mounted) return;
    _showReaderSnack(
      _contentCache.containsKey(next)
          ? '预取完成，当前已缓存 $_cachedChapterCount 章'
          : '预取失败，请检查网络或解析规则',
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
    HapticFeedback.selectionClick();

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

    // 横向翻页：本章正文未就绪时若点击上一页直接切回上一章末尾
    if (_pageSlices.isEmpty) {
      if (_currentChapterIndex > 0) {
        _switchChapter(_currentChapterIndex - 1, toLastPage: true);
      }
      return;
    }

    // 本章内往前翻一页
    if (_currentPageIndex > 0) {
      _pageController?.previousPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }

    // 已是本章第一页 → 无缝回退至上一章最后一页
    if (_currentChapterIndex > 0) {
      _switchChapterToLastPage(_currentChapterIndex - 1);
    } else {
      _showReaderSnack('已是全书第一页');
    }
  }

  /// 点击右侧 1/3 区域：下一页（横向翻页 / 纵向滚屏）
  void _goToNextPage() {
    HapticFeedback.selectionClick();

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

    // 横向翻页：本章内后一页
    if (_pageSlices.isEmpty) return;
    if (_currentPageIndex < _pageSlices.length - 1) {
      _pageController?.nextPage(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
      return;
    }

    // 已是本章最后一页 → 无缝续读下一章
    if (_currentChapterIndex < _chapters.length - 1) {
      _switchChapter(_currentChapterIndex + 1);
    } else {
      _showReaderSnack('已是最后一章');
    }
  }

  /// 切换到指定章节并直接定位到该章最后一页（用于「上一页」跨章回溯）
  void _switchChapterToLastPage(int index) {
    _switchChapter(index, toLastPage: true);
  }

  /// 阅读区三区点击热层：左 1/3 上一页、中 1/3 呼出菜单、右 1/3 下一页
  ///
  /// 说明：热层位于正文（SelectableText）之上，且仅注册 onTap 手势，
  /// 因此可以稳定抢到单击事件，同时不干扰长按划词、拖动选择与滑动翻页手势。
  Widget _buildTapZones() {
    return Row(
      children: [
        Expanded(
          flex: 33,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _goToPreviousPage,
          ),
        ),
        Expanded(
          flex: 34,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleControls,
          ),
        ),
        Expanded(
          flex: 33,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _goToNextPage,
          ),
        ),
      ],
    );
  }

  // ==================== 章内进度（底部控制栏进度条） ====================

  /// 当前章节内的阅读进度（0.0 ~ 1.0）
  ///
  /// - 横向翻页模式：按「当前页码 / 本章总页数」计算；
  /// - 纵向长卷模式：按「滚动偏移 / 最大滚动距离」计算。
  double get _chapterProgress {
    if (_pageMode == PageTurnMode.horizontal) {
      if (_pageSlices.isEmpty) return 0.0;
      return ((_currentPageIndex + 1) / _pageSlices.length).clamp(0.0, 1.0);
    }

    if (!_scrollController.hasClients) return 0.0;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return 0.0;
    return (_scrollController.offset / maxExtent).clamp(0.0, 1.0);
  }

  /// 章内进度文案（横向显示页码，纵向显示百分比）
  String get _chapterProgressLabel {
    if (_pageMode == PageTurnMode.horizontal) {
      if (_pageSlices.isEmpty) return '--';
      return '本章 第 ${_currentPageIndex + 1} / ${_pageSlices.length} 页';
    }
    return '本章 ${(_chapterProgress * 100).round()}%';
  }

  /// 拖动章内进度条进行章内跳转
  void _seekChapterProgress(double ratio) {
    final safeRatio = ratio.clamp(0.0, 1.0);

    // 横向：按比例换算目标页码并直接跳转（无动画，保证拖动跟手）
    if (_pageMode == PageTurnMode.horizontal) {
      if (_pageSlices.isEmpty) return;
      final target = ((safeRatio * _pageSlices.length).ceil() - 1)
          .clamp(0, _pageSlices.length - 1);
      if (target == _currentPageIndex) return;
      setState(() => _currentPageIndex = target);
      _pageController?.jumpToPage(target);
      return;
    }

    // 纵向：按比例换算滚动距离
    if (!_scrollController.hasClients) return;
    final maxExtent = _scrollController.position.maxScrollExtent;
    if (maxExtent <= 0) return;
    _scrollController.jumpTo((safeRatio * maxExtent).clamp(0.0, maxExtent));
  }

  /// 智能清洗与规范化小说正文排版 (去除 HTML 标签、实体字符、自动补齐两格首行缩进)
  String _cleanNovelContent(String raw) {
    if (raw.isEmpty) return '';
    String text = raw
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&quot;', '"')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&amp;', '&');

    final lines = text.split('\n');
    final formattedLines = <String>[];
    for (final l in lines) {
      final trimmed = l.trim();
      if (trimmed.isEmpty) continue;
      // 自动补齐两格全角空格标准首行缩进
      if (!trimmed.startsWith('　　')) {
        formattedLines.add('　　$trimmed');
      } else {
        formattedLines.add(trimmed);
      }
    }
    return formattedLines.join('\n\n');
  }

  /// 读取用户阅读偏好
  Future<void> _loadUserPreferences() async {
    try {
      final savedFontSize = await AppStorage.getDouble('novel_font_size');
      final savedLineHeight = await AppStorage.getDouble('novel_line_height');
      final savedThemeName = await AppStorage.getString('novel_theme');
      final savedPageMode = await AppStorage.getString('novel_page_mode');

      if (savedFontSize != null && mounted) {
        setState(() => _fontSize = savedFontSize);
      }
      if (savedLineHeight != null && mounted) {
        setState(() => _lineHeight = savedLineHeight);
      }
      if (savedThemeName != null && mounted) {
        setState(() {
          _readerTheme = ReaderTheme.values.firstWhere(
            (e) => e.name == savedThemeName,
            orElse: () => ReaderTheme.parchment,
          );
        });
      }
      if (savedPageMode != null && mounted) {
        setState(() {
          _pageMode = savedPageMode == 'vertical' ? PageTurnMode.verticalScroll : PageTurnMode.horizontal;
        });
      }
    } catch (_) {}
  }

  /// 保存阅读偏好
  Future<void> _savePreference(String key, dynamic value) async {
    if (value is double) {
      await AppStorage.setDouble(key, value);
    } else if (value is String) {
      await AppStorage.setString(key, value);
    }
  }

  double _lastRenderWidth = 0;
  double _lastRenderHeight = 0;

  /// 使用 Flutter 原生 TextPainter 结合二分查找进行亚像素级精准文本分页
  /// 
  /// 每一页的高度严格适配可用物理空间，绝不超出屏幕发生垂直溢出，也不会浪费下半屏空间；
  /// 并在截断点附近智能寻找段落换行符，实现最自然的段落自然断句体验。
  List<String> _computeTextPages({
    required String text,
    required double maxWidth,
    required double maxHeight,
    required TextStyle textStyle,
  }) {
    if (text.isEmpty) return [''];
    if (maxWidth <= 0 || maxHeight <= 0) return [text];

    final List<String> pages = [];
    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    int start = 0;
    final totalLen = text.length;

    while (start < totalLen) {
      final remain = totalLen - start;
      if (remain <= 0) break;

      // 使用二分查找寻找当前物理视口高度下能容纳的最大字符长度
      int low = 1;
      int high = remain;
      int bestLen = 1;

      while (low <= high) {
        final mid = (low + high) ~/ 2;
        final candidate = text.substring(start, start + mid);
        textPainter.text = TextSpan(text: candidate, style: textStyle);
        textPainter.layout(maxWidth: maxWidth);

        if (textPainter.height <= maxHeight) {
          bestLen = mid;
          low = mid + 1; // 尝试容纳更多字符
        } else {
          high = mid - 1; // 高度超出当前视口，缩小字符区间
        }
      }

      int end = start + bestLen;

      // 智能段落自然吸附：若非全书末尾且在截断点前 35 字符内发现换行符，优先在此换行处自然断页
      if (end < totalLen) {
        final newlineIndex = text.lastIndexOf('\n', end);
        if (newlineIndex != -1 && newlineIndex > start && (end - newlineIndex) <= 35) {
          end = newlineIndex + 1;
        }
      }

      final pageText = text.substring(start, end);
      if (pageText.isNotEmpty) {
        pages.add(pageText);
      }
      start = end;
    }

    if (pages.isEmpty) pages.add(text);
    return pages;
  }

  /// 依据真实视口物理宽高与 TextPainter 精确计算当前章节分页
  void _recalculatePages({double? width, double? height}) {
    // 空章节保护：避免无章节时越界访问
    if (_chapters.isEmpty) {
      _pageSlices = [];
      _currentPageIndex = 0;
      return;
    }

    final currentContent = _chapters[_currentChapterIndex].content;
    if (currentContent.isEmpty) {
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

    final textStyle = TextStyle(
      fontSize: _fontSize,
      height: _lineHeight,
      letterSpacing: 0.5,
    );

    final slices = _computeTextPages(
      text: currentContent,
      maxWidth: targetWidth,
      maxHeight: targetHeight,
      textStyle: textStyle,
    );

    _pageSlices = slices;
    if (_openAtLastPage && _pageSlices.isNotEmpty) {
      _currentPageIndex = _pageSlices.length - 1;
      _openAtLastPage = false;
    } else {
      _currentPageIndex = _currentPageIndex.clamp(0, math.max(0, _pageSlices.length - 1));
    }
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

      // 纵向模式下以目标章重建连续阅读序列（避免残留旧章内容造成错位）
      if (_pageMode == PageTurnMode.verticalScroll) {
        _verticalSequence
          ..clear()
          ..add(index);
        _verticalBlockKeys
          ..clear()
          ..putIfAbsent(index, () => GlobalKey());
      }
    });

    // 通知上层同步阅读进度
    widget.onChapterChanged?.call(index, _chapters[index].title);

    // 触发异步加载目标章节
    _loadChapterContent(index);

    if (_pageMode == PageTurnMode.horizontal) {
      _syncPageController();
    } else if (_pageMode == PageTurnMode.verticalScroll && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// 准确定位 PageController 到当前真实切片页（包含上一章桥接页偏移）
  void _syncPageController() {
    final targetRaw = _prevBridgeCount + (_pageSlices.isNotEmpty ? _currentPageIndex.clamp(0, _pageSlices.length - 1) : 0);
    final controller = _pageController;
    if (controller != null && controller.hasClients) {
      controller.jumpToPage(targetRaw);
    } else {
      _pageController?.dispose();
      _pageController = PageController(initialPage: targetRaw);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 空章节保护：未传入任何可读章节时展示空态，杜绝越界与伪造正文
    if (_chapters.isEmpty) {
      return _buildEmptyScaffold();
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
              child: _buildReaderBody(chapter),
            ),

            // 2. 阅读区三区点击热层 (左 1/3 上一页 / 中 1/3 呼出菜单 / 右 1/3 下一页)
            Positioned.fill(child: _buildTapZones()),

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

  /// 无章节空态（严禁再注入示例假章节，避免用户误认为真实正文）
  Widget _buildEmptyScaffold() {
    return Scaffold(
      backgroundColor: _readerTheme.bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Ionicons.bookOutline, size: 42, color: _readerTheme.subText),
                const SizedBox(height: 16),
                Text(
                  '暂无章节内容',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: _readerTheme.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '该作品尚未解析出章节目录，请返回详情页刷新后重试',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, height: 1.5, color: _readerTheme.subText),
                ),
                const SizedBox(height: 22),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary, width: 0.8),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Ionicons.arrowBackOutline, size: 15),
                  label: const Text('返回详情页'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 构建阅读器主体（状态分流：加载中 / 加载失败 / 正文排版）
  Widget _buildReaderBody(NovelChapter chapter) {
    // 状态 A：正文加载中且无可用内容
    if (_isLoadingContent && chapter.content.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            Text(
              '正在抓取并排版章节正文...',
              style: TextStyle(fontSize: 13, color: _readerTheme.subText),
            ),
          ],
        ),
      );
    }

    // 状态 B：正文加载失败且无可用内容
    if (_contentError != null && chapter.content.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Ionicons.alertCircleOutline, size: 36, color: _readerTheme.subText),
              const SizedBox(height: 12),
              Text(
                '章节正文抓取失败',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: _readerTheme.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _contentError!,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: _readerTheme.subText),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () => _loadChapterContent(_currentChapterIndex, forceReload: true),
                icon: const Icon(Ionicons.refreshOutline, size: 14),
                label: const Text('重试加载'),
              ),
            ],
          ),
        ),
      );
    }

    // 状态 C：正文就绪，根据模式渲染平滑横翻或长篇纵滚
    return _pageMode == PageTurnMode.horizontal
        ? _buildHorizontalPageView(chapter)
        : _buildVerticalScrollView();
  }

  /// 横向平滑翻页视口
  Widget _buildHorizontalPageView(NovelChapter chapter) {
    return Column(
      children: [
        // 顶部小标题栏 (章节名与书名)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  chapter.title,
                  style: TextStyle(fontSize: 11, color: _readerTheme.subText),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                widget.bookTitle,
                style: TextStyle(fontSize: 11, color: _readerTheme.subText),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        // 翻页主体 (采用 LayoutBuilder 动态感知真实物理视口，驱动 TextPainter 亚像素级精确分页)
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final renderWidth = (constraints.maxWidth - 40).clamp(100.0, 4000.0);
              final renderHeight = (constraints.maxHeight - 16).clamp(100.0, 4000.0);

              // 当物理视口尺寸发生变化（如初次渲染或横竖屏旋转）或尚未分页时，触发亚像素级精准重算
              if ((_lastRenderWidth - renderWidth).abs() > 1.0 ||
                  (_lastRenderHeight - renderHeight).abs() > 1.0 ||
                  _pageSlices.isEmpty ||
                  (_pageSlices.length == 1 && _pageSlices.first == chapter.content && chapter.content.length > 300)) {
                _recalculatePages(width: renderWidth, height: renderHeight);
              }

              // 空正文保护：正文为空或尚未切片时展示轻量占位，避免 PageView 越界
              if (_pageSlices.isEmpty) {
                return Center(
                  child: Text(
                    '正文排版中...',
                    style: TextStyle(fontSize: 12, color: _readerTheme.subText),
                  ),
                );
              }

              final prevCount = _prevBridgeCount;
              final totalCount = _totalPageCount;

              return PageView.builder(
                key: ValueKey('novel_pageview_${_currentChapterIndex}_$totalCount'),
                controller: _pageController,
                itemCount: totalCount,
                onPageChanged: (idx) {
                  // 滑入章首衔接页：自动回退上一章最后一页
                  if (_hasPrevChapter && idx == 0) {
                    _autoAdvanceToPreviousChapter();
                    return;
                  }
                  // 滑入章末衔接页：自动续读下一章第一页
                  if (_hasNextChapter && idx >= prevCount + _pageSlices.length) {
                    _autoAdvanceToNextChapter();
                    return;
                  }
                  // 正常切片正文页
                  final sliceIdx = idx - prevCount;
                  setState(() {
                    _currentPageIndex = sliceIdx.clamp(0, math.max(0, _pageSlices.length - 1));
                  });
                  // 翻到两端附近时提前双向预取
                  if (sliceIdx <= 1 || sliceIdx >= _pageSlices.length - 2) {
                    _maybePrefetchAdjacent();
                  }
                },
                itemBuilder: (context, index) {
                  // 1. 章首上一章衔接页
                  if (_hasPrevChapter && index == 0) {
                    return _buildPreviousChapterBridge();
                  }
                  // 2. 章末下一章衔接页
                  if (_hasNextChapter && index >= prevCount + _pageSlices.length) {
                    return _buildNextChapterBridge();
                  }
                  // 3. 正文内容页
                  final sliceIdx = index - prevCount;
                  if (sliceIdx < 0 || sliceIdx >= _pageSlices.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    // 单击手势统一由上层的三区点击热层接管（保留长按划词与拖动选择）
                    child: SelectableText(
                      _pageSlices[sliceIdx],
                      // 翻页模式下严格禁用垂直方向滚动物理特性，杜绝上下滑动导致翻页手势冲突
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: _lineHeight,
                        color: _readerTheme.text,
                        letterSpacing: 0.5,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),

        // 底部页码指示器
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '第 ${_currentChapterIndex + 1} / ${_chapters.length} 章',
                style: TextStyle(fontSize: 11, color: _readerTheme.subText),
              ),
              Row(
                children: [
                  // 全书最后一页给出明确收尾提示，避免用户反复滑动却无反馈
                  if (_currentChapterIndex >= _chapters.length - 1 &&
                      _pageSlices.isNotEmpty &&
                      _currentPageIndex >= _pageSlices.length - 1)
                    Text(
                      '已是最后一章 · ',
                      style: TextStyle(fontSize: 11, color: _readerTheme.subText),
                    ),
                  if (_currentChapterIndex == 0 &&
                      _pageSlices.isNotEmpty &&
                      _currentPageIndex == 0)
                    Text(
                      '全书起始 · ',
                      style: TextStyle(fontSize: 11, color: _readerTheme.subText),
                    ),
                  Text(
                    _pageSlices.isNotEmpty ? '${_currentPageIndex + 1} / ${_pageSlices.length}' : '',
                    style: TextStyle(fontSize: 11, color: _readerTheme.subText),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 章首衔接页（横向模式在第一页向右滑动展示，随后自动回退到上一章最后一页）
  Widget _buildPreviousChapterBridge() {
    final prevIndex = _currentChapterIndex - 1;
    final prevTitle = prevIndex >= 0 ? _chapters[prevIndex].title : '';
    final isReady = prevIndex >= 0 &&
        (_contentCache.containsKey(prevIndex) || _prefetching.contains(prevIndex));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            '正在返回上一章',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _readerTheme.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            prevTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _readerTheme.subText),
          ),
          const SizedBox(height: 10),
          Text(
            isReady ? '正文已就绪，即将无缝切换' : '正在加载正文...',
            style: TextStyle(fontSize: 11, color: _readerTheme.subText),
          ),
        ],
      ),
    );
  }

  /// 章末衔接页（横向模式滑到本章最后一页之后展示，随后自动续读下一章）
  Widget _buildNextChapterBridge() {
    final nextIndex = _currentChapterIndex + 1;
    final nextTitle = nextIndex < _chapters.length ? _chapters[nextIndex].title : '';
    final isReady =
        _contentCache.containsKey(nextIndex) || _prefetching.contains(nextIndex);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.primary),
          ),
          const SizedBox(height: 18),
          Text(
            '正在进入下一章',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: _readerTheme.text,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            nextTitle,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _readerTheme.subText),
          ),
          const SizedBox(height: 10),
          Text(
            isReady ? '正文已就绪，即将无缝续读' : '正在预取正文...',
            style: TextStyle(fontSize: 11, color: _readerTheme.subText),
          ),
        ],
      ),
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

    final bool hasMore = _verticalSequence.last < _chapters.length - 1 &&
        !_verticalFailed.contains(_verticalSequence.last + 1);

    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      itemCount: _verticalSequence.length + (hasMore ? 1 : 0),
      itemBuilder: (context, i) {
        // 末尾续载状态占位
        if (i >= _verticalSequence.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 30),
            child: Center(
              child: Text(
                '正在续载下一章...',
                style: TextStyle(fontSize: 12, color: _readerTheme.subText),
              ),
            ),
          );
        }

        final chIndex = _verticalSequence[i];
        final ch = _chapters[chIndex];
        final content = _contentCache[chIndex] ?? ch.content;

        return Column(
          key: _verticalBlockKeys.putIfAbsent(chIndex, () => GlobalKey()),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 章节分隔与标题
            if (i > 0) ...[
              const SizedBox(height: 20),
              Divider(color: _readerTheme.subText.withValues(alpha: 0.18)),
              const SizedBox(height: 18),
            ],
            Center(
              child: Text(
                ch.title,
                style: TextStyle(
                  fontSize: _fontSize + 4,
                  fontWeight: FontWeight.bold,
                  color: _readerTheme.text,
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 单击手势统一由上层的三区点击热层接管（保留长按划词与拖动选择）
            SelectableText(
              content.isEmpty ? '正文加载中...' : content,
              style: TextStyle(
                fontSize: _fontSize,
                height: _lineHeight,
                color: _readerTheme.text,
                letterSpacing: 0.5,
              ),
            ),
            // 全书末尾提示
            if (i == _verticalSequence.length - 1 && !hasMore) ...[
              const SizedBox(height: 36),
              Center(
                child: Text(
                  '— 已是最后一章 —',
                  style: TextStyle(fontSize: 12, color: _readerTheme.subText),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// 顶部控制栏 (支持一键复制整章、重新加载、查看目录)
  Widget _buildTopBar(NovelChapter chapter) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        // 由不透明色块升级为纵向渐变遮罩，控制栏与正文过渡更自然
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _readerTheme.bg,
              _readerTheme.bg.withValues(alpha: 0.92),
              _readerTheme.bg.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.72, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 14),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded, color: _readerTheme.text, size: 20),
              onPressed: () => Navigator.maybePop(context),
            ),
            Expanded(
              child: Text(
                widget.bookTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: _readerTheme.text,
                ),
              ),
            ),

            // 重新刷新加载章节
            IconButton(
              icon: Icon(Ionicons.refreshOutline, color: _readerTheme.text, size: 18),
              tooltip: '刷新章节',
              onPressed: () => _loadChapterContent(_currentChapterIndex, forceReload: true),
            ),

            // 章节目录抽屉
            IconButton(
              icon: Icon(Ionicons.reorderFourOutline, color: _readerTheme.text, size: 20),
              tooltip: '章节目录',
              onPressed: _showCatalogDrawer,
            ),
          ],
        ),
      ),
    );
  }

  /// 底部控制面板
  Widget _buildBottomControls(NovelChapter chapter) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        // 由不透明色块升级为纵向渐变遮罩，避免底部生硬切断正文
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              _readerTheme.bg,
              _readerTheme.bg.withValues(alpha: 0.94),
              _readerTheme.bg.withValues(alpha: 0.0),
            ],
            stops: const [0.0, 0.74, 1.0],
          ),
        ),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 进度控制行
            Row(
              children: [
                IconButton(
                  icon: Icon(Ionicons.chevronBackOutline, color: _readerTheme.text),
                  onPressed: _currentChapterIndex > 0 ? () => _switchChapter(_currentChapterIndex - 1) : null,
                ),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: _readerTheme.subText.withValues(alpha: 0.3),
                      thumbColor: AppColors.primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    // 进度条语义为「当前章节内的阅读进度」（横向=页码比例，纵向=滚动比例）
                    child: Slider(
                      value: _chapterProgress,
                      onChanged: _seekChapterProgress,
                    ),
                  ),
                ),
                IconButton(
                  icon: Icon(Ionicons.chevronForwardOutline, color: _readerTheme.text),
                  onPressed: _currentChapterIndex < _chapters.length - 1
                      ? () => _switchChapter(_currentChapterIndex + 1)
                      : null,
                ),
              ],
            ),

            // 章内进度文案（横向：页码 / 纵向：百分比）
            Center(
              child: Text(
                _chapterProgressLabel,
                style: TextStyle(fontSize: 11, color: _readerTheme.subText),
              ),
            ),

            const SizedBox(height: 4),

            // 功能操作按钮行
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildActionButton(
                  icon: Ionicons.bookOutline,
                  label: '目录',
                  onTap: _showCatalogDrawer,
                ),
                // 缓存状态与手动预取（复制整章入口已统一收敛至顶栏，避免重复）
                _buildActionButton(
                  icon: Ionicons.downloadOutline,
                  label: '已缓存 $_cachedChapterCount 章',
                  onTap: _prefetchNextManually,
                ),
                _buildActionButton(
                  icon: _pageMode == PageTurnMode.horizontal
                      ? Ionicons.tabletPortraitOutline
                      : Ionicons.menuOutline,
                  label: _pageMode.label,
                  onTap: _togglePageMode,
                ),
                _buildActionButton(
                  icon: Ionicons.optionsOutline,
                  label: '排版',
                  onTap: () {
                    setState(() {
                      _showSettingsPanel = !_showSettingsPanel;
                    });
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: _readerTheme.text),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 11, color: _readerTheme.text),
            ),
          ],
        ),
      ),
    );
  }

  /// 排版设置扩展抽屉 (底色、字号、行距)
  Widget _buildSettingsDrawer() {
    return Positioned(
      bottom: 96,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: _readerTheme.bg,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: _readerTheme.subText.withValues(alpha: 0.2)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 护眼底色选择器
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: ReaderTheme.values.map((th) {
                final isSelected = th == _readerTheme;
                return GestureDetector(
                  onTap: () {
                    setState(() => _readerTheme = th);
                    _savePreference('novel_theme', th.name);
                  },
                  child: Container(
                    width: 68,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: th.bg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : Colors.black12,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        th.name,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: th.text,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 16),

            // 翻页模式选择（与底栏快捷切换共享同一套位置保持逻辑）
            Row(
              children: [
                Text('翻页', style: TextStyle(fontSize: 13, color: _readerTheme.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: PageTurnMode.values.map((mode) {
                      final isSelected = mode == _pageMode;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(mode.label, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          selectedColor: AppColors.primary,
                          backgroundColor: _readerTheme.bg,
                          labelStyle: TextStyle(
                            color: isSelected ? Colors.white : _readerTheme.text,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSelected
                                ? AppColors.primary
                                : _readerTheme.subText.withValues(alpha: 0.35),
                          ),
                          onSelected: (val) {
                            if (val && !isSelected) _togglePageMode();
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 字号调节
            Row(
              children: [
                Text('字号', style: TextStyle(fontSize: 13, color: _readerTheme.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: Row(
                    children: [
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(40, 32),
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: _readerTheme.subText.withValues(alpha: 0.4)),
                        ),
                        onPressed: () {
                          if (_fontSize <= 12) return;
                          _applyTypographyChange(() => _fontSize -= 1);
                          _savePreference('novel_font_size', _fontSize);
                        },
                        child: Text('A-', style: TextStyle(color: _readerTheme.text)),
                      ),
                      Expanded(
                        child: Center(
                          child: Text(
                            '${_fontSize.round()} px',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: _readerTheme.text,
                            ),
                          ),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(40, 32),
                          padding: EdgeInsets.zero,
                          side: BorderSide(color: _readerTheme.subText.withValues(alpha: 0.4)),
                        ),
                        onPressed: () {
                          if (_fontSize >= 32) return;
                          _applyTypographyChange(() => _fontSize += 1);
                          _savePreference('novel_font_size', _fontSize);
                        },
                        child: Text('A+', style: TextStyle(color: _readerTheme.text)),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 行高间距
            Row(
              children: [
                Text('行距', style: TextStyle(fontSize: 13, color: _readerTheme.text)),
                const SizedBox(width: 16),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 3,
                      activeTrackColor: AppColors.primary,
                      inactiveTrackColor: _readerTheme.subText.withValues(alpha: 0.2),
                      thumbColor: AppColors.primary,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      value: _lineHeight,
                      min: 1.2,
                      max: 2.2,
                      divisions: 5,
                      // 拖动前锚定阅读位置，松手后统一还原，避免连续拖动时页面抖动
                      onChangeStart: (_) => _typographyAnchorOffset = _currentCharOffset,
                      onChanged: (val) {
                        setState(() {
                          _lineHeight = val;
                          _recalculatePages();
                        });
                        _savePreference('novel_line_height', val);
                      },
                      onChangeEnd: (_) {
                        if (_typographyAnchorOffset >= 0) {
                          _restoreReadingPosition(_typographyAnchorOffset);
                          _typographyAnchorOffset = -1;
                        }
                      },
                    ),
                  ),
                ),
                Text(
                  '${_lineHeight.toStringAsFixed(1)}x',
                  style: TextStyle(fontSize: 12, color: _readerTheme.text),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 打开章节目录（左侧抽屉）
  ///
  /// 每次打开前重建滚动控制器并预置偏移量，使目录一打开就自动定位到当前正在阅读的章节。
  void _showCatalogDrawer() {
    HapticFeedback.lightImpact();

    // 预置偏移：当前章上方保留 2 行上下文，定位更自然
    final double targetOffset =
        ((_currentChapterIndex - 2).clamp(0, _chapters.length)) * _catalogItemHeight;
    _catalogScrollController?.dispose();
    _catalogScrollController = ScrollController(initialScrollOffset: targetOffset);
    setState(() {});

    _scaffoldKey.currentState?.openDrawer();
  }

  /// 章节目录（左侧抽屉面板）
  Widget _buildCatalogDrawer() {
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.76,
      backgroundColor: _readerTheme.bg,
      child: SafeArea(
        child: Column(
          children: [
            // 顶部信息栏（书名 + 章节总数 + 缓存进度）
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.bookTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: _readerTheme.text,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 ${_chapters.length} 章 · 已缓存 $_cachedChapterCount 章',
                          style: TextStyle(fontSize: 11, color: _readerTheme.subText),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Ionicons.closeOutline, color: _readerTheme.subText, size: 20),
                    tooltip: '关闭目录',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _readerTheme.subText.withValues(alpha: 0.18)),

            // 章节列表（固定行高，便于用 initialScrollOffset 精确定位到当前章）
            Expanded(
              child: ListView.builder(
                controller: _catalogScrollController,
                itemExtent: _catalogItemHeight,
                itemCount: _chapters.length,
                itemBuilder: (context, index) => _buildCatalogItem(index),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 目录单项：章节名 + 缓存状态图标（已缓存 / 预取中 / 未缓存可一键缓存）
  Widget _buildCatalogItem(int index) {
    final isCurrent = index == _currentChapterIndex;
    final isCached = (_contentCache[index] ?? '').isNotEmpty;
    final isPrefetching = _prefetching.contains(index);

    final Widget statusIcon;
    if (isPrefetching) {
      statusIcon = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
      );
    } else if (isCached) {
      statusIcon = Icon(
        Ionicons.checkmarkCircle,
        size: 17,
        color: AppColors.primary.withValues(alpha: 0.85),
      );
    } else {
      // 未缓存章节：提供一键缓存入口
      statusIcon = InkWell(
        onTap: () => _downloadChapterFromCatalog(index),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Icon(
            Ionicons.cloudDownloadOutline,
            size: 17,
            color: _readerTheme.subText.withValues(alpha: 0.7),
          ),
        ),
      );
    }

    return InkWell(
      onTap: () {
        Navigator.pop(context);
        _switchChapter(index);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: isCurrent ? AppColors.primary.withValues(alpha: 0.10) : null,
        child: Row(
          children: [
            // 当前章左侧高亮竖条
            Container(
              width: 3,
              height: 18,
              decoration: BoxDecoration(
                color: isCurrent ? AppColors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _chapters[index].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                  color: isCurrent ? AppColors.primary : _readerTheme.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            statusIcon,
          ],
        ),
      ),
    );
  }

  /// 从目录一键缓存（下载）指定章节
  Future<void> _downloadChapterFromCatalog(int index) async {
    HapticFeedback.lightImpact();
    if ((_contentCache[index] ?? '').isNotEmpty) return;

    await _prefetchChapter(index);
    if (!mounted) return;

    final success = (_contentCache[index] ?? '').isNotEmpty;
    if (success) {
      // 该章此前若在纵向续载中失败过，缓存成功后解除熔断标记
      _verticalFailed.remove(index);
      setState(() {});
    }
    _showReaderSnack(
      success
          ? '《${_chapters[index].title}》已缓存，可离线续读'
          : '《${_chapters[index].title}》缓存失败，请检查网络或解析规则',
    );
  }
}
