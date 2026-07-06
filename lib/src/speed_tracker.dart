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
  static const double _fallbackStationarySpeedEpsilon = 0.2;
  static const double _fallbackRmsResidualFloor = 1.5;
  static const double _fallbackMaxRmsResidual = 8.0;
  static const double _fallbackRmsResidualAccuracyFactor = 0.75;
  static const double _fallbackMaxResidualFloor = 3.0;
  static const double _fallbackMaxResidual = 12.0;
  static const double _fallbackMaxResidualAccuracyFactor = 1.5;
  static const double _fallbackMinTravelDistance = 5.0;
  static const double _fallbackTravelResidualFactor = 3.0;
  static const double _fallbackStationaryClusterFloor = 3.0;
  static const double _fallbackMinDirectionAlignment = 0.5;
  static const double _fallbackMaxSegmentSpeedFactor = 3.0;
  static const double _fallbackSegmentSpeedAccuracyFactor = 2.0;
  static const double _fallbackConfirmationMinTolerance = 1.0;
  static const double _fallbackConfirmationSpeedFactor = 0.35;
  static const Duration maxSampleAge = Duration(seconds: 5);
  static const Duration positionUpdateInterval = Duration(seconds: 1);
  static const Duration freshnessTimeout = Duration(seconds: 10);
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

    final locationSettings = createLocationSettings(defaultTargetPlatform);
    final speedProcessor = _SpeedSampleProcessor(processNoise: processNoise);

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

    final regression = _fitFallbackRegression(regressionPoints);
    if (regression == null) {
      return null;
    }

    final medianHorizontalAccuracy = _medianHorizontalAccuracy(samples);
    final fittedSpeed = sqrt((regression.xSlope * regression.xSlope) + (regression.ySlope * regression.ySlope));
    final elapsedSeconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (fittedSpeed < _fallbackStationarySpeedEpsilon) {
      if (!_isStationaryFallbackCluster(regressionPoints, medianHorizontalAccuracy)) {
        return null;
      }
    } else {
      if (!_hasAcceptableFallbackFit(regression, medianHorizontalAccuracy, fittedSpeed * elapsedSeconds)) {
        return null;
      }
      if (!_hasConsistentFallbackSegments(regressionPoints, regression, fittedSpeed)) {
        return null;
      }
    }

    final speed = fittedSpeed < _fallbackStationarySpeedEpsilon ? 0.0 : fittedSpeed;
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

  static _FallbackRegressionResult? _fitFallbackRegression(List<_FallbackRegressionPoint> points) {
    final xRegression = _weightedLinearRegression(points, (point) => point.x);
    final yRegression = _weightedLinearRegression(points, (point) => point.y);
    if (xRegression == null || yRegression == null) {
      return null;
    }

    var weightSum = 0.0;
    var weightedSquaredResidualSum = 0.0;
    var maxResidual = 0.0;
    for (final point in points) {
      final xResidual = point.x - xRegression.valueAt(point.t);
      final yResidual = point.y - yRegression.valueAt(point.t);
      final residual = sqrt((xResidual * xResidual) + (yResidual * yResidual));
      weightSum += point.weight;
      weightedSquaredResidualSum += point.weight * residual * residual;
      maxResidual = max(maxResidual, residual);
    }

    if (weightSum <= 0) {
      return null;
    }

    return _FallbackRegressionResult(
      xSlope: xRegression.slope,
      xIntercept: xRegression.intercept,
      ySlope: yRegression.slope,
      yIntercept: yRegression.intercept,
      weightedRmsResidual: sqrt(weightedSquaredResidualSum / weightSum),
      maxResidual: maxResidual,
    );
  }

  static _FallbackAxisRegression? _weightedLinearRegression(
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
    final slope = covariance / variance;
    return _FallbackAxisRegression(slope: slope, intercept: meanValue - (slope * meanTime));
  }

  static bool _hasAcceptableFallbackFit(
    _FallbackRegressionResult regression,
    double medianHorizontalAccuracy,
    double fittedTravelDistance,
  ) {
    final rmsResidualLimit = min(
      _fallbackMaxRmsResidual,
      max(_fallbackRmsResidualFloor, medianHorizontalAccuracy * _fallbackRmsResidualAccuracyFactor),
    );
    if (regression.weightedRmsResidual > rmsResidualLimit) {
      return false;
    }

    final maxResidualLimit = min(
      _fallbackMaxResidual,
      max(_fallbackMaxResidualFloor, medianHorizontalAccuracy * _fallbackMaxResidualAccuracyFactor),
    );
    if (regression.maxResidual > maxResidualLimit) {
      return false;
    }

    final minTravelDistance = max(
      _fallbackMinTravelDistance,
      regression.weightedRmsResidual * _fallbackTravelResidualFactor,
    );
    return fittedTravelDistance >= minTravelDistance;
  }

  static bool _hasConsistentFallbackSegments(
    List<_FallbackRegressionPoint> points,
    _FallbackRegressionResult regression,
    double fittedSpeed,
  ) {
    final directionX = regression.xSlope / fittedSpeed;
    final directionY = regression.ySlope / fittedSpeed;
    final maxSegmentSpeed = max(
      fittedSpeed * _fallbackMaxSegmentSpeedFactor,
      fittedSpeed + (fallbackSpeedAccuracy * _fallbackSegmentSpeedAccuracyFactor),
    );
    final segmentCount = points.length - 1;
    final requiredAlignedSegments = max(3, (segmentCount * 0.75).ceil());
    var alignedSegments = 0;

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final elapsedSeconds = current.t - previous.t;
      if (elapsedSeconds <= 0) {
        return false;
      }

      final xVelocity = (current.x - previous.x) / elapsedSeconds;
      final yVelocity = (current.y - previous.y) / elapsedSeconds;
      final segmentSpeed = sqrt((xVelocity * xVelocity) + (yVelocity * yVelocity));
      if (segmentSpeed > maxSegmentSpeed) {
        return false;
      }

      if (segmentSpeed > 0) {
        final alignment = ((xVelocity * directionX) + (yVelocity * directionY)) / segmentSpeed;
        if (alignment >= _fallbackMinDirectionAlignment) {
          alignedSegments++;
        }
      }
    }

    return alignedSegments >= requiredAlignedSegments;
  }

  static bool _isStationaryFallbackCluster(List<_FallbackRegressionPoint> points, double medianHorizontalAccuracy) {
    final maxClusterSpan = max(_fallbackStationaryClusterFloor, medianHorizontalAccuracy);
    for (var i = 0; i < points.length; i++) {
      final first = points[i];
      for (var j = i + 1; j < points.length; j++) {
        final second = points[j];
        final xDelta = second.x - first.x;
        final yDelta = second.y - first.y;
        if (sqrt((xDelta * xDelta) + (yDelta * yDelta)) > maxClusterSpan) {
          return false;
        }
      }
    }
    return true;
  }

  static double _medianHorizontalAccuracy(List<_ValidPositionSample> samples) {
    final accuracies = samples.map((sample) => sample.horizontalAccuracy).toList(growable: false)..sort();
    final middle = accuracies.length ~/ 2;
    if (accuracies.length.isOdd) {
      return accuracies[middle];
    }
    return (accuracies[middle - 1] + accuracies[middle]) / 2;
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

class _ProcessedSpeedSample {
  final Speed speed;
  final AcceptedSpeedSample acceptedSample;

  const _ProcessedSpeedSample({required this.speed, required this.acceptedSample});
}

class _SpeedSampleProcessor {
  final double processNoise;
  final List<_ValidPositionSample> _fallbackPositionSamples = [];
  var _acceptedStreamSampleCount = 0;
  KalmanFilter? _kalmanFilter;
  AcceptedSpeedSample? _lastAcceptedSample;
  AcceptedSpeedSample? _pendingFallbackSample;

  _SpeedSampleProcessor({required this.processNoise});

  _ProcessedSpeedSample? process(Position position, DateTime now) {
    final positionSample = SpeedTracker._validatePositionSample(position, now);
    if (positionSample == null) {
      return null;
    }

    final addedToFallbackWindow = SpeedTracker._appendFallbackPositionSample(_fallbackPositionSamples, positionSample);
    if (!addedToFallbackWindow && SpeedTracker._hasAmbiguousZeroSpeed(position)) {
      return null;
    }

    final previousAcceptedSample = _lastAcceptedSample;
    final validation = SpeedTracker._resolveSpeedSampleValidation(
      position: position,
      positionSample: positionSample,
      fallbackPositionSamples: _fallbackPositionSamples,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: !_isStartupWarmup,
    );
    if (validation == null) {
      if (SpeedTracker._hasAmbiguousZeroSpeed(position)) {
        _pendingFallbackSample = null;
      }
      return null;
    }

    final acceptedSample = validation.acceptedSample;
    if (acceptedSample == null) {
      _pendingFallbackSample = null;
      _removeRejectedFallbackOutlier(position, validation, addedToFallbackWindow);
      return null;
    }

    if (!_shouldEmitAcceptedSample(acceptedSample, previousAcceptedSample)) {
      return null;
    }

    _lastAcceptedSample = acceptedSample;
    _acceptedStreamSampleCount++;

    final filteredSpeed = _filterSpeed(acceptedSample, previousAcceptedSample);
    final accuracy = _accuracyFor(acceptedSample);
    return _ProcessedSpeedSample(
      speed: Speed.current(filteredSpeed.isNegative ? 0 : filteredSpeed, accuracy.clamp(0.0, 1.0)),
      acceptedSample: acceptedSample,
    );
  }

  bool get _isStartupWarmup => _acceptedStreamSampleCount < SpeedTracker.startupWarmupAcceptedSamples;

  bool _shouldEmitAcceptedSample(AcceptedSpeedSample acceptedSample, AcceptedSpeedSample? previousAcceptedSample) {
    if (acceptedSample.source == SpeedSampleSource.platform ||
        acceptedSample.speed == 0 ||
        previousAcceptedSample != null) {
      _pendingFallbackSample = null;
      return true;
    }

    final pendingFallbackSample = _pendingFallbackSample;
    if (pendingFallbackSample == null) {
      _pendingFallbackSample = acceptedSample;
      return false;
    }

    final tolerance = max(
      SpeedTracker._fallbackConfirmationMinTolerance,
      pendingFallbackSample.speed * SpeedTracker._fallbackConfirmationSpeedFactor,
    );
    if ((acceptedSample.speed - pendingFallbackSample.speed).abs() <= tolerance) {
      _pendingFallbackSample = null;
      return true;
    }

    _pendingFallbackSample = acceptedSample;
    return false;
  }

  void _removeRejectedFallbackOutlier(Position position, SpeedSampleValidation validation, bool addedToFallbackWindow) {
    if (validation.rejectionReason == SpeedSampleRejectionReason.implausibleAcceleration &&
        addedToFallbackWindow &&
        SpeedTracker._hasAmbiguousZeroSpeed(position)) {
      _fallbackPositionSamples.removeLast();
    }
  }

  double _filterSpeed(AcceptedSpeedSample acceptedSample, AcceptedSpeedSample? previousAcceptedSample) {
    final existingFilter = _kalmanFilter;
    if (_acceptedStreamSampleCount <= SpeedTracker.startupWarmupAcceptedSamples || existingFilter == null) {
      _kalmanFilter = _createKalmanFilter(acceptedSample);
      return acceptedSample.speed;
    }

    final elapsedTime = previousAcceptedSample == null
        ? const Duration(seconds: 1)
        : acceptedSample.timestamp.difference(previousAcceptedSample.timestamp);
    return existingFilter.update(
      acceptedSample.speed,
      acceptedSample.speedAccuracy.measurementNoise,
      elapsedTime: elapsedTime,
    );
  }

  double _accuracyFor(AcceptedSpeedSample acceptedSample) {
    final speedConfidence = acceptedSample.speedAccuracy.confidence;
    final positionConfidence =
        1.0 -
        (min(acceptedSample.horizontalAccuracy, SpeedTracker.maxHorizontalAccuracyError) /
            SpeedTracker.maxHorizontalAccuracyError);
    return speedConfidence * positionConfidence;
  }

  KalmanFilter _createKalmanFilter(AcceptedSpeedSample sample) {
    return KalmanFilter(
      initialMeasurement: sample.speed,
      initialMeasurementNoise: sample.speedAccuracy.measurementNoise,
      processNoise: processNoise,
    );
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

class _FallbackRegressionResult {
  final double xSlope;
  final double xIntercept;
  final double ySlope;
  final double yIntercept;
  final double weightedRmsResidual;
  final double maxResidual;

  const _FallbackRegressionResult({
    required this.xSlope,
    required this.xIntercept,
    required this.ySlope,
    required this.yIntercept,
    required this.weightedRmsResidual,
    required this.maxResidual,
  });
}

class _FallbackAxisRegression {
  final double slope;
  final double intercept;

  const _FallbackAxisRegression({required this.slope, required this.intercept});

  double valueAt(double t) => intercept + (slope * t);
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
  kilometersPerHour(3.600000),
  milesPerHour(2.236936),
  metersPerSecond(1),
  footPerSecond(3.280840),
  knots(1.943844);

  final double _factor;

  const SpeedUnit(this._factor);

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
