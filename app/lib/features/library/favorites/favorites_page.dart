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
import 'package:fluxforge/shared/widgets/app_delete_snack_bar.dart';
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
        _buildFilterBar(favorites, isDark),
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

  Widget _buildFilterBar(List<FavoriteItem> favorites, bool isDark) {
    const filters = [
      {'key': 'all', 'label': '全部'},
      {'key': 'video', 'label': '影视'},
      {'key': 'novel', 'label': '小说'},
      {'key': 'comic', 'label': '漫画/图集'},
    ];

    // 每个类型带数量：否则用户只能一个个点进去、撞上空态才知道那一类没有内容
    int countOf(String key) => key == 'all'
        ? favorites.length
        : favorites.where((f) => f.mediaType == key).length;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final f in filters) ...[
            _buildFilterChip(
              f['key']!,
              f['label']!,
              countOf(f['key']!),
              isDark,
            ),
            const SizedBox(width: 6),
          ],
        ],
      ),
    );
  }

  /// 过滤胶囊：与「日志页 / 设置页」同一套自绘样式（Material ChoiceChip 在此前是孤例）
  ///
  /// 末尾带该类型的数量：数量为 0 的胶囊自动降淡，用户不必点进去才发现是空的。
  Widget _buildFilterChip(String key, String label, int count, bool isDark) {
    final isSelected = _selectedFilter == key;
    final isEmpty = count == 0;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _selectedFilter = key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? Colors.grey : Colors.black87),
              ),
            ),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? AppColors.primary
                    : (isDark ? Colors.grey : Colors.black87).withValues(
                        alpha: isEmpty ? 0.4 : 0.75,
                      ),
              ),
            ),
          ],
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
              // 原样传入原文地址：拼接 baseUrl 是规则代码自己的职责，
              // App 侧不要替它补全，否则规则会再拼一次，变成两份 baseUrl。
              url: item.url,
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
          //
          // 叠两样东西：左下角**类型标签**（此前类型只能靠封面猜，而上面筛选栏
          // 正是按类型分的，自相矛盾）、左侧**主色竖条**（有更新时列表里一眼可辨，
          // 不必逐个读胶囊）。两者都在封面内，不影响右侧文字排版。
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 66,
              height: 88,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  item.cover.isNotEmpty
                      ? AppImage(imageUrl: item.cover, fit: BoxFit.cover)
                      : Container(
                          color: isDark ? Colors.white10 : Colors.black12,
                          child: Icon(
                            MediaDisplay.typeIcon(item.mediaType),
                            color: Colors.grey,
                            size: 24,
                          ),
                        ),
                  if (item.hasUpdate)
                    const Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: SizedBox(
                        width: 3,
                        child: ColoredBox(color: AppColors.primary),
                      ),
                    ),
                  Positioned(
                    left: 4,
                    bottom: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        MediaDisplay.typeLabel(item.mediaType),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
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
                // 两行对照：看过的进度是「我的位置」，字重更重；源站最新是参考信息，次要
                Text(
                  '上次看到：${_progressLabel(item)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: isDark
                        ? AppColors.darkTextPrimary
                        : AppColors.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '最新更新：${item.latestEpisode.isNotEmpty ? item.latestEpisode : "与源站保持同步"}',
                  style: TextStyle(
                    fontSize: 11,
                    color: item.hasUpdate
                        ? AppColors.primary
                        : (isDark
                              ? AppColors.darkTextMuted
                              : AppColors.lightTextMuted),
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
    await favoriteService.removeFavorite(item.id);
    if (!context.mounted) return;

    showDeleteSnackBar(
      context,
      message: '已移除《${item.title}》',
      onUndo: () => favoriteService.addFavorite(item),
    );
  }
}
