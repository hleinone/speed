import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/signal_strength.dart';

void main() {
  testWidgets('uses aligned bar and color thresholds', (tester) async {
    const inactiveColor = Color(0xff123456);
    const cases = <({double value, int activeBars, Color color})>[
      (value: 0.499999, activeBars: 1, color: Colors.red),
      (value: 0.5, activeBars: 2, color: Colors.amber),
      (value: 0.749999, activeBars: 2, color: Colors.amber),
      (value: 0.75, activeBars: 3, color: Colors.lightGreen),
      (value: 0.899999, activeBars: 3, color: Colors.lightGreen),
      (value: 0.9, activeBars: 4, color: Colors.green),
    ];
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue).copyWith(surfaceContainer: inactiveColor),
    );

    for (final testCase in cases) {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Center(
            child: SizedBox(width: 160, height: 8, child: SignalStrength(value: testCase.value)),
          ),
        ),
      );

      final bars = tester
          .widgetList<ColoredBox>(find.descendant(of: find.byType(SignalStrength), matching: find.byType(ColoredBox)))
          .toList(growable: false);
      final expectedColors = <Color>[
        ...List<Color>.filled(testCase.activeBars, testCase.color),
        ...List<Color>.filled(4 - testCase.activeBars, inactiveColor),
      ];

      expect(bars.map((bar) => bar.color), expectedColors, reason: 'signal value ${testCase.value}');
    }
  });
}
