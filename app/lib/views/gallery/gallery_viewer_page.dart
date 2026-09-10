import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';

/// 图集/漫画浏览模式枚举
enum GalleryMode {
  grid('展厅网格'),
  comicStrip('垂直条漫');

  const GalleryMode(this.label);
  final String label;
}

/// 现代漫画与图集查看器 (FluxGallery)
/// 
/// 支持双模式自由切换 (2/3列瀑布流展厅 vs 垂直无缝条漫连续下拉)
/// 搭配 1.0x ~ 4.0x 双指无级平滑缩放、双击快速复位、长按保存/分享抽屉
class GalleryViewerPage extends StatefulWidget {
  const GalleryViewerPage({
    super.key,
    this.title = '图集浏览',
    this.images = const [],
    this.referer = '',
    this.initialIndex = 0,
    this.initialMode = GalleryMode.grid,
  });

  /// 图集或漫画标题
  final String title;

  /// 图片直链列表
  final List<String> images;

  /// 防盗链请求头 Referer
  final String referer;

  /// 初始定位图片序号
  final int initialIndex;

  /// 初始查看模式
  final GalleryMode initialMode;

  @override
  State<GalleryViewerPage> createState() => _GalleryViewerPageState();
}

class _GalleryViewerPageState extends State<GalleryViewerPage> {
  late List<String> _images;
  late GalleryMode _mode;
  final ScrollController _scrollController = ScrollController();

  // 默认精美示范高清壁纸流 (用于外部未传递或加载中降级)
  static const List<String> _fallbackImages = [
    'https://images.unsplash.com/photo-1579783902614-a3fb3927b675?w=1200&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1541701494587-cb58502866ab?w=1200&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1518770660439-4636190af475?w=1200&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=1200&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1519681393784-d120267933ba?w=1200&auto=format&fit=crop&q=80',
    'https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?w=1200&auto=format&fit=crop&q=80',
  ];

  @override
  void initState() {
    super.initState();
    _images = widget.images.isNotEmpty ? widget.images : _fallbackImages;
    _mode = widget.initialMode;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 切换模式 (瀑布展厅 / 垂直条漫)
  void _toggleMode() {
    setState(() {
      _mode = _mode == GalleryMode.grid ? GalleryMode.comicStrip : GalleryMode.grid;
    });
  }

  /// 弹出单张图片操作快捷抽屉
  void _showImageActions(BuildContext context, String imageUrl, int index) {
    HapticFeedback.lightImpact();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? AppColors.darkSurface : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 8, bottom: 8),
                  child: Text(
                    '图片操作 · 第 ${index + 1} / ${_images.length} 张',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(LucideIcons.share2, color: AppColors.primary),
                  title: const Text('分享图片直链'),
                  onTap: () {
                    Navigator.pop(ctx);
                    SharePlus.instance.share(ShareParams(text: imageUrl));
                  },
                ),
                ListTile(
                  leading: const Icon(LucideIcons.copy, color: AppColors.primary),
                  title: const Text('复制图片链接'),
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: imageUrl));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('已复制图片直链至剪贴板')),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 打开沉浸式全屏手势放大查看器
  void _openFullScreenViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => _FullScreenImageViewer(
          images: _images,
          initialIndex: index,
          title: widget.title,
          referer: widget.referer,
          onAction: (img, idx) => _showImageActions(ctx, img, idx),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // 模式切换按钮
          IconButton(
            tooltip: _mode == GalleryMode.grid ? '切换为垂直条漫' : '切换为展厅网格',
            icon: Icon(_mode == GalleryMode.grid ? LucideIcons.columns2 : LucideIcons.layoutGrid),
            onPressed: _toggleMode,
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                '共 ${_images.length} 张',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: _images.isEmpty
          ? const EmptyState(
              icon: LucideIcons.imageOff,
              title: '暂无图片数据',
              description: '未获取到可供展示的高清图片资源',
            )
          : (_mode == GalleryMode.grid ? _buildGridView(isDark) : _buildComicStripView(isDark)),
    );
  }

  /// 模式一：瀑布流大图展厅 (2/3列网格卡片)
  Widget _buildGridView(bool isDark) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.72,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final imgUrl = _images[index];

        return AppCard(
          borderRadius: 14,
          onTap: () => _openFullScreenViewer(index),
          onLongPress: () => _showImageActions(context, imgUrl, index),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ExtendedImage.network(
                imgUrl,
                fit: BoxFit.cover,
                cache: true,
                headers: widget.referer.isNotEmpty ? {'Referer': widget.referer} : null,
                loadStateChanged: (state) {
                  switch (state.extendedImageLoadState) {
                    case LoadState.loading:
                      return Container(
                        color: isDark ? Colors.white10 : Colors.black12,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                          ),
                        ),
                      );
                    case LoadState.failed:
                      return Container(
                        color: isDark ? Colors.white10 : Colors.black12,
                        child: const Icon(LucideIcons.imageOff, color: Colors.grey, size: 24),
                      );
                    case LoadState.completed:
                      return null;
                  }
                },
              ),
              // 底部轻量序号角标
              Positioned(
                bottom: 6,
                right: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 模式二：垂直条漫阅读器 (漫画专用无缝长下拉)
  Widget _buildComicStripView(bool isDark) {
    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.zero,
      itemCount: _images.length,
      itemBuilder: (context, index) {
        final imgUrl = _images[index];

        return GestureDetector(
          onTap: () => _openFullScreenViewer(index),
          onLongPress: () => _showImageActions(context, imgUrl, index),
          child: Container(
            color: isDark ? Colors.black : Colors.white,
            child: ExtendedImage.network(
              imgUrl,
              fit: BoxFit.fitWidth,
              cache: true,
              headers: widget.referer.isNotEmpty ? {'Referer': widget.referer} : null,
              loadStateChanged: (state) {
                switch (state.extendedImageLoadState) {
                  case LoadState.loading:
                    return Container(
                      height: 320,
                      color: isDark ? Colors.white10 : Colors.black12,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                        ),
                      ),
                    );
                  case LoadState.failed:
                    return Container(
                      height: 200,
                      color: isDark ? Colors.white10 : Colors.black12,
                      child: const Center(
                        child: Icon(LucideIcons.imageOff, color: Colors.grey, size: 32),
                      ),
                    );
                  case LoadState.completed:
                    return null;
                }
              },
            ),
          ),
        );
      },
    );
  }
}

/// 沉浸式全屏手势滑动与无级放大查看器
class _FullScreenImageViewer extends StatefulWidget {
  const _FullScreenImageViewer({
    required this.images,
    required this.initialIndex,
    required this.title,
    required this.referer,
    required this.onAction,
  });

  final List<String> images;
  final int initialIndex;
  final String title;
  final String referer;
  final void Function(String imageUrl, int index) onAction;

  @override
  State<_FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<_FullScreenImageViewer> {
  late int _currentIndex;
  late final ExtendedPageController _pageController;
  bool _showAppBar = true;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = ExtendedPageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // 1. 无级手势放大 PageView
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () => setState(() => _showAppBar = !_showAppBar),
            child: ExtendedImageGesturePageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (idx) => setState(() => _currentIndex = idx),
              itemBuilder: (context, index) {
                final imgUrl = widget.images[index];

                return ExtendedImage.network(
                  imgUrl,
                  fit: BoxFit.contain,
                  mode: ExtendedImageMode.gesture,
                  cache: true,
                  headers: widget.referer.isNotEmpty ? {'Referer': widget.referer} : null,
                  initGestureConfigHandler: (state) {
                    return GestureConfig(
                      minScale: 0.9,
                      animationMinScale: 0.7,
                      maxScale: 4.0,
                      animationMaxScale: 4.5,
                      speed: 1.0,
                      inertialSpeed: 100.0,
                      initialScale: 1.0,
                      inPageView: true,
                    );
                  },
                );
              },
            ),
          ),

          // 2. 顶部微透控制栏
          if (_showAppBar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.black87, Colors.transparent],
                  ),
                ),
                padding: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 4,
                  left: 8,
                  right: 8,
                  bottom: 16,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Text(
                        widget.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(LucideIcons.moreVertical, color: Colors.white, size: 20),
                      onPressed: () => widget.onAction(widget.images[_currentIndex], _currentIndex),
                    ),
                  ],
                ),
              ),
            ),

          // 3. 底部页码指示胶囊
          Positioned(
            bottom: 24,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24, width: 0.8),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.images.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
