import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/position_delta_speed_estimator.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;
import 'package:speed/src/util/kalman_filter.dart';

const double _fallbackConfirmationMinTolerance = 1.0;
const double _fallbackConfirmationSpeedFactor = 0.35;
const double _startupJumpConfirmationMinTolerance = 1.0;
const double _startupJumpConfirmationSpeedFactor = 0.20;
const double _platformPositionConsistencySigmaFactor = 2.0;
const double _platformPositionConsistencyMinTolerance = 2.0;
const double _platformPositionConsistencyMinConfidenceFactor = 0.25;

const int _confirmedPlatformPositionConflictCount = 2;

class ProcessedSpeedSample {
  final Speed speed;
  final AcceptedSpeedSample acceptedSample;

  const ProcessedSpeedSample({required this.speed, required this.acceptedSample});
}

class SpeedSampleProcessor {
  final double processNoise;
  final PositionSampleValidator _positionSampleValidator = const PositionSampleValidator();
  final SpeedSampleValidator _speedSampleValidator = const SpeedSampleValidator();
  final PositionDeltaSpeedEstimator _positionDeltaSpeedEstimator = PositionDeltaSpeedEstimator();
  var _acceptedStreamSampleCount = 0;
  var _platformPositionConflictCount = 0;
  KalmanFilter? _kalmanFilter;
  AcceptedSpeedSample? _lastAcceptedSample;
  AcceptedSpeedSample? _pendingFallbackSample;
  AcceptedSpeedSample? _pendingStartupJumpSample;

  SpeedSampleProcessor({required this.processNoise});

  ProcessedSpeedSample? process(Position position, DateTime now) {
    final positionSample = _positionSampleValidator.validate(position, now);
    if (positionSample == null) {
      return null;
    }

    final hasUnknownSpeedAccuracy = _speedSampleValidator.hasUnknownSpeedAccuracy(position.speedAccuracy);
    final addedToFallbackWindow = _positionDeltaSpeedEstimator.addSample(positionSample);
    if (hasUnknownSpeedAccuracy && !positionSample.hasKnownHorizontalAccuracy) {
      _pendingFallbackSample = null;
      _pendingStartupJumpSample = null;
      return null;
    }
    if (!addedToFallbackWindow && hasUnknownSpeedAccuracy) {
      return null;
    }

    final previousAcceptedSample = _lastAcceptedSample;
    final validation = _resolveSpeedSampleValidation(
      position: position,
      positionSample: positionSample,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: !_isStartupWarmup,
    );
    if (validation == null) {
      if (hasUnknownSpeedAccuracy) {
        _pendingFallbackSample = null;
      }
      _pendingStartupJumpSample = null;
      return null;
    }

    late final AcceptedSpeedSample validationAcceptedSample;
    switch (validation) {
      case SpeedSampleAccepted(:final sample):
        validationAcceptedSample = sample;
      case SpeedSampleRejected(:final reason):
        _pendingFallbackSample = null;
        _pendingStartupJumpSample = null;
        _removeRejectedFallbackOutlier(position, reason, addedToFallbackWindow);
        return null;
    }

    final resolvedSample = _resolvePlatformPositionConsistency(
      acceptedSample: validationAcceptedSample,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: !_isStartupWarmup,
      addedToFallbackWindow: addedToFallbackWindow,
    );
    final acceptedSample = resolvedSample.acceptedSample;

    if (!_shouldEmitAcceptedSample(acceptedSample, previousAcceptedSample)) {
      return null;
    }

    _lastAcceptedSample = acceptedSample;
    _acceptedStreamSampleCount++;

    final filteredSpeed = _filterSpeed(acceptedSample, previousAcceptedSample, resetFilter: resolvedSample.resetFilter);
    final accuracy = _accuracyFor(acceptedSample);
    return ProcessedSpeedSample(
      speed: Speed.current(filteredSpeed.isNegative ? 0 : filteredSpeed, accuracy.clamp(0.0, 1.0)),
      acceptedSample: acceptedSample,
    );
  }

  bool get _isStartupWarmup => _acceptedStreamSampleCount < config.startupWarmupAcceptedSamples;

  SpeedSampleValidation? _resolveSpeedSampleValidation({
    required Position position,
    required ValidPositionSample positionSample,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
  }) {
    final speedAccuracy = _speedSampleValidator.normalizeSpeedAccuracy(position.speedAccuracy);
    if (!speedAccuracy.isKnown) {
      if (!positionSample.hasKnownHorizontalAccuracy) {
        return null;
      }

      return _createFallbackSpeedSample(
        currentSample: positionSample,
        previousAcceptedSample: previousAcceptedSample,
        enforceAccelerationLimit: enforceAccelerationLimit,
      );
    }

    return _speedSampleValidator.validateAcceptedSample(
      speed: position.speed,
      timestamp: positionSample.timestamp,
      horizontalAccuracy: positionSample.horizontalAccuracy,
      speedAccuracy: speedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      allowUnknownHorizontalAccuracy: true,
      allowUnknownSpeedAccuracy: false,
      source: SpeedSampleSource.platform,
      now: positionSample.receivedAt,
    );
  }

  SpeedSampleValidation? _createFallbackSpeedSample({
    required ValidPositionSample currentSample,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
  }) {
    final estimate = _positionDeltaSpeedEstimator.estimate();
    if (estimate == null) {
      return null;
    }

    return _speedSampleValidator.validateAcceptedSample(
      speed: estimate.speed,
      timestamp: currentSample.timestamp,
      horizontalAccuracy: currentSample.horizontalAccuracy,
      speedAccuracy: estimate.speedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      allowUnknownHorizontalAccuracy: false,
      allowUnknownSpeedAccuracy: true,
      source: SpeedSampleSource.positionDelta,
    );
  }

  _ResolvedAcceptedSample _resolvePlatformPositionConsistency({
    required AcceptedSpeedSample acceptedSample,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
    required bool addedToFallbackWindow,
  }) {
    if (acceptedSample.source != SpeedSampleSource.platform) {
      _platformPositionConflictCount = 0;
      return _ResolvedAcceptedSample(acceptedSample: acceptedSample);
    }

    if (!addedToFallbackWindow) {
      _platformPositionConflictCount = 0;
      return _ResolvedAcceptedSample(acceptedSample: acceptedSample);
    }

    final positionEstimate = _positionDeltaSpeedEstimator.estimate();
    if (positionEstimate == null) {
      _platformPositionConflictCount = 0;
      return _ResolvedAcceptedSample(acceptedSample: acceptedSample);
    }

    final consistencyCheck = _checkPlatformPositionConsistency(
      platformSample: acceptedSample,
      positionEstimate: positionEstimate,
    );
    if (!consistencyCheck.isConflict) {
      _platformPositionConflictCount = 0;
      return _ResolvedAcceptedSample(acceptedSample: acceptedSample);
    }

    final platformSample = acceptedSample.withPositionConsistencyConfidence(consistencyCheck.confidenceFactor);
    _platformPositionConflictCount = min(_confirmedPlatformPositionConflictCount, _platformPositionConflictCount + 1);
    if (_platformPositionConflictCount < _confirmedPlatformPositionConflictCount) {
      return _ResolvedAcceptedSample(acceptedSample: platformSample);
    }

    final fallbackValidation = _speedSampleValidator.validateAcceptedSample(
      speed: positionEstimate.speed,
      timestamp: acceptedSample.timestamp,
      horizontalAccuracy: acceptedSample.horizontalAccuracy,
      speedAccuracy: positionEstimate.speedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      allowUnknownHorizontalAccuracy: false,
      allowUnknownSpeedAccuracy: true,
      source: SpeedSampleSource.positionDelta,
    );
    return switch (fallbackValidation) {
      SpeedSampleAccepted(:final sample) => _ResolvedAcceptedSample(acceptedSample: sample, resetFilter: true),
      SpeedSampleRejected() => _ResolvedAcceptedSample(acceptedSample: platformSample),
    };
  }

  _PlatformPositionConsistencyCheck _checkPlatformPositionConsistency({
    required AcceptedSpeedSample platformSample,
    required FallbackSpeedEstimate positionEstimate,
  }) {
    final difference = (platformSample.speed - positionEstimate.speed).abs();
    final tolerance = max(
      _platformPositionConsistencyMinTolerance,
      _platformPositionConsistencySigmaFactor *
          sqrt(platformSample.speedAccuracy.measurementNoise + positionEstimate.speedAccuracy.measurementNoise),
    );

    if (difference <= tolerance) {
      return const _PlatformPositionConsistencyCheck(isConflict: false, confidenceFactor: 1.0);
    }

    return _PlatformPositionConsistencyCheck(
      isConflict: true,
      confidenceFactor: (tolerance / difference).clamp(_platformPositionConsistencyMinConfidenceFactor, 1.0),
    );
  }

  bool _shouldEmitAcceptedSample(AcceptedSpeedSample acceptedSample, AcceptedSpeedSample? previousAcceptedSample) {
    if (!_shouldEmitStartupSample(acceptedSample, previousAcceptedSample)) {
      _pendingFallbackSample = null;
      return false;
    }

    _pendingStartupJumpSample = null;
    return _shouldEmitFallbackSample(acceptedSample, previousAcceptedSample);
  }

  bool _shouldEmitStartupSample(AcceptedSpeedSample acceptedSample, AcceptedSpeedSample? previousAcceptedSample) {
    if (acceptedSample.source != SpeedSampleSource.platform || !_isStartupWarmup || previousAcceptedSample == null) {
      return true;
    }

    final elapsedSeconds =
        acceptedSample.timestamp.difference(previousAcceptedSample.timestamp).inMicroseconds /
        Duration.microsecondsPerSecond;
    if (elapsedSeconds <= 0 ||
        _speedSampleValidator.hasPlausibleSpeedChange(
          previousSample: previousAcceptedSample,
          speed: acceptedSample.speed,
          speedAccuracy: acceptedSample.speedAccuracy,
          elapsedSeconds: elapsedSeconds,
        )) {
      return true;
    }

    final pendingStartupJumpSample = _pendingStartupJumpSample;
    if (pendingStartupJumpSample != null && _matchesPendingStartupJump(acceptedSample, pendingStartupJumpSample)) {
      return true;
    }

    _pendingStartupJumpSample = acceptedSample;
    return false;
  }

  bool _matchesPendingStartupJump(AcceptedSpeedSample acceptedSample, AcceptedSpeedSample pendingStartupJumpSample) {
    final tolerance = max(
      _startupJumpConfirmationMinTolerance,
      pendingStartupJumpSample.speed * _startupJumpConfirmationSpeedFactor,
    );
    return (acceptedSample.speed - pendingStartupJumpSample.speed).abs() <= tolerance;
  }

  bool _shouldEmitFallbackSample(AcceptedSpeedSample acceptedSample, AcceptedSpeedSample? previousAcceptedSample) {
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
      _fallbackConfirmationMinTolerance,
      pendingFallbackSample.speed * _fallbackConfirmationSpeedFactor,
    );
    if ((acceptedSample.speed - pendingFallbackSample.speed).abs() <= tolerance) {
      _pendingFallbackSample = null;
      return true;
    }

    _pendingFallbackSample = acceptedSample;
    return false;
  }

  void _removeRejectedFallbackOutlier(
    Position position,
    SpeedSampleRejectionReason reason,
    bool addedToFallbackWindow,
  ) {
    if (reason == SpeedSampleRejectionReason.implausibleAcceleration &&
        addedToFallbackWindow &&
        _speedSampleValidator.hasUnknownSpeedAccuracy(position.speedAccuracy)) {
      _positionDeltaSpeedEstimator.removeLastSample();
    }
  }

  double _filterSpeed(
    AcceptedSpeedSample acceptedSample,
    AcceptedSpeedSample? previousAcceptedSample, {
    bool resetFilter = false,
  }) {
    if (resetFilter) {
      _kalmanFilter = _createKalmanFilter(acceptedSample);
      return acceptedSample.speed;
    }

    final existingFilter = _kalmanFilter;
    if (existingFilter == null) {
      _kalmanFilter = _createKalmanFilter(acceptedSample);
      return acceptedSample.speed;
    }

    final elapsedTime = previousAcceptedSample == null
        ? const Duration(seconds: 1)
        : acceptedSample.timestamp.difference(previousAcceptedSample.timestamp);
    final filteredSpeed = existingFilter.update(
      acceptedSample.speed,
      _measurementNoiseFor(acceptedSample),
      elapsedTime: elapsedTime,
    );
    if (_acceptedStreamSampleCount <= config.startupWarmupAcceptedSamples) {
      return acceptedSample.speed;
    }
    return filteredSpeed;
  }

  double _accuracyFor(AcceptedSpeedSample acceptedSample) {
    final speedConfidence = acceptedSample.speedAccuracy.confidence;
    final positionConfidence = PositionSampleValidator.horizontalAccuracyConfidence(acceptedSample.horizontalAccuracy);
    return speedConfidence * positionConfidence * acceptedSample.positionConsistencyConfidence;
  }

  KalmanFilter _createKalmanFilter(AcceptedSpeedSample sample) {
    return KalmanFilter(
      initialMeasurement: sample.speed,
      initialMeasurementNoise: _measurementNoiseFor(sample),
      processNoise: processNoise,
    );
  }

  double _measurementNoiseFor(AcceptedSpeedSample sample) {
    return sample.speedAccuracy.measurementNoise / sample.positionConsistencyConfidence;
  }
}

class _ResolvedAcceptedSample {
  final AcceptedSpeedSample acceptedSample;
  final bool resetFilter;

  const _ResolvedAcceptedSample({required this.acceptedSample, this.resetFilter = false});
}

class _PlatformPositionConsistencyCheck {
  final bool isConflict;
  final double confidenceFactor;

  const _PlatformPositionConsistencyCheck({required this.isConflict, required this.confidenceFactor});
}
