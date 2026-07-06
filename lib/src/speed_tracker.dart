import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
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
  static const double fallbackSpeedConfidence = unknownSpeedConfidence * 0.5;
  static const double minFallbackStationaryDeadband = 2.0;
  static const double maxFallbackStationaryDeadband = 10.0;
  static const double _fallbackStationarySpeedEpsilon = 0.2;
  static const Duration maxSampleAge = Duration(seconds: 5);
  static const Duration positionUpdateInterval = Duration(seconds: 1);
  static const Duration freshnessTimeout = Duration(seconds: 10);
  static const Duration minFallbackSampleInterval = Duration(milliseconds: 500);
  static const Duration _fallbackRegressionWindow = Duration(seconds: 5);
  static const Duration _minFallbackRegressionSpan = Duration(seconds: 3);
  static const Duration maxFutureSampleSkew = Duration(seconds: 1);
  static const int _minFallbackRegressionSamples = 4;
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
    final fallbackPositionSamples = <_ValidPositionSample>[];

    final locationSettings = createLocationSettings(defaultTargetPlatform);

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
          final now = _clock();
          final positionSample = _validatePositionSample(position, now);
          if (positionSample == null) {
            return;
          }

          final addedToFallbackWindow = _appendFallbackPositionSample(fallbackPositionSamples, positionSample);
          if (!addedToFallbackWindow && _hasAmbiguousZeroSpeed(position)) {
            return;
          }

          final previousAcceptedSample = lastAcceptedSample;
          final isStartupWarmup = acceptedStreamSampleCount < startupWarmupAcceptedSamples;
          final validation = _resolveSpeedSampleValidation(
            position: position,
            positionSample: positionSample,
            fallbackPositionSamples: fallbackPositionSamples,
            previousAcceptedSample: previousAcceptedSample,
            enforceAccelerationLimit: !isStartupWarmup,
          );
          if (validation == null) {
            return;
          }

          final acceptedSample = validation.acceptedSample;
          if (acceptedSample == null) {
            if (validation.rejectionReason == SpeedSampleRejectionReason.implausibleAcceleration &&
                addedToFallbackWindow &&
                _hasAmbiguousZeroSpeed(position)) {
              fallbackPositionSamples.removeLast();
            }
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

  KalmanFilter _createKalmanFilter(AcceptedSpeedSample sample) {
    return KalmanFilter(
      initialMeasurement: sample.speed,
      initialMeasurementNoise: sample.speedAccuracy.measurementNoise,
      processNoise: processNoise,
    );
  }

  static bool _appendFallbackPositionSample(List<_ValidPositionSample> samples, _ValidPositionSample sample) {
    if (samples.isNotEmpty && !sample.timestamp.isAfter(samples.last.timestamp)) {
      return false;
    }

    samples.add(sample);
    samples.removeWhere(
      (historySample) => sample.timestamp.difference(historySample.timestamp) > _fallbackRegressionWindow,
    );
    return true;
  }

  static SpeedSampleValidation? _resolveSpeedSampleValidation({
    required Position position,
    required _ValidPositionSample positionSample,
    required List<_ValidPositionSample> fallbackPositionSamples,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
  }) {
    if (_hasAmbiguousZeroSpeed(position)) {
      return _createFallbackSpeedSample(
        currentSample: positionSample,
        samples: fallbackPositionSamples,
        previousAcceptedSample: previousAcceptedSample,
        enforceAccelerationLimit: enforceAccelerationLimit,
      );
    }

    return validateSpeedSample(
      speed: position.speed,
      timestamp: positionSample.timestamp,
      horizontalAccuracy: positionSample.horizontalAccuracy,
      speedAccuracy: position.speedAccuracy,
      now: positionSample.receivedAt,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
    );
  }

  static bool _hasAmbiguousZeroSpeed(Position position) => position.speed == 0 && position.speedAccuracy == 0;

  static _ValidPositionSample? _validatePositionSample(Position position, DateTime now) {
    if (!position.latitude.isFinite || position.latitude < -90 || position.latitude > 90) {
      return null;
    }

    if (!position.longitude.isFinite || position.longitude <= -180 || position.longitude > 180) {
      return null;
    }

    if (position.timestamp.difference(now) > maxFutureSampleSkew) {
      return null;
    }

    if (now.difference(position.timestamp) > maxSampleAge) {
      return null;
    }

    if (!position.accuracy.isFinite || position.accuracy <= 0 || position.accuracy > maxAcceptedHorizontalAccuracy) {
      return null;
    }

    return _ValidPositionSample(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      horizontalAccuracy: position.accuracy,
      receivedAt: now,
    );
  }

  static SpeedSampleValidation? _createFallbackSpeedSample({
    required _ValidPositionSample currentSample,
    required List<_ValidPositionSample> samples,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
  }) {
    final estimate = _estimateFallbackSpeed(samples);
    if (estimate == null) {
      return null;
    }

    return _validateSpeedSample(
      speed: estimate.speed,
      timestamp: currentSample.timestamp,
      horizontalAccuracy: currentSample.horizontalAccuracy,
      speedAccuracy: estimate.speedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      source: SpeedSampleSource.positionDelta,
    );
  }

  static _FallbackSpeedEstimate? _estimateFallbackSpeed(List<_ValidPositionSample> samples) {
    if (samples.length < _minFallbackRegressionSamples) {
      return null;
    }

    final firstSample = samples.first;
    final lastSample = samples.last;
    final elapsed = lastSample.timestamp.difference(firstSample.timestamp);
    if (elapsed < _minFallbackRegressionSpan) {
      return null;
    }

    final origin = samples.first;
    final regressionPoints = samples
        .map((sample) {
          final t = sample.timestamp.difference(origin.timestamp).inMicroseconds / Duration.microsecondsPerSecond;
          final x =
              Geolocator.distanceBetween(origin.latitude, origin.longitude, origin.latitude, sample.longitude) *
              (sample.longitude >= origin.longitude ? 1 : -1);
          final y =
              Geolocator.distanceBetween(origin.latitude, origin.longitude, sample.latitude, origin.longitude) *
              (sample.latitude >= origin.latitude ? 1 : -1);
          final weight = 1 / (sample.horizontalAccuracy * sample.horizontalAccuracy);
          return _FallbackRegressionPoint(t: t, x: x, y: y, weight: weight);
        })
        .toList(growable: false);

    final xVelocity = _weightedSlope(regressionPoints, (point) => point.x);
    final yVelocity = _weightedSlope(regressionPoints, (point) => point.y);
    if (xVelocity == null || yVelocity == null) {
      return null;
    }

    final fittedSpeed = sqrt((xVelocity * xVelocity) + (yVelocity * yVelocity));
    final speed = fittedSpeed < _fallbackStationarySpeedEpsilon ? 0.0 : fittedSpeed;
    final elapsedSeconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    final speedAccuracy = SpeedAccuracyEstimate(
      standardDeviation: max(
        fallbackSpeedAccuracy,
        (firstSample.horizontalAccuracy + lastSample.horizontalAccuracy) / elapsedSeconds,
      ),
      confidence: fallbackSpeedConfidence,
      isKnown: false,
    );

    return _FallbackSpeedEstimate(speed: speed, speedAccuracy: speedAccuracy);
  }

  static double? _weightedSlope(
    List<_FallbackRegressionPoint> points,
    double Function(_FallbackRegressionPoint) value,
  ) {
    var weightSum = 0.0;
    var weightedTimeSum = 0.0;
    var weightedValueSum = 0.0;
    for (final point in points) {
      weightSum += point.weight;
      weightedTimeSum += point.weight * point.t;
      weightedValueSum += point.weight * value(point);
    }

    if (weightSum <= 0) {
      return null;
    }

    final meanTime = weightedTimeSum / weightSum;
    final meanValue = weightedValueSum / weightSum;
    var covariance = 0.0;
    var variance = 0.0;
    for (final point in points) {
      final centeredTime = point.t - meanTime;
      covariance += point.weight * centeredTime * (value(point) - meanValue);
      variance += point.weight * centeredTime * centeredTime;
    }

    if (variance <= 0) {
      return null;
    }
    return covariance / variance;
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
    return _validateSpeedSample(
      speed: speed,
      timestamp: timestamp,
      horizontalAccuracy: horizontalAccuracy,
      speedAccuracy: normalizeSpeedAccuracy(speedAccuracy),
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      source: SpeedSampleSource.platform,
      now: now,
    );
  }

  static SpeedSampleValidation _validateSpeedSample({
    required double speed,
    required DateTime timestamp,
    required double horizontalAccuracy,
    required SpeedAccuracyEstimate speedAccuracy,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
    required SpeedSampleSource source,
    DateTime? now,
  }) {
    if (!speed.isFinite || speed < 0) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidSpeed);
    }

    final receivedAt = now;
    if (receivedAt != null) {
      if (timestamp.difference(receivedAt) > maxFutureSampleSkew) {
        return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.futureTimestamp);
      }

      if (receivedAt.difference(timestamp) > maxSampleAge) {
        return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.staleTimestamp);
      }
    }

    if (!horizontalAccuracy.isFinite || horizontalAccuracy <= 0 || horizontalAccuracy > maxAcceptedHorizontalAccuracy) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidHorizontalAccuracy);
    }

    final acceptedSample = AcceptedSpeedSample(
      speed: speed,
      timestamp: timestamp,
      horizontalAccuracy: horizontalAccuracy,
      speedAccuracy: speedAccuracy,
      source: source,
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
        speedAccuracy.standardDeviation;
    if ((speed - previousSample.speed).abs() > allowedSpeedChange) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.implausibleAcceleration);
    }

    return SpeedSampleValidation.accepted(acceptedSample);
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

class AcceptedSpeedSample {
  final double speed;
  final DateTime timestamp;
  final double horizontalAccuracy;
  final SpeedAccuracyEstimate speedAccuracy;
  final SpeedSampleSource source;

  const AcceptedSpeedSample({
    required this.speed,
    required this.timestamp,
    required this.horizontalAccuracy,
    required this.speedAccuracy,
    this.source = SpeedSampleSource.platform,
  });
}

class _ValidPositionSample {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double horizontalAccuracy;
  final DateTime receivedAt;

  const _ValidPositionSample({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.horizontalAccuracy,
    required this.receivedAt,
  });
}

class _FallbackSpeedEstimate {
  final double speed;
  final SpeedAccuracyEstimate speedAccuracy;

  const _FallbackSpeedEstimate({required this.speed, required this.speedAccuracy});
}

class _FallbackRegressionPoint {
  final double t;
  final double x;
  final double y;
  final double weight;

  const _FallbackRegressionPoint({required this.t, required this.x, required this.y, required this.weight});
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

enum SpeedSampleSource { platform, positionDelta }

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
