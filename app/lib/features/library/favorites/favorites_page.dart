import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/utils/media_utils.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/shared/widgets/app_card.dart';
import 'package:fluxforge/shared/widgets/app_empty_state.dart';
import 'package:fluxforge/shared/widgets/app_image.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';
import 'package:fluxforge/features/media/shared/media_detail_page.dart';
import 'package:fluxforge/features/media/shared/media_favorite_actions.dart';

/// 我的收藏与智能追更中心页面 (FavoritesPage)
///
/// 全页只有两个真实数据来源，职责不重叠：
/// - 收藏库 [favoriteService] —— 条目本身与「源站最新集」；
/// - 消费记录 [playHistoryService] —— **真实进度**。「上次看到」一律以此为准，
///   收藏项里的 `lastEpisode` 只在导入备份 / 确实没有进度时兜底；
///   打开详情页也**只清红点**，不改写进度（见 [FavoriteService.markAsRead]）。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

class _FavoritesPageState extends State<FavoritesPage> {
  String _selectedFilter = 'all'; // 'all' | 'video' | 'novel' | 'comic'
  bool _isCheckingUpdates = false;

  /// 卡片上展示的「上次看到」
  String _progressLabel(FavoriteItem item) {
    final label = MediaFavoriteActions.progressOf(item);
    return label.isNotEmpty ? label : '暂无进度';
  }

  /// 执行智能追更检测（手动刷新时全量探测源站，含单项失败容错）
  Future<void> _checkUpdates() async {
    if (_isCheckingUpdates) return;
    setState(() => _isCheckingUpdates = true);
    HapticFeedback.lightImpact();

    final count = await favoriteService.checkUpdates(
      probe: MediaFavoriteActions.probeLatest,
      progressOf: MediaFavoriteActions.progressOf,
    );
    if (!mounted) return;
    setState(() => _isCheckingUpdates = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(count > 0 ? '检测到 $count 部作品有更新！' : '当前所有收藏均已是最新进度'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        title: const Text(
          '我的收藏与追更',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        actions: [
          if (_isCheckingUpdates)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.primary,
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: '检查全量追更',
              icon: const Icon(Ionicons.refreshOutline),
              onPressed: _checkUpdates,
            ),
        ],
      ),
      // 收藏库与消费记录任一变化都要重绘：「上次看到」来自后者
      body: ValueListenableBuilder<List<FavoriteItem>>(
        valueListenable: favoriteService.favoritesNotifier,
        builder: (context, favorites, _) =>
            ValueListenableBuilder<List<PlayRecord>>(
              valueListenable: playHistoryService.recordsNotifier,
              builder: (context, _, _) =>
                  _buildContent(context, favorites, isDark),
            ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<FavoriteItem> favorites,
    bool isDark,
  ) {
    // 首次磁盘读取未完成前不渲染空态，避免「有收藏却先闪一下暂无收藏」
    if (!favoriteService.isLoaded) {
      return const Center(child: AppLoading(message: '正在读取本地收藏...'));
    }

    final filtered =
        favorites.where((item) {
            if (_selectedFilter == 'all') return true;
            return item.mediaType == _selectedFilter;
          }).toList()
          // 有更新的置顶，其次按最近更新时间
          ..sort((a, b) {
            if (a.hasUpdate != b.hasUpdate) return a.hasUpdate ? -1 : 1;
            return b.updatedAt.compareTo(a.updatedAt);
          });

    return Column(
      children: [
        _buildFilterBar(isDark),
        Expanded(
          child: filtered.isEmpty
              ? AppEmptyState(
                  icon: Ionicons.bookmarkOutline,
                  title: favorites.isEmpty ? '暂无收藏条目' : '该类型下暂无收藏',
                  description: favorites.isEmpty
                      ? '在影视、小说或漫画详情页点击右上角收藏，即可开启智能追更提醒'
                      : '切换到「全部」查看其它收藏，或去详情页收藏更多内容',
                )
              : RefreshIndicator(
                  onRefresh: _checkUpdates,
                  color: AppColors.primary,
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
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
  }

  Widget _buildFilterBar(bool isDark) {
    const filters = [
      {'key': 'all', 'label': '全部'},
      {'key': 'video', 'label': '影视'},
      {'key': 'novel', 'label': '小说'},
      {'key': 'comic', 'label': '漫画/图集'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final f in filters) ...[
            _buildFilterChip(f['key']!, f['label']!, isDark),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  /// 过滤胶囊：与「日志页 / 设置页」同一套自绘样式（Material ChoiceChip 在此前是孤例）
  Widget _buildFilterChip(String key, String label, bool isDark) {
    final isSelected = _selectedFilter == key;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.2)
              : (isDark
                    ? Colors.white.withValues(alpha: 0.05)
                    : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected
                ? AppColors.primary
                : (isDark ? Colors.grey : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildFavoriteCard(
    BuildContext context,
    FavoriteItem item,
    bool isDark,
  ) {
    return AppCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      borderRadius: 16,
      onTap: () {
        HapticFeedback.selectionClick();
        // 打开详情即视为「已知晓更新」，只清红点，不伪造观看进度
        favoriteService.markAsRead(item.id);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MediaDetailPage(
              type: item.mediaType,
              title: item.title,
              cover: item.cover,
              url: item.id.startsWith('http') ? item.id : '',
              // 绑定收藏时记录的规则：否则详情页只能靠 baseUrl host 反查，
              // 命中不了就会报「未指定对应解析规则」
              rule: MediaFavoriteActions.ruleOf(item),
            ),
          ),
        );
      },
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面海报（走统一图片组件：自带占位、失败兜底与缓存）
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 64,
              height: 84,
              child: item.cover.isNotEmpty
                  ? AppImage(imageUrl: item.cover, fit: BoxFit.cover)
                  : Container(
                      color: isDark ? Colors.white10 : Colors.black12,
                      child: Icon(
                        MediaDisplay.typeIcon(item.mediaType),
                        color: Colors.grey,
                        size: 24,
                      ),
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
                          color: isDark
                              ? AppColors.darkTextPrimary
                              : AppColors.lightTextPrimary,
                        ),
                      ),
                    ),
                    // 追更微胶囊角标
                    if (item.hasUpdate)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
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
                            const Icon(
                              Ionicons.sparklesOutline,
                              color: Colors.white,
                              size: 10,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'NEW · ${item.latestEpisode.isNotEmpty ? item.latestEpisode : "有更新"}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '上次看到：${_progressLabel(item)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.darkTextSecondary
                        : AppColors.lightTextSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '最新更新：${item.latestEpisode.isNotEmpty ? item.latestEpisode : "与源站保持同步"}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark
                        ? AppColors.darkTextMuted
                        : AppColors.lightTextMuted,
                  ),
                ),
              ],
            ),
          ),

          // 移除收藏：低风险操作，用「可撤销」代替二次确认
          IconButton(
            tooltip: '移除收藏',
            icon: const Icon(
              Ionicons.trashOutline,
              size: 16,
              color: Colors.grey,
            ),
            onPressed: () => _removeWithUndo(context, item),
          ),
        ],
      ),
    );
  }

  /// 移除收藏并提供撤销（相比二次确认，更适合这种可逆的轻量操作）
  Future<void> _removeWithUndo(BuildContext context, FavoriteItem item) async {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    await favoriteService.removeFavorite(item.id);

    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('已移除《${item.title}》'),
          action: SnackBarAction(
            label: '撤销',
            onPressed: () => favoriteService.addFavorite(item),
          ),
        ),
      );
  }
}
