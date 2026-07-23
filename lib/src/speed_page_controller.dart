import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracking_source.dart';
import 'package:speed/src/speed_unit_store.dart';

sealed class SpeedPageState {
  const SpeedPageState();
}

final class SpeedPageAcquiring extends SpeedPageState {
  const SpeedPageAcquiring();
}

final class SpeedPageCurrent extends SpeedPageState {
  const SpeedPageCurrent(this.speed);

  final CurrentSpeed speed;
}

final class SpeedPageUnavailable extends SpeedPageState {
  const SpeedPageUnavailable();
}

final class SpeedPagePermissionDenied extends SpeedPageState {
  const SpeedPagePermissionDenied({required this.isPermanent});

  final bool isPermanent;
}

final class SpeedPageLocationDisabled extends SpeedPageState {
  const SpeedPageLocationDisabled();
}

final class SpeedPagePreciseLocationRequired extends SpeedPageState {
  const SpeedPagePreciseLocationRequired();
}

final class SpeedPageFailure extends SpeedPageState {
  const SpeedPageFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class SpeedPageController extends ChangeNotifier {
  SpeedPageController({
    required SpeedTrackingSource trackingSource,
    required SpeedUnitStore speedUnitStore,
    SpeedUnit? initialSpeedUnit,
  }) : _trackingSource = trackingSource,
       _speedUnitStore = speedUnitStore,
       _speedUnit = initialSpeedUnit ?? SpeedUnit.metersPerSecond,
       _loadStoredSpeedUnit = initialSpeedUnit == null;

  final SpeedTrackingSource _trackingSource;
  final SpeedUnitStore _speedUnitStore;
  final bool _loadStoredSpeedUnit;

  StreamSubscription<Speed>? _speedSubscription;
  SpeedPageState _state = const SpeedPageAcquiring();
  SpeedUnit _speedUnit;
  int _trackingGeneration = 0;
  bool _hasStarted = false;
  bool _hasUserSelectedSpeedUnit = false;
  bool _retryAfterSettings = false;
  bool _isDisposed = false;

  SpeedPageState get state => _state;

  SpeedUnit get speedUnit => _speedUnit;

  void start() {
    if (_hasStarted) return;
    _hasStarted = true;

    unawaited(retry());
    if (_loadStoredSpeedUnit) {
      unawaited(_loadSpeedUnit());
    }
  }

  Future<void> retry() async {
    if (_isDisposed) return;

    _retryAfterSettings = false;
    final generation = ++_trackingGeneration;
    final previousSubscription = _speedSubscription;
    _speedSubscription = null;
    _setState(const SpeedPageAcquiring());
    await previousSubscription?.cancel();

    if (_isDisposed || generation != _trackingGeneration) return;

    try {
      final subscription = _trackingSource.track().listen(
        (speed) => _handleSpeed(speed, generation),
        onError: (Object error, StackTrace stackTrace) => _handleTrackingError(error, stackTrace, generation),
        onDone: () => _handleTrackingDone(generation),
      );

      if (_isDisposed || generation != _trackingGeneration || _stateStopsTracking) {
        await subscription.cancel();
      } else {
        _speedSubscription = subscription;
      }
    } catch (error, stackTrace) {
      _handleTrackingError(error, stackTrace, generation);
    }
  }

  Future<bool> openAppSettings() => _openSettings(_trackingSource.openAppSettings);

  Future<bool> openLocationSettings() => _openSettings(_trackingSource.openLocationSettings);

  void onAppResumed() {
    if (!_retryAfterSettings) return;
    _retryAfterSettings = false;
    unawaited(retry());
  }

  void selectSpeedUnit(SpeedUnit unit) {
    _hasUserSelectedSpeedUnit = true;
    if (_speedUnit != unit) {
      _speedUnit = unit;
      notifyListeners();
    }
    unawaited(_saveSpeedUnit(unit));
  }

  bool get _stateStopsTracking {
    return _state is SpeedPagePermissionDenied ||
        _state is SpeedPageLocationDisabled ||
        _state is SpeedPagePreciseLocationRequired ||
        _state is SpeedPageFailure;
  }

  void _handleSpeed(Speed speed, int generation) {
    if (_isDisposed || generation != _trackingGeneration) return;
    _setState(switch (speed) {
      CurrentSpeed() => SpeedPageCurrent(speed),
      UnavailableSpeed() => const SpeedPageUnavailable(),
    });
  }

  void _handleTrackingError(Object error, StackTrace stackTrace, int generation) {
    if (_isDisposed || generation != _trackingGeneration) return;

    final state = switch (error) {
      SpeedTrackingException(kind: SpeedTrackingFailureKind.permissionDenied) => const SpeedPagePermissionDenied(
        isPermanent: false,
      ),
      SpeedTrackingException(kind: SpeedTrackingFailureKind.permissionDeniedForever) => const SpeedPagePermissionDenied(
        isPermanent: true,
      ),
      SpeedTrackingException(kind: SpeedTrackingFailureKind.locationServicesDisabled) =>
        const SpeedPageLocationDisabled(),
      SpeedTrackingException(kind: SpeedTrackingFailureKind.preciseLocationRequired) =>
        const SpeedPagePreciseLocationRequired(),
      SpeedTrackingException(
        kind: SpeedTrackingFailureKind.unexpected,
        :final cause,
        stackTrace: final failureStackTrace,
      ) =>
        SpeedPageFailure(cause ?? error, failureStackTrace ?? stackTrace),
      _ => SpeedPageFailure(error, stackTrace),
    };

    _setState(state);
    if (state is SpeedPageFailure) {
      _logError('Speed tracking failed', state.error, state.stackTrace);
    }
    unawaited(_cancelCurrentSubscription(generation));
  }

  void _handleTrackingDone(int generation) {
    if (_isDisposed || generation != _trackingGeneration) return;
    _speedSubscription = null;
    if (_state is SpeedPageAcquiring || _state is SpeedPageCurrent) {
      _setState(const SpeedPageUnavailable());
    }
  }

  Future<void> _cancelCurrentSubscription(int generation) async {
    if (_isDisposed || generation != _trackingGeneration) return;
    final subscription = _speedSubscription;
    _speedSubscription = null;
    await subscription?.cancel();
  }

  Future<bool> _openSettings(Future<bool> Function() openSettings) async {
    try {
      final opened = await openSettings();
      _retryAfterSettings = opened;
      return opened;
    } catch (error, stackTrace) {
      _retryAfterSettings = false;
      _logError('Failed to open settings', error, stackTrace);
      return false;
    }
  }

  void _setState(SpeedPageState state) {
    if (_isDisposed) {
      return;
    }
    _state = state;
    notifyListeners();
  }

  Future<void> _loadSpeedUnit() async {
    try {
      final unit = await _speedUnitStore.load();
      if (_isDisposed || _hasUserSelectedSpeedUnit || unit == _speedUnit) {
        return;
      }
      _speedUnit = unit;
      notifyListeners();
    } catch (error, stackTrace) {
      _logError('Failed to load the speed unit', error, stackTrace);
    }
  }

  Future<void> _saveSpeedUnit(SpeedUnit unit) async {
    try {
      await _speedUnitStore.save(unit);
    } catch (error, stackTrace) {
      _logError('Failed to save the speed unit', error, stackTrace);
    }
  }

  void _logError(String message, Object error, StackTrace stackTrace) {
    debugPrint('$message: $error');
    debugPrint(stackTrace.toString());
  }

  @override
  void dispose() {
    _isDisposed = true;
    _trackingGeneration += 1;
    unawaited(_speedSubscription?.cancel());
    super.dispose();
  }
}
