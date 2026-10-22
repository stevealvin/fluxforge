import 'dart:async';

import 'package:flutter/services.dart';
import 'package:ionicons/ionicons.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/di/di.dart';
import 'package:fluxforge/app/router/app_navigator.dart';
import 'package:fluxforge/app/theme/app_colors.dart';
import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/features/discover/controllers/discover_session.dart';
import 'package:fluxforge/features/discover/engines/discover_aggregator.dart';
import 'package:fluxforge/features/discover/models/discover_item.dart';
import 'package:fluxforge/features/discover/widgets/discover_channel_bar.dart';
import 'package:fluxforge/features/discover/widgets/discover_grid.dart';
import 'package:fluxforge/features/discover/widgets/discover_hero_carousel.dart';
import 'package:fluxforge/shared/widgets/app_loading.dart';

/// 发现页：跨源内容聚合（类型为主轴，规则源退到后台）
///
/// ### 与旧版的根本差别
/// 旧版是「列出所有规则源、逐个切换看它的内容」—— 本质是个**规则浏览器**。
/// 现版把导航主轴换成**媒体类型**（影视 / 小说 / 漫画 / 图集）：
/// 进入页面即并发向多个启用源拉取内容、跨源去重后合并成一条流，
/// 用户面对的是「一堆内容」而不是「一堆源」。
///
/// ### 页面结构（自上而下）
/// 1. **沉浸式轮播**：各源推荐位各贡献一条（全出血，AppBar 透明叠在其上）；
/// 2. **频道段**：媒体类型切换，带各频道实际条目数；
/// 3. **频道副标题**：跨 N 个源聚合 · M 条，右侧显示聚合进度；
/// 4. **双列网格**：当前频道的条目（与轮播互斥，同一条不会两处都出现）。
///
/// 轮播与网格的取值、排序、去重全部在 [DiscoverSession] 与
/// [DiscoverAggregator] 里完成，页面只负责渲染。
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage>
    with AutomaticKeepAliveClientMixin {
  /// 跨源聚合会话：持有全部可变状态，页面只渲染
  late final DiscoverSession _session;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _session = DiscoverSession(
      resolveAllRules: () => ruleService.enabledRules,
    );
    // 规则集合变化（新增 / 启用 / 停用）后重新聚合
    ruleService.rulesNotifier.addListener(_onRulesChanged);
    unawaited(_session.load());
  }

  void _onRulesChanged() {
    if (!mounted) return;
    unawaited(_session.load());
  }

  @override
  void dispose() {
    ruleService.rulesNotifier.removeListener(_onRulesChanged);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      // 轮播全出血，AppBar 透明叠在其上（顶部暗色渐变保证浅色图标可读）
      extendBodyBehindAppBar: true,
      backgroundColor: isDark ? AppColors.darkBg : AppColors.lightBg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleSpacing: 0,
        title: Row(
          children: [
            Hero(
              tag: 'logo',
              child: Image.asset(
                'assets/icon/icon.png',
                width: 30,
                height: 30,
                errorBuilder: (_, _, _) =>
                    const Icon(Ionicons.flashOutline, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'FluxForge',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          // 收藏入口在底部导航栏的「收藏」Tab，不在此重复设置
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Ionicons.searchOutline, color: Colors.white),
            onPressed: () => context.pushSearch(),
          ),
          IconButton(
            tooltip: '规则市场',
            icon: const Icon(Ionicons.storefrontOutline, color: Colors.white),
            onPressed: () => context.pushMarket(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: AnimatedBuilder(
        animation: _session,
        builder: (context, _) {
          if (ruleService.enabledRules.isEmpty) {
            return _buildEmptyRuleState(isDark);
          }
          return Column(
            children: [
              // 1. 沉浸式轮播（延伸到 AppBar 后面）
              DiscoverHeroCarousel(
                isDark: isDark,
                items: _session.heroPool,
                onItemTap: _openDetail,
              ),

              // 2. 频道切换
              const SizedBox(height: 12),
              DiscoverChannelBar(
                isDark: isDark,
                selected: _session.selectedKind,
                onSelected: _session.selectKind,
                counts: _channelCounts(),
              ),

              // 3. 频道副标题 + 聚合进度
              _buildChannelHeader(isDark),

              // 4. 当前频道的网格
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => _session.load(),
                  child: DiscoverGrid(
                    isDark: isDark,
                    items: _session.channelItems,
                    onItemTap: _openDetail,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  /// 各频道的条目数（供频道胶囊上的数字展示）
  Map<MediaKind, int> _channelCounts() {
    final grouped = DiscoverAggregator.groupByKind(_session.allItems);
    return {
      for (final kind in MediaKind.values)
        kind: kind == MediaKind.all
            ? _session.allItems.length
            : (grouped[kind]?.length ?? 0),
    };
  }

  /// 频道副标题：跨 N 个源聚合 · M 条，右侧显示聚合进度
  Widget _buildChannelHeader(bool isDark) {
    final title = _session.selectedKind == MediaKind.all
        ? '全部'
        : _session.selectedKind.label;
    final sourceCount = _session.statusMap.length;
    final itemCount = _session.channelItems.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
            ),
          ),
          const SizedBox(width: 7),
          Flexible(
            child: Text(
              sourceCount > 0
                  ? '跨 $sourceCount 个源聚合 · $itemCount 条'
                  : '正在准备内容源…',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ),
          const Spacer(),
          if (_session.loading && _session.sourceCount > 0) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: const AppLoading.compact(size: 12, strokeWidth: 1.5),
            ),
            const SizedBox(width: 6),
            Text(
              '${_session.finishedCount}/${_session.sourceCount}',
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 打开内容详情
  void _openDetail(DiscoverItem item) {
    context.pushRuleDetail(
      RuleDetailArgs(
        url: item.url,
        title: item.title,
        cover: item.cover,
        rule: item.source,
      ),
    );
  }

  /// 无可用规则源时的空态：引导去规则市场
  Widget _buildEmptyRuleState(bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Ionicons.compassOutline,
              size: 44,
              color: isDark
                  ? AppColors.darkTextTertiary
                  : AppColors.lightTextTertiary,
            ),
            const SizedBox(height: 14),
            Text(
              '还没有启用的规则源',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: isDark
                    ? AppColors.darkTextPrimary
                    : AppColors.lightTextPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '规则源是内容的来源。添加并启用一个源，就能开始浏览聚合内容。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.6,
                color: isDark
                    ? AppColors.darkTextMuted
                    : AppColors.lightTextMuted,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => context.pushMarket(),
              icon: const Icon(Ionicons.storefrontOutline, size: 16),
              label: const Text('前往规则市场'),
            ),
          ],
        ),
      ),
    );
  }
}
