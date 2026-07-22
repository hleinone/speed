import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speed/src/animated_app_bar_gradient.dart';
import 'package:speed/src/display_wake_lock.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/logo.dart';
import 'package:speed/src/signal_strength.dart';
import 'package:speed/src/speed_page_controller.dart';
import 'package:speed/src/speed_tracker.dart';
import 'package:speed/src/speed_unit_localization.dart';
import 'package:speed/src/speed_unit_store.dart';

class SpeedPage extends StatefulWidget {
  const SpeedPage({super.key, this.screenAwake, this.trackingSource, this.speedUnitStore, this.initialSpeedUnit});

  final ScreenAwake? screenAwake;
  final SpeedTrackingSource? trackingSource;
  final SpeedUnitStore? speedUnitStore;
  final SpeedUnit? initialSpeedUnit;

  @override
  State<SpeedPage> createState() => _SpeedPageState();
}

class _SpeedPageState extends State<SpeedPage> with WidgetsBindingObserver {
  late final _screenAwake = widget.screenAwake ?? const DisplayWakeLock();
  late final SpeedPageController _controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller = SpeedPageController(
      trackingSource: widget.trackingSource ?? SpeedTracker(),
      speedUnitStore: widget.speedUnitStore ?? const SharedPreferencesSpeedUnitStore(),
      initialSpeedUnit: widget.initialSpeedUnit,
    )..start();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.onAppResumed();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _openAppSettings() async {
    if (!await _controller.openAppSettings()) {
      _showSettingsOpenFailure();
    }
  }

  Future<void> _openLocationSettings() async {
    if (!await _controller.openLocationSettings()) {
      _showSettingsOpenFailure();
    }
  }

  void _showSettingsOpenFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(L10n.of(context).settingsOpenFailed)));
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
              child: _SpeedPageBody(
                state: _controller.state,
                speedUnit: _controller.speedUnit,
                onRetry: () => unawaited(_controller.retry()),
                onOpenAppSettings: () => unawaited(_openAppSettings()),
                onOpenLocationSettings: () => unawaited(_openLocationSettings()),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SpeedPageBody extends StatelessWidget {
  const _SpeedPageBody({
    required this.state,
    required this.speedUnit,
    required this.onRetry,
    required this.onOpenAppSettings,
    required this.onOpenLocationSettings,
  });

  final SpeedPageState state;
  final SpeedUnit speedUnit;
  final VoidCallback onRetry;
  final VoidCallback onOpenAppSettings;
  final VoidCallback onOpenLocationSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return switch (state) {
      SpeedPageAcquiring() => _SpeedStatusView(
        indicator: const CircularProgressIndicator(),
        title: l10n.acquiringSpeedTitle,
        message: l10n.acquiringSpeedMessage,
      ),
      SpeedPageCurrent(:final speed) => _SpeedReadout(speed: speed, speedUnit: speedUnit),
      SpeedPageUnavailable() => _SpeedStatusView(
        indicator: const Icon(Icons.gps_off, size: 48),
        title: l10n.speedUnavailableTitle,
        message: l10n.speedUnavailableMessage,
        actions: [_primaryAction(l10n.tryAgain, Icons.refresh, onRetry)],
      ),
      SpeedPagePermissionDenied(:final isPermanent) => _permissionDenied(context, isPermanent),
      SpeedPageLocationDisabled() => _SpeedStatusView(
        indicator: const Icon(Icons.location_disabled, size: 48),
        title: l10n.locationServicesDisabledTitle,
        message: l10n.locationServicesDisabledMessage,
        actions: [
          _primaryAction(l10n.openLocationSettings, Icons.settings, onOpenLocationSettings),
          _secondaryAction(l10n.tryAgain, Icons.refresh, onRetry),
        ],
      ),
      SpeedPagePreciseLocationRequired() => _SpeedStatusView(
        indicator: const Icon(Icons.gps_fixed, size: 48),
        title: l10n.preciseLocationRequiredTitle,
        message: l10n.preciseLocationRequiredMessage,
        actions: [
          _primaryAction(l10n.openAppSettings, Icons.settings, onOpenAppSettings),
          _secondaryAction(l10n.tryAgain, Icons.refresh, onRetry),
        ],
      ),
      SpeedPageFailure() => _SpeedStatusView(
        indicator: const Icon(Icons.error_outline, size: 48),
        title: l10n.speedTrackingErrorTitle,
        message: l10n.speedTrackingErrorMessage,
        actions: [_primaryAction(l10n.tryAgain, Icons.refresh, onRetry)],
      ),
    };
  }

  Widget _permissionDenied(BuildContext context, bool isPermanent) {
    final l10n = L10n.of(context);
    final retryAction = isPermanent
        ? _secondaryAction(l10n.tryAgain, Icons.refresh, onRetry)
        : _primaryAction(l10n.tryAgain, Icons.refresh, onRetry);
    final settingsAction = isPermanent
        ? _primaryAction(l10n.openAppSettings, Icons.settings, onOpenAppSettings)
        : _secondaryAction(l10n.openAppSettings, Icons.settings, onOpenAppSettings);

    return _SpeedStatusView(
      indicator: const Icon(Icons.location_off, size: 48),
      title: l10n.locationPermissionDeniedTitle,
      message: isPermanent ? l10n.locationPermissionDeniedForeverMessage : l10n.locationPermissionDeniedMessage,
      actions: isPermanent ? [settingsAction, retryAction] : [retryAction, settingsAction],
    );
  }

  Widget _primaryAction(String label, IconData icon, VoidCallback onPressed) {
    return FilledButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }

  Widget _secondaryAction(String label, IconData icon, VoidCallback onPressed) {
    return OutlinedButton.icon(onPressed: onPressed, icon: Icon(icon), label: Text(label));
  }
}

class _SpeedStatusView extends StatelessWidget {
  const _SpeedStatusView({
    required this.indicator,
    required this.title,
    required this.message,
    this.actions = const [],
  });

  final Widget indicator;
  final String title;
  final String message;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            indicator,
            const SizedBox(height: 24),
            Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 24),
              Wrap(alignment: WrapAlignment.center, spacing: 12, runSpacing: 12, children: actions),
            ],
          ],
        ),
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
          .map((unit) => DropdownMenuEntry(label: unit.localizedTitle(context), value: unit))
          .toList(growable: false),
      onSelected: (unit) {
        if (unit != null) onSelected(unit);
      },
    );
  }
}

class _SpeedReadout extends StatelessWidget {
  const _SpeedReadout({required this.speed, required this.speedUnit});

  final CurrentSpeed speed;
  final SpeedUnit speedUnit;

  @override
  Widget build(BuildContext context) {
    final numberFormat = NumberFormat.decimalPattern(L10n.of(context).localeName)
      ..minimumFractionDigits = 0
      ..maximumFractionDigits = 1;
    final speedText = numberFormat.format(speed.getAs(speedUnit));
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
            Text(speedUnit.localizedTitle(context), style: Theme.of(context).textTheme.displaySmall),
          ],
        ),
        SizedBox(height: 8, width: 160, child: SignalStrength(value: speed.accuracy)),
      ],
    );
  }
}
