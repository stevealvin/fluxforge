import 'dart:async';

import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/features/media/comic/reader/controllers/comic_reader_preferences.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';

/// 图片「加载中 / 加载失败」占位页的高度
///
/// 两者**必须一致**：高度不同会在状态切换（加载中 → 失败）时让列表项高度突变，
/// 连续滚动模式下表现为滚动位置抖动、画面跳动（此前是 280 / 220 两个值）。
const double kComicPagePlaceholderHeight = 280;

/// 全屏沉浸式漫画与画廊阅读引擎
class ComicReaderPage extends StatefulWidget {
  const ComicReaderPage({
    super.key,
    required this.imageList,
    this.title = '漫画阅读',
    this.initialIndex = 0,
    this.headers,
    this.initialContinuousMode,
    this.onChapterChange,
    this.hasPreviousChapter = false,
    this.hasNextChapter = false,
    this.onOpenCatalog,
    this.onPageChanged,
  });

  final List<String> imageList;
  final String title;
  final int initialIndex;
  final Map<String, String>? headers;
  final bool? initialContinuousMode;

  /// 用户请求切章（`-1` 上一章 / `+1` 下一章）；新章内容的解析由宿主负责
  final void Function(int delta)? onChapterChange;

  /// 相邻章是否存在 —— 决定是否在章节边界给出"上一章 / 下一章"入口
  final bool hasPreviousChapter;
  final bool hasNextChapter;

  /// 打开章节目录（章节形态由宿主提供；为 null 时顶栏不出现目录入口）
  final VoidCallback? onOpenCatalog;

  /// 页内位置变化 `(index, total)` —— 宿主据此登记「看到第几页」
  final void Function(int index, int total)? onPageChanged;

  @override
  State<ComicReaderPage> createState() => _ComicReaderPageState();
}

class _ComicReaderPageState extends State<ComicReaderPage> {
  late int _currentIndex;
  late final ExtendedPageController _pageController;
  late final ScrollController _scrollController;
  late final List<GlobalKey> _itemKeys;

  bool _isContinuousMode = false;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(
      0,
      widget.imageList.isEmpty ? 0 : widget.imageList.length - 1,
    );
    _pageController = ExtendedPageController(initialPage: _currentIndex);
    _scrollController = ScrollController();
    _itemKeys = List.generate(widget.imageList.length, (_) => GlobalKey());

    _initReadingMode();
  }

  Future<void> _initReadingMode() async {
    if (widget.initialContinuousMode != null) {
      if (mounted) {
        setState(() {
          _isContinuousMode = widget.initialContinuousMode!;
        });
        if (_isContinuousMode) {
          unawaited(_jumpToIndex(_currentIndex));
        }
      }
      return;
    }

    try {
      final saved = await ComicReaderPreferences.loadContinuousMode();
      if (saved != null && mounted) {
        setState(() {
          _isContinuousMode = saved;
        });
        if (_isContinuousMode) {
          unawaited(_jumpToIndex(_currentIndex));
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 设定阅读方式（长漫画 / 左右翻页）并持久化
  Future<void> _setReadingMode(bool continuous) async {
    if (continuous == _isContinuousMode) return;
    setState(() {
      _isContinuousMode = continuous;
    });

    await ComicReaderPreferences.saveContinuousMode(continuous);

    // 两种模式都用同一条定位路径（内部按模式分派）：
    // 切模式时"停在第一张"就是因为这里原来直接 ensureVisible，
    // 而刚重建的列表里目标项还没被构建。
    if (mounted) unawaited(_jumpToIndex(_currentIndex));
  }

  /// 各张图的**实测**高度（只量渲染出来的项，量到就缓存）
  ///
  /// 长图模式下每张的高度由图片自身比例决定，构建前无从得知；
  /// 而跳页要算滚动偏移，所以必须"已测的用实测、未测的用均值"。
  final Map<int, double> _measuredHeight = {};

  /// 未实测项的兜底高度：已测项的均值（一张都没测过时用占位高度）
  double get _fallbackItemHeight {
    if (_measuredHeight.isEmpty) return kComicPagePlaceholderHeight;
    var sum = 0.0;
    for (final height in _measuredHeight.values) {
      sum += height;
    }
    return sum / _measuredHeight.length;
  }

  /// 第 [index] 张的**估算**滚动偏移
  double _estimatedOffsetFor(int index) {
    final fallback = _fallbackItemHeight;
    var offset = 0.0;
    for (int i = 0; i < index; i++) {
      offset += _measuredHeight[i] ?? fallback;
    }
    return offset;
  }

  /// 量一遍已构建的项，充实高度缓存（滚动与跳页各调一次，开销为一次 O(n) 读尺寸）
  void _measureBuiltItems() {
    for (int i = 0; i < _itemKeys.length; i++) {
      final box = _itemKeys[i].currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.height > 0) {
        _measuredHeight[i] = box.size.height;
      }
    }
  }

  /// 定位到第 [index] 张（**两种阅读模式共用的一条路**）
  ///
  /// 长图模式此前直接用 `Scrollable.ensureVisible`，有两个硬伤：
  /// 1. 目标项**没被构建**时 `currentContext` 为空 —— 调用静默失败。
  ///    长图集里点第 40 张、把进度条拖到后半段"没反应"，根因就在这里；
  /// 2. 每项高度随图片加载而变，一次性定位本来就容易落空。
  ///
  /// 所以改成「按估算偏移先跳过去 → 等一帧 → 目标已构建就精修」，最多试几轮：
  /// 每轮都会量到新的真实高度，估算随之收敛（首轮 280 的占位高度偏差，
  /// 第二轮就能按实测均值纠正），几轮内必然命中。
  Future<void> _jumpToIndex(int index) async {
    final total = widget.imageList.length;
    if (total == 0) return;
    final target = index.clamp(0, total - 1);

    if (!_isContinuousMode) {
      await _jumpToPageWhenReady(target);
      return;
    }

    for (var attempt = 0; attempt < 6; attempt++) {
      if (!mounted) return;
      if (!_scrollController.hasClients) {
        // 列表还没挂上（首帧 / 刚从翻页切过来）：等一帧再试。
        // 这里若直接 return，定位就彻底落空了 —— 正是"切到长图回到第一张"的成因。
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }

      final keyContext = _itemKeys[target].currentContext;
      // 循环里可能已经等过帧：目标项随时可能被回收，用之前再确认一次它还挂着
      if (keyContext != null && keyContext.mounted) {
        await Scrollable.ensureVisible(
          keyContext,
          alignment: 0.0,
          duration: Duration.zero,
        );
        _measureBuiltItems();
        return;
      }

      _scrollController.jumpTo(
        _estimatedOffsetFor(target)
            .clamp(0.0, _scrollController.position.maxScrollExtent),
      );
      // 等这一帧走完：列表会把目标附近构建出来，并给出该处的真实高度
      await WidgetsBinding.instance.endOfFrame;
      _measureBuiltItems();
    }
  }

  /// 翻页模式定位
  ///
  /// 两处静默失败都在这里兜住：
  /// 1. PageView 刚重建的当帧控制器还没挂上 —— 单帧 `jumpToPage` 等于没调；
  /// 2. 新挂载的 PageView 会先报一次第 0 页，把刚跳好的页码又拽回去 ——
  ///    所以跳完要等一帧回读真实页码，没停住就再跳一次。
  Future<void> _jumpToPageWhenReady(int index) async {
    for (var attempt = 0; attempt < 3; attempt++) {
      if (!mounted) return;
      if (!_pageController.hasClients) {
        await WidgetsBinding.instance.endOfFrame;
        continue;
      }

      _pageController.jumpToPage(index);
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_pageController.hasClients) return;

      if ((_pageController.page ?? index.toDouble()).round() != index) {
        continue;
      }
      if (_currentIndex != index) {
        setState(() => _currentIndex = index);
      }
      return;
    }
  }

  void _updateIndexOnScroll() {
    if (!mounted || _itemKeys.isEmpty) return;
    // 拖动滑块期间一切以滑块为准，否则滚动回写会把滑块「拽回去」
    if (_sliderValue != null) return;
    final screenCenterY = MediaQuery.of(context).size.height / 2;

    int bestIndex = _currentIndex;
    double minDistance = double.infinity;

    for (int i = 0; i < _itemKeys.length; i++) {
      final keyContext = _itemKeys[i].currentContext;
      if (keyContext != null) {
        final renderBox = keyContext.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          final pos = renderBox.localToGlobal(Offset.zero);
          final top = pos.dy;
          final bottom = top + renderBox.size.height;
          if (screenCenterY >= top && screenCenterY <= bottom) {
            bestIndex = i;
            break;
          }
          final itemCenterY = top + renderBox.size.height / 2;
          final dist = (screenCenterY - itemCenterY).abs();
          if (dist < minDistance) {
            minDistance = dist;
            bestIndex = i;
          }
        }
      }
    }

    if (bestIndex != _currentIndex && mounted) {
      setState(() {
        _currentIndex = bestIndex;
      });
      widget.onPageChanged?.call(bestIndex, widget.imageList.length);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageList.length;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 阅读主体视口
          GestureDetector(
            onTap: () {
              setState(() {
                _showControls = !_showControls;
              });
            },
            child: widget.imageList.isEmpty
                ? const Center(
                    child: Text(
                      '图集内容为空',
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : _isContinuousMode
                ? _buildContinuousVerticalList()
                : _buildPagedHorizontalViewer(),
          ),

          // 2. 顶部悬浮控制栏
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            top: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: _buildTopBar(total),
          ),

          // 3. 底部悬浮指示器与控制面板
          AnimatedPositioned(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            bottom: _showControls ? 0 : -160,
            left: 0,
            right: 0,
            child: _buildBottomBar(total),
          ),

          // 4. 章节边界：章节形态下翻到首/末张时给出切章入口
          if (widget.onChapterChange != null && total > 0 && !_showControls)
            Positioned(
              left: 16,
              right: 16,
              bottom: 28,
              child: Row(
                children: [
                  if (widget.hasPreviousChapter && _currentIndex == 0)
                    _buildChapterNavPill(
                      icon: Ionicons.chevronBackOutline,
                      label: '上一章',
                      onTap: () => widget.onChapterChange?.call(-1),
                    ),
                  const Spacer(),
                  if (widget.hasNextChapter && _currentIndex == total - 1)
                    _buildChapterNavPill(
                      icon: Ionicons.chevronForwardOutline,
                      label: '下一章',
                      trailingIcon: true,
                      onTap: () => widget.onChapterChange?.call(1),
                    ),
                ],
              ),
            ),

          // 5. 纵向长漫模式常驻右下角微悬浮胶囊页码指示
          if (_isContinuousMode && !_showControls && total > 0)
            Positioned(
              right: 16,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  '${_currentIndex + 1} / $total',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// 章节边界胶囊（上一章 / 下一章）
  Widget _buildChapterNavPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool trailingIcon = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!trailingIcon) ...[
              Icon(icon, size: 14, color: Colors.white),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (trailingIcon) ...[
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: Colors.white),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContinuousVerticalList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
          // 顺手把渲染出来的项量一遍：跳页要靠这些实测高度算偏移
          _measureBuiltItems();
          _updateIndexOnScroll();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        padding: EdgeInsets.zero,
        physics: const BouncingScrollPhysics(),
        itemCount: widget.imageList.length,
        itemBuilder: (context, index) {
          final imgUrl = widget.imageList[index];
          return Container(
            key: _itemKeys[index],
            width: double.infinity,
            margin: EdgeInsets.zero,
            padding: EdgeInsets.zero,
            child: _buildComicImage(
              source: imgUrl,
              fit: BoxFit.fitWidth,
              headers: widget.headers,
              mode: ExtendedImageMode.none,
              loadStateChanged: (state) {
                switch (state.extendedImageLoadState) {
                  case LoadState.loading:
                    return _buildImagePlaceholder(
                      height: kComicPagePlaceholderHeight,
                      child: _buildLoadingIndicator(),
                    );
                  case LoadState.completed:
                    return null;
                  case LoadState.failed:
                    return _buildImagePlaceholder(
                      height: kComicPagePlaceholderHeight,
                      child: _buildRetryPrompt(() => state.reLoadImage()),
                    );
                }
              },
            ),
          );
        },
      ),
    );
  }

  /// 构建漫画图片组件：本地离线文件优先，缺省回退网络加载
  ///
  /// [source] 既可为网络 URL，也可为离线下载后的本地绝对路径
  /// （详情页在打开阅读器前会把已下载的图片替换为本地路径）。
  Widget _buildComicImage({
    required String source,
    required BoxFit fit,
    required ExtendedImageMode mode,
    Map<String, String>? headers,
    GestureConfig Function(ExtendedImageState)? initGestureConfigHandler,
    // 注意：extended_image 的 loadStateChanged 允许返回 null（表示交给默认渲染）
    Widget? Function(ExtendedImageState)? loadStateChanged,
  }) {
    // 统一交给 AppImage.reader：协议校验、请求头、缓存与**本地文件分支**都收在组件里。
    // 阅读器自己拼 ExtendedImage，等于在"图片加载唯一出口"之外又开一套策略。
    return AppImage.reader(
      imageUrl: source,
      headers: headers,
      fit: fit,
      mode: mode,
      gestureConfig: initGestureConfigHandler,
      loadStateChanged: loadStateChanged,
    );
  }

  /// 图片占位页：加载中与失败**共用同一底色与高度口径**
  ///
  /// [height] 为空表示撑满父级（翻页模式整屏占位）；连续滚动模式必须传
  /// [kComicPagePlaceholderHeight]，否则状态切换时列表项高度突变、滚动位置抖动。
  Widget _buildImagePlaceholder({required Widget child, double? height}) {
    return Container(
      height: height,
      // 与 Scaffold 背景同色：换成另一种深灰会在切换瞬间显出一块色块
      color: Colors.black,
      child: Center(child: child),
    );
  }

  /// 占位页里的加载指示器（两种阅读模式共用同一尺寸）
  Widget _buildLoadingIndicator() {
    return const SizedBox(
      width: 28,
      height: 28,
      child: CircularProgressIndicator(
        strokeWidth: 2,
        valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
      ),
    );
  }

  /// 占位页里的失败形态：图标 + 重试入口（两种阅读模式共用同一尺寸与样式）
  Widget _buildRetryPrompt(VoidCallback onRetry) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Ionicons.imageOutline, color: Colors.white38, size: 44),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onRetry,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.white12,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              '点击重试',
              style: TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPagedHorizontalViewer() {
    return ExtendedImageGesturePageView.builder(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.imageList.length,
      onPageChanged: (index) {
        // 拖动滑块期间不接受页面回写（松手后由 [_seekToIndex] 统一定位）
        if (_sliderValue != null) return;
        setState(() {
          _currentIndex = index;
        });
        widget.onPageChanged?.call(index, widget.imageList.length);
      },
      itemBuilder: (context, index) {
        final imgUrl = widget.imageList[index];
        return _buildComicImage(
          source: imgUrl,
          fit: BoxFit.contain,
          headers: widget.headers,
          mode: ExtendedImageMode.gesture,
          initGestureConfigHandler: (state) {
            return GestureConfig(
              minScale: 0.9,
              animationMinScale: 0.7,
              maxScale: 3.5,
              animationMaxScale: 4.0,
              speed: 1.0,
              inertialSpeed: 100.0,
              initialScale: 1.0,
              inPageView: true,
            );
          },
          loadStateChanged: (state) {
            switch (state.extendedImageLoadState) {
              case LoadState.loading:
                // 翻页模式整屏占位：不设高度、撑满视口（与连续模式共用同一实现）
                return _buildImagePlaceholder(child: _buildLoadingIndicator());
              case LoadState.completed:
                return null;
              case LoadState.failed:
                return _buildImagePlaceholder(
                  child: _buildRetryPrompt(() => state.reLoadImage()),
                );
            }
          },
        );
      },
    );
  }

  Widget _buildTopBar(int total) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 4,
        bottom: 8,
        left: 8,
        right: 12,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new_rounded,
              color: Colors.white,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                // 页码只由底部栏给出（与小说阅读器同构）：两处都显示会重复，
                // 也容易在拖动进度条时出现两个数字不同步
              ],
            ),
          ),

          // 目录与阅读方式入口统一放在**底部栏**（见 [_buildBottomBar]）：
          // 沉浸阅读时顶栏只保留「返回 + 标题 + 页码」，不在右上角堆控件
        ],
      ),
    );
  }

  /// 拖动中的临时滑块值（`null` = 未拖动，跟随 [_currentIndex]）
  ///
  /// 拖动期间**不做任何跳页**：逐帧 `jumpToPage` / `ensureVisible` 会与
  /// `onPageChanged`、滚动通知互相回写 —— 手指划得快时滑块会被拽回原处，
  /// 表现就是「慢慢滑有反应、滑快了没效果」。松手时定位一次即可。
  double? _sliderValue;

  /// 滑块松手后定位一次
  ///
  /// 位置上报保持**单一来源**：横向模式交给 PageView 的 `onPageChanged`
  /// （`jumpToPage` 本就会触发），长漫模式没有这个回调，才由这里上报 ——
  /// 否则同一页会被登记两次。
  void _seekToIndex(int target) {
    final total = widget.imageList.length;
    if (total == 0) return;
    final index = target.clamp(0, total - 1);

    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      if (_isContinuousMode) widget.onPageChanged?.call(index, total);
    }

    unawaited(_jumpToIndex(index));
  }

  /// 上一页 / 下一页
  ///
  /// 与滑块走**同一条定位路径**（[_seekToIndex]）：边界自动夹紧，
  /// 拖动中的闸门也一并生效。
  void _goToPrevPage() => _seekToIndex(_currentIndex - 1);
  void _goToNextPage() => _seekToIndex(_currentIndex + 1);

  /// 底部功能按钮（与小说阅读器同款：图标在上、文案在下）
  ///
  /// 样式对齐小说阅读器的 `ReaderBarActionButton`，但**不跨 feature 复用**它 ——
  /// comic 直接依赖 novel 的内部组件会形成 features 横向依赖。
  ///
  /// 按钮不因「当前处于该模式」而改变样式：label 本身已写明当前模式，
  /// 额外的颜色 / 字重都属于重复强调（此前是染绿，后改为加粗，现全部去掉）。
  Widget _buildBottomAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final content = InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: Colors.white),
            const SizedBox(height: 3),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Colors.white),
            ),
          ],
        ),
      ),
    );
    if (tooltip == null) return content;
    return Tooltip(message: tooltip, child: content);
  }

  /// 阅读方式：底部弹出选择（与章节目录同一交互层）
  Future<void> _openReadingModeSheet() async {
    final selected = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          // 跟随主题：原来写死深色底 + 白色字，浅色主题下会是一块突兀的黑
          child: Material(
            color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                    child: Text(
                      '阅读方式',
                      style: TextStyle(
                        color: isDark
                            ? AppColors.darkTextPrimary
                            : AppColors.lightTextPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  _buildReadingModeOption(
                    sheetContext: sheetContext,
                    value: false,
                    icon: Ionicons.bookOutline,
                    title: '左右翻页',
                    subtitle: '单张横滑，适合短篇与图集',
                  ),
                  _buildReadingModeOption(
                    sheetContext: sheetContext,
                    value: true,
                    icon: Ionicons.readerOutline,
                    title: '长漫画',
                    subtitle: '纵向连续，适合条漫与长图',
                  ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected != null) await _setReadingMode(selected);
  }

  Widget _buildReadingModeOption({
    required BuildContext sheetContext,
    required bool value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final current = _isContinuousMode == value;
    final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
    final textColor = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final mutedColor = isDark
        ? AppColors.darkTextMuted
        : AppColors.lightTextMuted;

    return InkWell(
      key: ValueKey('reading_mode_$value'),
      onTap: () => Navigator.pop(sheetContext, value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Icon(icon, size: 18, color: textColor),
            const SizedBox(width: 10),
            Text(title, style: TextStyle(fontSize: 13.5, color: textColor)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: mutedColor),
              ),
            ),
            // 选中只给一个勾：此前整项染绿，而模式名本身已说明当前选择
            if (current) Icon(Ionicons.checkmark, size: 16, color: textColor),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar(int total) {
    if (total == 0) return const SizedBox.shrink();

    final maxIndex = (total - 1).toDouble();
    final sliderValue = (_sliderValue ?? _currentIndex.toDouble()).clamp(
      0.0,
      maxIndex,
    );
    // 拖动中页码实时跟随滑块，给出「正在跳到第几页」的反馈
    final displayIndex = (_sliderValue?.round() ?? _currentIndex) + 1;
    final canGoPrev = _currentIndex > 0;
    final canGoNext = _currentIndex < total - 1;

    return Container(
      // 背景保持「顶部完全透明」的渐变遮罩：图片区与浅色主题之间不留生硬的色块分界
      padding: EdgeInsets.only(
        top: 6,
        bottom: MediaQuery.of(context).padding.bottom + 8,
        left: 8,
        right: 8,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.5),
            Colors.black.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.72, 1.0],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 进度行：页码 / 上一页 / 进度条 / 下一页
          //
          // 页码并入本行（原先独占一行）—— 底部栏因此少一行，高度降约 20px
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10, right: 2),
                child: Text(
                  '$displayIndex / $total',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
              IconButton(
                tooltip: '上一页',
                icon: const Icon(Ionicons.chevronBackOutline, size: 20),
                color: Colors.white,
                disabledColor: Colors.white24,
                onPressed: canGoPrev ? _goToPrevPage : null,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: AppColors.primary,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    trackHeight: 3,
                  ),
                  child: Slider(
                    value: sliderValue,
                    min: 0,
                    max: maxIndex,
                    // 拖动只更新本地值，松手才定位：见 [_sliderValue] 的说明
                    onChanged: (val) => setState(() => _sliderValue = val),
                    onChangeEnd: (val) {
                      setState(() => _sliderValue = null);
                      _seekToIndex(val.round());
                    },
                  ),
                ),
              ),
              IconButton(
                tooltip: '下一页',
                icon: const Icon(Ionicons.chevronForwardOutline, size: 20),
                color: Colors.white,
                disabledColor: Colors.white24,
                onPressed: canGoNext ? _goToNextPage : null,
              ),
            ],
          ),

          const SizedBox(height: 2),

          // 功能按钮行：目录（章节形态才有）与阅读方式，都从底部面板进入
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              if (widget.onOpenCatalog != null)
                _buildBottomAction(
                  icon: Ionicons.listOutline,
                  label: '目录',
                  tooltip: '目录',
                  onTap: widget.onOpenCatalog!,
                ),
              _buildBottomAction(
                icon: _isContinuousMode
                    ? Ionicons.readerOutline
                    : Ionicons.bookOutline,
                label: _isContinuousMode ? '长漫画' : '左右翻页',
                onTap: _openReadingModeSheet,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
