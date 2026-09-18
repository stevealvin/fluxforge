import 'package:fluxforge/domain/rule/rule.dart';

/// 类型化路由参数模型
///
/// 背景：此前所有页面跳转都以 `extra: <String, dynamic>{'rule': ..., 'title': ...}`
/// 的魔法字典传参，键名写错不会有任何编译期提示，只能在运行时表现为"参数丢了"。
///
/// 现在约定：
/// 1. **跳转端**只构造这里的参数类（配合 `app_navigator.dart` 的扩展方法），字段名由编译器校验；
/// 2. **注册端**统一调用各类的 `tryParse`，把解析与容错集中在一处；
/// 3. `tryParse` 同时兼容三种历史形态：参数类对象 / 裸 `Rule` / 旧字典，保证渐进迁移期不炸。

/// 从任意 extra 中提取规则对象（集中处理 Rule 实例与序列化 Map 两种来源）
Rule? _ruleFrom(Object? raw) {
  if (raw is Rule) return raw;
  if (raw is Map) {
    final dynamic r = raw['rule'];
    if (r is Rule) return r;
    if (r is Map) return Rule.fromJson(Map<String, dynamic>.from(r));
  }
  return null;
}

/// 搜索页参数（可选绑定某个规则源，或携带初始关键词）
class SearchArgs {
  const SearchArgs({this.rule, this.keyword});

  final Rule? rule;
  final String? keyword;

  static SearchArgs? tryParse(Object? extra) {
    if (extra is SearchArgs) return extra;
    if (extra is Rule) return SearchArgs(rule: extra);
    if (extra is Map) {
      return SearchArgs(
        rule: _ruleFrom(extra),
        keyword: extra['keyword']?.toString(),
      );
    }
    return null;
  }
}

/// 仅携带一条规则的参数（规则分类发现浏览 / 规则调试测试共用）
class RuleArgs {
  const RuleArgs(this.rule);

  final Rule rule;

  /// 解析失败返回 null，由调用方决定展示哪个兜底页
  static Rule? tryParse(Object? extra) {
    if (extra is RuleArgs) return extra.rule;
    return _ruleFrom(extra);
  }
}

/// 规则详情参数：跳转到媒体详情页并绑定规则（原 `/rule_detail`）
class RuleDetailArgs {
  const RuleDetailArgs({
    required this.title,
    required this.url,
    this.cover = '',
    this.rule,
  });

  final String title;
  final String url;
  final String cover;
  final Rule? rule;

  static RuleDetailArgs? tryParse(Object? extra) {
    if (extra is RuleDetailArgs) return extra;
    if (extra is Map) {
      return RuleDetailArgs(
        title: extra['title']?.toString() ?? '',
        url: extra['url']?.toString() ?? '',
        cover: extra['cover']?.toString() ?? '',
        rule: _ruleFrom(extra),
      );
    }
    return null;
  }
}

/// 通用媒体详情参数（原 `/detail`，按 type 分发到视频 / 小说 / 图集）
class MediaDetailArgs {
  const MediaDetailArgs({
    required this.title,
    required this.url,
    this.type = 'video',
    this.cover = '',
  });

  final String type;
  final String title;
  final String url;
  final String cover;

  static MediaDetailArgs? tryParse(Object? extra) {
    if (extra is MediaDetailArgs) return extra;
    if (extra is Map) {
      return MediaDetailArgs(
        type: extra['type']?.toString() ?? 'video',
        title: extra['title']?.toString() ?? '媒体详情',
        url: extra['url']?.toString() ?? '',
        cover: extra['cover']?.toString() ?? '',
      );
    }
    return null;
  }
}
