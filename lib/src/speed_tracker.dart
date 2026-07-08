import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/speed_sample_processor.dart';
import 'package:speed/src/speed_tracker/speed_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;

export 'package:speed/src/speed_tracker/models.dart';

typedef SpeedTrackerClock = DateTime Function();
typedef SpeedTrackerPermissionChecker = Future<bool> Function();
typedef SpeedTrackerPositionStreamProvider = Stream<Position> Function(LocationSettings locationSettings);

class SpeedTracker {
  static const double fallbackSpeedAccuracy = config.fallbackSpeedAccuracy;
  static const double unknownSpeedConfidence = config.unknownSpeedConfidence;
  static const double maxSpeedAccuracyError = config.maxSpeedAccuracyError;
  static const double maxAcceptedHorizontalAccuracy = config.maxAcceptedHorizontalAccuracy;
  static const double maxPlausibleAcceleration = config.maxPlausibleAcceleration;
  static const double fallbackSpeedConfidence = config.fallbackSpeedConfidence;
  static const Duration maxSampleAge = config.maxSampleAge;
  static const Duration positionUpdateInterval = config.positionUpdateInterval;
  static const Duration freshnessTimeout = config.freshnessTimeout;
  static const Duration maxFutureSampleSkew = config.maxFutureSampleSkew;
  static const int startupWarmupAcceptedSamples = config.startupWarmupAcceptedSamples;

  /// Process noise per second for the Kalman filter. A lower value means more smoothing but less responsiveness.
  final double processNoise;
  final SpeedTrackerClock _clock;
  final SpeedTrackerPermissionChecker? _permissionChecker;
  final SpeedTrackerPositionStreamProvider? _positionStreamProvider;

  SpeedTracker({
    this.processNoise = 0.1,
    SpeedTrackerClock? clock,
    SpeedTrackerPermissionChecker? permissionChecker,
    SpeedTrackerPositionStreamProvider? positionStreamProvider,
  }) : _clock = clock ?? DateTime.now,
       _permissionChecker = permissionChecker,
       _positionStreamProvider = positionStreamProvider;

  Stream<Speed> get stream async* {
    late final StreamController<Speed> controller;
    StreamSubscription<Position>? positionStreamSubscription;
    Timer? freshnessTimer;
    SpeedStatus lastEmittedStatus = SpeedStatus.unavailable;

    final locationSettings = createLocationSettings(defaultTargetPlatform);
    final speedProcessor = SpeedSampleProcessor(processNoise: processNoise);

    final hasPermission = await (_permissionChecker ?? _checkPermissions)();
    if (!hasPermission) {
      yield* Stream.error('Location permission denied');
      return;
    }

    void emitUnavailable() {
      if (controller.isClosed || lastEmittedStatus == SpeedStatus.unavailable) {
        return;
      }

      controller.add(const Speed.unavailable());
      lastEmittedStatus = SpeedStatus.unavailable;
    }

    void scheduleFreshnessWatchdog(AcceptedSpeedSample sample) {
      freshnessTimer?.cancel();
      final age = _clock().difference(sample.timestamp);
      final delay = freshnessTimeout - age;
      freshnessTimer = Timer(delay.isNegative ? Duration.zero : delay, emitUnavailable);
    }

    void emitCurrentSpeed(Speed speed, AcceptedSpeedSample sample) {
      if (controller.isClosed) {
        return;
      }

      controller.add(speed);
      lastEmittedStatus = SpeedStatus.current;
      scheduleFreshnessWatchdog(sample);
    }

    void onListen() {
      positionStreamSubscription = _getPositionStream(locationSettings).listen(
        (position) {
          final processedSample = speedProcessor.process(position, _clock());
          if (processedSample != null) {
            emitCurrentSpeed(processedSample.speed, processedSample.acceptedSample);
          }
        },
        onError: (error) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
      );
    }

    Future<void> onCancel() async {
      freshnessTimer?.cancel();
      await positionStreamSubscription?.cancel();
    }

    controller = StreamController<Speed>(
      onListen: onListen,
      onPause: () => positionStreamSubscription?.pause(),
      onResume: () => positionStreamSubscription?.resume(),
      onCancel: onCancel,
    );

    yield* controller.stream;
  }

  Stream<Position> _getPositionStream(LocationSettings locationSettings) {
    final positionStreamProvider = _positionStreamProvider;
    if (positionStreamProvider != null) {
      return positionStreamProvider(locationSettings);
    }
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  @visibleForTesting
  static LocationSettings createLocationSettings(TargetPlatform platform) {
    if (platform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: positionUpdateInterval,
      );
    }
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return AppleSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    }
    return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
  }

  static SpeedAccuracyEstimate normalizeSpeedAccuracy(double speedAccuracy) {
    return const SpeedSampleValidator().normalizeSpeedAccuracy(speedAccuracy);
  }

  static SpeedSampleValidation validateSpeedSample({
    required double speed,
    required DateTime timestamp,
    required double horizontalAccuracy,
    required double speedAccuracy,
    required DateTime now,
    AcceptedSpeedSample? previousAcceptedSample,
    bool enforceAccelerationLimit = true,
  }) {
    return const SpeedSampleValidator().validate(
      speed: speed,
      timestamp: timestamp,
      horizontalAccuracy: horizontalAccuracy,
      speedAccuracy: speedAccuracy,
      now: now,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
    );
  }

  Future<bool> _checkPermissions() async {
    final platform = defaultTargetPlatform;
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      debugPrint('permission: $permission');
      return false;
    }

    var accuracy = LocationAccuracyStatus.precise;
    if (platform == TargetPlatform.android || platform == TargetPlatform.iOS) {
      accuracy = await Geolocator.getLocationAccuracy();
    }

    if (platform == TargetPlatform.iOS && accuracy == LocationAccuracyStatus.reduced) {
      accuracy = await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'SpeedPurposeKey');
    }

    debugPrint('permission: $permission, accuracy: $accuracy');

    return accuracy == LocationAccuracyStatus.precise;
  }
}
