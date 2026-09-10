import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/net_image.dart';

/// 规范化的媒体条目模型（严格遵循固定契约）
class _MediaItem {
  final String title;
  final String url;
  final String cover;
  final String desc;
  final String badge;

  const _MediaItem({
    required this.title,
    required this.url,
    required this.cover,
    this.desc = '',
    this.badge = '',
  });

  factory _MediaItem.fromMap(Map map) {
    return _MediaItem(
      title: map['title']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
      cover: map['cover']?.toString() ?? '',
      desc: map['desc']?.toString() ?? '',
      badge: map['badge']?.toString() ?? '',
    );
  }
}

/// 规范化的分类标签模型
class _DiscoveryTab {
  final String title;
  final String url;

  const _DiscoveryTab({
    required this.title,
    required this.url,
  });

  factory _DiscoveryTab.fromMap(Map map) {
    return _DiscoveryTab(
      title: map['title']?.toString() ?? '',
      url: map['url']?.toString() ?? '',
    );
  }
}

/// 规则发现流浏览视图
/// 
/// 固定接收规则 discovery 生命周期返回的结构：
/// { tabs?: Array<{ title: string, url: string }>, items: MediaItem[], hasMore?: boolean } 或 MediaItem[]
class RuleDiscoveryPage extends StatefulWidget {
  const RuleDiscoveryPage({
    super.key,
    required this.rule,
  });

  final Rule rule;

  @override
  State<RuleDiscoveryPage> createState() => _RuleDiscoveryPageState();
}

class _RuleDiscoveryPageState extends State<RuleDiscoveryPage> {
  final ScrollController _scrollController = ScrollController();

  // 状态机
  List<_MediaItem> _items = [];
  List<_DiscoveryTab> _tabs = [];
  _DiscoveryTab? _selectedTab;
  int _currentPage = 1;
  bool _hasMore = false;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _isGridView = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadDiscovery(page: 1);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && !_loadingMore && _hasMore) {
        _loadMore();
      }
    }
  }

  /// 执行规则发现请求
  Future<void> _loadDiscovery({required int page, bool isLoadMore = false}) async {
    if (isLoadMore) {
      setState(() {
        _loadingMore = true;
      });
    } else {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final tabParam = _resolveTabParam(_selectedTab);
      final result = await RuleEngine.discovery(
        widget.rule,
        page: page,
        tab: tabParam,
      );

      final List<_MediaItem> fetchedItems = [];
      final List<_DiscoveryTab> fetchedTabs = [];
      bool fetchedHasMore = false;

      // 严格按照固定格式解构数据
      if (result is Map) {
        // 1. 读取 items
        final rawItems = result['items'];
        if (rawItems is List) {
          for (final e in rawItems) {
            if (e is Map) {
              fetchedItems.add(_MediaItem.fromMap(e));
            }
          }
        }

        // 2. 读取 tabs
        final rawTabs = result['tabs'];
        if (rawTabs is List) {
          for (final t in rawTabs) {
            if (t is Map) {
              fetchedTabs.add(_DiscoveryTab.fromMap(t));
            } else if (t is String && t.isNotEmpty) {
              fetchedTabs.add(_DiscoveryTab(title: t, url: t));
            }
          }
        }

        // 3. 读取 hasMore
        fetchedHasMore = result['hasMore'] == true;
      } else if (result is List) {
        // 纯数组直接作为 items 处理
        for (final e in result) {
          if (e is Map) {
            fetchedItems.add(_MediaItem.fromMap(e));
          }
        }
      }

      if (mounted) {
        setState(() {
          if (page == 1) {
            _items = fetchedItems;
            if (fetchedTabs.isNotEmpty) {
              _tabs = fetchedTabs;
              // 默认选中第一个 Tab
              if (_selectedTab == null && _tabs.isNotEmpty) {
                _selectedTab = _tabs.first;
              }
            }
          } else {
            _items = [..._items, ...fetchedItems];
          }

          _currentPage = page;
          _hasMore = fetchedHasMore;
        });
      }
    } catch (e) {
      debugPrint('[RuleDiscoveryPage] load error: $e');
      if (mounted) {
        setState(() {
          _error = '发现内容加载失败: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  /// 触底加载更多
  Future<void> _loadMore() async {
    await _loadDiscovery(page: _currentPage + 1, isLoadMore: true);
  }

  /// 智能解析传递给规则的分类 Tab 参数（契约：严格优先传递机器路由载荷 url，仅当无 url 时回退 title）
  String _resolveTabParam(_DiscoveryTab? tab) {
    if (tab == null) return '';
    if (tab.url.isNotEmpty) {
      return tab.url;
    }
    return tab.title;
  }

  /// 切换分类标签
  void _onSelectTab(_DiscoveryTab tab) {
    if (_loading) return;
    if (_selectedTab?.url == tab.url && _selectedTab?.title == tab.title) {
      return;
    }
    setState(() {
      _selectedTab = tab;
      _items = [];
    });
    _loadDiscovery(page: 1);
  }

  /// 点击媒体卡片跳转至详情
  void _onItemTap(_MediaItem item) {
    context.push('/rule_detail', extra: {
      'title': item.title,
      'url': item.url,
      'cover': item.cover,
      'rule': widget.rule,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.rule.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Text(
              '${widget.rule.type.toUpperCase()} · 发现推荐',
              style: TextStyle(
                fontSize: 11,
                color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: _isGridView ? '切换为列表视图' : '切换为网格视图',
            icon: Icon(_isGridView ? LucideIcons.list : LucideIcons.layoutGrid),
            onPressed: () {
              setState(() {
                _isGridView = !_isGridView;
              });
            },
          ),
          IconButton(
            tooltip: '在此源中搜索',
            icon: const Icon(LucideIcons.search),
            onPressed: () {
              context.push('/search', extra: {'rule': widget.rule});
            },
          ),
          IconButton(
            tooltip: '刷新',
            icon: const Icon(LucideIcons.refreshCw),
            onPressed: () => _loadDiscovery(page: 1),
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部横向分类栏 (若规则提供了 tabs)
          if (_tabs.isNotEmpty) _buildTabsBar(isDark),

          // 主数据内容展示区
          Expanded(
            child: _buildBody(isDark),
          ),
        ],
      ),
    );
  }

  /// 构建横向分类滚动栏
  Widget _buildTabsBar(bool isDark) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkSurface : AppColors.lightSurface,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.5,
          ),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _tabs.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final tab = _tabs[index];
          final isSelected = _selectedTab?.url == tab.url && _selectedTab?.title == tab.title;

          return ChoiceChip(
            label: Text(tab.title),
            selected: isSelected,
            selectedColor: AppColors.primary.withValues(alpha: 0.16),
            labelStyle: TextStyle(
              fontSize: 12,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
            ),
            side: BorderSide(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (_) => _onSelectTab(tab),
          );
        },
      ),
    );
  }

  /// 构建主视图主体内容
  Widget _buildBody(bool isDark) {
    if (_loading && _items.isEmpty) {
      return const Center(
        child: LoadingIndicator(message: '正在调用沙箱加载发现内容...'),
      );
    }

    if (_error != null && _items.isEmpty) {
      return Center(
        child: EmptyState(
          icon: LucideIcons.alertTriangle,
          title: '发现流加载失败',
          description: _error,
          actionText: '重新加载',
          onAction: () => _loadDiscovery(page: 1),
        ),
      );
    }

    if (_items.isEmpty) {
      return Center(
        child: EmptyState(
          icon: LucideIcons.inbox,
          title: '暂无发现内容',
          description: '当前规则未返回任何推荐项目',
          actionText: '刷新重试',
          onAction: () => _loadDiscovery(page: 1),
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () => _loadDiscovery(page: 1),
      child: _isGridView ? _buildGridView(isDark) : _buildListView(isDark),
    );
  }

  bool get _isVideoRule {
    final t = widget.rule.type.toLowerCase().trim();
    return t == 'video' || t == 'tv' || t == 'movie' || t == 'anime' || t == 'short' || t.isEmpty;
  }

  /// 网格海报视图
  Widget _buildGridView(bool isDark) {
    final isVideo = _isVideoRule;
    return GridView.builder(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: isVideo ? 1.12 : 0.72,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: _items.length + (_loadingMore || _hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return _buildLoadingMoreFooter();
        }
        final item = _items[index];
        return isVideo ? _buildVideoGridCard(item, isDark) : _buildPortraitGridCard(item);
      },
    );
  }

  /// 列表紧凑视图
  Widget _buildListView(bool isDark) {
    final isVideo = _isVideoRule;
    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: _items.length + (_loadingMore || _hasMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == _items.length) {
          return _buildLoadingMoreFooter();
        }
        final item = _items[index];
        return isVideo ? _buildVideoListCard(item, isDark) : _buildPortraitListCard(item);
      },
    );
  }

  /// 单条横屏视频网格卡片（顶部 16:9 封面，宽大于高）
  Widget _buildVideoGridCard(_MediaItem item, bool isDark) {
    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      onTap: () => _onItemTap(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部 16:9 横屏视频封面（宽大于高）
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(
                    imageUrl: item.cover,
                    fit: BoxFit.cover,
                    headers: widget.rule.baseUrl.isNotEmpty ? {'referer': widget.rule.baseUrl} : null,
                  ),
                  // 底部轻度渐变微遮罩
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 28,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ),
                  // 角标 (如更新集数、清晰度等)
                  if (item.badge.isNotEmpty)
                    Positioned(
                      right: 6,
                      bottom: 5,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.badge,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // 底部标题与描述
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      height: 1.25,
                    ),
                  ),
                  if (item.desc.isNotEmpty)
                    Text(
                      item.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单条竖版海报网格卡片（适用于图集、漫画等）
  Widget _buildPortraitGridCard(_MediaItem item) {
    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      onTap: () => _onItemTap(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
            // 海报封面
            NetImage(
              imageUrl: item.cover,
              fit: BoxFit.cover,
              headers: widget.rule.baseUrl.isNotEmpty ? {'referer': widget.rule.baseUrl} : null,
            ),
            // 底部渐变暗色遮罩
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0.5, 1.0],
                  ),
                ),
              ),
            ),
            // 角标 (若有)
            if (item.badge.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.badge,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            // 底部标题与描述
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (item.desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
    );
  }

  /// 单条横屏视频列表卡片（缩略图 140x80，宽大于高）
  Widget _buildVideoListCard(_MediaItem item, bool isDark) {
    return AppCard(
      padding: const EdgeInsets.all(8),
      borderRadius: 12,
      onTap: () => _onItemTap(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 横屏 16:9 视频缩略图（宽大于高）
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 140,
              height: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(
                    imageUrl: item.cover,
                    fit: BoxFit.cover,
                    headers: widget.rule.baseUrl.isNotEmpty ? {'referer': widget.rule.baseUrl} : null,
                  ),
                  if (item.badge.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          item.badge,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 80,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          height: 1.25,
                        ),
                      ),
                      if (item.desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          widget.rule.name,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const Icon(LucideIcons.playCircle, size: 16, color: AppColors.primary),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 单条竖版海报列表卡片（适用于图集、漫画等）
  Widget _buildPortraitListCard(_MediaItem item) {
    return AppCard(
      padding: const EdgeInsets.all(10),
      borderRadius: 12,
      onTap: () => _onItemTap(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 90,
                  height: 120,
                  child: NetImage(
                    imageUrl: item.cover,
                    fit: BoxFit.cover,
                    headers: widget.rule.baseUrl.isNotEmpty ? {'referer': widget.rule.baseUrl} : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 120,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (item.desc.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              item.desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (item.badge.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.badge,
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Icon(LucideIcons.chevronRight, size: 18, color: Colors.grey),
            ],
          ),
    );
  }

  /// 底部加载状态指示
  Widget _buildLoadingMoreFooter() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: _loadingMore
            ? const LoadingIndicator.compact(size: 20)
            : const Text(
                '没有更多内容了',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
      ),
    );
  }
}
