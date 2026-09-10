import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../services/di.dart';
import '../../services/favorite_service.dart';
import '../../widgets/app_card.dart';
import '../../widgets/empty_state.dart';
import '../detail/media_detail_page.dart';

/// 我的收藏与智能追更中心页面 (FavoritesPage)
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String _selectedFilter = 'all'; // 'all' | 'video' | 'novel' | 'picture'
  bool _isCheckingUpdates = false;

  @override
  void initState() {
    super.initState();
    _seedSampleIfEmpty();
  }

  /// 若首次使用且收藏为空，预置两条高质感示例条目，便于立即体验追更微胶囊红点机制
  void _seedSampleIfEmpty() {
    if (favoriteService.favorites.isEmpty) {
      favoriteService.addFavorite(
        FavoriteItem(
          id: 'sample_video_1',
          title: '凡人修仙传 重置版',
          cover: 'https://images.unsplash.com/photo-1534447677768-be436bb09401?w=400&fit=crop&q=80',
          mediaType: 'video',
          lastEpisode: '第112集',
          latestEpisode: '第113集',
          hasUpdate: true,
          updatedAt: DateTime.now(),
        ),
      );
      favoriteService.addFavorite(
        FavoriteItem(
          id: 'sample_novel_1',
          title: '三体 · 死神永生',
          cover: 'https://images.unsplash.com/photo-1512820790803-83ca734da794?w=400&fit=crop&q=80',
          mediaType: 'novel',
          lastEpisode: '第32章',
          latestEpisode: '第33章 阶梯计划',
          hasUpdate: true,
          updatedAt: DateTime.now(),
        ),
      );
    }
  }

  /// 执行智能追更检测
  Future<void> _checkUpdates() async {
    setState(() => _isCheckingUpdates = true);
    HapticFeedback.lightImpact();

    final count = await favoriteService.checkUpdates();
    if (mounted) {
      setState(() => _isCheckingUpdates = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(count > 0 ? '检测到 $count 部作品有更新！' : '当前所有收藏均已是最新进度'),
        ),
      );
    }
  }

  IconData _getTypeIcon(String mediaType) {
    switch (mediaType.toLowerCase()) {
      case 'video':
      case 'tv':
      case 'movie':
        return LucideIcons.film;
      case 'novel':
      case 'book':
        return LucideIcons.bookOpen;
      case 'comic':
      case 'picture':
      case 'gallery':
        return LucideIcons.image;
      default:
        return LucideIcons.bookmark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text('我的收藏与追更', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        actions: [
          _isCheckingUpdates
              ? const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    ),
                  ),
                )
              : IconButton(
                  tooltip: '检查全量追更',
                  icon: const Icon(LucideIcons.refreshCw),
                  onPressed: _checkUpdates,
                ),
        ],
      ),
      body: ValueListenableBuilder<List<FavoriteItem>>(
        valueListenable: favoriteService.favoritesNotifier,
        builder: (context, favorites, _) {
          final filtered = favorites.where((item) {
            if (_selectedFilter == 'all') return true;
            return item.mediaType == _selectedFilter;
          }).toList();

          return Column(
            children: [
              // 顶部类型过滤筛选 Tag
              _buildFilterBar(isDark),

              // 收藏列表
              Expanded(
                child: filtered.isEmpty
                    ? const EmptyState(
                        icon: LucideIcons.bookmark,
                        title: '暂无收藏条目',
                        description: '在浏览影视、小说或画廊时点击收藏，享受智能追更提醒',
                      )
                    : RefreshIndicator(
                        onRefresh: _checkUpdates,
                        color: AppColors.primary,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            return _buildFavoriteCard(context, item, isDark);
                          },
                        ),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFilterBar(bool isDark) {
    final filters = [
      {'key': 'all', 'label': '全部'},
      {'key': 'video', 'label': '影视'},
      {'key': 'novel', 'label': '小说'},
      {'key': 'comic', 'label': '漫画/图集'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f['key'];
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ChoiceChip(
              label: Text(f['label']!),
              selected: isSelected,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : (isDark ? Colors.white70 : Colors.black87),
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              side: BorderSide(
                color: isSelected ? AppColors.primary : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
              ),
              onSelected: (val) {
                if (val) setState(() => _selectedFilter = f['key']!);
              },
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFavoriteCard(BuildContext context, FavoriteItem item, bool isDark) {
    return AppCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      onTap: () {
        // 消除未读更新红点
        favoriteService.markAsRead(item.id);
        // 跳转详情分发
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (ctx) => MediaDetailPage(
              type: item.mediaType,
              title: item.title,
              cover: item.cover,
              url: item.id.startsWith('http') ? item.id : null,
            ),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面海报
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 64,
              height: 84,
              color: isDark ? Colors.white10 : Colors.black12,
              child: item.cover.isNotEmpty
                  ? Image.network(
                      item.cover,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Icon(_getTypeIcon(item.mediaType), color: Colors.grey, size: 24),
                      ),
                    )
                  : Center(
                      child: Icon(_getTypeIcon(item.mediaType), color: Colors.grey, size: 24),
                    ),
            ),
          ),
          const SizedBox(width: 12),

          // 核心详情
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                        ),
                      ),
                    ),
                    // 追更微胶囊角标
                    if (item.hasUpdate)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(LucideIcons.sparkles, color: Colors.white, size: 10),
                            const SizedBox(width: 3),
                            Text(
                              'NEW · ${item.latestEpisode.isNotEmpty ? item.latestEpisode : "有更新"}',
                              style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '上次看到：${item.lastEpisode.isNotEmpty ? item.lastEpisode : "暂无进度"}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '最新更新：${item.latestEpisode.isNotEmpty ? item.latestEpisode : "与源站保持同步"}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),

          // 右侧取消收藏按钮
          IconButton(
            icon: const Icon(LucideIcons.trash2, size: 16, color: Colors.grey),
            onPressed: () {
              favoriteService.removeFavorite(item.id);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已从收藏中移除')),
              );
            },
          ),
        ],
      ),
    );
  }
}
