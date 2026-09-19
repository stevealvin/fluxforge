import 'package:get_it/get_it.dart';
import 'package:fluxforge/core/network/api_client.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/data/backup/backup_service.dart';
import 'package:fluxforge/data/download/download_service.dart';
import 'package:fluxforge/data/library/favorite_service.dart';
import 'package:fluxforge/data/library/history_service.dart';
import 'package:fluxforge/data/library/play_history_service.dart';
import 'package:fluxforge/data/rule/rule_service.dart';
import 'package:fluxforge/data/sites/site_store.dart';

/// 全局唯一服务定位器单例
final GetIt getIt = GetIt.instance;

/// 快捷单例访问器语法糖 (消除频繁手写 `GetIt.I<T>()` 或大小写混用)
ApiClient get apiClient => getIt<ApiClient>();
RuleService get ruleService => getIt<RuleService>();
HistoryService get historyService => getIt<HistoryService>();
AppService get appService => getIt<AppService>();
FavoriteService get favoriteService => getIt<FavoriteService>();
BackupService get backupService => getIt<BackupService>();

/// 自定义站点入口管理服务
SiteStore get siteStore => getIt<SiteStore>();

/// 统一媒体消费历史与断点续播服务
PlayHistoryService get playHistoryService => getIt<PlayHistoryService>();

/// 离线下载服务（小说全本 / 漫画整部）
DownloadService get downloadService => getIt<DownloadService>();

/// 统一注册所有核心基础设施与业务服务
void configureDependencies() {
  if (!getIt.isRegistered<AppService>()) {
    getIt.registerSingleton<AppService>(AppService());
  }

  if (!getIt.isRegistered<ApiClient>()) {
    final currentSettings = getIt<AppService>().settings;
    final client = ApiClient(
      timeoutSeconds: currentSettings.requestTimeoutSeconds,
    );
    if (currentSettings.customUserAgent.trim().isNotEmpty) {
      client.updateConfig(userAgent: currentSettings.customUserAgent);
    }
    getIt.registerSingleton<ApiClient>(client);

    // 监听偏好设置变更，动态联动更新网络请求超时与 User-Agent
    getIt<AppService>().settingsNotifier.addListener(() {
      final s = getIt<AppService>().settingsNotifier.value;
      client.updateConfig(
        timeoutSeconds: s.requestTimeoutSeconds,
        userAgent: s.customUserAgent.trim().isNotEmpty ? s.customUserAgent : null,
      );
    });
  }


  if (!getIt.isRegistered<RuleService>()) {
    getIt.registerSingleton<RuleService>(RuleService(apiClient: apiClient));
  }

  if (!getIt.isRegistered<HistoryService>()) {
    getIt.registerSingleton<HistoryService>(HistoryService());
  }

  if (!getIt.isRegistered<FavoriteService>()) {
    getIt.registerSingleton<FavoriteService>(FavoriteService());
  }

  if (!getIt.isRegistered<PlayHistoryService>()) {
    getIt.registerSingleton<PlayHistoryService>(PlayHistoryService());
  }

  if (!getIt.isRegistered<DownloadService>()) {
    getIt.registerSingleton<DownloadService>(DownloadService(
      ruleService: ruleService,
      apiClient: apiClient,
    ));
  }

  if (!getIt.isRegistered<BackupService>()) {
    getIt.registerSingleton<BackupService>(BackupService(
      ruleService: ruleService,
      favoriteService: favoriteService,
      historyService: historyService,
      playHistoryService: playHistoryService,
    ));
  }

  if (!getIt.isRegistered<SiteStore>()) {
    getIt.registerSingleton<SiteStore>(SiteStore());
  }
}
