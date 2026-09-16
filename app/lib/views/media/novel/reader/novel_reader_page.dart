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
/// 一键整章复制与 SelectableText 长按划词自由选区复制、上下连续长篇滚动、
/// 四大经典护眼底色、字号行距无级微调及目录抽屉快速切章
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

  // 默认演示文本 (若外部未传递章节时提供优质示例)
  static const String _sampleChapterContent = '''
　　第一章 科学边界
　　恋恋不舍地告别了那片璀璨的星云，飞船缓缓启动了跃迁引擎。在宇宙宏大而冰冷的尺度面前，一切文明的辉煌与挣扎都显得如此渺小而静谧。

　　汪淼觉得，纳米材料不过是浩瀚自然规律偶然向人类眨了下眼睛。而今夜，整个天空仿佛变成了一面巨大的幕布，那些原本永恒闪烁的恒星，在以某种不可名状的节律微微脉动着。

　　“整个宇宙，将为你闪烁。”
　　申玉菲的声音平静而漠然，宛如从虚无深处传来的低语。汪淼站在射电天文基地的观测台上，寒风刺骨，他抬头望去，夜空如常。但戴上滤镜的那一刻，不可思议的奇迹发生了——那并非视觉的波动，而是宇宙背景辐射在以莫尔斯电码的频率，向整个地球文明敲击着倒计时。

　　那是宏伟的诗篇，也是残酷的丧钟。
　　在这浩瀚苍穹之下，两个不同文明的命运齿轮，就此轰然交错。
''';

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _setupChapters();
    _loadUserPreferences();
    _pageController = PageController(initialPage: _currentPageIndex);
    _recalculatePages();

    // 初始进入立即按需调度沙箱加载章节内容
    _loadChapterContent(_currentChapterIndex);

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
    super.dispose();
  }

  /// 准备章节数据并初始化缓存
  void _setupChapters() {
    if (widget.chapters.isNotEmpty) {
      _chapters = List<NovelChapter>.from(widget.chapters);
    } else {
      _chapters = [
        const NovelChapter(title: '第一章 科学边界', content: _sampleChapterContent),
        const NovelChapter(
          title: '第二章 台球与物理规律',
          content: '　　丁仪领着汪淼穿过昏暗的实验室，中央摆放着一台巨大的超高能粒子对撞机模型...\n\n　　“物理学从来没有真正存在过，汪淼，我们只是在黑暗的密室里摸索规律的盲人。”',
        ),
      ];
    }

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

    // 1. 如果已有本地缓存且非强制刷新，直接挂载并重新切片
    if (!forceReload && _contentCache.containsKey(index) && _contentCache[index]!.isNotEmpty) {
      final cached = _contentCache[index]!;
      setState(() {
        _chapters[index] = _chapters[index].copyWith(content: cached);
        _isLoadingContent = false;
        _contentError = null;
        _recalculatePages();
      });
      return;
    }

    final currentCh = _chapters[index];
    final chapterUrl = currentCh.url?.trim() ?? '';

    // 若无目标 URL 且已有正文，直接使用
    if (chapterUrl.isEmpty) {
      if (currentCh.content.isNotEmpty) {
        _contentCache[index] = currentCh.content;
        _recalculatePages();
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
        });
      }
    } catch (e) {
      if (mounted && _currentChapterIndex == index) {
        setState(() {
          _isLoadingContent = false;
          _contentError = '正文加载失败: $e';
        });
      }
    }
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

  /// 复制当前章节完整正文至系统剪贴板
  void _copyCurrentChapter() {
    final chapter = _chapters[_currentChapterIndex];
    if (chapter.content.isEmpty || _isLoadingContent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('当前章节正文尚未就绪，暂无法复制'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    final fullText = '${chapter.title}\n\n${chapter.content}';
    Clipboard.setData(ClipboardData(text: fullText));
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制《${chapter.title}》全篇正文到剪贴板'),
        duration: const Duration(seconds: 2),
      ),
    );
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
    _currentPageIndex = _currentPageIndex.clamp(0, _pageSlices.length - 1);
  }

  /// 切换章节
  void _switchChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _currentChapterIndex = index;
      _currentPageIndex = 0;
      _recalculatePages();
    });

    // 通知上层同步阅读进度
    widget.onChapterChanged?.call(index, _chapters[index].title);

    // 触发异步加载目标章节
    _loadChapterContent(index);

    if (_pageMode == PageTurnMode.horizontal && _pageController != null) {
      _pageController!.jumpToPage(0);
    } else if (_pageMode == PageTurnMode.verticalScroll && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chapter = _chapters[_currentChapterIndex];

    return Scaffold(
      backgroundColor: _readerTheme.bg,
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

            // 2. 顶部微拟态控制栏 (返回、书名、复制、刷新、目录)
            if (_showControls) _buildTopBar(chapter),

            // 3. 底部微拟态控制面板 (上一章、下一章、目录、排版设置、进度条)
            if (_showControls) _buildBottomControls(chapter),

            // 4. 排版设置扩展抽屉 (字号、行距、护眼底色、翻页模式)
            if (_showSettingsPanel) _buildSettingsDrawer(),
          ],
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
        : _buildVerticalScrollView(chapter);
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

              return PageView.builder(
                controller: _pageController,
                itemCount: _pageSlices.length,
                onPageChanged: (idx) {
                  setState(() {
                    _currentPageIndex = idx;
                  });
                },
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    child: SelectableText(
                      _pageSlices[index],
                      // 翻页模式下严格禁用垂直方向滚动物理特性，杜绝上下滑动导致翻页手势冲突
                      scrollPhysics: const NeverScrollableScrollPhysics(),
                      style: TextStyle(
                        fontSize: _fontSize,
                        height: _lineHeight,
                        color: _readerTheme.text,
                        letterSpacing: 0.5,
                      ),
                      onTap: _toggleControls,
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
              Text(
                _pageSlices.isNotEmpty ? '${_currentPageIndex + 1} / ${_pageSlices.length}' : '',
                style: TextStyle(fontSize: 11, color: _readerTheme.subText),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 上下连续无缝长篇滚动视口
  Widget _buildVerticalScrollView(NovelChapter chapter) {
    return ListView(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      children: [
        Center(
          child: Text(
            chapter.title,
            style: TextStyle(
              fontSize: _fontSize + 4,
              fontWeight: FontWeight.bold,
              color: _readerTheme.text,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          chapter.content,
          style: TextStyle(
            fontSize: _fontSize,
            height: _lineHeight,
            color: _readerTheme.text,
            letterSpacing: 0.5,
          ),
          onTap: _toggleControls,
        ),
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton(
              onPressed: _currentChapterIndex > 0 ? () => _switchChapter(_currentChapterIndex - 1) : null,
              child: Text('上一章', style: TextStyle(color: _readerTheme.subText)),
            ),
            Text(
              '第 ${_currentChapterIndex + 1} / ${_chapters.length} 章',
              style: TextStyle(color: _readerTheme.subText, fontSize: 12),
            ),
            TextButton(
              onPressed: _currentChapterIndex < _chapters.length - 1
                  ? () => _switchChapter(_currentChapterIndex + 1)
                  : null,
              child: const Text('下一章', style: TextStyle(color: AppColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  /// 顶部控制栏 (支持一键复制整章、重新加载、查看目录)
  Widget _buildTopBar(NovelChapter chapter) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        color: _readerTheme.bg.withValues(alpha: 0.95),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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

            // 一键复制本章全部内容
            IconButton(
              icon: Icon(Ionicons.copyOutline, color: _readerTheme.text, size: 19),
              tooltip: '复制本章正文',
              onPressed: _copyCurrentChapter,
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
        color: _readerTheme.bg.withValues(alpha: 0.96),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                    child: Slider(
                      value: _chapters.isNotEmpty
                          ? (_currentChapterIndex / (_chapters.length - 1).clamp(1, 9999))
                          : 0.0,
                      onChanged: (val) {
                        final target = (val * (_chapters.length - 1)).round();
                        if (target != _currentChapterIndex) {
                          _switchChapter(target);
                        }
                      },
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
                _buildActionButton(
                  icon: Ionicons.copyOutline,
                  label: '复制本章',
                  onTap: _copyCurrentChapter,
                ),
                _buildActionButton(
                  icon: _pageMode == PageTurnMode.horizontal ? Ionicons.tabletPortraitOutline : Ionicons.menuOutline,
                  label: _pageMode.label,
                  onTap: () {
                    setState(() {
                      _pageMode = _pageMode == PageTurnMode.horizontal
                          ? PageTurnMode.verticalScroll
                          : PageTurnMode.horizontal;
                    });
                    _savePreference('novel_page_mode', _pageMode == PageTurnMode.verticalScroll ? 'vertical' : 'horizontal');
                  },
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
    required dynamic icon,
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
            icon is IconData ? Icon(icon, size: 20, color: _readerTheme.text) : Icon(icon as IconData, size: 20, color: _readerTheme.text),
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
                          if (_fontSize > 12) {
                            setState(() {
                              _fontSize -= 1;
                              _recalculatePages();
                            });
                            _savePreference('novel_font_size', _fontSize);
                          }
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
                          if (_fontSize < 32) {
                            setState(() {
                              _fontSize += 1;
                              _recalculatePages();
                            });
                            _savePreference('novel_font_size', _fontSize);
                          }
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
                      onChanged: (val) {
                        setState(() {
                          _lineHeight = val;
                          _recalculatePages();
                        });
                        _savePreference('novel_line_height', val);
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

  /// 章节目录抽屉
  void _showCatalogDrawer() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _readerTheme.bg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '目录 (共 ${_chapters.length} 章)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _readerTheme.text,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: _readerTheme.subText, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _chapters.length,
                  itemBuilder: (context, index) {
                    final isCurrent = index == _currentChapterIndex;
                    return ListTile(
                      title: Text(
                        _chapters[index].title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? AppColors.primary : _readerTheme.text,
                        ),
                      ),
                      trailing: isCurrent
                          ? const Icon(Ionicons.checkmarkOutline, color: AppColors.primary, size: 16)
                          : null,
                      onTap: () {
                        Navigator.pop(ctx);
                        _switchChapter(index);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
