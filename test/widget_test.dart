import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Flutter widget harness renders Material content', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: Text('Masjid App'))),
      ),
    );

    expect(find.text('Masjid App'), findsOneWidget);
  });
}
