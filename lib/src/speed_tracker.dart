import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/util/kalman_filter.dart';

typedef SpeedTrackerClock = DateTime Function();
typedef SpeedTrackerPermissionChecker = Future<bool> Function();
typedef SpeedTrackerPositionStreamProvider = Stream<Position> Function(LocationSettings locationSettings);

class SpeedTracker {
  static const double fallbackSpeedAccuracy = 2.0;
  static const double unknownSpeedConfidence = 0.25;
  static const double maxSpeedAccuracyError = 5.0;
  static const double maxAcceptedHorizontalAccuracy = 50.0;
  static const double maxHorizontalAccuracyError = maxAcceptedHorizontalAccuracy;
  static const double maxPlausibleAcceleration = 8.0;
  static const Duration maxSampleAge = Duration(seconds: 5);
  static const Duration maxFutureSampleSkew = Duration(seconds: 1);
  static const int startupWarmupAcceptedSamples = 3;

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
    var acceptedStreamSampleCount = 0;

    /// The Kalman filter instance for smoothing speed.
    KalmanFilter? kalmanFilter;
    AcceptedSpeedSample? lastAcceptedSample;

    final LocationSettings locationSettings;

    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    } else if (Platform.isIOS || Platform.isMacOS) {
      locationSettings = AppleSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    } else {
      locationSettings = const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    }

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
      final delay = maxSampleAge - age;
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
          final previousAcceptedSample = lastAcceptedSample;
          final isStartupWarmup = acceptedStreamSampleCount < startupWarmupAcceptedSamples;
          final validation = validateSpeedSample(
            speed: position.speed,
            timestamp: position.timestamp,
            horizontalAccuracy: position.accuracy,
            speedAccuracy: position.speedAccuracy,
            now: _clock(),
            previousAcceptedSample: previousAcceptedSample,
            enforceAccelerationLimit: !isStartupWarmup,
          );
          final acceptedSample = validation.acceptedSample;
          if (acceptedSample == null) {
            return;
          }

          lastAcceptedSample = acceptedSample;
          acceptedStreamSampleCount++;

          final double filteredSpeed;
          final existingFilter = kalmanFilter;
          if (acceptedStreamSampleCount <= startupWarmupAcceptedSamples) {
            kalmanFilter = _createKalmanFilter(acceptedSample);
            filteredSpeed = acceptedSample.speed;
          } else if (existingFilter == null) {
            kalmanFilter = _createKalmanFilter(acceptedSample);
            filteredSpeed = acceptedSample.speed;
          } else {
            final elapsedTime = previousAcceptedSample == null
                ? const Duration(seconds: 1)
                : acceptedSample.timestamp.difference(previousAcceptedSample.timestamp);
            // Update the filter with the new measurement.
            filteredSpeed = existingFilter.update(
              acceptedSample.speed,
              acceptedSample.speedAccuracy.measurementNoise,
              elapsedTime: elapsedTime,
            );
          }

          // Use the same combined accuracy logic as before.
          final double speedConfidence = acceptedSample.speedAccuracy.confidence;
          final double positionConfidence =
              1.0 - (min(acceptedSample.horizontalAccuracy, maxHorizontalAccuracyError) / maxHorizontalAccuracyError);
          final double finalAccuracy = speedConfidence * positionConfidence;

          emitCurrentSpeed(
            Speed.current(
              filteredSpeed.isNegative ? 0 : filteredSpeed, // Ensure speed is not negative
              finalAccuracy.clamp(0.0, 1.0),
            ),
            acceptedSample,
          );
        },
        onError: (error) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
      );
    }

    Future<void> onCancel() async {
      debugPrint('Cancelled speed tracking');
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

  KalmanFilter _createKalmanFilter(AcceptedSpeedSample sample) {
    return KalmanFilter(
      initialMeasurement: sample.speed,
      initialMeasurementNoise: sample.speedAccuracy.measurementNoise,
      processNoise: processNoise,
    );
  }

  static SpeedAccuracyEstimate normalizeSpeedAccuracy(double speedAccuracy) {
    if (speedAccuracy.isFinite && speedAccuracy > 0) {
      return SpeedAccuracyEstimate(
        standardDeviation: speedAccuracy,
        confidence: 1.0 - (min(speedAccuracy, maxSpeedAccuracyError) / maxSpeedAccuracyError),
        isKnown: true,
      );
    }

    return const SpeedAccuracyEstimate(
      standardDeviation: fallbackSpeedAccuracy,
      confidence: unknownSpeedConfidence,
      isKnown: false,
    );
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
    if (!speed.isFinite || speed < 0) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidSpeed);
    }

    if (timestamp.difference(now) > maxFutureSampleSkew) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.futureTimestamp);
    }

    if (now.difference(timestamp) > maxSampleAge) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.staleTimestamp);
    }

    if (!horizontalAccuracy.isFinite || horizontalAccuracy <= 0 || horizontalAccuracy > maxAcceptedHorizontalAccuracy) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidHorizontalAccuracy);
    }

    final normalizedSpeedAccuracy = normalizeSpeedAccuracy(speedAccuracy);
    final acceptedSample = AcceptedSpeedSample(
      speed: speed,
      timestamp: timestamp,
      horizontalAccuracy: horizontalAccuracy,
      speedAccuracy: normalizedSpeedAccuracy,
    );
    final previousSample = previousAcceptedSample;
    if (previousSample == null) {
      return SpeedSampleValidation.accepted(acceptedSample);
    }

    final elapsedSeconds =
        timestamp.difference(previousSample.timestamp).inMicroseconds / Duration.microsecondsPerSecond;
    if (elapsedSeconds <= 0) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.nonIncreasingTimestamp);
    }

    if (!enforceAccelerationLimit) {
      return SpeedSampleValidation.accepted(acceptedSample);
    }

    final allowedSpeedChange =
        (maxPlausibleAcceleration * elapsedSeconds) +
        previousSample.speedAccuracy.standardDeviation +
        normalizedSpeedAccuracy.standardDeviation;
    if ((speed - previousSample.speed).abs() > allowedSpeedChange) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.implausibleAcceleration);
    }

    return SpeedSampleValidation.accepted(acceptedSample);
  }

  Future<bool> _checkPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      debugPrint('permission: $permission');
      return false;
    }

    var accuracy = LocationAccuracyStatus.precise;
    if (Platform.isAndroid || Platform.isIOS) {
      accuracy = await Geolocator.getLocationAccuracy();
    }

    if (Platform.isIOS && accuracy == LocationAccuracyStatus.reduced) {
      accuracy = await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'SpeedPurposeKey');
    }

    debugPrint('permission: $permission, accuracy: $accuracy');

    return accuracy == LocationAccuracyStatus.precise;
  }
}

class AcceptedSpeedSample {
  final double speed;
  final DateTime timestamp;
  final double horizontalAccuracy;
  final SpeedAccuracyEstimate speedAccuracy;

  const AcceptedSpeedSample({
    required this.speed,
    required this.timestamp,
    required this.horizontalAccuracy,
    required this.speedAccuracy,
  });
}

class SpeedSampleValidation {
  final AcceptedSpeedSample? acceptedSample;
  final SpeedSampleRejectionReason? rejectionReason;

  const SpeedSampleValidation.accepted(this.acceptedSample) : rejectionReason = null, assert(acceptedSample != null);

  const SpeedSampleValidation.rejected(this.rejectionReason) : acceptedSample = null, assert(rejectionReason != null);

  bool get isAccepted => acceptedSample != null;
}

enum SpeedSampleRejectionReason {
  invalidSpeed,
  staleTimestamp,
  futureTimestamp,
  invalidHorizontalAccuracy,
  nonIncreasingTimestamp,
  implausibleAcceleration,
}

class SpeedAccuracyEstimate {
  final double standardDeviation;
  final double confidence;
  final bool isKnown;

  const SpeedAccuracyEstimate({required this.standardDeviation, required this.confidence, required this.isKnown});

  double get measurementNoise => standardDeviation * standardDeviation;
}

enum SpeedStatus { current, unavailable }

class Speed {
  /// Speed in meters per second
  final double? value;

  /// Accuracy of the speed measurement, ranging from 0.0 (worst) to 1.0 (best)
  final double accuracy;

  final SpeedStatus status;

  const Speed.current(double this.value, this.accuracy) : status = SpeedStatus.current;

  const Speed.unavailable() : value = null, accuracy = 0, status = SpeedStatus.unavailable;

  bool get isCurrent => status == SpeedStatus.current;

  double getAs(SpeedUnit unit, [int precision = 1]) {
    final currentValue = value;
    if (currentValue == null) {
      throw StateError('Speed is unavailable');
    }
    return double.parse((currentValue * unit._factor).toStringAsFixed(precision));
  }
}

enum SpeedUnit {
  kilometersPerHour,
  milesPerHour,
  metersPerSecond,
  footPerSecond,
  knots;

  double get _factor {
    switch (this) {
      case SpeedUnit.kilometersPerHour:
        return 3.600000;
      case SpeedUnit.milesPerHour:
        return 2.236936;
      case SpeedUnit.metersPerSecond:
        return 1;
      case SpeedUnit.footPerSecond:
        return 3.280840;
      case SpeedUnit.knots:
        return 1.943844;
    }
  }

  String title(BuildContext context) {
    switch (this) {
      case SpeedUnit.kilometersPerHour:
        return L10n.of(context).kilometersPerHour;
      case SpeedUnit.milesPerHour:
        return L10n.of(context).milesPerHour;
      case SpeedUnit.metersPerSecond:
        return L10n.of(context).metersPerSecond;
      case SpeedUnit.footPerSecond:
        return L10n.of(context).footPerSecond;
      case SpeedUnit.knots:
        return L10n.of(context).knots;
    }
  }
}
