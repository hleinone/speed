import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speed/src/animated_app_bar_gradient.dart';
import 'package:speed/src/display_wake_lock.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/logo.dart';
import 'package:speed/src/signal_strength.dart';
import 'package:speed/src/speed_page_controller.dart';
import 'package:speed/src/speed_tracker.dart';
import 'package:speed/src/speed_unit_store.dart';

class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key, this.screenAwake, this.speedStream, this.speedUnitStore, this.initialSpeedUnit});

  final ScreenAwake? screenAwake;
  final Stream<Speed>? speedStream;
  final SpeedUnitStore? speedUnitStore;
  final SpeedUnit? initialSpeedUnit;

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> {
  late final _screenAwake = widget.screenAwake ?? const DisplayWakeLock();
  late final SpeedPageController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SpeedPageController(
      speedStream: widget.speedStream ?? SpeedTracker().stream,
      speedUnitStore: widget.speedUnitStore ?? const SharedPreferencesSpeedUnitStore(),
      initialSpeedUnit: widget.initialSpeedUnit,
      onError: _showError,
    )..start();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showError(Object error, StackTrace _) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
    });
  }

  @override
  Widget build(BuildContext context) {
    return KeepScreenAwake(
      screenAwake: _screenAwake,
      child: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          return Scaffold(
            appBar: AppBar(
              flexibleSpace: const AnimatedAppBarGradient(colors: [Color(0xFFAF0000), Color(0xFF5CB0FF)]),
              title: const Align(
                alignment: AlignmentDirectional.centerStart,
                child: SpeedLogo(height: 28, semanticLabel: 'Speed'),
              ),
              actions: [_SpeedUnitMenu(selectedUnit: _controller.speedUnit, onSelected: _controller.selectSpeedUnit)],
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
            ),
            body: Center(
              child: _SpeedReadout(speed: _controller.speed, speedUnit: _controller.speedUnit),
            ),
          );
        },
      ),
    );
  }
}

class _SpeedUnitMenu extends StatelessWidget {
  const _SpeedUnitMenu({required this.selectedUnit, required this.onSelected});

  final SpeedUnit selectedUnit;
  final ValueChanged<SpeedUnit> onSelected;

  @override
  Widget build(BuildContext context) {
    return DropdownMenu(
      initialSelection: selectedUnit,
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
          .map((unit) => DropdownMenuEntry(label: unit.title(context), value: unit))
          .toList(growable: false),
      onSelected: (unit) {
        if (unit != null) onSelected(unit);
      },
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.speed, required this.speedUnit});

  final Speed? speed;
  final SpeedUnit speedUnit;

  @override
  Widget build(BuildContext context) {
    final speed = this.speed;
    if (speed == null) {
      return const CircularProgressIndicator();
    }

    final numberFormat = NumberFormat.decimalPattern(L10n.of(context).localeName);
    final speedText = speed.isCurrent ? numberFormat.format(speed.getAs(speedUnit)) : '--';
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
            Text(speedUnit.title(context), style: Theme.of(context).textTheme.displaySmall),
          ],
        ),
        SizedBox(height: 8, width: 160, child: SignalStrength(value: speed.isCurrent ? speed.accuracy : 0)),
      ],
    );
  }
}
