import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_unit_store.dart';

typedef SpeedPageErrorHandler = void Function(Object error, StackTrace stackTrace);

class SpeedPageController extends ChangeNotifier {
  SpeedPageController({
    required Stream<Speed> speedStream,
    required SpeedUnitStore speedUnitStore,
    SpeedUnit? initialSpeedUnit,
    SpeedPageErrorHandler? onError,
  }) : _speedStream = speedStream,
       _speedUnitStore = speedUnitStore,
       _speedUnit = initialSpeedUnit ?? SpeedUnit.metersPerSecond,
       _loadStoredSpeedUnit = initialSpeedUnit == null,
       _onError = onError;

  final Stream<Speed> _speedStream;
  final SpeedUnitStore _speedUnitStore;
  final bool _loadStoredSpeedUnit;
  final SpeedPageErrorHandler? _onError;

  StreamSubscription<Speed>? _speedSubscription;
  Speed? _speed;
  SpeedUnit _speedUnit;
  bool _hasStarted = false;
  bool _hasUserSelectedSpeedUnit = false;
  bool _isDisposed = false;

  Speed? get speed => _speed;

  SpeedUnit get speedUnit => _speedUnit;

  void start() {
    if (_hasStarted) return;
    _hasStarted = true;

    _speedSubscription = _speedStream.listen(_handleSpeed, onError: _handleError);
    if (_loadStoredSpeedUnit) {
      unawaited(_loadSpeedUnit());
    }
  }

  void selectSpeedUnit(SpeedUnit unit) {
    _hasUserSelectedSpeedUnit = true;
    if (_speedUnit != unit) {
      _speedUnit = unit;
      notifyListeners();
    }
    unawaited(_saveSpeedUnit(unit));
  }

  void _handleSpeed(Speed speed) {
    if (_isDisposed) return;
    _speed = speed;
    notifyListeners();
  }

  void _handleError(Object error, StackTrace stackTrace) {
    if (_isDisposed) return;
    _onError?.call(error, stackTrace);
  }

  Future<void> _loadSpeedUnit() async {
    try {
      final unit = await _speedUnitStore.load();
      if (_isDisposed || _hasUserSelectedSpeedUnit || unit == _speedUnit) return;
      _speedUnit = unit;
      notifyListeners();
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
    }
  }

  Future<void> _saveSpeedUnit(SpeedUnit unit) async {
    try {
      await _speedUnitStore.save(unit);
    } catch (error, stackTrace) {
      _handleError(error, stackTrace);
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    unawaited(_speedSubscription?.cancel());
    super.dispose();
  }
}
