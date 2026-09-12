import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/storage/app_storage.dart';
import 'core/theme/app_theme.dart';
import 'core/utils/app_logger.dart';
import 'router.dart';
import 'services/di.dart';
import 'services/rule_engine.dart';

void main() async {
  // 确保 Flutter 底层桥接层绑定就绪
  WidgetsFlutterBinding.ensureInitialized();

  // 0. 全局 Flutter 异常捕获与诊断桥接，避免未捕获异常丢失
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    AppLogger.addLog(
      level: 'ERROR',
      tag: 'FlutterError',
      message: details.exceptionAsString(),
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // 全局渲染崩溃防御拦截：自定义 ErrorWidget，彻底告别系统原生全屏灰屏
  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Material(
      color: const Color(0xFF0B0F19),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 52),
                const SizedBox(height: 16),
                const Text(
                  '界面渲染异常捕获',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                Text(
                  details.exceptionAsString(),
                  style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.4),
                  textAlign: TextAlign.center,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    if (router.canPop()) {
                      router.pop();
                    } else {
                      router.go('/home');
                    }
                  },
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('返回上一页'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  };

  // 1. 初始化底层高性能持久化存储
  await AppStorage.init();

  // 2. 统一注册核心基础设施与业务服务单例
  configureDependencies();
  await historyService.init();

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
