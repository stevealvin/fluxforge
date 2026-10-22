import 'package:flutter_test/flutter_test.dart';

import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/discover/engines/discover_aggregator.dart';
import 'package:fluxforge/features/discover/models/discover_item.dart';

/// 发现页跨源聚合纯逻辑（解析 / 去重 / 分组 / 轮播池）
void main() {
  Rule rule(String name, String type, {int? id}) => Rule(
    name: name,
    baseUrl: 'https://x.example',
    type: type,
    code: '',
    id: id,
  );

  DiscoverItem item(
    String title,
    Rule source, {
    String cover = '',
    MediaKind? kind,
  }) => DiscoverItem(
    title: title,
    url: 'https://x.com/${source.id}',
    cover: cover,
    desc: '',
    badge: '',
    source: source,
    kind: kind ?? MediaKind.video,
  );

  test('解析兼容三种返回形态，无标题条目被丢弃', () {
    final r = rule('极光影视', 'video', id: 1);
    const entry = {'title': '星海拾遗', 'url': 'https://x.com/1'};
    expect(DiscoverAggregator.parseItems([entry], r).length, 1);
    expect(DiscoverAggregator.parseItems({'items': [entry]}, r).length, 1);
    expect(
      DiscoverAggregator.parseItems({
        'sections': [
          {
            'title': '推荐',
            'items': [entry],
          },
        ],
      }, r).length,
      1,
    );
    expect(DiscoverAggregator.parseItems([{'title': ''}], r), isEmpty);
  });

  test('跨源去重：同名只留一条，且保留信息更全的', () {
    final a = rule('极光影视', 'video', id: 1);
    final b = rule('星辰书库', 'novel', id: 2);
    final result = DiscoverAggregator.dedupe([
      item('星海拾遗', a),
      item('星 海 拾 遗', b, cover: 'https://c.jpg'),
    ]);
    expect(result.length, 1);
    expect(result.first.source.name, '星辰书库');
  });

  test('轮播池：每个源只贡献一条', () {
    final a = rule('极光影视', 'video', id: 1);
    final b = rule('星辰书库', 'novel', id: 2);
    final pool = DiscoverAggregator.buildHeroPool([
      item('剧A', a),
      item('剧B', a, cover: 'https://c.jpg'),
      item('书A', b),
    ]);
    expect(pool.length, 2);
    expect(pool.first.title, '剧B', reason: '同源多候选时取信息最全的');
  });

  test('按类型分组，组内顺序保持', () {
    final a = rule('极光影视', 'video', id: 1);
    final b = rule('星辰书库', 'novel', id: 2);
    final grouped = DiscoverAggregator.groupByKind([
      item('剧A', a),
      item('书A', b, kind: MediaKind.novel),
      item('剧B', a),
    ]);
    expect(grouped[MediaKind.video]!.length, 2);
    expect(grouped[MediaKind.video]!.first.title, '剧A');
  });
}