import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../common/rule_engine.dart';
import '../../di/rule_service.dart';
import '../../model/rule.dart';

/// 现代化发现页面
/// 支持多规则动态切换、沙箱发现流实时渲染与极速内容浏览
class DiscoverPage extends StatefulWidget {
  const DiscoverPage({super.key});

  @override
  State<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends State<DiscoverPage> {
  final RuleService _ruleService = GetIt.I<RuleService>();

  Rule? _selectedRule;
  List<dynamic> _discoveryData = [];
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initDefaultRule();
  }

  void _initDefaultRule() {
    final enabledRules = _ruleService.rules.where((r) => r.enabled).toList();
    if (enabledRules.isNotEmpty) {
      _selectedRule = enabledRules.first;
      _loadDiscovery(_selectedRule!);
    }
  }

  Future<void> _loadDiscovery(Rule rule) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await RuleEngine.discovery(rule);
      if (result is List) {
        setState(() {
          _discoveryData = result;
        });
      } else if (result is Map && result['list'] is List) {
        setState(() {
          _discoveryData = result['list'] as List;
        });
      } else {
        setState(() {
          _discoveryData = [];
        });
      }
    } catch (e) {
      debugPrint('Discovery error: $e');
      setState(() {
        _error = '发现内容加载失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  /// 构建横向规则选择器
  Widget _buildRuleSelector(List<Rule> enabledRules, bool isDark) {
    return Container(
      height: 42,
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: enabledRules.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final rule = enabledRules[index];
          final isSelected = _selectedRule?.id == rule.id;

          return ChoiceChip(
            label: Text(rule.name),
            selected: isSelected,
            selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
            labelStyle: TextStyle(
              color: isSelected
                  ? const Color(0xFF10B981)
                  : (isDark ? Colors.white70 : Colors.black87),
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            ),
            side: BorderSide(
              color: isSelected
                  ? const Color(0xFF10B981)
                  : (isDark ? const Color(0xFF1E2D27) : const Color(0xFFE5E7EB)),
            ),
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

  /// 构建空规则状态
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
                color: const Color(0xFF10B981).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(LucideIcons.compass, size: 36, color: Color(0xFF10B981)),
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
                backgroundColor: const Color(0xFF059669),
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

  /// 构建单分类分组下的网格列表
  Widget _buildCategoryGrid(List items, Rule currentRule) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.15,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemBuilder: (BuildContext context, int index) {
        final item = items[index];
        final title = item['title']?.toString() ?? '';
        final href = item['href']?.toString() ?? '';
        final cover = item['cover']?.toString() ?? '';

        return Card(
          clipBehavior: Clip.hardEdge,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: InkWell(
            onTap: () {
              context.push('/rule_detail', extra: {
                'href': href,
                'title': title,
                'cover': cover,
                'rule': currentRule,
              });
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
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
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
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
                errorBuilder: (_, _, _) => const Icon(LucideIcons.zap, color: Color(0xFF10B981)),
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
        valueListenable: _ruleService.rulesNotifier,
        builder: (context, allRules, _) {
          final enabledRules = allRules.where((r) => r.enabled).toList();

          if (enabledRules.isEmpty) {
            return _buildEmptyRuleState(context, isDark);
          }

          // 如果当前选中的规则失效或不存在，则自动重定向到第一个启用的规则
          if (_selectedRule == null || !enabledRules.any((r) => r.id == _selectedRule!.id)) {
            _selectedRule = enabledRules.first;
            _loadDiscovery(_selectedRule!);
          }

          return RefreshIndicator(
            color: const Color(0xFF10B981),
            onRefresh: () async {
              if (_selectedRule != null) {
                await _loadDiscovery(_selectedRule!);
              }
            },
            child: CustomScrollView(
              slivers: [
                // 顶部规则选择栏
                SliverToBoxAdapter(
                  child: _buildRuleSelector(enabledRules, isDark),
                ),

                if (_loading)
                  const SliverFillRemaining(
                    child: Center(
                      child: CircularProgressIndicator(color: Color(0xFF10B981)),
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
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final section = _discoveryData[index];
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
                                          color: const Color(0xFF10B981),
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
                                _buildCategoryGrid(items, _selectedRule!),
                              ],
                            ),
                          );
                        } else if (section is Map) {
                          // 单一元素平铺模式
                          if (index == 0) {
                            return _buildCategoryGrid(_discoveryData, _selectedRule!);
                          }
                          return const SizedBox.shrink();
                        }
                        return const SizedBox.shrink();
                      },
                      childCount: _discoveryData.length,
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}