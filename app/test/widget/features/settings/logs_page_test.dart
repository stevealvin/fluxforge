import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:fluxforge/app/theme/app_theme.dart';
import 'package:fluxforge/core/logging/app_logger.dart';
import 'package:fluxforge/features/settings/logs_page.dart';

void main() {
  testWidgets('LogsPage renders with AppTheme without crash', (WidgetTester tester) async {
    AppLogger.addLog(
      level: 'INFO',
      tag: 'Rule Sandbox',
      message: 'QuickJS 沙箱内核初始化就绪',
    );
    AppLogger.addLog(
      level: 'ERROR',
      tag: 'Network',
      message: 'Failed to connect: 500 Internal Server Error',
      error: 'SocketException',
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        home: const LogsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('沙箱运行日志'), findsOneWidget);
    expect(find.text('QuickJS 沙箱内核初始化就绪'), findsOneWidget);
  });
}
