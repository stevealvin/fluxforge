import 'dart:ui' as ui;

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
///   打开详情页也**只清红点**，不改写进度（见 [FavoriteService.markOpened]）。
class FavoritesPage extends StatefulWidget {
  const FavoritesPage({super.key});

  @override
  State<FavoritesPage> createState() => _FavoritesPageState();
}

/// 卡片与封面的统一圆角（同一份取值：封面左侧两角要与卡片外沿重合）
const double _cardRadius = 12;

/// 封面区宽度（左列固定宽）
const double _coverWidth = 160;

/// 封面区高度 —— **它同时就是整张卡片的高度**
///
/// 108 是信息区最满时（两行标题 + 进度 + 更新至）排下来的高度：封面是标尺，
/// 信息区只能在这块地方里排版，不许反过来把文字撑高卡片。
///
/// 这里**故意不把封面框锁成 16:9**：宽图按 16:9 完整显示（160×90）后，上下
/// 各 9px 的余量交给模糊版补；竖图则铺满高度、左右补 —— 两种封面都不裁。
const double _coverHeight = 108;

/// 模糊补边层的解码宽度：只贡献色彩与层次，解小图即可
const int _coverBlurCacheWidth = 168;

/// 清晰封面层：宽图满幅时 160dp 宽，按 3x 屏取 480
const int _coverCacheWidth = 480;

/// 收藏列表的排序方式（顶栏右上角切换，默认最近观看）
enum _FavoriteSortMode {
  /// 最近观看：按 [FavoriteItem.lastActiveAt] 倒序
  ///
  /// 「最近活动」= **点击进入详情**（见 [FavoriteService.markOpened]），
  /// 刻意不做更细的播放 / 阅读进度打点。
  recentActivity,

  /// 收藏时间：按 [FavoriteItem.updatedAt] 倒序
  favoritedAt,
}

class _FavoritesPageState extends State<FavoritesPage> {
  String _selectedFilter = 'all'; // 'all' | 'video' | 'novel' | 'comic'
  bool _isCheckingUpdates = false;

  // 默认「最近观看」：这一页回答的是"我最近在追什么"，收藏时间只是备选视角。
  // 刻意不持久化 —— 每次进入本页都回到默认，免得上次的切换变成一个
  // 说不清来历的顺序。
  _FavoriteSortMode _sortMode = _FavoriteSortMode.recentActivity;

  /// 卡片上展示的「上次看到」
  String _progressLabel(FavoriteItem item) {
    final label = MediaFavoriteActions.progressOf(item);
    return label.isNotEmpty ? label : '暂无进度';
  }

  /// 切换排序方式：最近观看 ⇄ 收藏时间
  ///
  /// 切完给一条短提示 —— 顺序变化不一定看得出来（尤其收藏少的时候），
  /// 提示把"刚刚发生了什么"讲明白。
  void _toggleSortMode() {
    HapticFeedback.selectionClick();
    setState(() {
      _sortMode = _sortMode == _FavoriteSortMode.recentActivity
          ? _FavoriteSortMode.favoritedAt
          : _FavoriteSortMode.recentActivity;
    });

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          duration: const Duration(milliseconds: 1200),
          content: Text(
            _sortMode == _FavoriteSortMode.recentActivity
                ? '已按最近观看排序'
                : '已按收藏时间排序',
          ),
        ),
      );
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
        // 左侧页名 + 中间筛选条：筛选是这一页的主操作，居中比贴着左边更好按，
        // 也给"这是哪一页"留一个锚点。
        //
        // 刷新入口仍然不恢复 —— 它本来就与下拉刷新重复（[RefreshIndicator] 走同一个
        // [_checkUpdates]），而追更检查是低频动作，不值得常驻一个按钮。
        titleSpacing: 12,
        title: Row(
          children: [
            const Text(
              '收藏',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: ValueListenableBuilder<List<FavoriteItem>>(
                  valueListenable: favoriteService.favoritesNotifier,
                  builder: (context, favorites, _) => FilterPillBar(
                    items: _filterItems(favorites),
                    selectedKey: _selectedFilter,
                    onSelected: (key) => setState(() => _selectedFilter = key),
                  ),
                ),
              ),
            ),
          ],
        ),
        backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
        elevation: 0,
        // 排序切换放右上角：两个视角互相替补 —— 「最近观看」看追更动线，
        // 「收藏时间」找回刚收的作品。用文字而不是图标，因为图标表达不出这两者。
        actions: [
          TextButton.icon(
            onPressed: _toggleSortMode,
            icon: Icon(
              _sortMode == _FavoriteSortMode.recentActivity
                  ? Ionicons.timeOutline
                  : Ionicons.bookmarkOutline,
              size: 15,
              color: AppColors.primary,
            ),
            label: Text(
              _sortMode == _FavoriteSortMode.recentActivity ? '最近观看' : '收藏时间',
              style: const TextStyle(fontSize: 12.5, color: AppColors.primary),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 4),
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
          // 两级：有更新的整批置顶（追更信号比顺序重要），组内按当前排序方式。
          // 注意组内键不是"收藏时间"—— 那是 [_FavoriteSortMode.favoritedAt]
          // 这一档才用的；默认档看的是"最近活动"。
          ..sort((a, b) {
            if (a.hasUpdate != b.hasUpdate) return a.hasUpdate ? -1 : 1;
            return switch (_sortMode) {
              _FavoriteSortMode.recentActivity => b.lastActiveAt.compareTo(
                a.lastActiveAt,
              ),
              _FavoriteSortMode.favoritedAt => b.updatedAt.compareTo(
                a.updatedAt,
              ),
            };
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
  /// 封面区固定 160×108 靠左，信息靠右 —— 一条占一整行后，「上次看到 / 更新至」
  /// 不必再挤成两行小字，扫读更快，标题也放得下两行。
  ///
  /// **卡片高度 = 封面高度**：封面是标尺，信息区只在这块地方里排版
  /// （纵向居中），不去撑高卡片 —— 所以每张卡的高度都一致，不随标题长短参差。
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
        // 封面贴边：卡片自己不留内边距，封面直接吃满左侧与上下沿
        // （内边距由右侧信息区自己控制）
        padding: EdgeInsets.zero,
        // 圆角收小一档：单列卡片本身就不宽，16 的角在列表里显得过于圆润
        borderRadius: 12,
        onTap: () => _openDetail(context, item),
        // 移除入口收进长按面板；面板里「移除收藏」仍是低风险操作，
        // 故照旧走「可撤销」而不是二次确认（见 [_showFavoriteActionsSheet]）
        onLongPress: () => _showFavoriteActionsSheet(context, item),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面区（左列 16:9）：宽封面满幅、竖封面左右模糊补边
            _buildCoverArea(item, isDark, hasUpdate),

            // 信息区：普通底色。模糊补边在封面区内 —— 文字区不垫模糊图，
            // 也就不存在"花底压字"的对比度问题。
            Expanded(
              child: Padding(
                // 纵向留白略小于横向：卡片高度由封面（108）决定，这两像素是从
                // 纵向抠出来给"两行标题 + 更新行"的最满排版的，横向不必让
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  // 纵向居中：卡片高度由封面（16:9）决定，信息比它矮时居中才不显得吊在顶上
                  mainAxisAlignment: MainAxisAlignment.center,
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
            ),
          ],
        ),
      ),
    );
  }

  /// 封面区（左列 160×108）：一条实现同时伺候两种封面
  ///
  /// - **视频封面**是 16:9 → `contain` 后 160×90，上下各 9px 由模糊版补；
  /// - **小说 / 图集 / 漫画的 2:3 竖封面** → `contain` 后 72×108，左右由模糊版补。
  ///
  /// 两张都走 `contain`、零裁切，缺的那条边一律由**同一张封面**的模糊版补上，
  /// 颜色与清晰图天然衔接。封面区尺寸固定，卡片高度才整齐。
  Widget _buildCoverArea(FavoriteItem item, bool isDark, bool hasUpdate) {
    return SizedBox(
      width: _coverWidth,
      height: _coverHeight,
      // 四角同半径：左侧两角与卡片外沿重合（被卡片裁掉，看不出接缝），
      // 右侧两角真的把圆角露出来 —— 封面与信息区之间不再是直角切口
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_cardRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (item.cover.isNotEmpty) ...[
              _buildCoverBlurLayer(item, isDark),
              // 完整封面居中：不做裁切，缺的那条边由下面的模糊层补
              AppImage(
                imageUrl: item.cover,
                fit: BoxFit.contain,
                cacheWidth: _coverCacheWidth,
              ),
            ] else
              // 没有封面时无图可模糊：退到类型图标，至少留一块可辨识的底色
              Container(
                color: isDark ? Colors.white10 : Colors.black12,
                child: Center(
                  child: Icon(
                    MediaDisplay.typeIcon(item.mediaType),
                    color: Colors.grey,
                    size: 26,
                  ),
                ),
              ),

            // 左上角：有更新（与卡片左上圆弧呼应，故不做完整圆角）
            if (hasUpdate)
              Positioned(
                left: 0,
                top: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2.5,
                  ),
                  decoration: BoxDecoration(
                    // 半透明底：与详情页封面上的规则来源角标同一档（75%），
                    // 压住封面底图的同时仍透出一层，不像实底那样糊住画面
                    color: AppColors.primary.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(_cardRadius),
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
    );
  }

  /// 封面模糊补边层：同一张封面放大模糊，再压一层暗遮罩
  ///
  /// 模糊层只贡献色彩与层次，故解小图即可（长列表里不必按原图解码）；
  /// 遮罩是必须的 —— 不压暗的话，补边那块会比中间的清晰图更抢眼。
  Widget _buildCoverBlurLayer(FavoriteItem item, bool isDark) {
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: AppImage(
              imageUrl: item.cover,
              fit: BoxFit.cover,
              cacheWidth: _coverBlurCacheWidth,
              // 加载中 / 失败都不画东西，避免封面区闪一个转圈
              placeholder: const SizedBox.shrink(),
              errorWidget: const SizedBox.shrink(),
            ),
          ),
          ColoredBox(
            color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.35),
          ),
        ],
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
  /// 清红点、记一次「最近活动」（排序用），且不改写观看进度；
  /// 原文地址与绑定规则都原样传下去。
  void _openDetail(BuildContext context, FavoriteItem item) {
    HapticFeedback.selectionClick();
    // 「最近活动」就按"点击进入"算，不做更细的进度打点；
    // 顺带清红点，但绝不改写「上次看到」（那是消费记录的职责）
    favoriteService.markOpened(item.id);
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
