import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/src/animated_app_bar_gradient.dart';
import 'package:speed/src/display_wake_lock.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/logo.dart';
import 'package:speed/src/signal_strength.dart';
import 'package:speed/src/speed_tracker.dart';

void main() {
  runApp(const SpeedApp());
}

class SpeedApp extends StatelessWidget {
  const SpeedApp({
    super.key,
    this.locale,
    this.home = const SpeedPage(),
    this.themeMode,
    this.fontFamily,
    this.debugShowCheckedModeBanner = true,
  });

  final Locale? locale;
  final Widget home;
  final ThemeMode? themeMode;
  final String? fontFamily;
  final bool debugShowCheckedModeBanner;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speed',
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      locale: locale,
      theme:
          ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
            fontFamily: fontFamily,
          ).copyWith(
            dropdownMenuTheme: const DropdownMenuThemeData(
              inputDecorationTheme: InputDecorationTheme(border: InputBorder.none, contentPadding: EdgeInsets.zero),
            ),
          ),
      darkTheme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        dropdownMenuTheme: const DropdownMenuThemeData(
          textStyle: TextStyle(color: Colors.black),
          inputDecorationTheme: InputDecorationTheme(border: InputBorder.none, contentPadding: EdgeInsets.zero),
        ),
      ),
      themeMode: themeMode ?? ThemeMode.system,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: home,
    );
  }
}

class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key, this.screenAwake, this.speedStream, this.initialSpeedUnit});

  final ScreenAwake? screenAwake;
  final Stream<Speed>? speedStream;
  final SpeedUnit? initialSpeedUnit;

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> with WidgetsBindingObserver {
  late NumberFormat _numberFormat;
  String? _localeName;
  late final _screenAwake = widget.screenAwake ?? const DisplayWakeLock();
  StreamSubscription<Speed>? _subscription;
  Speed? _speed;
  late SpeedUnit _speedUnit;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableScreenAwake());

    _speedUnit = widget.initialSpeedUnit ?? SpeedUnit.metersPerSecond;

    final speedStream = widget.speedStream ?? SpeedTracker().stream;
    _subscription = speedStream.listen(
      (speed) {
        setState(() => _speed = speed);
      },
      onError: (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
      },
    );

    if (widget.initialSpeedUnit == null) {
      SharedPreferences.getInstance().then((sharedPreferences) {
        final index = sharedPreferences.getInt('selected_speed_unit') ?? SpeedUnit.metersPerSecond.index;
        if (!mounted) return;
        setState(() => _speedUnit = SpeedUnit.values.elementAtOrNull(index) ?? SpeedUnit.metersPerSecond);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_enableScreenAwake());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final localeName = L10n.of(context).localeName;
    if (_localeName != localeName) {
      _localeName = localeName;
      _numberFormat = NumberFormat.decimalPattern(localeName);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_subscription?.cancel());
    unawaited(_disableScreenAwake());
    super.dispose();
  }

  Future<void> _enableScreenAwake() async {
    try {
      await _screenAwake.enable();
    } catch (error, stackTrace) {
      debugPrint('Failed to enable display wake lock: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _disableScreenAwake() async {
    try {
      await _screenAwake.disable();
    } catch (error, stackTrace) {
      debugPrint('Failed to disable display wake lock: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: const AnimatedAppBarGradient(colors: [Color(0xFFAF0000), Color(0xFF5CB0FF)]),
        title: const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SpeedLogo(height: 28, semanticLabel: 'Speed'),
        ),
        actions: [
          DropdownMenu(
            initialSelection: _speedUnit,
            textAlign: TextAlign.end,
            enableSearch: false,
            requestFocusOnTap: false,
            keyboardType: TextInputType.none,
            menuStyle: const MenuStyle(
              elevation: WidgetStatePropertyAll(0),
              shadowColor: WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            ),
            dropdownMenuEntries: SpeedUnit.values
                .map((u) => DropdownMenuEntry(label: u.title(context), value: u))
                .toList(),
            onSelected: (value) {
              if (value == null) return;
              setState(() => _speedUnit = value);
              SharedPreferences.getInstance().then((sharedPreferences) {
                sharedPreferences.setInt('selected_speed_unit', _speedUnit.index);
              });
            },
          ),
        ],
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      body: Center(
        child: Builder(
          builder: (context) {
            final speed = _speed;
            if (speed == null) {
              return const CircularProgressIndicator();
            }
            final speedText = speed.isCurrent ? _numberFormat.format(speed.getAs(_speedUnit)) : '--';
            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.ideographic,
                  spacing: 8,
                  children: [
                    Text(speedText, style: Theme.of(context).textTheme.displayLarge),
                    Text(_speedUnit.title(context), style: Theme.of(context).textTheme.displaySmall),
                  ],
                ),
                SizedBox(height: 8, width: 160, child: SignalStrength(value: speed.isCurrent ? speed.accuracy : 0)),
              ],
            );
          },
        ),
      ),
    );
  }
}
