import '../common/store.dart';

class HistoryService {

  final List<String> searchHistory = [];

  HistoryService() {
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    var history = await Store.getStringList('searchHistory');
    if (history != null) {
      searchHistory.addAll(history);
    }
  }

  Future<void> addHistory(String keyword) async {
    if (searchHistory.contains(keyword)) {
      searchHistory.remove(keyword);
    }
    searchHistory.insert(0, keyword);

    await _saveHistory();
  }

  Future<void> updateHistory(List<String> list) async {
    if (list.isEmpty) {
      await clearHistory();
      return;
    }

    searchHistory.clear();
    searchHistory.addAll(list);
    await _saveHistory();
  } 

  Future<void> removeHistory(String keyword) async{
    searchHistory.remove(keyword);

    await _saveHistory();
  }

  Future<void> clearHistory() async {
    searchHistory.clear();
    await Store.remove('searchHistory');
  }

  /// 保存搜索历史
  Future<void> _saveHistory() async {
    await Store.setStringList('searchHistory', searchHistory);
  }
}