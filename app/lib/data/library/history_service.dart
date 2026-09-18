import 'package:flutter/foundation.dart';
import 'package:fluxforge/core/storage/app_storage.dart';

/// 搜索历史记录服务
/// 基于 AppStorage 本地持久化，并提供 searchHistoryNotifier 细粒度响应式更新流
class HistoryService {
  static const String storageKey = 'search_history';

  final ValueNotifier<List<String>> searchHistoryNotifier = ValueNotifier<List<String>>([]);

  List<String> get searchHistory => searchHistoryNotifier.value;

  HistoryService() {
    _loadHistory();
  }

  /// 异步显式预热初始化
  Future<void> init() async {
    await _loadHistory();
  }

  /// 异步从持久化存储加载历史记录 (带双格式容错与强异常捕获)
  Future<void> _loadHistory() async {
    try {
      // 1. 优先尝试从高兼容性 JSON Array 读取
      final rawJson = await AppStorage.getJson(storageKey);
      if (rawJson is List) {
        final list = rawJson.map((e) => e.toString().trim()).where((e) => e.isNotEmpty).toList();
        searchHistoryNotifier.value = List.unmodifiable(list);
        return;
      }

      // 2. 回退尝试从系统 StringList 读取 (兼容旧数据)
      final rawList = await AppStorage.getStringList(storageKey);
      if (rawList != null && rawList.isNotEmpty) {
        final list = rawList.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        searchHistoryNotifier.value = List.unmodifiable(list);
        // 自动迁移至 JSON 格式
        await AppStorage.setJson(storageKey, list);
      }
    } catch (e) {
      debugPrint('[HistoryService] 加载搜索历史异常: $e');
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
    searchHistoryNotifier.value = const [];
    try {
      await AppStorage.remove(storageKey);
    } catch (e) {
      debugPrint('[HistoryService] 清空搜索历史异常: $e');
    }
  }

  /// 持久化并通知监听器 (双写容错)
  Future<void> _saveHistory(List<String> list) async {
    final safeList = list.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    searchHistoryNotifier.value = List.unmodifiable(safeList);
    try {
      // 1. 优先以标准 JSON Array 持久化
      await AppStorage.setJson(storageKey, safeList);
      // 2. 同步写入 StringList 保障各平台底层兼容
      await AppStorage.setStringList(storageKey, safeList);
    } catch (e) {
      debugPrint('[HistoryService] 保存搜索历史异常: $e');
    }
  }
}
