import 'package:material_ui/material_ui.dart';
import 'package:get_it/get_it.dart';
import 'package:go_router/go_router.dart';

import '../../common/rule_engine.dart';
import '../../di/history_service.dart';
import '../../di/rule_service.dart';
import '../../model/rule.dart';
import '../../widgets/net_image.dart';

/// 全局多规则搜索页面
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final RuleService _ruleService = GetIt.I<RuleService>();
  final HistoryService _historyService = GetIt.I<HistoryService>();
  List<Rule> get _ruleList => _ruleService.rules;

  final TextEditingController _controller = TextEditingController();

  bool _loading = false;
  final List<dynamic> _list = [];
  late List<String> _searchHistoryList;
  bool _showHistory = true;

  @override
  void initState() {
    super.initState();
    _searchHistoryList = _historyService.searchHistory.toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _saveHistory() {
    _historyService.updateHistory(_searchHistoryList);
  }

  Future<void> _onSearch(String text) async {
    final query = text.trim();
    if (query.isEmpty) return;

    setState(() {
      _showHistory = false;
      _searchHistoryList.remove(query);
      _searchHistoryList.insert(0, query);
      _list.clear();
      _loading = true;
    });
    _saveHistory();

    for (final rule in _ruleList) {
      if (!rule.enabled) continue;
      try {
        final result = await RuleEngine.search(rule, query);
        if (result is List && mounted) {
          setState(() {
            for (final item in result) {
              if (item is Map) {
                item['rule'] = rule;
                item['baseUrl'] = rule.baseUrl;
              }
            }
            _list.addAll(result);
          });
        }
      } catch (e) {
        debugPrint('Search error for rule ${rule.name}: $e');
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  void _onBack() {
    if (_showHistory) {
      context.pop();
    } else {
      setState(() {
        _list.clear();
        _loading = false;
        _showHistory = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (value, data) {
        _onBack();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 6,
          title: SearchBar(
            controller: _controller,
            elevation: const WidgetStatePropertyAll(0),
            constraints: const BoxConstraints(minHeight: 36),
            backgroundColor: WidgetStatePropertyAll(Colors.black12.withValues(alpha: 0.05)),
            hintText: '请输入搜索内容...',
            leading: const Icon(Icons.search, size: 18),
            onSubmitted: (value) {
              _onSearch(value);
            },
          ),
          actionsPadding: EdgeInsets.zero,
          actions: [
            TextButton.icon(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.search_rounded),
              label: const Text('搜索'),
              onPressed: () {
                _onSearch(_controller.text);
              },
            ),
          ],
        ),
        extendBody: true,
        body: Column(
          children: [
            Offstage(
              offstage: !_showHistory,
              child: _buildSearchHistory(),
            ),
            Offstage(
              offstage: !_loading,
              child: const LinearProgressIndicator(minHeight: 2),
            ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchHistory() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '最近搜索',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              if (_searchHistoryList.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.comfortable),
                  onPressed: () {
                    setState(() {
                      _searchHistoryList.clear();
                    });
                    _saveHistory();
                  },
                  child: const Text('清除'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _searchHistoryList.map((text) {
              return InputChip(
                label: Text(text),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.only(left: 8),
                backgroundColor: Colors.black.withValues(alpha: 0.03),
                onPressed: () {
                  _controller.text = text;
                  _onSearch(text);
                },
                onDeleted: () {
                  setState(() {
                    _searchHistoryList.remove(text);
                  });
                  _saveHistory();
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      itemCount: _list.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _list[index];
        return InkWell(
          onTap: () {
            context.push(
              '/rule_detail',
              extra: {
                'title': item['title'],
                'href': item['href'],
                'cover': item['cover'],
                'rule': item['rule'],
              },
            );
          },
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.max,
              children: [
                Container(
                  clipBehavior: Clip.hardEdge,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                  ),
                  width: 120,
                  child: AspectRatio(
                    aspectRatio: 3 / 2,
                    child: NetImage(
                      imageUrl: item['cover'],
                      fit: BoxFit.cover,
                      headers: {'referer': item['baseUrl']},
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [Text(item['title']?.toString() ?? '')],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
