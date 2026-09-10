import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_indicator.dart';
import '../../widgets/net_image.dart';

/// 单个源规则的检索状态
class _RuleSearchStatus {
  final Rule rule;
  bool isSearching;
  bool hasError = false;
  String? errorMessage;
  int count = 0;

  _RuleSearchStatus({
    required this.rule,
    this.isSearching = true,
  });
}

/// 规范化后的跨源检索结果条目
class _NormalizedSearchResult {
  final String title;
  final String url;
  final String cover;
  final String desc;
  final String? badge;
  final List<String>? tags;
  final Rule rule;
  final String baseUrl;
  final Map<String, dynamic> raw;

  _NormalizedSearchResult({
    required this.title,
    required this.url,
    required this.cover,
    required this.desc,
    this.badge,
    this.tags,
    required this.rule,
    required this.baseUrl,
    required this.raw,
  });

  factory _NormalizedSearchResult.fromMap(Map<dynamic, dynamic> map, Rule rule) {
    return _NormalizedSearchResult(
      title: map['title']?.toString() ?? '未知内容',
      url: map['url']?.toString() ?? '',
      cover: map['cover']?.toString() ?? '',
      desc: map['desc']?.toString() ?? '',
      badge: map['badge']?.toString(),
      tags: map['tags'] is List
          ? (map['tags'] as List).map((e) => e.toString()).toList()
          : null,
      rule: rule,
      baseUrl: rule.baseUrl,
      raw: Map<String, dynamic>.from(map),
    );
  }
}

/// 全局跨媒体多源并发聚合搜索页面
class SearchPage extends StatefulWidget {
  final String? initialKeyword;
  final Rule? targetRule;

  const SearchPage({
    super.key,
    this.initialKeyword,
    this.targetRule,
  });

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  /// 搜索轮次 Epoch，用于并发请求时丢弃已过期的上一轮结果
  int _searchEpoch = 0;

  /// 全局并发搜索加载中
  bool _loading = false;

  /// 分页加载更多中
  bool _loadingMore = false;

  /// 当前搜索关键词
  String _currentQuery = '';

  /// 全源聚合结果集
  final List<_NormalizedSearchResult> _allResults = [];

  /// 规则状态字典：Key 为规则唯一标识 (id 或 name)
  final Map<String, _RuleSearchStatus> _ruleStatusMap = {};

  /// 当前选中的筛选源规则（null 代表全部源）
  Rule? _selectedRuleFilter;

  /// 视图模式：true 为双列瀑布流海报网格，false 为紧凑卡片列表
  bool _isGridView = false;

  /// 历史搜索关键词列表
  List<String> _historyList = [];

  /// 是否展示历史/推荐面板
  bool _showHistory = true;

  /// 分页游标：记录每个规则当前已加载的页码
  final Map<String, int> _rulePageMap = {};

  /// 推荐热门探测词
  static const List<String> _hotSuggestions = [
    '电影', '番剧', '动漫', '电视剧', '科幻', '悬疑', '动作', '经典',
  ];

  @override
  void initState() {
    super.initState();
    _historyList = historyService.searchHistory.toList();

    _scrollController.addListener(_onScroll);
    ruleService.rulesNotifier.addListener(_onRulesChanged);

    // 处理初始关键词入参自动触发搜索
    if (widget.initialKeyword != null && widget.initialKeyword!.trim().isNotEmpty) {
      _controller.text = widget.initialKeyword!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch(_controller.text);
      });
    }

    if (widget.targetRule != null) {
      _selectedRuleFilter = widget.targetRule;
    }
  }

  void _onRulesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ruleService.rulesNotifier.removeListener(_onRulesChanged);
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_loading && !_loadingMore && !_showHistory && _allResults.isNotEmpty) {
        _loadMoreResults();
      }
    }
  }

  /// 保存搜索历史
  void _saveHistory() {
    historyService.updateHistory(_historyList);
  }

  /// 单项删除历史记录
  void _removeHistoryItem(String item) {
    setState(() {
      _historyList.remove(item);
    });
    _saveHistory();
  }

  /// 清空全部历史记录
  void _clearAllHistory() {
    setState(() {
      _historyList.clear();
    });
    _saveHistory();
  }

  /// 获取当前有效的检索规则列表
  List<Rule> _getEligibleRules() {
    if (widget.targetRule != null) {
      return [widget.targetRule!];
    }
    return ruleService.rules.where((r) => r.enabled).toList();
  }

  /// 发起全局多源并发流式检索
  Future<void> _performSearch(String text) async {
    final query = text.trim();
    if (query.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入搜索关键词'),
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    _focusNode.unfocus();
    final thisEpoch = ++_searchEpoch;

    final targetRules = _getEligibleRules();

    setState(() {
      _currentQuery = query;
      _showHistory = false;
      _loading = true;
      _allResults.clear();
      _ruleStatusMap.clear();
      _rulePageMap.clear();

      // 维护历史词队列（最新搜索置顶）
      _historyList.remove(query);
      _historyList.insert(0, query);

      // 初始化各源检索状态
      for (final rule in targetRules) {
        final key = rule.id.isNotEmpty ? rule.id : rule.name;
        _ruleStatusMap[key] = _RuleSearchStatus(rule: rule, isSearching: true);
        _rulePageMap[key] = 1;
      }
    });
    _saveHistory();

    if (targetRules.isEmpty) {
      setState(() {
        _loading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('暂无可用的规则源，请先在规则市场中导入并启用规则'),
          action: SnackBarAction(
            label: '去导入',
            onPressed: () => context.push('/market'),
          ),
        ),
      );
      return;
    }

    // 逐源流式执行检索任务（单源完成即刻更新 UI，避免 QuickJS 并发冲突与死锁）
    for (final rule in targetRules) {
      if (!mounted || _searchEpoch != thisEpoch) break;
      final key = rule.id.isNotEmpty ? rule.id : rule.name;

      try {
        final raw = await RuleEngine.search(rule, query, page: 1)
            .timeout(const Duration(seconds: 20));

        if (!mounted || _searchEpoch != thisEpoch) break;

        final List items = raw is List
            ? raw
            : (raw is Map && raw['items'] is List ? raw['items'] as List : const []);

        final List<_NormalizedSearchResult> parsed = [];
        for (final item in items) {
          if (item is Map) {
            parsed.add(_NormalizedSearchResult.fromMap(item, rule));
          }
        }

        if (mounted && _searchEpoch == thisEpoch) {
          setState(() {
            _allResults.addAll(parsed);
            final status = _ruleStatusMap[key];
            if (status != null) {
              status.isSearching = false;
              status.count = parsed.length;
            }
          });
        }
      } catch (e) {
        debugPrint('【搜索引擎】源 [${rule.name}] 检索异常: $e');
        if (mounted && _searchEpoch == thisEpoch) {
          setState(() {
            final status = _ruleStatusMap[key];
            if (status != null) {
              status.isSearching = false;
              status.hasError = true;
              status.errorMessage = e.toString();
            }
          });
        }
      }
    }

    if (mounted && _searchEpoch == thisEpoch) {
      setState(() {
        _loading = false;
      });
    }
  }

  /// 加载下一页数据
  Future<void> _loadMoreResults() async {
    if (_loadingMore || _currentQuery.isEmpty) return;

    final thisEpoch = _searchEpoch;
    final targetRules = _selectedRuleFilter != null
        ? [_selectedRuleFilter!]
        : _getEligibleRules();

    setState(() {
      _loadingMore = true;
    });

    for (final rule in targetRules) {
      if (!mounted || _searchEpoch != thisEpoch) break;
      final key = rule.id.isNotEmpty ? rule.id : rule.name;
      final nextPage = (_rulePageMap[key] ?? 1) + 1;

      try {
        final raw = await RuleEngine.search(rule, _currentQuery, page: nextPage)
            .timeout(const Duration(seconds: 20));
        if (!mounted || _searchEpoch != thisEpoch) break;

        final List items = raw is List
            ? raw
            : (raw is Map && raw['items'] is List ? raw['items'] as List : const []);

        final List<_NormalizedSearchResult> parsed = [];
        for (final item in items) {
          if (item is Map) {
            parsed.add(_NormalizedSearchResult.fromMap(item, rule));
          }
        }

        if (mounted && _searchEpoch == thisEpoch && parsed.isNotEmpty) {
          setState(() {
            _allResults.addAll(parsed);
            _rulePageMap[key] = nextPage;
            final status = _ruleStatusMap[key];
            if (status != null) {
              status.count += parsed.length;
            }
          });
        }
      } catch (e) {
        debugPrint('【搜索分页】源 [${rule.name}] 第 $nextPage 页加载失败: $e');
      }
    }

    if (mounted && _searchEpoch == thisEpoch) {
      setState(() {
        _loadingMore = false;
      });
    }
  }

  /// 页面返回逻辑处理
  void _handleBack() {
    if (_showHistory) {
      context.pop();
    } else {
      setState(() {
        _allResults.clear();
        _loading = false;
        _loadingMore = false;
        _showHistory = true;
        _selectedRuleFilter = null;
      });
    }
  }

  /// 获取经过源过滤后的最终展示列表
  List<_NormalizedSearchResult> get _displayResults {
    if (_selectedRuleFilter == null) {
      return _allResults;
    }
    final targetKey = _selectedRuleFilter!.id.isNotEmpty
        ? _selectedRuleFilter!.id
        : _selectedRuleFilter!.name;
    return _allResults.where((r) {
      final key = r.rule.id.isNotEmpty ? r.rule.id : r.rule.name;
      return key == targetKey;
    }).toList();
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
            // 搜索进度指示条 (并发检索中展示)
            if (_loading)
              const LinearProgressIndicator(
                minHeight: 2.5,
                color: AppColors.primary,
                backgroundColor: Colors.transparent,
              ),

            // 源筛选胶囊栏 (仅在有检索行为或结果时呈现)
            if (!_showHistory && _ruleStatusMap.isNotEmpty)
              _buildSourceFilterBar(isDark),

            // 主内容区域：历史/推荐面板或聚合结果
            Expanded(
              child: _showHistory
                  ? _buildHistoryAndSuggestionsView(isDark)
                  : _buildResultsView(isDark),
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部搜索栏与操作区
  PreferredSizeWidget _buildSearchBar(bool isDark) {
    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
              onPressed: _handleBack,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              tooltip: '返回',
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 38,
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
                  autofocus: widget.initialKeyword == null,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: widget.targetRule != null
                        ? '在「${widget.targetRule!.name}」中搜索...'
                        : '搜索海量影视、番剧、小说...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      size: 18,
                      color: AppColors.primary,
                    ),
                    suffixIconConstraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    suffixIcon: _controller.text.isNotEmpty
                        ? GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _controller.clear();
                              setState(() {
                                _showHistory = true;
                                _allResults.clear();
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 8),
                              child: Icon(Icons.clear_rounded, size: 16),
                            ),
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    border: InputBorder.none,
                  ),
                  onChanged: (val) {
                    setState(() {});
                  },
                  onSubmitted: (val) => _performSearch(val),
                ),
              ),
            ),
            const SizedBox(width: 10),
            AppButton.compact(
              label: '搜索',
              onPressed: () => _performSearch(_controller.text),
            ),
          ],
        ),
      ),
    );
  }

  /// 来源规则过滤横向滑动胶囊栏
  Widget _buildSourceFilterBar(bool isDark) {
    final totalCount = _allResults.length;
    final activeSearchingCount = _ruleStatusMap.values.where((s) => s.isSearching).length;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkBg : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                // “全部”源胶囊
                FilterChip(
                  label: Text('全部 ($totalCount)'),
                  selected: _selectedRuleFilter == null,
                  onSelected: (selected) {
                    setState(() {
                      _selectedRuleFilter = null;
                    });
                  },
                  showCheckmark: false,
                  avatar: activeSearchingCount > 0
                      ? const LoadingIndicator.compact(size: 12, strokeWidth: 1.5)
                      : null,
                  selectedColor: AppColors.primary.withValues(alpha: 0.16),
                  checkmarkColor: AppColors.primary,
                  labelStyle: TextStyle(
                    fontSize: 12,
                    fontWeight: _selectedRuleFilter == null ? FontWeight.bold : FontWeight.normal,
                    color: _selectedRuleFilter == null
                        ? AppColors.primary
                        : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                  ),
                  side: BorderSide(
                    color: _selectedRuleFilter == null
                        ? AppColors.primary.withValues(alpha: 0.5)
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                  ),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                const SizedBox(width: 8),

                // 各规则单独胶囊
                ..._ruleStatusMap.values.map((status) {
                  final isSelected = _selectedRuleFilter == status.rule;
                  final ruleName = status.rule.name;

                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      selected: isSelected,
                      onSelected: (selected) {
                        setState(() {
                          _selectedRuleFilter = selected ? status.rule : null;
                        });
                      },
                      showCheckmark: false,
                      avatar: status.isSearching
                          ? const LoadingIndicator.compact(size: 12, strokeWidth: 1.5)
                          : status.hasError
                              ? const Icon(Icons.error_outline_rounded, size: 14, color: Colors.orangeAccent)
                              : null,
                      label: Text(
                        status.hasError
                            ? '$ruleName (异常)'
                            : '$ruleName (${status.count})',
                      ),
                      selectedColor: AppColors.primary.withValues(alpha: 0.16),
                      labelStyle: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? AppColors.primary
                            : (isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary),
                      ),
                      side: BorderSide(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.5)
                            : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  );
                }),
              ],
            ),
          ),
          // 状态提示与视图切换条
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _loading
                      ? '正在并发检索各源数据 (剩余 $activeSearchingCount 源)...'
                      : '已汇聚 ${_displayResults.length} 条检索结果',
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  ),
                ),
                // 列表 / 双列网格视图切换按键
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    setState(() {
                      _isGridView = !_isGridView;
                    });
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    child: Row(
                      children: [
                        Icon(
                          _isGridView ? LucideIcons.list : LucideIcons.layoutGrid,
                          size: 14,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isGridView ? '列表排版' : '双列网格',
                          style: const TextStyle(fontSize: 11, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 搜索历史与探索词面板
  Widget _buildHistoryAndSuggestionsView(bool isDark) {
    final activeRules = _getEligibleRules();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 规则状态提示卡片 (若无可用规则则引导开启)
        if (activeRules.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: isDark ? 0.12 : 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '当前未启用任何解析规则，搜索将无法获取内容',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => context.push('/market'),
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  child: const Text('去市场导入'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],

        // 搜索历史模块
        if (_historyList.isNotEmpty) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '搜索历史',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.delete_outline_rounded, size: 15),
                label: const Text('清空历史', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _clearAllHistory,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _historyList.map((text) {
              return InputChip(
                avatar: const Icon(LucideIcons.clock, size: 13, color: AppColors.primary),
                label: Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                  ),
                ),
                backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
                side: BorderSide(
                  color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  width: 0.8,
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                deleteIcon: const Icon(Icons.close_rounded, size: 14),
                deleteIconColor: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                onPressed: () {
                  _controller.text = text;
                  _performSearch(text);
                },
                onDeleted: () => _removeHistoryItem(text),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // 探索灵感推荐词
        Row(
          children: [
            const Icon(LucideIcons.sparkles, size: 16, color: AppColors.primary),
            const SizedBox(width: 6),
            Text(
              '探索推荐',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _hotSuggestions.map((text) {
            return ActionChip(
              label: Text(
                text,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              backgroundColor: isDark ? AppColors.darkCard : AppColors.lightSurface,
              side: BorderSide(
                color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                width: 0.8,
              ),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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

  /// 搜索结果列表/网格视图
  Widget _buildResultsView(bool isDark) {
    final results = _displayResults;

    // 正在检索且当前无任何结果
    if (results.isEmpty && _loading) {
      return const Center(
        child: LoadingIndicator(
          message: '正在并发调度已启用的解析沙箱...',
        ),
      );
    }

    // 检索完成但无匹配结果
    if (results.isEmpty && !_loading) {
      return Center(
        child: EmptyState(
          icon: LucideIcons.searchX,
          title: '未检索到相关内容',
          description: '建议更换简短词汇，或前往规则中心开启更多源进行聚合检索',
          actionText: '去规则市场发现',
          onAction: () => context.push('/market'),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _performSearch(_currentQuery),
      color: AppColors.primary,
      child: _isGridView
          ? _buildGridView(results, isDark)
          : _buildListView(results, isDark),
    );
  }

  /// 紧凑卡片式列表视图
  Widget _buildListView(List<_NormalizedSearchResult> results, bool isDark) {
    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: results.length + (_loadingMore ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: LoadingIndicator.compact(size: 20),
            ),
          );
        }

        final item = results[index];
        return _buildResultCard(item, isDark);
      },
    );
  }

  /// 双列瀑布流海报网格视图
  Widget _buildGridView(List<_NormalizedSearchResult> results, bool isDark) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: results.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: LoadingIndicator.compact(size: 20),
            ),
          );
        }

        final item = results[index];
        return _buildGridCard(item, isDark);
      },
    );
  }

  /// 单条列表卡片
  Widget _buildResultCard(_NormalizedSearchResult item, bool isDark) {
    return AppCard(
      borderRadius: 12,
      padding: const EdgeInsets.all(10),
      onTap: () => _navigateToDetail(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
              // 封面海报
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 95,
                  height: 135,
                  child: NetImage(
                    imageUrl: item.cover,
                    fit: BoxFit.cover,
                    headers: item.baseUrl.isNotEmpty ? {'referer': item.baseUrl} : null,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // 详情信息区
              Expanded(
                child: SizedBox(
                  height: 135,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                          if (item.desc.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              item.desc,
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
                      // 底部标签栏 (分类、规则源徽章)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.rule.name,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final displayTag = item.badge ??
                                  (item.tags != null && item.tags!.isNotEmpty ? item.tags!.first : null);
                              if (displayTag == null || displayTag.isEmpty) {
                                return const SizedBox.shrink();
                              }
                              return Text(
                                displayTag,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
    );
  }

  /// 单条海报网格卡片
  Widget _buildGridCard(_NormalizedSearchResult item, bool isDark) {
    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      onTap: () => _navigateToDetail(item),
      child: Stack(
        fit: StackFit.expand,
        children: [
            // 海报全幅背景
            NetImage(
              imageUrl: item.cover,
              fit: BoxFit.cover,
              headers: item.baseUrl.isNotEmpty ? {'referer': item.baseUrl} : null,
            ),
            // 底部暗色渐变遮罩 (保证标题清晰易读)
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
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
            // 顶部右上角来源小角标
            Positioned(
              top: 6,
              right: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  item.rule.name,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
            // 底部标题与信息
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (item.desc.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
    );
  }

  /// 跳转至规则详情或通用媒体分发页
  void _navigateToDetail(_NormalizedSearchResult item) {
    context.push(
      '/rule_detail',
      extra: {
        'title': item.title,
        'url': item.url,
        'cover': item.cover,
        'rule': item.rule,
      },
    );
  }
}
