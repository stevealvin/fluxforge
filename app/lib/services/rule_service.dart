import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/network/api_client.dart';
import '../core/storage/app_storage.dart';
import '../models/rule.dart';

/// 规则管理与云端同步服务
/// 负责规则增删改查、启用切换、云端市场规则拉取及 JSON/URL 动态导入
class RuleService {
  static const String storageKey = 'local_rules';

  final ValueNotifier<List<Rule>> rulesNotifier = ValueNotifier<List<Rule>>([]);
  final ApiClient _apiClient;

  List<Rule> get rules => rulesNotifier.value;
  List<Rule> get enabledRules => rules.where((r) => r.enabled).toList();

  RuleService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient() {
    init();
  }

  /// 初始化并从本地存储加载规则
  Future<void> init() async {
    try {
      final jsonStr = await AppStorage.getString(storageKey);
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonStr);
        final loaded = decoded
            .map((e) => Rule.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
        rulesNotifier.value = List.unmodifiable(loaded);
      } else {
        rulesNotifier.value = [];
      }
    } catch (e) {
      debugPrint('[RuleService] Failed to load local_rules: $e');
      rulesNotifier.value = [];
    }
  }

  /// 持久化保存规则列表
  Future<void> saveRules(List<Rule> newRules) async {
    rulesNotifier.value = List.unmodifiable(newRules);
    try {
      final listJson = newRules.map((r) => r.toJson()).toList();
      await AppStorage.setString(storageKey, jsonEncode(listJson));
    } catch (e) {
      debugPrint('[RuleService] Failed to save local_rules: $e');
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

  /// 新增或覆盖更新单条规则
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

  /// 批量从远程 URL 导入规则集 (支持 JSON 格式规则集)
  Future<int> importFromUrl(String url) async {
    try {
      final response = await _apiClient.get(url);
      if (response.statusCode == 200) {
        dynamic data = response.data;
        if (data is String) {
          data = jsonDecode(data);
        }
        return await _parseAndSaveRules(data);
      }
    } catch (e) {
      debugPrint('[RuleService] importFromUrl error: $e');
      rethrow;
    }
    return 0;
  }

  /// 从 JSON 文本批量导入规则
  Future<int> importFromJson(String jsonText) async {
    try {
      final decoded = jsonDecode(jsonText);
      return await _parseAndSaveRules(decoded);
    } catch (e) {
      debugPrint('[RuleService] importFromJson error: $e');
      rethrow;
    }
  }

  /// 解析并合并新规则到本地
  Future<int> _parseAndSaveRules(dynamic data) async {
    List<dynamic> list = [];
    if (data is List) {
      list = data;
    } else if (data is Map && data.containsKey('rules') && data['rules'] is List) {
      list = data['rules'] as List;
    } else if (data is Map) {
      list = [data];
    }

    if (list.isEmpty) return 0;

    final incoming = list
        .map((e) => Rule.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();

    final current = List<Rule>.from(rules);
    int count = 0;

    for (final rule in incoming) {
      final idx = current.indexWhere((r) =>
          (r.id != null && rule.id != null && r.id == rule.id) ||
          (r.name == rule.name && r.baseUrl == rule.baseUrl));

      if (idx >= 0) {
        current[idx] = rule;
      } else {
        current.add(rule);
      }
      count++;
    }

    await saveRules(current);
    return count;
  }
}
