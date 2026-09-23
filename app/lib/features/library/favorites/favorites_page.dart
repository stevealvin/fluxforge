import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';

import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/core/utils/media_utils.dart';
import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
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
                  child: GridView.builder(
                    // 显式 padding 会**覆盖**滚动组件的自动 padding：本页是底部导航
                    // 的一个 Tab，必须自己留出底部栏高度，否则最后一行会被毛玻璃压住。
                    // （extendBody 时 Scaffold 已把底部栏高度注入 MediaQuery.padding）
                    padding: EdgeInsets.fromLTRB(
                      16,
                      8,
                      16,
                      8 + MediaQuery.paddingOf(context).bottom,
                    ),
                    // 每行 4 个：单元格变窄后封面比例仍锁定 2:3（宽高同比缩小），
                    // 故高宽比要跟着放大到约 1/0.42
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 14,
                          // 封面(2:3) + 两行标题 + 进度行（可选更新行）的高度比；
                          // 封面用 Expanded 吃掉文字之外的余量，文字行数变化不会溢出
                          childAspectRatio: 0.42,
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

  /// 单个收藏卡（书架式：封面为主角，下方标题 / 进度 / 更新）
  ///
  /// 封面占满卡宽、2:3 海报比例 —— 收藏是「我的书架」，封面才是识别物的主体。
  ///
  /// 「有更新」的信号收敛为**两处、分工不同**：封面左上角小角标（扫列表时第一眼
  /// 可见）+ 下方「更新至」行（读得出具体集数）。此前是封面左竖条 + NEW 胶囊 +
  /// 主色文字，三处说同一件事，等于噪声。
  Widget _buildFavoriteCard(
    BuildContext context,
    FavoriteItem item,
    bool isDark,
  ) {
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final hasUpdate = item.hasUpdate;

    return GestureDetector(
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
      // 网格里放不下垃圾桶按钮，且左上 / 左下角已被角标占用 —— 移除改长按。
      // 仍是低风险操作，故照旧走「可撤销」而不是二次确认。
      onLongPress: () => _removeWithUndo(context, item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 封面（主角）：吃掉网格单元里除文字外的全部高度
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
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
                            size: 26,
                          ),
                        ),
                  // 左上角：有更新（扫描信号，与封面左上圆弧呼应，故不做完整圆角）
                  if (hasUpdate)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2.5,
                        ),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(14),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        child: const Text(
                          'NEW',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ),
                  // 左下角：类型标签（筛选栏按类型分，卡片必须能对上，否则自相矛盾）
                  Positioned(
                    left: 6,
                    bottom: 6,
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
          const SizedBox(height: 8),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              height: 1.25,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          // 进度是「我的位置」，也是这一页真正要回答的问题，故用主文本色
          Text(
            '上次看到：${_progressLabel(item)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: textPrimary),
          ),
          // 无更新时不占这一行：源站最新集在没有新内容时没有信息量
          if (hasUpdate) ...[
            const SizedBox(height: 2),
            Text(
              '更新至：${item.latestEpisode.isNotEmpty ? item.latestEpisode : "有更新"}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
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
