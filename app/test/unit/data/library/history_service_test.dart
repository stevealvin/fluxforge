// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

import 'package:fluxforge/data/library/history_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();

  testWidgets('HistoryService saves and broadcasts search keywords correctly', (WidgetTester tester) async {
    final history = HistoryService();
    await history.init();

    await history.clearHistory();
    expect(history.searchHistory, isEmpty);

    await history.addHistory('测试关键词1');
    expect(history.searchHistory.contains('测试关键词1'), isTrue);
    expect(history.searchHistory.first, equals('测试关键词1'));

    await history.addHistory('测试关键词2');
    expect(history.searchHistory.first, equals('测试关键词2'));
    expect(history.searchHistory.length, equals(2));

    await history.removeHistory('测试关键词1');
    expect(history.searchHistory.contains('测试关键词1'), isFalse);
    expect(history.searchHistory.length, equals(1));
  });
}
