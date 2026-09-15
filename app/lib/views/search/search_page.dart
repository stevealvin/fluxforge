import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ionicons/ionicons.dart';

import '../../core/theme/app_colors.dart';
import '../../models/rule.dart';
import '../../services/di.dart';
import '../../services/rule_engine.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_empty_state.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/app_net_image.dart';

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
      raw: map.map((k, v) => MapEntry(k.toString(), v)),
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
    _focusNode.addListener(_onFocusChanged);
    historyService.searchHistoryNotifier.addListener(_onHistoryChanged);

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

  /// 搜索历史响应式同步更新
  void _onHistoryChanged() {
    if (mounted) {
      setState(() {
        _historyList = historyService.searchHistory.toList();
      });
    }
  }

  /// 焦点状态改变时刷新界面，实现外层容器单圆角高亮过渡
  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    historyService.searchHistoryNotifier.removeListener(_onHistoryChanged);
    ruleService.rulesNotifier.removeListener(_onRulesChanged);
    _focusNode.removeListener(_onFocusChanged);
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

  /// 单项删除历史记录
  void _removeHistoryItem(String item) {
    historyService.removeHistory(item);
  }

  /// 清空全部历史记录
  void _clearAllHistory() {
    historyService.clearHistory();
  }

  /// 安全获取规则唯一标识 Key（防御 int/String/null 等各种数据源类型，杜绝 NoSuchMethodError）
  static String _getRuleKey(Rule? rule) {
    if (rule == null) return '';
    final idVal = rule.id;
    if (idVal != null) {
      final idStr = idVal.toString().trim();
      if (idStr.isNotEmpty) return idStr;
    }
    return rule.name.trim();
  }

  /// 判断两个规则是否为同一个源
  static bool _isSameRule(Rule? a, Rule? b) {
    if (a == null || b == null) return a == b;
    return _getRuleKey(a) == _getRuleKey(b);
  }

  /// 获取当前有效的检索规则列表
  List<Rule> _getEligibleRules() {
    if (widget.targetRule != null) {
      return [widget.targetRule!];
    }
    return ruleService.rules.where((r) => r.enabled).toList();
  }

  /// 手动中止正在进行的跨源并发检索 (开源阅读同款 Stop 机制)
  void _cancelSearch() {
    if (!_loading) return;
    setState(() {
      _searchEpoch++;
      _loading = false;
      // 将剩余尚未完成的规则源标记为已停止
      for (final status in _ruleStatusMap.values) {
        if (status.isSearching) {
          status.isSearching = false;
        }
      }
    });
  }

  /// 发起全局多源并发流式检索 (类开源阅读并发聚合模型)
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

    // 前置校验：若当前无可用规则，立即提示并引导去市场导入，避免清空界面导致用户困惑
    final targetRules = _getEligibleRules();
    if (targetRules.isEmpty) {
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

    final thisEpoch = ++_searchEpoch;

    // 关键修复 1：全网搜索模式下必须无条件重置选中的源胶囊为 null (全部)，
    // 彻底杜绝因残留源筛选将新检索出来的其他源条目全部过滤为空、从而引发“一直显示加载动画”的严重假死缺陷！
    setState(() {
      _currentQuery = query;
      _showHistory = false;
      _loading = true;
      _allResults.clear();
      _ruleStatusMap.clear();
      _rulePageMap.clear();
      if (widget.targetRule == null) {
        _selectedRuleFilter = null;
      }

      // 初始化各源检索状态（统一使用安全 Key 提取，防御 int 类型主键崩溃）
      for (final rule in targetRules) {
        final key = _getRuleKey(rule);
        _ruleStatusMap[key] = _RuleSearchStatus(rule: rule, isSearching: true);
        _rulePageMap[key] = 1;
      }
    });

    // 关键修复 2：异步持久化搜索历史记录
    unawaited(historyService.addHistory(query));

    // 让出主事件队列确保 UI 能够先平滑渲染顶部进度条与流式准备态
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!mounted || _searchEpoch != thisEpoch) return;

    // 关键架构升级：受控并发池并发调度 (开源阅读同款流式调度架构)
    // 默认并发 3~4 个沙箱任务，单源超时收窄至合理范围，杜绝单个死链源阻塞全局
    const int maxConcurrent = 3;
    final int timeoutSec = appService.settingsNotifier.value.requestTimeoutSeconds.clamp(5, 12);

    Future<void> runRuleSearch(Rule rule) async {
      if (!mounted || _searchEpoch != thisEpoch) return;
      final key = _getRuleKey(rule);

      try {
        final raw = await RuleEngine.search(rule, query, page: 1, timeoutSeconds: timeoutSec)
            .timeout(Duration(seconds: timeoutSec + 1));

        if (!mounted || _searchEpoch != thisEpoch) return;

        final List items = raw is List
            ? raw
            : (raw is Map && raw['items'] is List ? raw['items'] as List : const []);

        final List<_NormalizedSearchResult> parsed = [];
        for (final item in items) {
          if (item is Map) {
            parsed.add(_NormalizedSearchResult.fromMap(item, rule));
          }
        }

        // 单源只要搜到数据，即刻流式更新到界面，用户无需等待全部源跑完即可立刻浏览！
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
        debugPrint('【流式搜索】源 [${rule.name}] 检索异常: $e');
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

    // 启动多 Worker 并发队列流式拉取
    final iterator = targetRules.iterator;
    Future<void> worker() async {
      while (iterator.moveNext()) {
        if (!mounted || _searchEpoch != thisEpoch) break;
        final rule = iterator.current;
        await runRuleSearch(rule);
      }
    }

    final workerCount = targetRules.length < maxConcurrent ? targetRules.length : maxConcurrent;
    final workers = List.generate(workerCount, (_) => worker());

    await Future.wait(workers);

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

    // 关键优化：让出主事件队列保证"加载更多"底部指示器先渲染完成，使用微延时替代易死锁挂起的 endOfFrame
    await Future<void>.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;

    for (final rule in targetRules) {
      if (!mounted || _searchEpoch != thisEpoch) break;
      final key = _getRuleKey(rule);
      final nextPage = (_rulePageMap[key] ?? 1) + 1;

      try {
        final timeoutSec = appService.settingsNotifier.value.requestTimeoutSeconds;
        final raw = await RuleEngine.search(rule, _currentQuery, page: nextPage, timeoutSeconds: timeoutSec)
            .timeout(Duration(seconds: timeoutSec + 2));
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
        _selectedRuleFilter = widget.targetRule;
      });
    }
  }

  /// 获取经过源过滤后的最终展示列表
  List<_NormalizedSearchResult> get _displayResults {
    if (_selectedRuleFilter == null) {
      return _allResults;
    }
    final targetKey = _getRuleKey(_selectedRuleFilter);
    return _allResults.where((r) {
      return _getRuleKey(r.rule) == targetKey;
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
            // 搜索进度指示条 (并发检索中展示，显示已完成规则比例)
            if (_loading)
              LinearProgressIndicator(
                value: _ruleStatusMap.isNotEmpty
                    ? (_ruleStatusMap.values.where((s) => !s.isSearching).length / _ruleStatusMap.length).clamp(0.0, 1.0)
                    : null,
                minHeight: 2.5,
                color: AppColors.primary,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
              ),

            // 源筛选胶囊栏 (仅在聚合多源检索且源数大于1时呈现，单源模式隐藏以保持界面清爽)
            if (!_showHistory && _ruleStatusMap.length > 1)
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
                    color: _focusNode.hasFocus
                        ? AppColors.primary
                        : (isDark ? AppColors.darkBorder : AppColors.lightBorder),
                    width: _focusNode.hasFocus ? 1.2 : 0.8,
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
                    // 彻底清除内层所有边框与背景继承，杜绝内外双重圆角嵌套叠加的 UI 缺陷
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    filled: false,
                    fillColor: Colors.transparent,
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
              label: _loading ? '停止' : '搜索',
              color: _loading ? Colors.redAccent.withValues(alpha: 0.85) : null,
              onPressed: _loading ? _cancelSearch : () => _performSearch(_controller.text),
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
                  final isSelected = _isSameRule(_selectedRuleFilter, status.rule);
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
                        Icon(_isGridView ? Ionicons.listOutline : Ionicons.gridOutline,
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
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    _controller.text = text;
                    _performSearch(text);
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : AppColors.lightSurface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                        width: 0.8,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 160),
                          child: Text(
                            text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 4),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _removeHistoryItem(text);
                          },
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(
                              Icons.close_rounded,
                              size: 13,
                              color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
        ],

        // 探索灵感推荐词
        Row(
          children: [
            const Icon(Ionicons.sparklesOutline, size: 16, color: AppColors.primary),
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

  /// 搜索结果列表/网格视图 (开源阅读同款流式响应)
  Widget _buildResultsView(bool isDark) {
    final results = _displayResults;

    // 正在检索且当前暂无任何源返回数据 (前数百毫秒等待态，带友好进度指示与一键停止)
    if (results.isEmpty && _loading) {
      final totalCount = _ruleStatusMap.length;
      final finishedCount = _ruleStatusMap.values.where((s) => !s.isSearching).length;

      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LoadingIndicator.compact(size: 28, strokeWidth: 2.5),
              const SizedBox(height: 16),
              Text(
                '全网流式聚合检索中...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                totalCount > 0
                    ? '已调度 $totalCount 个规则沙箱 (已完成 $finishedCount 源)'
                    : '正在调度规则沙箱...',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.stop_circle_outlined, size: 16),
                label: const Text('停止检索', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                  side: BorderSide(
                    color: isDark ? AppColors.darkBorder : AppColors.lightBorder,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _cancelSearch,
              ),
            ],
          ),
        ),
      );
    }

    // 检索完成但无匹配结果 (带单源异常诊断感知)
    if (results.isEmpty && !_loading) {
      final singleTargetRule = widget.targetRule;
      final targetStatus = singleTargetRule != null
          ? _ruleStatusMap[_getRuleKey(singleTargetRule)]
          : null;

      if (targetStatus != null && targetStatus.hasError) {
        return Center(
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: '规则「${singleTargetRule!.name}」检索异常',
            description: targetStatus.errorMessage != null && targetStatus.errorMessage!.isNotEmpty
                ? '错误原因: ${targetStatus.errorMessage}'
                : '目标源站点可能网络受阻或沙箱脚本解析错误，建议前往调试器查看',
            actionText: '调试此规则',
            onAction: () => context.push('/rule_test', extra: singleTargetRule),
          ),
        );
      }

      return Center(
        child: EmptyState(
          icon: Ionicons.searchOutline,
          title: '未检索到相关内容',
          description: widget.targetRule != null
              ? '在「${widget.targetRule!.name}」中未搜到结果，建议更换简短词汇'
              : '建议更换简短词汇，或前往规则中心开启更多源进行聚合检索',
          actionText: widget.targetRule != null ? '重试搜索' : '去规则市场发现',
          onAction: () {
            if (widget.targetRule != null) {
              _performSearch(_controller.text);
            } else {
              context.push('/market');
            }
          },
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
    final showBottomLoader = _loading || _loadingMore;

    return ListView.separated(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      itemCount: results.length + (showBottomLoader ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LoadingIndicator.compact(size: 14, strokeWidth: 1.8),
                  const SizedBox(width: 8),
                  Text(
                    _loading ? '正在流式检索其余规则源...' : '加载更多中...',
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final item = results[index];
        return _buildResultCard(item, isDark);
      },
    );
  }

  bool _isVideoRule(Rule rule) {
    final t = rule.type.toLowerCase().trim();
    return t == 'video' || t == 'tv' || t == 'movie' || t == 'anime' || t == 'short' || t.isEmpty;
  }

  /// 双列瀑布流海报网格视图
  Widget _buildGridView(List<_NormalizedSearchResult> results, bool isDark) {
    final isMostlyVideo = widget.targetRule != null
        ? _isVideoRule(widget.targetRule!)
        : (results.isEmpty || results.where((r) => _isVideoRule(r.rule)).length >= results.length / 2);
    final showBottomLoader = _loading || _loadingMore;

    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: isMostlyVideo ? 1.12 : 0.65,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: results.length + (showBottomLoader ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == results.length) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const LoadingIndicator.compact(size: 14, strokeWidth: 1.8),
                  const SizedBox(width: 6),
                  Text(
                    _loading ? '检索中...' : '加载中...',
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final item = results[index];
        final isVideo = _isVideoRule(item.rule);
        return isVideo ? _buildVideoGridCard(item, isDark) : _buildGridCard(item, isDark);
      },
    );
  }

  /// 单条列表卡片
  Widget _buildResultCard(_NormalizedSearchResult item, bool isDark) {
    if (_isVideoRule(item.rule)) {
      return _buildVideoResultCard(item, isDark);
    }
    return _buildPortraitResultCard(item, isDark);
  }

  /// 单条横屏视频列表卡片（缩略图 140x80，宽大于高）
  Widget _buildVideoResultCard(_NormalizedSearchResult item, bool isDark) {
    // 优先提取清晰度/集数等角标，无角标时回退第一标签
    final displayTag = item.badge ??
        (item.tags != null && item.tags!.isNotEmpty ? item.tags!.first : null);

    return AppCard(
      borderRadius: 12,
      padding: const EdgeInsets.all(8),
      onTap: () => _navigateToDetail(item),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 横屏视频封面 16:9 (140x80，宽大于高)
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 140,
              height: 80,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(
                    imageUrl: item.cover,
                    fit: BoxFit.cover,
                    headers: item.baseUrl.isNotEmpty ? {'referer': item.baseUrl} : null,
                  ),
                  // 修复关键缺陷：Positioned 必须是 Stack 的直接子组件，严禁被 Builder 等包裹，否则导致 ParentDataWidget 断言崩溃灰屏
                  if (displayTag != null && displayTag.isNotEmpty)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          displayTag,
                          style: const TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 80,
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
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                          height: 1.25,
                        ),
                      ),
                      if (item.desc.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          item.desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? AppColors.darkTextSecondary : AppColors.lightTextSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            item.rule.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Ionicons.playCircleOutline, size: 16, color: AppColors.primary),
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

  /// 单条竖屏列表卡片（适用于图集、小说等）
  Widget _buildPortraitResultCard(_NormalizedSearchResult item, bool isDark) {
    final displayTag = item.badge ??
        (item.tags != null && item.tags!.isNotEmpty ? item.tags!.first : null);

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
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.rule.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                            ),
                          ),
                          if (displayTag != null && displayTag.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                displayTag,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                                ),
                              ),
                            ),
                          ],
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

  /// 单条横屏视频网格卡片（16:9 封面，宽大于高）
  Widget _buildVideoGridCard(_NormalizedSearchResult item, bool isDark) {
    final displayTag = item.badge ??
        (item.tags != null && item.tags!.isNotEmpty ? item.tags!.first : null);

    return AppCard(
      padding: EdgeInsets.zero,
      borderRadius: 12,
      onTap: () => _navigateToDetail(item),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部 16:9 封面
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  NetImage(
                    imageUrl: item.cover,
                    fit: BoxFit.cover,
                    headers: item.baseUrl.isNotEmpty ? {'referer': item.baseUrl} : null,
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
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.rule.name,
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  // 修复关键缺陷：Positioned 必须是 Stack 的直接子组件，严禁被 Builder 等包裹，否则导致 ParentDataWidget 断言崩溃灰屏
                  if (displayTag != null && displayTag.isNotEmpty)
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
                          displayTag,
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
              padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: isDark ? AppColors.darkTextPrimary : AppColors.lightTextPrimary,
                      height: 1.25,
                    ),
                  ),
                  if (item.desc.isNotEmpty)
                    Text(
                      item.desc,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: isDark ? AppColors.darkTextMuted : AppColors.lightTextMuted,
                      ),
                    )
                  else
                    const SizedBox.shrink(),
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
