import 'package:fluxforge/domain/rule/rule.dart';

/// 单个规则源在本轮发现聚合中的状态
///
/// 与搜索页的 `RuleSearchStatus` 刻意分开：发现页不需要分页游标与
/// `hasMore`（当前只取各源推荐位首页），但需要「该源贡献了多少条」，
/// 供频道副标题写「跨 N 个源聚合」。
class DiscoverSourceStatus {
  DiscoverSourceStatus({required this.rule});

  /// 参与聚合的规则源
  final Rule rule;

  /// 本轮是否仍在拉取
  bool loading = true;

  /// 该源是否失败
  bool hasError = false;

  /// 失败原因
  String? errorMessage;

  /// 该源解析出的条目数
  int count = 0;

  /// 源的唯一标识（id 或 name）
  String get key => rule.id?.toString() ?? rule.name;
}
