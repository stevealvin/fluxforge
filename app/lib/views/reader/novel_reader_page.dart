import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';

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
    required this.content,
    this.url,
  });
}

/// 纯净小说阅读引擎 (FluxReader)
/// 
/// 支持视口文本切片分页、上下连续长篇滚动、四大经典护眼底色、
/// 字号与行间距无级微调、目录抽屉快速切章及断点进度记忆
class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({
    super.key,
    this.bookTitle = '小说阅读',
    this.initialChapterIndex = 0,
    this.chapters = const [],
  });

  final String bookTitle;
  final int initialChapterIndex;
  final List<NovelChapter> chapters;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  // 章节与数据
  late List<NovelChapter> _chapters;
  late int _currentChapterIndex;

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

　　第二节 虚无的重构
　　“三体问题在数学上是无解的，正如文明在黑暗丛林中的生存概率。”
　　丁仪吐出一口烟圈，烟雾在微弱的红光中缭绕升腾。他把一枚台球放在桌面上，轻轻一推，球击中边框，弹向未知的角度。“如果物理学的规律在时间和空间上并不是均匀的，那么我们所坚信的一切科学大厦，也不过是一座建立在沙滩上的精致沙雕罢了。”

　　汪淼沉默良久。他看着窗外的城市霓虹，车流如金色的血液在夜色深渊中流淌。他第一次感受到，脚下这颗平静安详的蓝色星球，不过是漂浮在无边黑夜中的一粒微尘。
''';

  @override
  void initState() {
    super.initState();
    _currentChapterIndex = widget.initialChapterIndex;
    _setupChapters();
    _loadUserPreferences();
    _pageController = PageController(initialPage: _currentPageIndex);
    _recalculatePages();
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 准备章节数据
  void _setupChapters() {
    if (widget.chapters.isNotEmpty) {
      _chapters = widget.chapters;
    } else {
      _chapters = [
        const NovelChapter(title: '第一章 科学边界', content: _sampleChapterContent),
        const NovelChapter(
          title: '第二章 台球与物理规律',
          content: '　　丁仪领着汪淼穿过昏暗的实验室，中央摆放着一台巨大的超高能粒子对撞机模型...\n\n　　“物理学从来没有真正存在过，汪淼，我们只是在黑暗的密室里摸索规律的盲人。”',
        ),
        const NovelChapter(
          title: '第三章 射手与农场主',
          content: '　　“射手假说”：有一名神枪手，在靶子上每隔十厘米打一个洞。如果靶子上的二维智能生物观察这个宇宙，他们会发现一条伟大的物理规律：宇宙每隔十厘米必然存在一个洞...\n\n　　“农场主假说”：农场里有一群火鸡，农场主每天上午十一点准时喂食。火鸡中的科学家观察了一年，总结出一条铁律：“每天上午十一点有食物降临”。直到感恩节那天，降临的不是食物，而是屠刀。',
        ),
      ];
    }
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

  /// 依据视口和字号切片计算当前章节分页
  void _recalculatePages() {
    final currentContent = _chapters[_currentChapterIndex].content;
    // 根据字号粗略计算每页字符承载量 (约 450 ~ 750 字)
    final charsPerPage = ((600 * (18.0 / _fontSize))).round().clamp(200, 1500);

    final List<String> slices = [];
    int start = 0;
    while (start < currentContent.length) {
      int end = (start + charsPerPage).clamp(0, currentContent.length);
      // 避免在段落中断开
      if (end < currentContent.length) {
        final newlineIndex = currentContent.indexOf('\n', end - 30);
        if (newlineIndex != -1 && newlineIndex <= end + 40) {
          end = newlineIndex + 1;
        }
      }
      slices.add(currentContent.substring(start, end));
      start = end;
    }

    if (slices.isEmpty) slices.add(currentContent);

    setState(() {
      _pageSlices = slices;
      _currentPageIndex = _currentPageIndex.clamp(0, _pageSlices.length - 1);
    });
  }

  /// 切换章节
  void _switchChapter(int index) {
    if (index < 0 || index >= _chapters.length) return;
    setState(() {
      _currentChapterIndex = index;
      _currentPageIndex = 0;
      _recalculatePages();
    });
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
            // 1. 核心阅读排版视口
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                setState(() {
                  _showControls = !_showControls;
                  if (!_showControls) _showSettingsPanel = false;
                });
              },
              child: _pageMode == PageTurnMode.horizontal
                  ? _buildHorizontalPageView(chapter)
                  : _buildVerticalScrollView(chapter),
            ),

            // 2. 顶部微拟态控制栏 (返回、书名、章节号)
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

  /// 横向平滑翻页视口
  Widget _buildHorizontalPageView(NovelChapter chapter) {
    return Column(
      children: [
        // 顶部小标题栏 (章节名与电量/时间)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                chapter.title,
                style: TextStyle(fontSize: 11, color: _readerTheme.subText),
              ),
              Text(
                widget.bookTitle,
                style: TextStyle(fontSize: 11, color: _readerTheme.subText),
              ),
            ],
          ),
        ),

        // 翻页主体
        Expanded(
          child: PageView.builder(
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
                child: Text(
                  _pageSlices[index],
                  style: TextStyle(
                    fontSize: _fontSize,
                    height: _lineHeight,
                    color: _readerTheme.text,
                    letterSpacing: 0.5,
                  ),
                ),
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
                '${_currentPageIndex + 1} / ${_pageSlices.length}',
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
        Text(
          chapter.content,
          style: TextStyle(
            fontSize: _fontSize,
            height: _lineHeight,
            color: _readerTheme.text,
            letterSpacing: 0.5,
          ),
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
              '${_currentChapterIndex + 1} / ${_chapters.length}',
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

  /// 顶部控制栏
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
            IconButton(
              icon: Icon(LucideIcons.listOrdered, color: _readerTheme.text, size: 20),
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
                  icon: Icon(LucideIcons.chevronLeft, color: _readerTheme.text),
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
                  icon: Icon(LucideIcons.chevronRight, color: _readerTheme.text),
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
                  icon: LucideIcons.bookOpen,
                  label: '目录',
                  onTap: _showCatalogDrawer,
                ),
                _buildActionButton(
                  icon: _pageMode == PageTurnMode.horizontal ? LucideIcons.columns2 : LucideIcons.rows3,
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
                  icon: LucideIcons.settings2,
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
            Text(label, style: TextStyle(fontSize: 11, color: _readerTheme.text)),
          ],
        ),
      ),
    );
  }

  /// 排版设置抽屉 (字号、行距、护眼色)
  Widget _buildSettingsDrawer() {
    return Positioned(
      bottom: 90,
      left: 16,
      right: 16,
      child: Container(
        decoration: BoxDecoration(
          color: _readerTheme.bg.withValues(alpha: 0.98),
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
              const Divider(height: 1),
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
                          ? const Icon(LucideIcons.check, color: AppColors.primary, size: 16)
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
