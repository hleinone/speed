import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/logo.dart';

void main() {
  testWidgets('SpeedLogo renders as a native Flutter widget', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: SpeedLogo(height: 28, semanticLabel: 'Speed')),
        ),
      ),
    );

    expect(find.byType(SpeedLogo), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SpeedLogo),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('Speed'), findsOneWidget);
  });
}
