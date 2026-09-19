import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/controllers/search_session.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Rule ruleOf(int id, {String name = '测试源', String type = 'video'}) => Rule(
        id: id,
        name: name,
        baseUrl: 'https://example.com',
        type: type,
        code: '',
      );

  test('无可用规则时直接返回，不进入加载态也不登记任何源', () async {
    final session = SearchSession(resolveRules: () => []);
    addTearDown(session.dispose);

    await session.search('斗罗大陆', timeoutSeconds: 1);

    expect(session.loading, isFalse);
    expect(session.statusMap, isEmpty);
    expect(session.allResults, isEmpty);
  });

  test('检索开始即进入加载态，并按安全 Key 登记全部源状态与分页游标', () async {
    final rules = [ruleOf(1, name: 'A源'), ruleOf(2, name: 'B源')];
    final session = SearchSession(resolveRules: () => rules);
    addTearDown(session.dispose);

    final future = session.search('斗罗大陆', timeoutSeconds: 1);

    expect(session.loading, isTrue);
    expect(session.currentQuery, equals('斗罗大陆'));
    expect(session.statusMap.keys, containsAll(['1', '2']));
    expect(session.rulePageMap, equals({'1': 1, '2': 1}));
    expect(session.statusMap.values.every((s) => s.isSearching), isTrue);

    await future;

    // 无论沙箱可用与否，最终必须收敛：加载结束且不再有源处于检索中
    expect(session.loading, isFalse);
    expect(session.statusMap.values.any((s) => s.isSearching), isFalse);
  });

  test('cancel 立即结束加载态并把剩余源标记为已停止', () async {
    final rules = [ruleOf(1), ruleOf(2), ruleOf(3)];
    final session = SearchSession(resolveRules: () => rules);
    addTearDown(session.dispose);

    final future = session.search('斗罗大陆', timeoutSeconds: 1);
    session.cancel();

    expect(session.loading, isFalse);
    expect(session.statusMap.values.every((s) => !s.isSearching), isTrue);

    await future;
    expect(session.loading, isFalse);
  });

  test('clearResults 清空结果并同时退出加载态', () async {
    final session = SearchSession(resolveRules: () => [ruleOf(1)]);
    addTearDown(session.dispose);

    await session.search('斗罗大陆', timeoutSeconds: 1);
    session.clearResults();

    expect(session.allResults, isEmpty);
    expect(session.loading, isFalse);
    expect(session.loadingMore, isFalse);
  });

  test('未登记过的选中源判定无更多，杜绝空轮询', () async {
    final session = SearchSession(resolveRules: () => [ruleOf(1), ruleOf(2)]);
    addTearDown(session.dispose);

    await session.search('斗罗大陆', timeoutSeconds: 1);

    // 全部源都已被封禁分页（异常封禁或确实无更多），故「全部」模式也无更多
    expect(session.hasMore, isFalse);
    // 选定一个从未参与检索的源，同样必须判定无更多
    session.selectRule(ruleOf(99, name: '陌生源'));
    expect(session.hasMore, isFalse);
    expect(session.displayResults, isEmpty);
  });

  test('关键词为空时不发起分页加载', () async {
    final session = SearchSession(resolveRules: () => [ruleOf(1)]);
    addTearDown(session.dispose);

    await session.loadMore(timeoutSeconds: 1);

    expect(session.loadingMore, isFalse);
  });

  test('clearResults 同步清空结果集、各源状态、分页游标与关键词', () async {
    final session = SearchSession(resolveRules: () => [ruleOf(1), ruleOf(2)]);
    addTearDown(session.dispose);

    await session.search('斗罗大陆', timeoutSeconds: 1);
    expect(session.statusMap, isNotEmpty);
    expect(session.currentQuery, isNotEmpty);

    session.clearResults();

    expect(session.allResults, isEmpty);
    expect(session.statusMap, isEmpty);
    expect(session.rulePageMap, isEmpty);
    expect(session.currentQuery, isEmpty);
    expect(session.loading, isFalse);
    expect(session.loadingMore, isFalse);
    expect(session.hasMore, isFalse);
  });

  test('clearResults 会中止在途检索，回包不得写回已清空的结果集', () async {
    final session = SearchSession(resolveRules: () => [ruleOf(1), ruleOf(2), ruleOf(3)]);
    addTearDown(session.dispose);

    // search 首个 await 是 30ms 让出窗口，此刻必然仍在「在途」状态、Worker 尚未启动
    final inflight = session.search('斗罗大陆', timeoutSeconds: 1);
    expect(session.loading, isTrue);

    session.clearResults();
    await inflight;

    // 轮次 Epoch 递增后，在途回包必须被丢弃，结果集不得「幽灵复活」
    expect(session.allResults, isEmpty);
    expect(session.statusMap, isEmpty);
    expect(session.loading, isFalse);
  });

  test('分页在途时被新一轮检索打断，loadingMore 不得永久卡住', () async {
    final rules = [ruleOf(1)];
    final session = SearchSession(resolveRules: () => rules);
    addTearDown(session.dispose);

    // 直接构造「已有结果且该源仍有余量」的分页前置状态（沙箱在测试环境不可用，无法真实产出）
    session.currentQuery = '斗罗大陆';
    session.statusMap['1'] = RuleSearchStatus(rule: rules.first, isSearching: false)..hasMore = true;
    session.rulePageMap['1'] = 1;
    expect(session.hasMore, isTrue);

    final paging = session.loadMore(timeoutSeconds: 1);
    expect(session.loadingMore, isTrue);

    // 30ms 让出窗口内用户点了「搜索」——线上高频路径
    final searching = session.search('新关键词', timeoutSeconds: 1);
    await Future.wait([paging, searching]);

    // 核心断言：分页标志必须被放开，否则底部永久转圈且上滑分页彻底失效
    expect(session.loadingMore, isFalse);
    expect(session.loading, isFalse);
  });

  test('分页与首轮检索严格互斥：检索在途时 loadMore 直接返回', () async {
    final rules = [ruleOf(1)];
    final session = SearchSession(resolveRules: () => rules);
    addTearDown(session.dispose);

    session.currentQuery = '斗罗大陆';
    session.statusMap['1'] = RuleSearchStatus(rule: rules.first, isSearching: false)..hasMore = true;
    session.rulePageMap['1'] = 1;

    final searching = session.search('新关键词', timeoutSeconds: 1);
    expect(session.loading, isTrue);

    await session.loadMore(timeoutSeconds: 1);

    // loading 守卫必须拦住分页，避免 loading 与 loadingMore 互相踩踏
    expect(session.loadingMore, isFalse);

    await searching;
  });
}
