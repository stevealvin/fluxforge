import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:material_ui/material_ui.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../di/register.dart';
import '../../di/rule_service.dart';
import '../../model/rule.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key});

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  static const String marketApiUrl = 'https://fluxforge.nle.lol/api/rules';

  final RuleService _ruleService = getIt<RuleService>();
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    },
  ));

  List<Rule> _marketRules = [];
  bool _loading = true;
  String? _errorMessage;
  bool _importingAll = false;

  @override
  void initState() {
    super.initState();
    _fetchMarketRules();
  }

  Future<void> _fetchMarketRules() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final response = await _dio.get(marketApiUrl);
      if (response.statusCode == 200) {
        final data = response.data;
        List<dynamic> list = [];
        if (data is List) {
          list = data;
        } else if (data is String) {
          final decoded = jsonDecode(data);
          if (decoded is List) list = decoded;
        }

        final parsed = list
            .map((e) => Rule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();

        setState(() {
          _marketRules = parsed;
          _loading = false;
        });
      } else {
        setState(() {
          _errorMessage = '加载失败 (HTTP ${response.statusCode})';
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '网络请求异常，请检查网络连接: $e';
        _loading = false;
      });
    }
  }

  /// 单条导入或更新
  Future<void> _importSingleRule(Rule rule) async {
    try {
      await _ruleService.addOrUpdateRule(rule);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已成功导入规则「${rule.name}」'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 2),
          ),
        );
        setState(() {}); // 刷新卡片导入状态
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  /// 一键全部导入
  Future<void> _importAllRules() async {
    if (_marketRules.isEmpty) return;

    setState(() {
      _importingAll = true;
    });

    try {
      for (final rule in _marketRules) {
        await _ruleService.addOrUpdateRule(rule);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('成功全量导入 ${_marketRules.length} 条规则！'),
            backgroundColor: const Color(0xFF059669),
            duration: const Duration(seconds: 3),
          ),
        );
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('全量导入失败: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _importingAll = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(LucideIcons.store, size: 20, color: Color(0xFF10B981)),
            SizedBox(width: 8),
            Text('规则市场', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 18)),
          ],
        ),
        actions: [
          if (!_loading && _marketRules.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.18),
                  foregroundColor: const Color(0xFF10B981),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _importingAll ? null : _importAllRules,
                icon: _importingAll
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(LucideIcons.download, size: 16),
                label: Text(_importingAll ? '导入中...' : '一键全部导入'),
              ),
            ),
        ],
      ),
      body: ValueListenableBuilder<List<Rule>>(
        valueListenable: _ruleService.rulesNotifier,
        builder: (context, localRules, _) {
          if (_loading) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(strokeWidth: 3, color: Color(0xFF10B981)),
                  SizedBox(height: 16),
                  Text('正在连接公共规则市场...', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }

          if (_errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline_rounded, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: _fetchMarketRules,
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('点击重试'),
                    ),
                  ],
                ),
              ),
            );
          }

          if (_marketRules.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(LucideIcons.inbox, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('市场暂无可用的公共规则', style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _fetchMarketRules,
                    child: const Text('刷新'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: _fetchMarketRules,
            color: const Color(0xFF10B981),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _marketRules.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final rule = _marketRules[index];
                final isImported = _ruleService.isRuleImported(rule);

                return Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF131D19) : Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? (isImported ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFF1E2D27))
                          : (isImported ? const Color(0xFF10B981).withValues(alpha: 0.3) : const Color(0xFFE5E7EB)),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                rule.type.toUpperCase(),
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                rule.name,
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (rule.version != null)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'v${rule.version}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                                ),
                              ),
                          ],
                        ),
                        if (rule.description != null && rule.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            rule.description!,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark ? const Color(0xFFA1A1AA) : const Color(0xFF52525B),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(LucideIcons.globe, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                rule.baseUrl,
                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 12),
                            if (isImported)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(LucideIcons.check, size: 14, color: Color(0xFF10B981)),
                                    SizedBox(width: 4),
                                    Text(
                                      '已导入',
                                      style: TextStyle(fontSize: 12, color: Color(0xFF10B981), fontWeight: FontWeight.w600),
                                    ),
                                  ],
                                ),
                              )
                            else
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF059669),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => _importSingleRule(rule),
                                icon: const Icon(LucideIcons.download, size: 14),
                                label: const Text('一键导入', style: TextStyle(fontSize: 12)),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
