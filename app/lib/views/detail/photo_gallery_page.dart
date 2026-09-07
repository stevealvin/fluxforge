import 'package:animations/animations.dart';
import 'package:extended_image/extended_image.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../services/rule_engine.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';

/// 图集瀑布流与相册详情页面
class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({
    super.key,
    required this.href,
    this.title = '图片集',
    this.referer = 'https://meirentu.cc/',
  });

  /// 目标图集链接
  final String href;

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
    return getDetail("$targetUrl");
    ''';
  }

  /// 加载图集数据
  Future<void> _loadGallery() async {
    setState(() {
      _loading = true;
    });

    try {
      final script = _buildExtractScript(widget.href);
      final result = await RuleEngine.execute(script);
      if (result is List && mounted) {
        setState(() {
          _imageList = result.map((e) => e.toString()).toList();
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
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
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

/// 沉浸式手势滑动与无级放大全屏图片查看器
class PhotoViewPage extends StatefulWidget {
  const PhotoViewPage({
    super.key,
    required this.imageList,
    this.initialIndex = 0,
    this.referer = '',
  });

  final List<String> imageList;
  final int initialIndex;
  final String referer;

  @override
  State<PhotoViewPage> createState() => _PhotoViewPageState();
}

class _PhotoViewPageState extends State<PhotoViewPage> {
  late int _currentIndex;
  late final ExtendedPageController _pageController;

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
    return Material(
      color: Colors.black,
      child: Stack(
        children: [
          // 手势滑动分页
          ExtendedImageGesturePageView.builder(
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
                headers: widget.referer.isNotEmpty ? {'Referer': widget.referer} : null,
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
          // 顶部半透明操作遮罩
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        '${_currentIndex + 1} / ${widget.imageList.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 48), // 占位保持居中对称
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
