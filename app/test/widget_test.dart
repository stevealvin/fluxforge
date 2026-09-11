import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:fluxforge/widgets/app_card.dart';

void main() {
  testWidgets('AppCard component renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: AppCard(
            child: Text('FluxForge Card Test'),
          ),
        ),
      ),
    );

    expect(find.text('FluxForge Card Test'), findsOneWidget);
    expect(find.byType(AppCard), findsOneWidget);
  });
}
