import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/core/network/api_client.dart';
import 'package:fluxforge/core/sandbox/rule_engine.dart';
import 'package:fluxforge/data/settings/app_service.dart';
import 'package:fluxforge/app/di/di.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    if (!getIt.isRegistered<AppService>()) {
      getIt.registerSingleton<AppService>(AppService());
    }
  });

  group('Timeout Configuration Tests', () {
    test('RuleEngine reads default timeout from AppSettings', () {
      final initialTimeout = appService.settings.requestTimeoutSeconds;
      expect(RuleEngine.defaultTimeoutSeconds, equals(initialTimeout));

      // 动态更新偏好设置 (15秒)
      appService.settingsNotifier.value = appService.settings.copyWith(requestTimeoutSeconds: 15);
      expect(RuleEngine.defaultTimeoutSeconds, equals(15));

      // 动态更新偏好设置 (60秒)
      appService.settingsNotifier.value = appService.settings.copyWith(requestTimeoutSeconds: 60);
      expect(RuleEngine.defaultTimeoutSeconds, equals(60));

      // 恢复默认 (30秒)
      appService.settingsNotifier.value = appService.settings.copyWith(requestTimeoutSeconds: 30);
      expect(RuleEngine.defaultTimeoutSeconds, equals(30));
    });

    test('ApiClient updateConfig dynamically updates Dio timeouts', () {
      final client = ApiClient(timeoutSeconds: 30);
      expect(client.dio.options.connectTimeout, equals(const Duration(seconds: 30)));
      expect(client.dio.options.receiveTimeout, equals(const Duration(seconds: 30)));
      expect(client.dio.options.sendTimeout, equals(const Duration(seconds: 30)));

      client.updateConfig(timeoutSeconds: 15);
      expect(client.dio.options.connectTimeout, equals(const Duration(seconds: 15)));
      expect(client.dio.options.receiveTimeout, equals(const Duration(seconds: 15)));
      expect(client.dio.options.sendTimeout, equals(const Duration(seconds: 15)));

      client.updateConfig(timeoutSeconds: 60);
      expect(client.dio.options.connectTimeout, equals(const Duration(seconds: 60)));
      expect(client.dio.options.receiveTimeout, equals(const Duration(seconds: 60)));
      expect(client.dio.options.sendTimeout, equals(const Duration(seconds: 60)));
    });
  });

  group('CookieJar & CookieManager Tests', () {
    test('RuleEngine provides active CookieJar and handles cookie lifecycle', () async {
      final jar = RuleEngine.cookieJar;
      expect(jar, isNotNull);

      final uri = Uri.parse('https://example.com/api/test');

      // 模拟存储 Cookie
      await jar.saveFromResponse(uri, [
        Cookie('session_id', 'test_cookie_value_123'),
        Cookie('auth_token', 'xyz987'),
      ]);

      // 验证根据目标 URI 加载 Cookie
      final cookies = await jar.loadForRequest(uri);
      expect(cookies.length, equals(2));
      expect(cookies.any((c) => c.name == 'session_id' && c.value == 'test_cookie_value_123'), isTrue);
      expect(cookies.any((c) => c.name == 'auth_token' && c.value == 'xyz987'), isTrue);

      // 验证一键清空所有 Cookie 缓存
      await RuleEngine.clearCookies();
      final clearedCookies = await jar.loadForRequest(uri);
      expect(clearedCookies.isEmpty, isTrue);
    });
  });
}

