import 'package:get_it/get_it.dart';
import '../core/network/api_client.dart';
import 'app_service.dart';
import 'history_service.dart';
import 'rule_service.dart';

/// 全局唯一服务定位器单例
final GetIt getIt = GetIt.instance;

/// 快捷单例访问器语法糖 (消除频繁手写 `GetIt.I<T>()` 或大小写混用)
ApiClient get apiClient => getIt<ApiClient>();
RuleService get ruleService => getIt<RuleService>();
HistoryService get historyService => getIt<HistoryService>();
AppService get appService => getIt<AppService>();

/// 统一注册所有核心基础设施与业务服务
void configureDependencies() {
  if (!getIt.isRegistered<ApiClient>()) {
    getIt.registerSingleton<ApiClient>(ApiClient());
  }

  if (!getIt.isRegistered<AppService>()) {
    getIt.registerSingleton<AppService>(AppService());
  }

  if (!getIt.isRegistered<RuleService>()) {
    getIt.registerSingleton<RuleService>(RuleService(apiClient: apiClient));
  }

  if (!getIt.isRegistered<HistoryService>()) {
    getIt.registerSingleton<HistoryService>(HistoryService());
  }
}
