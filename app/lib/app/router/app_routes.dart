/// 全局路由路径常量
///
/// 目的：消除「注册端」与「跳转端」各写一遍的魔法字符串 —— 路径改名只需改这里，
/// 编译器会暴露所有引用点。
///
/// 命名约定：
/// - `xxx`：**跳转用**的绝对路径（以 `/` 开头）；
/// - `xxxSegment`：**注册用**的相对段。
///   GoRouter 的嵌套子路由 `path` 必须为相对段（以 `/` 开头会打破嵌套关系），
///   因此同一路由需要同时提供这两种形式。
class AppRoutes {
  const AppRoutes._();

  // ==================== 顶层路由 ====================

  /// 启动闪屏页
  static const String splash = '/splash';

  /// 主外壳（底部导航容器）
  static const String home = '/';

  // ==================== 子路由：跳转绝对路径 ====================

  /// 内置浏览器（携带 query 参数 url / title）
  static const String browser = '/web';

  /// 全局跨源搜索
  static const String search = '/search';

  /// 规则分类发现浏览
  static const String ruleDiscovery = '/rule_discovery';

  /// 规则多阶段调试与测试
  static const String ruleTest = '/rule_test';

  /// 规则内容详情（媒体详情页 + 绑定规则）
  static const String ruleDetail = '/rule_detail';

  /// 通用媒体详情分发
  static const String mediaDetail = '/detail';

  /// 系统设置
  static const String settings = '/settings';

  /// 沙箱与系统日志中心
  static const String logs = '/logs';

  /// 规则市场
  static const String market = '/market';

  /// 我的收藏与智能追更
  static const String favorites = '/favorites';

  /// 历史管理中心
  static const String history = '/history';

  /// 离线下载管理
  static const String downloads = '/downloads';

  /// 广告拦截规则管理
  static const String adblock = '/adblock';

  // ==================== 子路由：注册相对段 ====================

  static const String browserSegment = 'web';
  static const String searchSegment = 'search';
  static const String ruleDiscoverySegment = 'rule_discovery';
  static const String ruleTestSegment = 'rule_test';
  static const String ruleDetailSegment = 'rule_detail';
  static const String mediaDetailSegment = 'detail';
  static const String settingsSegment = 'settings';
  static const String logsSegment = 'logs';
  static const String marketSegment = 'market';
  static const String favoritesSegment = 'favorites';
  static const String historySegment = 'history';
  static const String downloadsSegment = 'downloads';
  static const String adblockSegment = 'adblock';
}
