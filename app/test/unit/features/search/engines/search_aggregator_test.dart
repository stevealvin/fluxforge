import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/search/engines/search_aggregator.dart';
import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/features/search/models/search_result.dart';

void main() {
  Rule rule({dynamic id, String name = '影视源', String type = 'video'}) => Rule(
        id: id,
        name: name,
        baseUrl: 'https://example.com',
        type: type,
        code: '',
      );

  group('ruleKeyOf', () {
    test('int / String 主键均可安全取键，绝不抛 NoSuchMethodError', () {
      expect(SearchAggregator.ruleKeyOf(rule(id: 1)), equals('1'));
      expect(SearchAggregator.ruleKeyOf(rule(id: 'abc')), equals('abc'));
    });

    test('主键为空时回退规则名', () {
      expect(SearchAggregator.ruleKeyOf(rule(id: null, name: '极光源')), equals('极光源'));
      expect(SearchAggregator.ruleKeyOf(rule(id: 0)), equals('0'));
    });

    test('传入 null 返回空串', () {
      expect(SearchAggregator.ruleKeyOf(null), isEmpty);
    });
  });

  group('isSameRule', () {
    test('同主键或同规则名判定为同一源', () {
      expect(SearchAggregator.isSameRule(rule(id: 7), rule(id: 7)), isTrue);
      expect(SearchAggregator.isSameRule(rule(id: 7), rule(id: 8)), isFalse);
      expect(
        SearchAggregator.isSameRule(rule(id: null, name: 'A'), rule(id: null, name: 'A')),
        isTrue,
      );
    });

    test('任一侧为 null 一律判定不同（不存在「两个空源是同一个源」的语义）', () {
      expect(SearchAggregator.isSameRule(null, null), isFalse);
      expect(SearchAggregator.isSameRule(rule(), null), isFalse);
      expect(SearchAggregator.isSameRule(null, rule()), isFalse);
    });
  });

  group('isVideoRule', () {
    test('视频类与未标注类型的源均按横版排版', () {
      for (final type in ['video', 'tv', 'movie', 'anime', 'short', '']) {
        expect(SearchAggregator.isVideoRule(rule(type: type)), isTrue, reason: type);
      }
    });

    test('小说与图集等非视频源按竖版海报排版', () {
      expect(SearchAggregator.isVideoRule(rule(type: 'novel')), isFalse);
      expect(SearchAggregator.isVideoRule(rule(type: 'picture')), isFalse);
      expect(SearchAggregator.isVideoRule(rule(type: '  NOVEL  ')), isFalse);
    });
  });

  group('itemsOf / hasMoreOf', () {
    test('兼容裸 List 与 {items: [...]} 两种契约', () {
      final rawList = [
        {'title': 'A'},
      ];
      final wrapped = {
        'items': [
          {'title': 'A'}
        ],
      };
      expect(SearchAggregator.itemsOf(rawList).length, equals(1));
      expect(SearchAggregator.itemsOf(wrapped).length, equals(1));
      expect(SearchAggregator.itemsOf(null), isEmpty);
      expect(SearchAggregator.itemsOf({'foo': 1}), isEmpty);
    });

    test('显式 hasMore 以其为准，未声明时以本页是否非空兜底', () {
      expect(SearchAggregator.hasMoreOf({'items': [], 'hasMore': false}, const []), isFalse);
      expect(SearchAggregator.hasMoreOf({'items': [], 'hasMore': true}, const []), isTrue);
      // 未声明 hasMore：空列表判定无更多，非空列表判定仍有可能有更多
      expect(SearchAggregator.hasMoreOf({'items': []}, const []), isFalse);
      expect(
        SearchAggregator.hasMoreOf({
          'items': [
            {'title': 'A'}
          ]
        }, const [{}]),
        isTrue,
      );
    });
  });

  group('parseResults', () {
    test('所有字段均做字符串兜底，杜绝类型错配崩溃', () {
      final raw = {
        'items': [
          {
            'title': 123,
            'url': null,
            'cover': true,
            'tags': ['科幻', 9.8],
          },
          '非法条目',
        ],
      };

      final parsed = SearchAggregator.parseResults(raw, rule(name: '数据源'));
      expect(parsed.length, equals(1)); // 非 Map 条目被丢弃
      expect(parsed.first.title, equals('123'));
      expect(parsed.first.url, isEmpty);
      expect(parsed.first.cover, equals('true'));
      expect(parsed.first.desc, isEmpty);
      expect(parsed.first.tags, equals(['科幻', '9.8']));
      expect(parsed.first.baseUrl, equals('https://example.com'));
      expect(parsed.first.rule.name, equals('数据源'));
    });

    test('传入非契约数据返回空列表', () {
      expect(SearchAggregator.parseResults(null, rule()), isEmpty);
      expect(SearchAggregator.parseResults('garbage', rule()), isEmpty);
    });
  });

  test('displayTag 优先取角标，无角标回退首个标签', () {
    final withBadge = NormalizedSearchResult.fromMap(
      {'title': 'A', 'badge': '4K', 'tags': ['科幻']},
      rule(),
    );
    final withoutBadge = NormalizedSearchResult.fromMap(
      {'title': 'B', 'tags': ['悬疑']},
      rule(),
    );
    final plain = NormalizedSearchResult.fromMap({'title': 'C'}, rule());

    expect(withBadge.displayTag, equals('4K'));
    expect(withoutBadge.displayTag, equals('悬疑'));
    expect(plain.displayTag, isNull);
  });

  group('filterByRule / hasMoreFor / finishedRatio', () {
    late Rule sourceA;
    late Rule sourceB;
    late List<NormalizedSearchResult> results;

    setUp(() {
      sourceA = rule(id: 1, name: 'A源');
      sourceB = rule(id: 2, name: 'B源');
      results = [
        NormalizedSearchResult.fromMap({'title': '1'}, sourceA),
        NormalizedSearchResult.fromMap({'title': '2'}, sourceB),
        NormalizedSearchResult.fromMap({'title': '3'}, sourceA),
      ];
    });

    test('未选源时全量返回，选定源时只留该源条目', () {
      expect(SearchAggregator.filterByRule(results, null).length, equals(3));
      expect(SearchAggregator.filterByRule(results, sourceA).length, equals(2));
      expect(SearchAggregator.filterByRule(results, sourceB).length, equals(1));
    });

    test('单源模式看单源 hasMore，全源模式存在任一有余量即为 true', () {
      final statusMap = {
        '1': RuleSearchStatus(rule: sourceA, isSearching: false)..hasMore = false,
        '2': RuleSearchStatus(rule: sourceB, isSearching: true)..hasMore = true,
      };
      expect(SearchAggregator.hasMoreFor(statusMap: statusMap, selectedRule: sourceA), isFalse);
      expect(SearchAggregator.hasMoreFor(statusMap: statusMap, selectedRule: sourceB), isTrue);
      expect(SearchAggregator.hasMoreFor(statusMap: statusMap, selectedRule: null), isTrue);
      // 未登记过的源一律判定无更多，杜绝空轮询
      expect(
        SearchAggregator.hasMoreFor(statusMap: statusMap, selectedRule: rule(id: 99)),
        isFalse,
      );
    });

    test('完成进度按已完成源数占比，空表返回 0', () {
      final statusMap = {
        '1': RuleSearchStatus(rule: sourceA, isSearching: false),
        '2': RuleSearchStatus(rule: sourceB, isSearching: true),
      };
      expect(SearchAggregator.finishedRatio(statusMap), closeTo(0.5, 0.001));
      expect(SearchAggregator.finishedRatio({}), equals(0.0));
      expect(SearchAggregator.searchingCount(statusMap), equals(1));
    });

    test('完成源数与进度条同源：finishedCount 与 finishedRatio 恒一致', () {
      final statusMap = {
        '1': RuleSearchStatus(rule: sourceA, isSearching: false),
        '2': RuleSearchStatus(rule: sourceB, isSearching: false),
        '3': RuleSearchStatus(rule: sourceA, isSearching: true),
        '4': RuleSearchStatus(rule: sourceB, isSearching: true),
      };
      // 等待态文案（源数）与顶部进度条（比例）必须表达同一件事，
      // 否则同一概念两处各算一遍，日后极易口径漂移
      expect(SearchAggregator.finishedCount(statusMap), equals(2));
      expect(
        SearchAggregator.finishedCount(statusMap) / statusMap.length,
        closeTo(SearchAggregator.finishedRatio(statusMap), 0.001),
      );
      expect(SearchAggregator.finishedCount({}), equals(0));
    });
  });
}
