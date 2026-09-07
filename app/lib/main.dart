import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'common/rule_engine.dart';
import 'di/register.dart';
import 'router.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kDebugMode) {
    // 保持屏幕常亮
    WakelockPlus.enable();
  }

  // 注册依赖
  configureDependencies();

  // 初始化js runtime
  RuleEngine.init();

  runApp(const MyApp());

  // 小白条、导航栏沉浸
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
    return MaterialApp.router(
      title: 'FluxForge',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white),
        cardTheme: const CardThemeData(
          clipBehavior: Clip.hardEdge,
        ),
      ),
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
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
    );
  }
}
