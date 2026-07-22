import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/main.dart';
import 'package:speed/src/animated_app_bar_gradient.dart';
import 'package:speed/src/display_wake_lock.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/logo.dart';
import 'package:speed/src/signal_strength.dart';
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
    expect(find.descendant(of: find.byType(SpeedLogo), matching: find.byType(CustomPaint)), findsOneWidget);
    expect(find.bySemanticsLabel('Speed'), findsOneWidget);
  });

  testWidgets('AppBar gradient uses the requested colors and moves horizontally', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AnimatedAppBarGradient(random: math.Random(42), colors: const [Color(0xffffffff), Color(0xff000000)]),
      ),
    );

    final initialGradient = _appBarGradient(tester);
    expect(initialGradient.colors, const [Color(0xffffffff), Color(0xff000000)]);

    await tester.pump(const Duration(seconds: 8));

    final movedGradient = _appBarGradient(tester);
    final initialCenter = _gradientCenter(initialGradient);
    final movedCenter = _gradientCenter(movedGradient);
    final horizontalTravel = (movedCenter.dx - initialCenter.dx).abs();
    final verticalTravel = (movedCenter.dy - initialCenter.dy).abs();

    expect(movedGradient.begin, isNot(initialGradient.begin));
    expect(horizontalTravel, greaterThan(verticalTravel));
  });

  testWidgets('AppBar gradient stays still when animations are disabled', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: AnimatedAppBarGradient(random: math.Random(42), colors: const [Color(0xffffffff), Color(0xff000000)]),
        ),
      ),
    );

    final initialGradient = _appBarGradient(tester);
    await tester.pump(const Duration(seconds: 30));
    final laterGradient = _appBarGradient(tester);

    expect(laterGradient.begin, initialGradient.begin);
    expect(laterGradient.end, initialGradient.end);
  });

  testWidgets('SpeedPage keeps the display awake while mounted', (tester) async {
    SharedPreferences.setMockInitialValues({});

    final screenAwake = _FakeScreenAwake();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: SpeedPage(
          screenAwake: screenAwake,
          speedStream: SpeedTracker(
            permissionChecker: () async => true,
            positionStreamProvider: (_) => const Stream<Position>.empty(),
          ).stream,
        ),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.flexibleSpace, isA<AnimatedAppBarGradient>());
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(screenAwake.enableCalls, 1);
    expect(screenAwake.disableCalls, 0);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(screenAwake.disableCalls, 1);
  });

  testWidgets('SpeedPage renders an injected speed with Finnish formatting', (tester) async {
    final screenAwake = _FakeScreenAwake();

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('fi'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: SpeedPage(
              screenAwake: screenAwake,
              speedStream: Stream.value(const Speed.current(42 / 2.236936, 0.68)),
              initialSpeedUnit: SpeedUnit.milesPerHour,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);
    expect(find.text('mi/h'), findsWidgets);
    expect(find.byType(SignalStrength), findsOneWidget);
  });

  testWidgets('SpeedPage renders an injected speed with English formatting', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: SpeedPage(
              screenAwake: _FakeScreenAwake(),
              speedStream: Stream.value(const Speed.current(42 / 2.236936, 0.68)),
              initialSpeedUnit: SpeedUnit.milesPerHour,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('42'), findsOneWidget);
    expect(find.text('mph'), findsWidgets);
    expect(tester.widget<SignalStrength>(find.byType(SignalStrength)).value, 0.68);
  });

  testWidgets('SpeedPage unit menu opens with all localized choices', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: SpeedPage(
              screenAwake: _FakeScreenAwake(),
              speedStream: Stream.value(const Speed.current(15, 0.88)),
              initialSpeedUnit: SpeedUnit.metersPerSecond,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownMenu<SpeedUnit>));
    await tester.pumpAndSettle();

    expect(find.text('km/h'), findsWidgets);
    expect(find.text('mph'), findsWidgets);
    expect(find.text('m/s'), findsWidgets);
    expect(find.text('fps'), findsWidgets);
    expect(find.text('knots'), findsWidgets);
  });
}

LinearGradient _appBarGradient(WidgetTester tester) {
  final decoratedBox = tester.widget<DecoratedBox>(
    find.descendant(of: find.byType(AnimatedAppBarGradient), matching: find.byType(DecoratedBox)),
  );
  return (decoratedBox.decoration as BoxDecoration).gradient! as LinearGradient;
}

Offset _gradientCenter(LinearGradient gradient) {
  final begin = gradient.begin as Alignment;
  final end = gradient.end as Alignment;
  return Offset((begin.x + end.x) / 2, (begin.y + end.y) / 2);
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
