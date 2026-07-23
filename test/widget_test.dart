import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speed/main.dart';
import 'package:speed/src/animated_app_bar_gradient.dart';
import 'package:speed/src/display_wake_lock.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/logo.dart';
import 'package:speed/src/signal_strength.dart';
import 'package:speed/src/speed_page.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracking_source.dart';
import 'package:speed/src/speed_unit_store.dart';

void main() {
  testWidgets('SpeedApp builds consistent light and dark themes', (tester) async {
    const themeProbeKey = ValueKey('theme-probe');

    for (final (themeMode, brightness) in [(ThemeMode.light, Brightness.light), (ThemeMode.dark, Brightness.dark)]) {
      await tester.pumpWidget(
        SpeedApp(
          themeMode: themeMode,
          fontFamily: 'TestFont',
          home: const SizedBox(key: themeProbeKey),
        ),
      );
      await tester.pumpAndSettle();

      final theme = Theme.of(tester.element(find.byKey(themeProbeKey)));
      final inputDecorationTheme = theme.dropdownMenuTheme.inputDecorationTheme;

      expect(theme.brightness, brightness);
      expect(theme.colorScheme.brightness, brightness);
      expect(theme.textTheme.bodyMedium?.fontFamily, 'TestFont');
      expect(theme.dropdownMenuTheme.textStyle, isNull);
      expect(inputDecorationTheme?.border, InputBorder.none);
      expect(inputDecorationTheme?.contentPadding, EdgeInsets.zero);
    }
  });

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
    final screenAwake = _FakeScreenAwake();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: SpeedPage(
          screenAwake: screenAwake,
          speedUnitStore: _FakeSpeedUnitStore(),
          trackingSource: _FakeTrackingSource([const Stream<Speed>.empty()]),
        ),
      ),
    );

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.flexibleSpace, isA<AnimatedAppBarGradient>());
    expect(appBar.backgroundColor, Colors.transparent);
    expect(appBar.surfaceTintColor, Colors.transparent);
    expect(screenAwake.enableCalls, 1);
    expect(screenAwake.disableCalls, 0);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(screenAwake.enableCalls, 2);

    await tester.pumpWidget(const SizedBox.shrink());

    expect(screenAwake.disableCalls, 1);
  });

  testWidgets('SpeedPage presents generic errors without exposing raw details', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: SpeedPage(
          screenAwake: _FakeScreenAwake(),
          trackingSource: _FakeTrackingSource([Stream<Speed>.error(StateError('secret GPS details'))]),
          speedUnitStore: _FakeSpeedUnitStore(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Something went wrong'), findsOneWidget);
    expect(find.text('Speed could not be measured. Please try again.'), findsOneWidget);
    expect(find.textContaining('secret GPS details'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('SpeedPage shows permanent permission recovery and retries', (tester) async {
    final source = _FakeTrackingSource([
      Stream<Speed>.error(
        SpeedTrackingException(
          SpeedTrackingFailureKind.permissionDeniedForever,
          cause: StateError('private platform message'),
        ),
      ),
      _activeSpeedStream(const CurrentSpeed(10, 0.75)),
    ]);
    await tester.pumpWidget(_speedPage(source));
    await tester.pump();
    await tester.pump();

    expect(find.text('Location access is needed'), findsOneWidget);
    expect(find.text('Allow location access in app settings to measure your speed.'), findsOneWidget);
    expect(find.text('Open app settings'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('private platform message'), findsNothing);

    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump();

    expect(find.text('10'), findsOneWidget);
    expect(source.trackCalls, 2);
  });

  testWidgets('SpeedPage explains retryable permission denial', (tester) async {
    final source = _FakeTrackingSource([
      Stream<Speed>.error(const SpeedTrackingException(SpeedTrackingFailureKind.permissionDenied)),
    ]);
    await tester.pumpWidget(_speedPage(source));
    await tester.pump();
    await tester.pump();

    expect(find.text('Location access is needed'), findsOneWidget);
    expect(find.text('Allow location access to measure your speed.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Open app settings'), findsOneWidget);
  });

  testWidgets('SpeedPage opens location settings and retries when the app resumes', (tester) async {
    final source = _FakeTrackingSource([
      Stream<Speed>.error(const SpeedTrackingException(SpeedTrackingFailureKind.locationServicesDisabled)),
      _activeSpeedStream(const CurrentSpeed(8, 0.8)),
    ]);
    await tester.pumpWidget(_speedPage(source));
    await tester.pump();
    await tester.pump();

    expect(find.text('Location services are off'), findsOneWidget);
    await tester.tap(find.text('Open location settings'));
    await tester.pump();
    expect(source.openLocationSettingsCalls, 1);
    expect(source.trackCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump();

    expect(find.text('8'), findsOneWidget);
    expect(source.trackCalls, 2);
  });

  testWidgets('SpeedPage shows a localized snackbar when settings cannot open', (tester) async {
    final source = _FakeTrackingSource([
      Stream<Speed>.error(const SpeedTrackingException(SpeedTrackingFailureKind.preciseLocationRequired)),
    ], appSettingsOpened: false);
    await tester.pumpWidget(_speedPage(source));
    await tester.pump();
    await tester.pump();

    expect(find.text('Precise location is needed'), findsOneWidget);
    await tester.tap(find.text('Open app settings'));
    await tester.pump();

    expect(find.text('Settings could not be opened.'), findsOneWidget);
    expect(find.text('Precise location is needed'), findsOneWidget);
  });

  testWidgets('SpeedPage localizes acquiring and unavailable states in Finnish', (tester) async {
    final speedStream = StreamController<Speed>();
    final source = _FakeTrackingSource([speedStream.stream]);
    await tester.pumpWidget(_speedPage(source, locale: const Locale('fi')));
    await tester.pump();

    expect(find.text('Haetaan nopeutta'), findsOneWidget);
    expect(find.text('Odotetaan GPS-signaalia…'), findsOneWidget);

    speedStream.add(const UnavailableSpeed());
    await tester.pump();

    expect(find.text('Nopeutta ei ole saatavilla'), findsOneWidget);
    expect(find.text('Yritä uudelleen'), findsOneWidget);
    await speedStream.close();
  });

  testWidgets('SpeedPage replaces a current speed when tracking completes', (tester) async {
    final speedStream = StreamController<Speed>();
    await tester.pumpWidget(_speedPage(_FakeTrackingSource([speedStream.stream])));
    await tester.pump();

    speedStream.add(const CurrentSpeed(12, 0.8));
    await tester.pump();
    expect(find.text('12'), findsOneWidget);
    expect(find.byType(SignalStrength), findsOneWidget);

    await speedStream.close();
    await tester.pump();

    expect(find.text('Speed unavailable'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Try again'), findsOneWidget);
    expect(find.byType(SignalStrength), findsNothing);
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
              trackingSource: _FakeTrackingSource([_activeSpeedStream(const CurrentSpeed(42 / 2.236936, 0.68))]),
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
              trackingSource: _FakeTrackingSource([_activeSpeedStream(const CurrentSpeed(42 / 2.236936, 0.68))]),
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

  testWidgets('SpeedPage rounds exact unit conversions in the readout', (tester) async {
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
              trackingSource: _FakeTrackingSource([_activeSpeedStream(const CurrentSpeed(1, 0.8))]),
              initialSpeedUnit: SpeedUnit.milesPerHour,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('2.2'), findsOneWidget);
    expect(find.text('2.236936'), findsNothing);
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
              trackingSource: _FakeTrackingSource([_activeSpeedStream(const CurrentSpeed(15, 0.88))]),
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

Stream<Speed> _activeSpeedStream(Speed speed) {
  return Stream.multi((controller) => controller.add(speed));
}

Widget _speedPage(_FakeTrackingSource source, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: SpeedPage(
      screenAwake: _FakeScreenAwake(),
      trackingSource: source,
      speedUnitStore: _FakeSpeedUnitStore(),
      initialSpeedUnit: SpeedUnit.metersPerSecond,
    ),
  );
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

class _FakeSpeedUnitStore implements SpeedUnitStore {
  SpeedUnit unit = SpeedUnit.metersPerSecond;

  @override
  Future<SpeedUnit> load() async => unit;

  @override
  Future<void> save(SpeedUnit unit) async {
    this.unit = unit;
  }
}

class _FakeTrackingSource implements SpeedTrackingSource {
  _FakeTrackingSource(this.streams, {this.appSettingsOpened = true});

  final List<Stream<Speed>> streams;
  final bool appSettingsOpened;
  int trackCalls = 0;
  int openAppSettingsCalls = 0;
  int openLocationSettingsCalls = 0;

  @override
  Stream<Speed> track() {
    final index = trackCalls++;
    return streams[index];
  }

  @override
  Future<bool> openAppSettings() async {
    openAppSettingsCalls += 1;
    return appSettingsOpened;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls += 1;
    return true;
  }
}
