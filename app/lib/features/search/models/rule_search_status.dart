import 'package:fluxforge/domain/rule/rule.dart';

/// 单个源规则在本轮检索中的状态
///
/// 由搜索页持有并随并发结果递增更新：[isSearching] 标记该源是否仍在跑，
/// [hasMore] 用于封禁「无更多数据」源的继续上滑分页，避免空轮询。
class RuleSearchStatus {
  final Rule rule;
  bool isSearching;
  bool hasError = false;
  String? errorMessage;
  int count = 0;

  /// 标记该规则源是否还有下一页数据，严禁无更多时无休止上滑加载
  bool hasMore = true;

  RuleSearchStatus({
    required this.rule,
    this.isSearching = true,
  });
}
