import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/domain/rule/rule.dart';

/// 规则调试流水线的沙箱动作入口（可注入，便于纯 Dart 单测）
///
/// 默认实现直接转发到 `RuleEngine` 的对应静态方法；单测可继承后覆写为可控的
/// 假实现（例如返回由测试手动完成的 `Completer.future`），从而稳定复现
/// 「阶段在途时被中止 / 被新一轮测试顶替」这类只能靠时序才能命中的场景。
///
/// 之所以用「注入入口」而不是把 `RuleEngine` 本身改成可取消：后者要改动
/// 沙箱调用的全局契约，影响搜索 / 详情 / 播放等所有调用方，风险远大于收益。
class RuleTestActions {
  const RuleTestActions();

  /// 阶段 1：发现 / 分类
  Future<dynamic> discovery(Rule rule) => RuleEngine.discovery(rule, page: 1);

  /// 阶段 2：关键词搜索
  Future<dynamic> search(Rule rule, String keyword) =>
      RuleEngine.search(rule, keyword, page: 1);

  /// 阶段 3：详情与选集
  Future<dynamic> detail(Rule rule, String url, {Map<String, dynamic>? item}) =>
      RuleEngine.detail(rule, url, item: item);

  /// 阶段 4：直链 / 正文解析
  Future<dynamic> parse(Rule rule, String url) => RuleEngine.parse(rule, url);
}
