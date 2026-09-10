import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/storage/app_storage.dart';
import 'core/theme/app_theme.dart';
import 'router.dart';
import 'services/di.dart';
import 'services/rule_engine.dart';

void main() async {
  // 确保 Flutter 底层桥接层绑定就绪
  WidgetsFlutterBinding.ensureInitialized();

  // 1. 初始化底层高性能持久化存储
  await AppStorage.init();

  // 2. 统一注册核心基础设施与业务服务单例
  configureDependencies();

  // 3. 预热初始化 QuickJS 脚本执行沙箱
  RuleEngine.init();

  runApp(const MyApp());

  // Android 平台系统级沉浸式边缘到边缘模式
  if (Platform.isAndroid) {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
      ),
    );
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: appService.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp.router(
          title: 'FluxForge',
          // 全局现代浅色主题 (纯净星暮白)
          theme: AppTheme.lightTheme,
          // 全局现代深色主题 (曜夜极光翡翠)
          darkTheme: AppTheme.darkTheme,
          // 响应式主题模式 (跟随系统/浅色/深色)
          themeMode: currentThemeMode,
          builder: (context, child) {
            return GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () {
                FocusManager.instance.primaryFocus?.unfocus();
              },
              child: Material(
                clipBehavior: Clip.hardEdge,
                child: child!,
              ),
            );
          },
          routerConfig: router,
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          locale: const Locale('zh', 'CN'),
          supportedLocales: const [
            Locale('zh', 'CN'),
            Locale('en', 'US'),
          ],
        );
      },
    );
  }
}
