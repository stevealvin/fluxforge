import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../services/rule_engine.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/net_image.dart';

/// 全局跨媒体多源聚合搜索页面
/// 
/// 支持遍历当前所有已启用的规则沙箱进行并发/串行检索，
/// 并聚合结果进行统一流式渲染与历史记录管理。
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  /// 是否正在检索中
  bool _loading = false;

  /// 搜索结果聚合列表
  final List<Map<String, dynamic>> _results = [];

  /// 历史搜索关键词列表
  List<String> _historyList = [];

  /// 当前是否显示历史面板 (未进行搜索或点击清空时展示)
  bool _showHistory = true;

  @override
  void initState() {
    super.initState();
    // 初始化读取持久化历史搜索记录
    _historyList = historyService.searchHistory.toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 保存当前搜索历史至持久化服务
  void _saveHistory() {
    historyService.updateHistory(_historyList);
  }

  /// 执行聚合搜索逻辑
  Future<void> _performSearch(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    // 收起键盘
    _focusNode.unfocus();

    setState(() {
      _showHistory = false;
      // 保持最新搜索词在首位
      _historyList.remove(query);
      _historyList.insert(0, query);
      _results.clear();
      _loading = true;
    });
    _saveHistory();

    final activeRules = ruleService.rules.where((r) => r.enabled).toList();

    // 遍历启用的规则执行搜索沙箱
    for (final rule in activeRules) {
      try {
        final result = await RuleEngine.search(rule, query);
        if (result is List && mounted) {
          final List<Map<String, dynamic>> parsedList = [];
          for (final item in result) {
            if (item is Map) {
              final mapItem = Map<String, dynamic>.from(item);
              mapItem['rule'] = rule;
              mapItem['baseUrl'] = rule.baseUrl;
              parsedList.add(mapItem);
            }
          }
          setState(() {
            _results.addAll(parsedList);
          });
        }
      } catch (e) {
        debugPrint('【搜索引擎】规则 ${rule.name} 检索失败: $e');
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  /// 页面返回逻辑处理
  void _handleBack() {
    if (_showHistory) {
      context.pop();
    } else {
      setState(() {
        _results.clear();
        _loading = false;
        _showHistory = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _handleBack();
        }
      },
      child: Scaffold(
        appBar: _buildSearchBar(isDark),
        body: Column(
          children: [
            // 搜索进度指示条
            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2,
                color: AppColors.primary,
                backgroundColor: Colors.transparent,
              ),
            // 内容区域：历史记录或结果列表
            Expanded(
              child: _showHistory
                  ? _buildHistoryView(isDark)
                  : _buildResultsView(isDark),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部搜索栏与操作按钮
  PreferredSizeWidget _buildSearchBar(bool isDark) {
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
        onPressed: _handleBack,
      ),
      title: Container(
        height: 40,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkCard : AppColors.lightSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.8,
          ),
        ),
        child: TextField(
          controller: _controller,
          focusNode: _focusNode,
          autofocus: true,
          textInputAction: TextInputAction.search,
          style: TextStyle(
            fontSize: 14,
            color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
          ),
          decoration: InputDecoration(
            hintText: '搜索海量影视、番剧、小说...',
            hintStyle: TextStyle(
              fontSize: 13,
              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
            ),
            prefixIcon: const Icon(
              Icons.search_rounded,
              size: 20,
              color: AppColors.primary,
            ),
            suffixIcon: _controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _controller.clear();
                      setState(() {
                        _showHistory = true;
                      });
                    },
                  )
                : null,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: InputBorder.none,
          ),
          onChanged: (val) {
            setState(() {});
          },
          onSubmitted: (val) => _performSearch(val),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: TextButton(
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            onPressed: () => _performSearch(_controller.text),
            child: const Text('搜索'),
          ),
        ),
      ],
    );
  }

  /// 搜索历史模块
  Widget _buildHistoryView(bool isDark) {
    if (_historyList.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: LucideIcons.history,
          title: '暂无搜索历史',
          description: '尝试搜索感兴趣的内容，体验聚合引擎的极速解析吧',
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '历史记录',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('清除全部', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(
                foregroundColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: () {
                setState(() {
                  _historyList.clear();
                });
                _saveHistory();
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _historyList.map((text) {
            return ActionChip(
              avatar: const Icon(LucideIcons.clock, size: 14, color: AppColors.primary),
              label: Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 0.8,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onPressed: () {
                _controller.text = text;
                _performSearch(text);
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 聚合搜索结果列表模块
  Widget _buildResultsView(bool isDark) {
    if (_results.isEmpty && !_loading) {
      return const Center(
        child: EmptyState(
          icon: LucideIcons.searchX,
          title: '未检索到相关结果',
          description: '建议更换更简短的关键词，或前往“规则中心”启用更多解析规则',
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = _results[index];
        final rule = item['rule'] as Rule?;
        final title = item['title']?.toString() ?? '未知内容';
        final coverUrl = item['cover']?.toString() ?? '';
        final baseUrl = item['baseUrl']?.toString() ?? '';

        return Material(
          color: isDark ? AppColors.darkCard : AppColors.lightCard,
          borderRadius: BorderRadius.circular(12),
          elevation: isDark ? 0 : 0.5,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              context.push(
                '/rule_detail',
                extra: {
                  'title': title,
                  'href': item['href'],
                  'cover': coverUrl,
                  'rule': rule,
                },
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面图容器
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 100,
                      height: 140,
                      child: NetImage(
                        imageUrl: coverUrl,
                        fit: BoxFit.cover,
                        headers: baseUrl.isNotEmpty ? {'referer': baseUrl} : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // 信息描述区
                  Expanded(
                    child: SizedBox(
                      height: 140,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                                ),
                              ),
                              if (item['desc'] != null && item['desc'].toString().isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  item['desc'].toString(),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          // 底部来源标识标签
                          if (rule != null)
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    rule.name,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
