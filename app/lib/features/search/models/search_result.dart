import 'package:fluxforge/domain/rule/rule.dart';

/// 规范化后的跨源检索结果条目
///
/// 沙箱各源返回的字段名与类型五花八门，这里统一收敛为强类型，
/// 供搜索结果列表 / 网格与详情跳转复用；[raw] 保留原始字典以便特殊源取用。
class NormalizedSearchResult {
  final String title;
  final String url;
  final String cover;
  final String desc;
  final String? badge;
  final List<String>? tags;
  final Rule rule;
  final String baseUrl;
  final Map<String, dynamic> raw;

  const NormalizedSearchResult({
    required this.title,
    required this.url,
    required this.cover,
    required this.desc,
    this.badge,
    this.tags,
    required this.rule,
    required this.baseUrl,
    required this.raw,
  });

  /// 从沙箱返回的条目字典构造（所有字段均做字符串兜底，杜绝类型错配崩溃）
  factory NormalizedSearchResult.fromMap(Map<dynamic, dynamic> map, Rule rule) {
    return NormalizedSearchResult(
      title: map['title']?.toString() ?? '未知内容',
      url: map['url']?.toString() ?? '',
      cover: map['cover']?.toString() ?? '',
      desc: map['desc']?.toString() ?? '',
      badge: map['badge']?.toString(),
      tags: map['tags'] is List
          ? (map['tags'] as List).map((e) => e.toString()).toList()
          : null,
      rule: rule,
      baseUrl: rule.baseUrl,
      raw: map.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  /// 卡片角标：优先取规则自带的清晰度 / 集数角标，无角标时回退第一个标签
  String? get displayTag =>
      badge ?? (tags != null && tags!.isNotEmpty ? tags!.first : null);
}
