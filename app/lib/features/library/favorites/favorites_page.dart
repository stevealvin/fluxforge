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
import 'package:fluxforge/shared/widgets/filter_pill_bar.dart';
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
        // 筛选条直接占顶栏：底部导航已经写着「收藏」，再放一遍页名是重复，
        // 省下的整行留给列表。
        //
        // 刷新入口一并撤掉 —— 它本来就与下拉刷新重复（[RefreshIndicator] 走同一个
        // [_checkUpdates]），而追更检查是低频动作，不值得常驻一个按钮。
        titleSpacing: 10,
        title: ValueListenableBuilder<List<FavoriteItem>>(
          valueListenable: favoriteService.favoritesNotifier,
          builder: (context, favorites, _) => FilterPillBar(
            items: _filterItems(favorites),
            selectedKey: _selectedFilter,
            onSelected: (key) => setState(() => _selectedFilter = key),
          ),
        ),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
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

    return filtered.isEmpty
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
              // 显式 padding 会**覆盖**滚动组件的自动 padding：本页是底部导航
              // 的一个 Tab，必须自己留出底部栏高度，否则最后一条会被毛玻璃压住。
              // （extendBody 时 Scaffold 已把底部栏高度注入 MediaQuery.padding）
              padding: EdgeInsets.fromLTRB(
                16,
                6,
                16,
                8 + MediaQuery.paddingOf(context).bottom,
              ),
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                return _buildFavoriteCard(context, item, isDark);
              },
            ),
          );
  }

  /// 收藏页的筛选项
  ///
  /// 本页「漫画」与「图集」同属一类，故 label 写「漫画/图集」；数量为 0 的类型
  /// 仍列出来（降淡）—— 用户不必点进去才发现那一类是空的。
  List<FilterPillItem> _filterItems(List<FavoriteItem> favorites) {
    const defs = [
      ('all', '全部'),
      ('video', '影视'),
      ('novel', '小说'),
      ('comic', '漫画/图集'),
    ];

    int countOf(String key) => key == 'all'
        ? favorites.length
        : favorites.where((f) => f.mediaType == key).length;

    return [
      for (final (key, label) in defs)
        FilterPillItem(key: key, label: label, count: countOf(key)),
    ];
  }

  /// 单个收藏卡（横向：左封面 + 右信息）
  ///
  /// 封面固定 84×126（2:3）靠左，信息靠右 —— 一条占一整行后，「上次看到 / 更新至」
  /// 不必再挤成两行小字，扫读更快，标题也放得下两行。
  ///
  /// 「有更新」的信号仍是**两处、分工不同**：封面左上角 NEW 角标（扫列表第一眼可见）
  /// + 「更新至」行（读得出具体集数）。
  Widget _buildFavoriteCard(
    BuildContext context,
    FavoriteItem item,
    bool isDark,
  ) {
    final textPrimary = isDark
        ? AppColors.darkTextPrimary
        : AppColors.lightTextPrimary;
    final muted = isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted;
    final hasUpdate = item.hasUpdate;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(10),
        borderRadius: 16,
        onTap: () => _openDetail(context, item),
        // 移除入口收进长按面板；面板里「移除收藏」仍是低风险操作，
        // 故照旧走「可撤销」而不是二次确认（见 [_showFavoriteActionsSheet]）
        onLongPress: () => _showFavoriteActionsSheet(context, item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面（2:3）
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                width: 84,
                height: 126,
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
                              topLeft: Radius.circular(12),
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
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // 右侧信息
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
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                            color: textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // 类型标签从封面挪到标题同行：筛选栏正是按类型分的，
                      // 卡片必须能对上；放右侧后也不必再往图上压一层深色底
                      Container(
                        margin: const EdgeInsets.only(top: 2),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          MediaDisplay.typeLabel(item.mediaType),
                          style: TextStyle(fontSize: 10, color: muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 进度是「我的位置」，也是这一页真正要回答的问题，故用主文本色
                  _buildInfoLine(
                    icon: Ionicons.timeOutline,
                    text: '上次看到：${_progressLabel(item)}',
                    color: textPrimary,
                    iconColor: muted,
                  ),
                  // 无更新时不占这一行：源站最新集在没有新内容时没有信息量
                  if (hasUpdate) ...[
                    const SizedBox(height: 4),
                    _buildInfoLine(
                      icon: Ionicons.sparklesOutline,
                      text:
                          '更新至：${item.latestEpisode.isNotEmpty ? item.latestEpisode : "有更新"}',
                      color: AppColors.primary,
                      iconColor: AppColors.primary,
                      bold: true,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 卡片里的一行「图标 + 文案」
  ///
  /// 进度与更新共用同一个实现，保证两行左边缘与图标尺寸一致 —— 各写一遍必然会漂。
  Widget _buildInfoLine({
    required IconData icon,
    required String text,
    required Color color,
    required Color iconColor,
    bool bold = false,
  }) {
    return Row(
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// 打开详情（唯一的入口是**点击卡片**）
  ///
  /// 清红点、不改写进度；原文地址与绑定规则都原样传下去。
  void _openDetail(BuildContext context, FavoriteItem item) {
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
  }

  /// 长按卡片弹出的面板（移除收藏）
  ///
  /// 此前是「长按即移除」：那个手势**没有任何可见入口** —— 想移除时找不到，
  /// 不想移除时又容易误触，所以保留一层「先弹面板把动作摆出来」。
  /// 面板里**不再放「查看详情」**：那和点击卡片完全同一条路径（同一个
  /// [_openDetail]），摆在这里只是把同一件事说两遍。
  /// 移除不做二次确认，后悔的代价交给移除后的 5 秒撤销提示（见 [_removeWithUndo]）。
  void _showFavoriteActionsSheet(BuildContext context, FavoriteItem item) {
    HapticFeedback.selectionClick();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部小横条
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // 面板标题：条目名（写不下就省略，不换行撑高面板）
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Ionicons.trashOutline,
                    size: 20,
                    color: AppColors.danger,
                  ),
                  title: const Text(
                    '移除收藏',
                    style: TextStyle(fontSize: 14, color: AppColors.danger),
                  ),
                  onTap: () {
                    Navigator.pop(sheetCtx);
                    _removeWithUndo(context, item);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
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
