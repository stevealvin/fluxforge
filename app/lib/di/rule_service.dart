import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../model/rule.dart';

class RuleService {
  static const String storageKey = 'local_rules';

  final ValueNotifier<List<Rule>> rulesNotifier = ValueNotifier<List<Rule>>([]);
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36',
    },
  ));

  List<Rule> get rules => rulesNotifier.value;
  List<Rule> get enabledRules => rules.where((r) => r.enabled).toList();

  RuleService() {
    init();
  }

  /// 初始化并从本地存储加载规则
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(storageKey);

      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final loaded = decoded.map((e) => Rule.fromJson(Map<String, dynamic>.from(e as Map))).toList();
        rulesNotifier.value = loaded;
      } else {
        rulesNotifier.value = [];
      }
    } catch (e) {
      debugPrint('Failed to load local_rules: $e');
      rulesNotifier.value = [];
    }
  }

  /// 持久化保存规则列表
  Future<void> saveRules(List<Rule> newRules) async {
    rulesNotifier.value = List.unmodifiable(newRules);
    try {
      final prefs = await SharedPreferences.getInstance();
      final listJson = newRules.map((r) => r.toJson()).toList();
      await prefs.setString(storageKey, jsonEncode(listJson));
    } catch (e) {
      debugPrint('Failed to save local_rules: $e');
    }
  }

  /// 切换规则启用/禁用状态
  Future<void> toggleRule(dynamic identifier, bool enabled) async {
    final updated = rules.map((r) {
      if ((r.id != null && r.id == identifier) || r.name == identifier) {
        return r.copyWith(enabled: enabled);
      }
      return r;
    }).toList();
    await saveRules(updated);
  }

  /// 删除规则
  Future<void> deleteRule(dynamic identifier) async {
    final updated = rules.where((r) {
      if (r.id != null && r.id == identifier) return false;
      if (r.name == identifier) return false;
      return true;
    }).toList();
    await saveRules(updated);
  }

  /// 别名：删除规则
  Future<void> removeRule(dynamic identifier) => deleteRule(identifier);

  /// 新增或覆盖规则
  Future<void> addOrUpdateRule(Rule rule) async {
    final current = List<Rule>.from(rules);
    final index = current.indexWhere((r) =>
        (r.id != null && rule.id != null && r.id == rule.id) ||
        (r.name == rule.name && r.baseUrl == rule.baseUrl));

    if (index >= 0) {
      current[index] = rule;
    } else {
      current.add(rule);
    }
    await saveRules(current);
  }

  /// 判断某规则是否已经在本地导入
  bool isRuleImported(Rule target) {
    return rules.any((r) =>
        (r.id != null && target.id != null && r.id == target.id) ||
        (r.name == target.name && r.baseUrl == target.baseUrl));
  }

  /// 从 JSON 字符串批量导入规则（支持单对象或数组）
  Future<int> importRulesFromJson(String jsonString) async {
    final trimmed = jsonString.trim();
    if (trimmed.isEmpty) return 0;

    dynamic decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (e) {
      throw Exception('规则数据格式解析失败，请检查 JSON 格式');
    }

    List<dynamic> rawList = [];
    if (decoded is List) {
      rawList = decoded;
    } else if (decoded is Map) {
      rawList = [decoded];
    } else {
      throw Exception('未知的规则数据类型');
    }

    final newRules = <Rule>[];
    for (var item in rawList) {
      if (item is Map) {
        try {
          newRules.add(Rule.fromJson(Map<String, dynamic>.from(item)));
        } catch (e) {
          debugPrint('Skipping invalid rule item: $e');
        }
      }
    }

    if (newRules.isEmpty) return 0;

    final current = List<Rule>.from(rules);
    int importedCount = 0;

    for (var nr in newRules) {
      final idx = current.indexWhere((r) =>
          (r.id != null && nr.id != null && r.id == nr.id) ||
          (r.name == nr.name && r.baseUrl == nr.baseUrl));

      if (idx >= 0) {
        // 保留本地的 enabled 状态
        current[idx] = nr.copyWith(enabled: current[idx].enabled);
      } else {
        current.add(nr);
      }
      importedCount++;
    }

    await saveRules(current);
    return importedCount;
  }

  /// 别名：从 JSON 导入
  Future<int> importFromJson(String jsonString) => importRulesFromJson(jsonString);

  /// 从网络 URL 导入（类似 Legado）
  Future<int> importRulesFromUrl(String url) async {
    final targetUrl = url.trim();
    if (targetUrl.isEmpty) {
      throw Exception('请输入有效的规则订阅链接');
    }

    final response = await _dio.get(targetUrl);
    if (response.statusCode == 200) {
      final data = response.data;
      if (data is String) {
        return await importRulesFromJson(data);
      } else if (data is List || data is Map) {
        return await importRulesFromJson(jsonEncode(data));
      } else {
        throw Exception('服务器返回了不支持的格式');
      }
    } else {
      throw Exception('请求失败 (HTTP ${response.statusCode})');
    }
  }

  /// 别名：从网络 URL 导入
  Future<int> importFromUrl(String url) => importRulesFromUrl(url);

  /// 查找特定规则
  Rule? getRuleByIdOrName(dynamic identifier) {
    try {
      return rules.firstWhere((r) => (r.id != null && r.id == identifier) || r.name == identifier);
    } catch (_) {
      return null;
    }
  }
}
