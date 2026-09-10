import 'package:flutter_test/flutter_test.dart';
import 'package:fluxforge/core/network/api_client.dart';
import 'package:fluxforge/services/rule_engine.dart';
import 'package:fluxforge/services/app_service.dart';
import 'package:fluxforge/services/di.dart';

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
}
