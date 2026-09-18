import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/domain/rule/rule.dart';
import 'package:fluxforge/app/router/app_routes.dart';
import 'package:fluxforge/app/router/route_args.dart';

// 调用方只需 import 本文件，即可同时获得导航方法与全部参数模型
export 'route_args.dart';

/// 类型化导航扩展
///
/// 调用方从此不再接触路由路径字符串与 `extra` 字典：
///
/// ```dart
/// // 旧写法：键名写错只能在运行时发现
/// context.push('/rule_detail', extra: {'titile': title, 'url': url, ...});
///
/// // 新写法：字段名由编译器校验
/// context.pushRuleDetail(RuleDetailArgs(title: title, url: url, rule: rule));
/// ```
///
/// 无参页面（设置 / 日志 / 市场等）统一走对应方法，路径改动时只需修改 `app_routes.dart`。
extension AppNavigator on BuildContext {
  // ==================== 无参页面 ====================

  /// 进入主外壳（可替代 `go('/')`）
  void goHome() => go(AppRoutes.home);

  /// 进入启动页
  void goSplash() => go(AppRoutes.splash);

  /// 系统设置
  void pushSettings() => push(AppRoutes.settings);

  /// 沙箱与系统日志中心
  void pushLogs() => push(AppRoutes.logs);

  /// 规则市场
  void pushMarket() => push(AppRoutes.market);

  /// 我的收藏与智能追更
  void pushFavorites() => push(AppRoutes.favorites);

  /// 历史管理中心
  void pushHistory() => push(AppRoutes.history);

  /// 离线下载管理
  void pushDownloads() => push(AppRoutes.downloads);

  /// 广告拦截规则管理
  void pushAdblock() => push(AppRoutes.adblock);

  // ==================== 带参页面 ====================

  /// 内置浏览器（自动完成 query 编码，杜绝手工拼接产生的截断问题）
  void pushBrowser({required String url, String? title}) {
    final uri = Uri(
      path: AppRoutes.browser,
      queryParameters: {
        'url': url,
        if (title != null && title.isNotEmpty) 'title': title,
      },
    );
    push(uri.toString());
  }

  /// 全局跨源搜索
  void pushSearch({Rule? rule, String? keyword}) {
    push(AppRoutes.search, extra: SearchArgs(rule: rule, keyword: keyword));
  }

  /// 规则分类发现浏览
  void pushRuleDiscovery(Rule rule) {
    push(AppRoutes.ruleDiscovery, extra: RuleArgs(rule));
  }

  /// 规则多阶段调试与测试
  void pushRuleTest(Rule rule) {
    push(AppRoutes.ruleTest, extra: RuleArgs(rule));
  }

  /// 规则详情（媒体详情页 + 绑定规则）
  void pushRuleDetail(RuleDetailArgs args) {
    push(AppRoutes.ruleDetail, extra: args);
  }

  /// 通用媒体详情分发
  void pushMediaDetail(MediaDetailArgs args) {
    push(AppRoutes.mediaDetail, extra: args);
  }
}
