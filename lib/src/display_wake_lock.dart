import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

abstract interface class ScreenAwake {
  Future<void> enable();

  Future<void> disable();
}

class DisplayWakeLock implements ScreenAwake {
  const DisplayWakeLock();

  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

class KeepScreenAwake extends StatefulWidget {
  const KeepScreenAwake({super.key, required this.screenAwake, required this.child});

  final ScreenAwake screenAwake;
  final Widget child;

  @override
  State<KeepScreenAwake> createState() => _KeepScreenAwakeState();
}

class _KeepScreenAwakeState extends State<KeepScreenAwake> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enable());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_enable());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_disable());
    super.dispose();
  }

  Future<void> _enable() async {
    try {
      await widget.screenAwake.enable();
    } catch (error, stackTrace) {
      debugPrint('Failed to enable display wake lock: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _disable() async {
    try {
      await widget.screenAwake.disable();
    } catch (error, stackTrace) {
      debugPrint('Failed to disable display wake lock: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
