import 'package:fluxforge/domain/media/media_kind.dart';
import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/features/discover/models/discover_item.dart';

/// 发现页的跨源聚合纯逻辑（无状态、可纯 Dart 单测）
///
/// 职责：把各源 discovery 的原始返回值收敛成**统一条目流**，并处理三件事：
/// 1. 解析（沙箱返回值形态不一：裸 List / `{items:[...]}` / 分组结构）；
/// 2. 跨源去重（同名内容多源重复时只留信息最全的一条）；
/// 3. 分组与取数（按类型分频道、每源挑轮播候选）。
///
/// 刻意与 `SearchAggregator` 分成两个类而非合并：搜索结果与发现条目的
/// 字段与语义不同（发现条目要带来源与类型分组），且 feature 之间不得互相依赖。
class DiscoverAggregator {
  const DiscoverAggregator._();

  /// 解析单源 discovery 返回值 → 条目列表
  ///
  /// 无标题的条目直接丢弃：它既无法在列表里展示，也没法参与跨源去重。
  static List<DiscoverItem> parseItems(dynamic raw, Rule rule) {
    final kind = mediaKindOfRuleType(rule.type);
    final out = <DiscoverItem>[];

    for (final entry in _itemsOf(raw)) {
      if (entry is! Map) continue;
      final map = Map<String, dynamic>.from(entry);
      final title = _str(map['title']);
      if (title.isEmpty) continue;

      out.add(
        DiscoverItem(
          title: title,
          url: _str(map['url']),
          cover: _str(map['cover']),
          desc: _str(map['desc']),
          badge: _str(map['badge']),
          source: rule,
          kind: kind,
        ),
      );
    }
    return out;
  }

  /// 跨源去重：同名（标题归一化后）只保留信息最全的一条
  ///
  /// 占位顺序稳定：先出现的源先占位，只有后来者信息**更全**时才替换，
  /// 这样列表顺序不会被后到的源打乱（替换是原位替换，不改变次序）。
  static List<DiscoverItem> dedupe(List<DiscoverItem> items) {
    final indexByKey = <String, int>{};
    final result = <DiscoverItem>[];

    for (final item in items) {
      final key = item.dedupeKey;
      if (key.isEmpty) {
        result.add(item);
        continue;
      }
      final index = indexByKey[key];
      if (index == null) {
        indexByKey[key] = result.length;
        result.add(item);
      } else if (item.completenessScore > result[index].completenessScore) {
        result[index] = item;
      }
    }
    return result;
  }

  /// 按媒体类型分组（保持首次出现顺序）
  static Map<MediaKind, List<DiscoverItem>> groupByKind(
    List<DiscoverItem> items,
  ) {
    final grouped = <MediaKind, List<DiscoverItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.kind, () => <DiscoverItem>[]).add(item);
    }
    return grouped;
  }

  /// 轮播池：**每个源贡献一条**代表内容
  ///
  /// 轮播是「源的橱窗」而不是「内容榜」—— 规则契约里没有热度 / 评分 / 时间戳，
  /// 任何「Top N」都是假的。但「每个源各露一条」是真实的：它让用户在不切换源的前提下
  /// 看到多个来源，正好呼应「源不该是导航主轴、但该有存在感」。
  ///
  /// 同一源有多条候选时取信息最全的那条。
  static List<DiscoverItem> buildHeroPool(List<DiscoverItem> items) {
    final bySource = <String, DiscoverItem>{};
    final order = <String>[];

    for (final item in items) {
      final key = item.source.id?.toString() ?? item.source.name;
      final existing = bySource[key];
      if (existing == null) {
        bySource[key] = item;
        order.add(key);
      } else if (item.completenessScore > existing.completenessScore) {
        bySource[key] = item;
      }
    }

    return [for (final key in order) bySource[key]!];
  }

  /// 取出沙箱返回值里的条目列表
  ///
  /// 兼容三种形态：裸 List、`{items: [...]}`、以及旧规则的分组结构
  /// （`{sections: [{title, items: [...]}]}`）—— 现有发现页本就兼容后者。
  static List<dynamic> _itemsOf(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map) {
      final items = raw['items'];
      if (items is List) return items;

      final sections = raw['sections'] ?? raw['groups'];
      if (sections is List) {
        final merged = <dynamic>[];
        for (final section in sections) {
          if (section is Map && section['items'] is List) {
            merged.addAll(section['items'] as List);
          }
        }
        return merged;
      }
    }
    return const [];
  }

  static String _str(dynamic value) => value?.toString().trim() ?? '';
}
