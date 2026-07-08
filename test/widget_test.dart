import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/main.dart';
import 'package:speed/src/display_wake_lock.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/logo.dart';
import 'package:speed/src/speed_tracker.dart';

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

  testWidgets('SpeedPage keeps the display awake while mounted', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    final screenAwake = _FakeScreenAwake();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: SpeedPage(
          screenAwake: screenAwake,
          speedTracker: SpeedTracker(
            permissionChecker: () async => true,
            positionStreamProvider: (_) => const Stream<Position>.empty(),
          ),
        ),
      ),
    );

    expect(screenAwake.enableCalls, 1);
    expect(screenAwake.disableCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(screenAwake.disableCalls, 1);
  });
}

class _FakeScreenAwake implements ScreenAwake {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enable() async {
    enableCalls += 1;
  }

  @override
  Future<void> disable() async {
    disableCalls += 1;
  }
}
