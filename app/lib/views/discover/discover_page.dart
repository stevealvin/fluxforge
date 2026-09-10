import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_card.dart';
import '../../widgets/loading_indicator.dart';

/// 现代化多规则动态发现推荐流视图
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> with AutomaticKeepAliveClientMixin {
  Rule? _selectedRule;
  List<dynamic> _discoveryData = [];
  bool _loading = false;
  String? _error;

  /// 发现页全局多源内存缓存 (Key: rule.id 或 rule.name)
  static final Map<String, List<dynamic>> _discoveryCache = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initDefaultRule();
  }

  void _initDefaultRule() {
    final enabledRules = ruleService.enabledRules;
    if (enabledRules.isNotEmpty) {
      _selectedRule = enabledRules.first;
      _loadDiscovery(_selectedRule!);
    }
  }

  String _getCacheKey(Rule rule) => rule.id?.toString() ?? rule.name;

  Future<void> _loadDiscovery(Rule rule, {bool forceRefresh = false}) async {
    final cacheKey = _getCacheKey(rule);

    // 1. 命中缓存且非强制刷新时，立即秒级渲染缓存数据，彻底告别重复等待与闪烁
    if (!forceRefresh &&
        _discoveryCache.containsKey(cacheKey) &&
        _discoveryCache[cacheKey]!.isNotEmpty) {
      setState(() {
        _discoveryData = _discoveryCache[cacheKey]!;
        _loading = false;
        _error = null;
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await RuleEngine.discovery(rule);
      final List parsed = result is List
          ? result
          : (result is Map && result['items'] is List ? result['items'] as List : const []);

      // 写入内存缓存
      _discoveryCache[cacheKey] = parsed;

      if (mounted && _selectedRule?.id == rule.id) {
        setState(() {
          _discoveryData = parsed;
        });
      }
    } catch (e) {
      debugPrint('[DiscoverPage] error: $e');
      if (mounted && _selectedRule?.id == rule.id) {
        setState(() {
          _error = '发现内容加载失败: $e';
        });
      }
    } finally {
      if (mounted && _selectedRule?.id == rule.id) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// 构建横向规则选择器（透明无底色，融合整体背景）
  Widget _buildRuleSelector(List<Rule> enabledRules, bool isDark) {
    return Container(
      height: 48,
      decoration: const BoxDecoration(
        color: Colors.transparent, // 彻底去掉背景底色
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        itemCount: enabledRules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final rule = enabledRules[index];
          final isSelected = _selectedRule?.id == rule.id;

          return ChoiceChip(
            label: Text(rule.name),
            selected: isSelected,
            showCheckmark: false,
            backgroundColor: Colors.transparent, // 去掉未选中 tab 背景色
            selectedColor: AppColors.primary.withValues(alpha: 0.12),
            labelStyle: TextStyle(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            side: BorderSide(
              color: isSelected
                  ? AppColors.primary
                  : (isDark ? AppColors.darkCardBorder.withValues(alpha: 0.5) : AppColors.lightCardBorder),
              width: isSelected ? 1.0 : 0.8,
            ),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (selected) {
              if (selected && _selectedRule?.id != rule.id) {
                setState(() {
                  _selectedRule = rule;
                });
                _loadDiscovery(rule);
              }
            },
          );
        },
      ),
    );
  }

  /// 构建未配置规则空状态
  Widget _buildEmptyRuleState(BuildContext context, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.compass, size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text(
              '尚未启用任何解析规则',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              '前往规则市场探索海量公共规则，开启全新体验。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => context.push('/market'),
              icon: const Icon(LucideIcons.store, size: 16),
              label: const Text('前往规则市场'),
            ),
          ],
        ),
      ),
    );
  }

  bool _isVideoRule(Rule rule) {
    final t = rule.type.toLowerCase().trim();
    return t == 'video' || t == 'tv' || t == 'movie' || t == 'anime' || t == 'short' || t.isEmpty;
  }

  /// 构建单个媒体海报卡片
  Widget _buildMediaCard(Map item, Rule currentRule) {
    final title = item['title']?.toString() ?? '';
    final url = item['url']?.toString() ?? '';
    final cover = item['cover']?.toString() ?? '';
    final badge = item['badge']?.toString() ?? '';
    final desc = item['desc']?.toString() ?? '';
    final isVideo = _isVideoRule(currentRule);

    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      onTap: () {
        context.push('/rule_detail', extra: {
          'url': url,
          'title': title,
          'cover': cover,
          'rule': currentRule,
        });
      },
      child: isVideo
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 顶部 16:9 横屏封面（宽大于高）
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: cover,
                          fit: BoxFit.cover,
                          httpHeaders: {
                            'referer': currentRule.baseUrl,
                            'user-agent':
                                'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
                          },
                          errorWidget: (_, _, _) => Container(
                            color: Colors.grey.withValues(alpha: 0.15),
                            child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                          ),
                        ),
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
                        if (badge.isNotEmpty)
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
                                badge,
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
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            height: 1.25,
                          ),
                        ),
                        if (desc.isNotEmpty && desc != badge)
                          Text(
                            desc,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Colors.grey,
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    httpHeaders: {
                      'referer': currentRule.baseUrl,
                      'user-agent':
                          'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.5 Mobile/15E148 Safari/604.1',
                    },
                    errorWidget: (_, _, _) => Container(
                      color: Colors.grey.withValues(alpha: 0.15),
                      child: const Icon(Icons.broken_image_rounded, color: Colors.grey),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.85),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0.55, 1.0],
                      ),
                    ),
                  ),
                ),
                if (badge.isNotEmpty)
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
                        badge,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  /// 构建瀑布流与媒体网格 (用于嵌套专区)
  Widget _buildCategoryGrid(List items, Rule currentRule) {
    final isVideo = _isVideoRule(currentRule);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: isVideo ? 1.12 : 0.72,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (BuildContext context, int index) {
        final item = items[index];
        if (item is! Map) return const SizedBox.shrink();
        return _buildMediaCard(item, currentRule);
      },
    );
  }

  /// 构建 Sliver 内容区域 (自适应分组与扁平列表)
  List<Widget> _buildSliverContent(List<dynamic> data, Rule currentRule) {
    final isGrouped = data.isNotEmpty &&
        data.first is Map &&
        data.first.containsKey('items') &&
        data.first['items'] is List;
    final isVideo = _isVideoRule(currentRule);

    if (isGrouped) {
      return [
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final section = data[index];
              if (section is Map && section.containsKey('items') && section['items'] is List) {
                final title = section['title']?.toString() ?? '推荐专区';
                final items = section['items'] as List;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: Row(
                          children: [
                            Container(
                              width: 4,
                              height: 16,
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              title,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                      _buildCategoryGrid(items, currentRule),
                    ],
                  ),
                );
              }
              return const SizedBox.shrink();
            },
            childCount: data.length,
          ),
        ),
      ];
    } else {
      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: isVideo ? 1.12 : 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final item = data[index];
                if (item is! Map) return const SizedBox.shrink();
                return _buildMediaCard(item, currentRule);
              },
              childCount: data.length,
            ),
          ),
        ),
      ];
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Hero(
              tag: 'logo',
              child: Image.asset(
                'assets/icon/icon.png',
                width: 32,
                height: 32,
                errorBuilder: (_, _, _) => const Icon(LucideIcons.zap, color: AppColors.primary),
              ),
            ),
            const SizedBox(width: 8),
            const Text(
              'FluxForge',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: '搜索',
            icon: const Icon(LucideIcons.search),
            onPressed: () => context.push('/search'),
          ),
          IconButton(
            tooltip: '规则市场',
            icon: const Icon(LucideIcons.store),
            onPressed: () => context.push('/market'),
          ),
        ],
      ),
      body: ValueListenableBuilder<List<Rule>>(
        valueListenable: ruleService.rulesNotifier,
        builder: (context, allRules, _) {
          final enabledRules = allRules.where((r) => r.enabled).toList();

          if (enabledRules.isEmpty) {
            return _buildEmptyRuleState(context, isDark);
          }

          if (_selectedRule == null || !enabledRules.any((r) => r.id == _selectedRule!.id)) {
            _selectedRule = enabledRules.first;
            _loadDiscovery(_selectedRule!);
          }

          return Column(
            children: [
              // 顶部固定规则选择栏 (固定在顶部，不随下方列表滑动)
              _buildRuleSelector(enabledRules, isDark),

              // 下方独立滚动的媒体发现流
              Expanded(
                child: RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    if (_selectedRule != null) {
                      await _loadDiscovery(_selectedRule!, forceRefresh: true);
                    }
                  },
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      if (_loading)
                        const SliverFillRemaining(
                          child: Center(
                            child: LoadingIndicator(message: '正在调用沙箱加载发现内容...'),
                          ),
                        )
                      else if (_error != null)
                        SliverFillRemaining(
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.error_outline_rounded, size: 40, color: Colors.orange),
                                  const SizedBox(height: 12),
                                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                                  const SizedBox(height: 16),
                                  FilledButton.tonal(
                                    onPressed: () => _loadDiscovery(_selectedRule!),
                                    child: const Text('重试'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                      else if (_discoveryData.isEmpty)
                        const SliverFillRemaining(
                          child: Center(
                            child: Text('当前规则暂无推荐内容', style: TextStyle(color: Colors.grey)),
                          ),
                        )
                      else
                        ..._buildSliverContent(_discoveryData, _selectedRule!),

                      // 底部避让毛玻璃导航栏
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 96),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
