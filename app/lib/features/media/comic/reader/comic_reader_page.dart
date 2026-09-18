import 'dart:io';

import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/core/storage/app_storage.dart';
import 'package:fluxforge/app/theme/app_colors.dart';

/// 漫画沉浸阅读模式持久化偏好键
const String _kComicReaderModeKey = 'comic_reader_continuous_mode';

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
  });

  final List<String> imageList;
  final String title;
  final int initialIndex;
  final Map<String, String>? headers;
  final bool? initialContinuousMode;
  final void Function(int delta)? onChapterChange;

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
    _currentIndex = widget.initialIndex.clamp(0, widget.imageList.isEmpty ? 0 : widget.imageList.length - 1);
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
          _scrollToCurrentIndexAfterBuild();
        }
      }
      return;
    }

    try {
      final saved = await AppStorage.getBool(_kComicReaderModeKey);
      if (saved != null && mounted) {
        setState(() {
          _isContinuousMode = saved;
        });
        if (_isContinuousMode) {
          _scrollToCurrentIndexAfterBuild();
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

  Future<void> _toggleReadingMode() async {
    final newMode = !_isContinuousMode;
    setState(() {
      _isContinuousMode = newMode;
    });

    try {
      await AppStorage.setBool(_kComicReaderModeKey, newMode);
    } catch (_) {}

    if (newMode) {
      _scrollToCurrentIndexAfterBuild();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    }
  }

  void _scrollToCurrentIndexAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      if (_currentIndex >= 0 && _currentIndex < _itemKeys.length) {
        final keyContext = _itemKeys[_currentIndex].currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(
            keyContext,
            alignment: 0.0,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _updateIndexOnScroll() {
    if (!mounted || _itemKeys.isEmpty) return;
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
                    child: Text('图集内容为空', style: TextStyle(color: Colors.white54)),
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
            bottom: _showControls ? 0 : -90,
            left: 0,
            right: 0,
            child: _buildBottomBar(total),
          ),

          // 4. 纵向长漫模式常驻右下角微悬浮胶囊页码指示
          if (_isContinuousMode && !_showControls && total > 0)
            Positioned(
              right: 16,
              bottom: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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

  Widget _buildContinuousVerticalList() {
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollUpdateNotification) {
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
                    return Container(
                      height: 280,
                      color: Colors.black,
                      child: const Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                          ),
                        ),
                      ),
                    );
                  case LoadState.completed:
                    return null;
                  case LoadState.failed:
                    return Container(
                      height: 220,
                      color: const Color(0xFF141414),
                      child: Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 36),
                            const SizedBox(height: 8),
                            GestureDetector(
                              onTap: () => state.reLoadImage(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white12,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  '重试加载',
                                  style: TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
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
    // 本地绝对路径（离线下载）→ 直接读沙盒文件，断网亦可阅读
    if (!source.startsWith('http://') && !source.startsWith('https://')) {
      return ExtendedImage.file(
        File(source),
        fit: fit,
        mode: mode,
        initGestureConfigHandler: initGestureConfigHandler,
        loadStateChanged: loadStateChanged,
      );
    }

    return ExtendedImage.network(
      source,
      fit: fit,
      headers: headers,
      mode: mode,
      initGestureConfigHandler: initGestureConfigHandler,
      loadStateChanged: loadStateChanged,
    );
  }

  Widget _buildPagedHorizontalViewer() {
    return ExtendedImageGesturePageView.builder(
      controller: _pageController,
      physics: const BouncingScrollPhysics(),
      itemCount: widget.imageList.length,
      onPageChanged: (index) {
        setState(() {
          _currentIndex = index;
        });
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
                return const Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
                    ),
                  ),
                );
              case LoadState.completed:
                return null;
              case LoadState.failed:
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 48),
                      const SizedBox(height: 12),
                      GestureDetector(
                        onTap: () => state.reLoadImage(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Text('点击重试', style: TextStyle(color: Colors.white70, fontSize: 13)),
                        ),
                      ),
                    ],
                  ),
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
            icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
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
                Text(
                  '${_currentIndex + 1} / $total 页',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),

          GestureDetector(
            onTap: _toggleReadingMode,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _isContinuousMode
                    ? AppColors.primary.withValues(alpha: 0.24)
                    : Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _isContinuousMode ? AppColors.primary : Colors.white24,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _isContinuousMode ? Ionicons.readerOutline : Ionicons.bookOutline,
                    color: _isContinuousMode ? AppColors.primaryLight : Colors.white,
                    size: 13,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _isContinuousMode ? '长漫画' : '左右翻页',
                    style: TextStyle(
                      color: _isContinuousMode ? AppColors.primaryLight : Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(int total) {
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: EdgeInsets.only(
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 10,
        left: 20,
        right: 20,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            Colors.black.withValues(alpha: 0.85),
            Colors.black.withValues(alpha: 0.0),
          ],
        ),
      ),
      child: Row(
        children: [
          Text(
            '${_currentIndex + 1}',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: AppColors.primary,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                trackHeight: 3,
              ),
              child: Slider(
                value: _currentIndex.toDouble().clamp(0, (total - 1).toDouble()),
                min: 0,
                max: (total - 1).toDouble(),
                onChanged: (val) {
                  final target = val.round();
                  if (target != _currentIndex) {
                    setState(() {
                      _currentIndex = target;
                    });
                    if (_isContinuousMode) {
                      _scrollToCurrentIndexAfterBuild();
                    } else {
                      _pageController.jumpToPage(target);
                    }
                  }
                },
              ),
            ),
          ),
          Text(
            '$total',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
