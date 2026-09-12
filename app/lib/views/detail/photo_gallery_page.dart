import 'package:animations/animations.dart';
import 'package:extended_image/extended_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/storage/app_storage.dart';
import '../../core/theme/app_colors.dart';
import '../../services/rule_engine.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

/// 漫画阅读模式全局持久化存储键名
const String _kComicReadingModePrefKey = 'photo_view_comic_mode';

/// 图集瀑布流与相册详情页面
class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({
    super.key,
    required this.url,
    this.title = '图片集',
    this.referer = 'https://meirentu.cc/',
  });

  /// 目标图集链接
  final String url;

  /// 图集标题
  final String title;

  /// 资源防盗链 Referer
  final String referer;

  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  bool _loading = false;
  List<String> _imageList = [];

  /// 生成执行提取图集明细的沙箱脚本
  String _buildExtractScript(String targetUrl) {
    return '''
    module.exports = async function() {
      const getData = async (url) => {
        try {
          let { data } = await axios.get(url, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
            }
          });
          let \$ = cheerio.load(data);
          let list = \$('.content img').map((i, el) => {
            return \$(el).attr('src');
          }).toArray();
          return list;
        } catch (error) {
          return [];
        }
      };
      const getDetail = async (url) => {
        try {
          let { data } = await axios.get(url, {
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
            }
          });
          let \$ = cheerio.load(data);
          let list = \$('.page a').map((i, el) => {
            return 'https://meirentu.cc' + \$(el).attr('href');
          }).toArray();
          list.pop();
          let result = [];
          for (const item of list) {
            let arr = await getData(item);
            result = result.concat(arr);
          }
          return result;
        } catch (error) {
          return [];
        }
      };
      return await getDetail("$targetUrl");
    };
    ''';
  }

  /// 加载图集数据
  Future<void> _loadGallery() async {
    setState(() {
      _loading = true;
    });

    try {
      final script = _buildExtractScript(widget.url);
      final result = await RuleEngine.execute(script);
      if (result is List && mounted) {
        setState(() {
          _imageList = result
              .map((e) => e.toString().trim())
              .where((s) => s.isNotEmpty)
              .toList();
        });
      }
    } catch (e) {
      debugPrint('【图集解析】加载失败: $e');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (_imageList.isNotEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: Text(
                  '共 ${_imageList.length} 张',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: LoadingIndicator(message: '正在解析精美画质图集...'));
    }

    if (_imageList.isEmpty) {
      return Center(
        child: EmptyState(
          icon: LucideIcons.imageOff,
          title: '暂未解析到图片内容',
          description: '目标图集可能已下架或需要更新解析规则',
          actionText: '重新加载',
          onAction: _loadGallery,
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(6),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 0.68,
      ),
      itemCount: _imageList.length,
      itemBuilder: (context, index) {
        final imgUrl = _imageList[index];

        return OpenContainer<bool>(
          transitionType: ContainerTransitionType.fadeThrough,
          closedElevation: 0,
          openElevation: 0,
          closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          closedColor: Colors.transparent,
          openColor: Colors.black,
          openBuilder: (context, _) {
            return PhotoViewPage(
              imageList: _imageList,
              initialIndex: index,
              referer: widget.referer,
            );
          },
          closedBuilder: (context, action) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ExtendedImage.network(
                imgUrl,
                cache: true,
                fit: BoxFit.cover,
                headers: {'Referer': widget.referer},
                loadStateChanged: (state) {
                  switch (state.extendedImageLoadState) {
                    case LoadState.loading:
                      return Container(
                        color: Colors.black12,
                        child: const Center(
                          child: LoadingIndicator.compact(size: 20),
                        ),
                      );
                    case LoadState.failed:
                      return Container(
                        color: Colors.black12,
                        child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                      );
                    case LoadState.completed:
                      return null;
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

/// 沉浸式手势滑动与长漫画全宽长列表全屏查看器
class PhotoViewPage extends StatefulWidget {
  const PhotoViewPage({
    super.key,
    required this.imageList,
    this.initialIndex = 0,
    this.referer = '',
    this.headers,
    this.initialContinuousMode,
  });

  /// 全部图片 URL 列表
  final List<String> imageList;

  /// 初始打开的图片索引
  final int initialIndex;

  /// 防盗链 Referer 请求头
  final String referer;

  /// 自定义网络请求头
  final Map<String, String>? headers;

  /// 显式指定的初始长漫画长卷模式 (若为 null 则自动加载本地持久化偏好)
  final bool? initialContinuousMode;

  @override
  State<PhotoViewPage> createState() => _PhotoViewPageState();
}

class _PhotoViewPageState extends State<PhotoViewPage> {
  late int _currentIndex;
  late final ExtendedPageController _pageController;
  late final ScrollController _scrollController;
  late final List<GlobalKey> _itemKeys;

  /// 是否为长漫画无缝纵向长卷模式 (true: 长漫画长列表, false: 左右翻页)
  bool _isComicMode = false;

  /// 是否显示顶部悬浮控制栏
  bool _showControls = true;

  Map<String, String>? get _effectiveHeaders {
    if (widget.headers != null && widget.headers!.isNotEmpty) {
      return widget.headers;
    }
    return widget.referer.isNotEmpty ? {'Referer': widget.referer} : null;
  }

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = ExtendedPageController(initialPage: widget.initialIndex);
    _scrollController = ScrollController();
    _itemKeys = List.generate(widget.imageList.length, (_) => GlobalKey());

    _initReadingMode();
  }

  /// 初始化阅读模式：优先读取显式传入的模式，其次读取全局持久化偏好
  Future<void> _initReadingMode() async {
    if (widget.initialContinuousMode != null) {
      if (mounted) {
        setState(() {
          _isComicMode = widget.initialContinuousMode!;
        });
        if (_isComicMode) {
          _scrollToCurrentIndexAfterBuild();
        }
      }
      return;
    }

    try {
      final saved = await AppStorage.getBool(_kComicReadingModePrefKey);
      if (saved != null && mounted) {
        setState(() {
          _isComicMode = saved;
        });
        if (_isComicMode) {
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

  /// 切换阅读模式 (长漫画长列表 vs 左右滑动翻页)
  Future<void> _toggleReadingMode() async {
    final newMode = !_isComicMode;
    setState(() {
      _isComicMode = newMode;
    });

    // 持久化保存用户偏好
    try {
      await AppStorage.setBool(_kComicReadingModePrefKey, newMode);
    } catch (_) {}

    if (newMode) {
      // 切换至长漫画长列表模式，等待下一帧布局完成后平滑定位到当前图片
      _scrollToCurrentIndexAfterBuild();
    } else {
      // 切换至左右滑动翻页模式，跳转至对应索引页面
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_currentIndex);
        }
      });
    }
  }

  /// 布局完成后平滑滚动至当前阅读索引所在条目
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

  /// 在长漫画模式滚动时，动态计算视口中央所在的图片索引并更新顶部指示器
  void _updateCurrentIndexFromScroll() {
    if (!mounted || _itemKeys.isEmpty) return;
    final mediaQuery = MediaQuery.maybeOf(context);
    final screenCenterY = (mediaQuery?.size.height ?? 800) / 2;

    for (int i = 0; i < widget.imageList.length; i++) {
      if (i < _itemKeys.length) {
        final keyContext = _itemKeys[i].currentContext;
        if (keyContext != null) {
          final box = keyContext.findRenderObject() as RenderBox?;
          if (box != null && box.hasSize) {
            final pos = box.localToGlobal(Offset.zero);
            final top = pos.dy;
            final bottom = top + box.size.height;
            if (top <= screenCenterY && bottom >= screenCenterY) {
              if (_currentIndex != i) {
                setState(() {
                  _currentIndex = i;
                });
              }
              break;
            }
          }
        }
      }
    }
  }

  /// 构建长漫画纵向无缝长卷单张图片 (零间隔、零圆角、全宽铺满、上下无缝拼接)
  Widget _buildComicItem(int index) {
    final url = widget.imageList[index];
    return Container(
      key: _itemKeys[index],
      width: double.infinity,
      color: Colors.black,
      child: ExtendedImage.network(
        url,
        width: double.infinity,
        fit: BoxFit.fitWidth,
        headers: _effectiveHeaders,
        cache: true,
        loadStateChanged: (state) {
          switch (state.extendedImageLoadState) {
            case LoadState.loading:
              return Container(
                width: double.infinity,
                height: 320,
                color: const Color(0xFF141414),
                child: const Center(
                  child: LoadingIndicator.compact(size: 22),
                ),
              );
            case LoadState.failed:
              return InkWell(
                onTap: () => state.reLoadImage(),
                child: Container(
                  width: double.infinity,
                  height: 200,
                  color: const Color(0xFF1A1A1A),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.broken_image_rounded, color: Colors.white38, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        '第 ${index + 1} 张图片加载失败，点击重试',
                        style: const TextStyle(color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              );
            case LoadState.completed:
              return null; // 图片加载完成，自然按宽铺满、高度自适应，上下无缝相接
          }
        },
      ),
    );
  }

  /// 构建左右滑动分页查看器
  Widget _buildHorizontalPageView() {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () {
        setState(() {
          _showControls = !_showControls;
        });
      },
      child: ExtendedImageGesturePageView.builder(
        controller: _pageController,
        itemCount: widget.imageList.length,
        scrollDirection: Axis.horizontal,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final url = widget.imageList[index];
          return ExtendedImage.network(
            url,
            fit: BoxFit.contain,
            mode: ExtendedImageMode.gesture,
            headers: _effectiveHeaders,
            initGestureConfigHandler: (state) {
              return GestureConfig(
                inPageView: true,
                initialScale: 1.0,
                minScale: 0.8,
                maxScale: 3.5,
                animationMinScale: 0.7,
                animationMaxScale: 4.0,
                speed: 1.0,
                inertialSpeed: 100.0,
                initialAlignment: InitialAlignment.center,
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. 主视口内容区 (长漫画无缝长卷 vs 左右滑动分页)
          Positioned.fill(
            child: _isComicMode
                ? GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                    },
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollUpdateNotification ||
                            notification is ScrollEndNotification) {
                          _updateCurrentIndexFromScroll();
                        }
                        return false;
                      },
                      child: ListView.builder(
                        controller: _scrollController,
                        padding: EdgeInsets.zero,
                        physics: const ClampingScrollPhysics(),
                        itemCount: widget.imageList.length,
                        itemBuilder: (context, index) => _buildComicItem(index),
                      ),
                    ),
                  )
                : _buildHorizontalPageView(),
          ),

          // 2. 顶部半透明操作遮罩与状态栏 (支持淡入淡出及位移隐藏，全屏沉浸)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            top: _showControls ? 0 : -90,
            left: 0,
            right: 0,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: _showControls ? 1.0 : 0.0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black87,
                      Colors.transparent,
                    ],
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // 返回按钮
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        // 当前阅读页码指示器
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white12, width: 0.8),
                          ),
                          child: Text(
                            '${_currentIndex + 1} / ${widget.imageList.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        // 模式切换胶囊按钮 (长漫画模式 vs 左右翻页模式)
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: _toggleReadingMode,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: _isComicMode
                                    ? AppColors.primary.withValues(alpha: 0.85)
                                    : Colors.black54,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: _isComicMode
                                      ? AppColors.primary
                                      : Colors.white12,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _isComicMode ? LucideIcons.scrollText : LucideIcons.columns2,
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    _isComicMode ? '长漫画' : '左右翻页',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
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
