import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/discover/controllers/discover_session.dart';

/// 发现页的跨源聚合会话
///
/// 守三条契约：
/// 1. **先到先入** —— 轮播池不等所有源，先回来的源先上；
/// 2. **轮播与网格互斥** —— 同一条内容不会在两个区域各出现一次；
/// 3. **轮次 Epoch** —— 新一轮开始后，上一轮迟到的结果不得污染结果集。
void main() {
  Rule rule(String name, String type, {int? id}) => Rule(
    name: name,
    baseUrl: 'https://x.example',
    type: type,
    code: '',
    id: id,
  );

  final videoRule = rule('极光影视', 'video', id: 1);
  final novelRule = rule('星辰书库', 'novel', id: 2);

  List<Map<String, dynamic>> entries(String prefix, int count) => [
    for (var i = 0; i < count; i++)
      {
        'title': '$prefix-$i',
        'url': 'https://x.com/$prefix/$i',
        'cover': 'https://x.com/$prefix/$i.jpg',
      },
  ];

  DiscoverSession buildSession(
    List<Rule> rules, {
    Future<dynamic> Function(Rule rule)? loader,
  }) => DiscoverSession(
    resolveAllRules: () => rules,
    loader: loader ?? (rule) async => {'items': entries(rule.name, 2)},
  );

  test('聚合多源结果，条目流按到达顺序累积', () async {
    final session = buildSession([videoRule, novelRule]);
    await session.load();

    expect(session.allItems.length, 4);
    expect(session.sourceCount, 2);
    expect(session.finishedCount, 2);
    expect(session.loading, isFalse);
  });

  test('轮播池每源一条，且先到先入', () async {
    final session = buildSession(
      [videoRule, novelRule],
      loader: (rule) async {
        if (rule.name == '星辰书库') {
          await Future<void>.delayed(const Duration(milliseconds: 30));
        }
        return {'items': entries(rule.name, 2)};
      },
    );
    await session.load();

    expect(session.heroPool.length, 2);
    // 先返回的源排在前面
    expect(session.heroPool.first.source.name, '极光影视');
  });

  test('轮播与网格互斥：同一条内容不会两处都出现', () async {
    final session = buildSession([videoRule]);
    await session.load();

    final heroKeys = session.heroPool.map((e) => e.dedupeKey).toSet();
    for (final item in session.channelItems) {
      expect(heroKeys.contains(item.dedupeKey), isFalse);
    }
    expect(session.channelItems.length, session.allItems.length - 1);
  });

  test('切换频道：立即用已有数据填充，并只保留该类型的源', () async {
    final session = buildSession([videoRule, novelRule]);
    await session.load();
    expect(session.allItems.length, 4);

    session.selectKind(MediaKind.novel);
    // 同步可见：不等网络
    expect(session.selectedKind, MediaKind.novel);
    expect(
      session.channelItems.every((e) => e.kind == MediaKind.novel),
      isTrue,
    );
  });

  test('轮次 Epoch：新一轮开始后，上一轮迟到的结果被丢弃', () async {
    var call = 0;
    final session = buildSession(
      [videoRule],
      loader: (rule) async {
        call++;
        if (call == 1) {
          // 第一轮：慢，且在第二轮开始之后才返回
          await Future<void>.delayed(const Duration(milliseconds: 60));
          return {'items': entries('stale', 3)};
        }
        return {'items': entries('fresh', 1)};
      },
    );

    final first = session.load();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = session.load();

    await Future.wait([first, second]);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(
      session.allItems.any((e) => e.title.startsWith('stale')),
      isFalse,
      reason: '上一轮的迟到结果必须被丢弃',
    );
    expect(session.allItems.any((e) => e.title.startsWith('fresh')), isTrue);
  });

  test('单个源失败不影响其它源，失败数被单独记下', () async {
    final session = buildSession(
      [videoRule, novelRule],
      loader: (rule) async {
        if (rule.name == '极光影视') throw StateError('boom');
        return {'items': entries(rule.name, 2)};
      },
    );
    await session.load();

    expect(session.failedCount, 1);
    expect(session.finishedCount, 2);
    expect(session.allItems.length, 2);
    expect(session.allFailed, isFalse);
  });
}
