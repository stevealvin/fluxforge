import 'package:flutter/foundation.dart';
import '../core/storage/app_storage.dart';

/// 搜索历史记录服务
/// 基于 AppStorage 本地持久化，并提供 searchHistoryNotifier 细粒度响应式更新流
class HistoryService {
  static const String storageKey = 'search_history';

  final ValueNotifier<List<String>> searchHistoryNotifier = ValueNotifier<List<String>>([]);

  List<String> get searchHistory => searchHistoryNotifier.value;

  HistoryService() {
    _loadHistory();
  }

  /// 异步从存储加载历史
  Future<void> _loadHistory() async {
    final list = await AppStorage.getStringList(storageKey);
    if (list != null) {
      searchHistoryNotifier.value = List.unmodifiable(list);
    }
  }

  /// 添加关键词至历史顶部 (去重并置顶)
  Future<void> addHistory(String keyword) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) return;

    final current = List<String>.from(searchHistory);
    current.remove(trimmed);
    current.insert(0, trimmed);

    // 最多保留 50 条历史记录
    if (current.length > 50) {
      current.removeRange(50, current.length);
    }

    await _saveHistory(current);
  }

  /// 更新整个历史列表
  Future<void> updateHistory(List<String> list) async {
    if (list.isEmpty) {
      await clearHistory();
      return;
    }
    await _saveHistory(list);
  }

  /// 移除单条关键词
  Future<void> removeHistory(String keyword) async {
    final current = List<String>.from(searchHistory);
    current.remove(keyword);
    await _saveHistory(current);
  }

  /// 清空历史记录
  Future<void> clearHistory() async {
    searchHistoryNotifier.value = [];
    await AppStorage.remove(storageKey);
  }

  /// 持久化并通知监听器
  Future<void> _saveHistory(List<String> list) async {
    searchHistoryNotifier.value = List.unmodifiable(list);
    await AppStorage.setStringList(storageKey, list);
  }
}
