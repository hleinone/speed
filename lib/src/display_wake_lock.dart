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
