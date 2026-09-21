import 'package:fluxforge/domain/rule/rule.dart';

import 'package:fluxforge/features/search/models/rule_search_status.dart';
import 'package:fluxforge/features/search/models/search_result.dart';

/// 跨源检索的聚合策略（纯逻辑，无状态，可纯 Dart 单测）
///
/// 只做「沙箱返回值 → 规范化结果」与「多源状态合并判定」这两类纯计算，
/// 不碰网络、不碰 BuildContext，因此可被单元测试直接覆盖。
class SearchAggregator {
  const SearchAggregator._();

  /// 视频类规则的媒体类型标识（命中则按 16:9 横版海报排版）
  static const Set<String> _videoTypes = {
    'video',
    'tv',
    'movie',
    'anime',
    'short',
    '',
  };

  /// 安全获取规则唯一标识 Key
  ///
  /// 防御 int / String / null 等各种数据源类型，杜绝 NoSuchMethodError。
  static String ruleKeyOf(Rule? rule) {
    if (rule == null) return '';
    final idVal = rule.id;
    if (idVal != null) {
      final idStr = idVal.toString().trim();
      if (idStr.isNotEmpty) return idStr;
    }
    return rule.name.trim();
  }

  /// 判断两个规则是否为同一个源
  ///
  /// 任一侧为 null 一律判定「不是同一个源」——「未选中任何源」与「某个源」不可比，
  /// 更不存在「两个空源是同一个源」的语义（该陷阱会让上层过滤逻辑静默走偏）。
  static bool isSameRule(Rule? a, Rule? b) {
    if (a == null || b == null) return false;
    return ruleKeyOf(a) == ruleKeyOf(b);
  }

  /// 判断规则是否为视频类（含空类型兜底，未标注类型的源默认按视频排版）
  static bool isVideoRule(Rule rule) {
    return _videoTypes.contains(rule.type.toLowerCase().trim());
  }

  /// 从沙箱返回值中提取条目列表
  ///
  /// 契约允许两种形态：直接返回 List，或返回 `{'items': [...]}` 包装。
  static List<dynamic> itemsOf(dynamic raw) {
    if (raw is List) return raw;
    if (raw is Map && raw['items'] is List) return raw['items'] as List;
    return const [];
  }

  /// 判定该源是否还有下一页
  ///
  /// 严格遵循规则引擎契约：显式提供 `hasMore` 时以其为准，
  /// 否则以「本页是否返回了条目」作为启发式兜底。
  static bool hasMoreOf(dynamic raw, List<dynamic> items) {
    if (raw is Map && raw.containsKey('hasMore')) {
      return raw['hasMore'] == true;
    }
    return items.isNotEmpty;
  }

  /// 把沙箱返回值解析为规范化结果列表（非 Map 条目直接丢弃）
  static List<NormalizedSearchResult> parseResults(dynamic raw, Rule rule) {
    final items = itemsOf(raw);
    final parsed = <NormalizedSearchResult>[];
    for (final item in items) {
      if (item is Map) {
        parsed.add(NormalizedSearchResult.fromMap(item, rule));
      }
    }
    return parsed;
  }

  /// 按选中源过滤结果集（[selected] 为 null 代表「全部」）
  static List<NormalizedSearchResult> filterByRule(
    List<NormalizedSearchResult> all,
    Rule? selected,
  ) {
    if (selected == null) return all;
    final targetKey = ruleKeyOf(selected);
    return all
        .where((r) => ruleKeyOf(r.rule) == targetKey)
        .toList(growable: false);
  }

  /// 当前筛选模式下是否还有更多页可加载
  ///
  /// 单源模式看单源，全源模式只要求存在任意还有余量的源。
  static bool hasMoreFor({
    required Map<String, RuleSearchStatus> statusMap,
    required Rule? selectedRule,
  }) {
    if (selectedRule != null) {
      return statusMap[ruleKeyOf(selectedRule)]?.hasMore ?? false;
    }
    return statusMap.values.any((s) => s.hasMore);
  }

  /// 已完成的源数量（`isSearching == false` 即视为完成，含成功、失败与超时）
  ///
  /// 与 [finishedRatio] 同源：进度条（比例）与等待态文案（源数）都走这里，
  /// 避免同一概念在页面与视图里各算一遍、日后口径漂移。
  static int finishedCount(Map<String, RuleSearchStatus> statusMap) {
    return statusMap.values.where((s) => !s.isSearching).length;
  }

  /// 本轮检索的完成进度（0.0 ~ 1.0），用于顶部进度条
  static double finishedRatio(Map<String, RuleSearchStatus> statusMap) {
    if (statusMap.isEmpty) return 0.0;
    return (finishedCount(statusMap) / statusMap.length).clamp(0.0, 1.0);
  }

  /// 仍在检索中的源数量
  static int searchingCount(Map<String, RuleSearchStatus> statusMap) {
    return statusMap.values.where((s) => s.isSearching).length;
  }
}
