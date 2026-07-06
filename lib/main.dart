import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/logo.dart';
import 'package:speed/src/signal_strength.dart';
import 'package:speed/src/speed_tracker.dart';

void main() {
  runApp(const SpeedApp());
}

class SpeedApp extends StatelessWidget {
  const SpeedApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speed',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)).copyWith(
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
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: const SpeedPage(),
    );
  }
}

class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key});

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> with TickerProviderStateMixin {
  late NumberFormat _numberFormat;
  String? _localeName;
  final _speedTracker = SpeedTracker();
  final _subscriptions = CompositeSubscription();
  Speed? _speed;
  SpeedUnit _speedUnit = SpeedUnit.metersPerSecond;

  @override
  void initState() {
    super.initState();

    _speedTracker.stream
        .listen(
          (speed) {
            setState(() => _speed = speed);
          },
          onError: (error) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
          },
        )
        .addTo(_subscriptions);

    SharedPreferences.getInstance().then((sharedPreferences) {
      final index = sharedPreferences.getInt('selected_speed_unit') ?? SpeedUnit.metersPerSecond.index;
      setState(() => _speedUnit = SpeedUnit.values[index]);
    });
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
    _subscriptions.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Align(
          alignment: AlignmentDirectional.centerStart,
          child: SpeedLogo(height: 28, semanticLabel: 'Speed'),
        ),
        actions: [
          DropdownMenu(
            initialSelection: _speedUnit,
            enableSearch: false,
            requestFocusOnTap: false,
            keyboardType: TextInputType.none,
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
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
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
