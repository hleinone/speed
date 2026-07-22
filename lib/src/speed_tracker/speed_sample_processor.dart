import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/platform_position_reconciler.dart';
import 'package:speed/src/speed_tracker/position_delta_speed_estimator.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';
import 'package:speed/src/speed_tracker/sample_confirmation_gate.dart';
import 'package:speed/src/speed_tracker/speed_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;
import 'package:speed/src/util/kalman_filter.dart';

class ProcessedSpeedSample {
  final CurrentSpeed speed;
  final AcceptedSpeedSample acceptedSample;

  const ProcessedSpeedSample({required this.speed, required this.acceptedSample});
}

class SpeedSampleProcessor {
  final double processNoise;
  final PositionSampleValidator _positionSampleValidator = const PositionSampleValidator();
  final SpeedSampleValidator _speedSampleValidator = const SpeedSampleValidator();
  final PositionDeltaSpeedEstimator _positionDeltaSpeedEstimator = PositionDeltaSpeedEstimator();
  final PlatformPositionReconciler _platformPositionReconciler = PlatformPositionReconciler();
  final SampleConfirmationGate _sampleConfirmationGate = SampleConfirmationGate();
  var _acceptedStreamSampleCount = 0;
  KalmanFilter? _kalmanFilter;
  AcceptedSpeedSample? _lastAcceptedSample;

  SpeedSampleProcessor({required this.processNoise});

  ProcessedSpeedSample? process(Position position, DateTime now) {
    final positionSample = _positionSampleValidator.validate(position, now);
    if (positionSample == null) {
      return null;
    }

    final hasUnknownSpeedAccuracy = _speedSampleValidator.hasUnknownSpeedAccuracy(position.speedAccuracy);
    final addedToFallbackWindow = _positionDeltaSpeedEstimator.addSample(positionSample);
    if (hasUnknownSpeedAccuracy && !positionSample.hasKnownHorizontalAccuracy) {
      _sampleConfirmationGate.reset();
      return null;
    }
    if (!addedToFallbackWindow && hasUnknownSpeedAccuracy) {
      return null;
    }

    final previousAcceptedSample = _lastAcceptedSample;
    final candidateValidation = _resolveCandidateValidation(
      position: position,
      positionSample: positionSample,
      hasUnknownSpeedAccuracy: hasUnknownSpeedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: !_isStartupWarmup,
    );
    if (candidateValidation == null) {
      _sampleConfirmationGate.reset();
      return null;
    }

    late final AcceptedSpeedSample candidate;
    switch (candidateValidation) {
      case SpeedSampleAccepted(:final sample):
        candidate = sample;
      case SpeedSampleRejected(:final reason):
        _sampleConfirmationGate.reset();
        _removeRejectedFallbackOutlier(position, reason, addedToFallbackWindow);
        return null;
    }

    final positionEstimate = candidate.source == SpeedSampleSource.platform && addedToFallbackWindow
        ? _positionDeltaSpeedEstimator.estimate()
        : null;
    final reconciledSample = _platformPositionReconciler.reconcile(
      candidate: candidate,
      positionSample: positionSample,
      positionEstimate: positionEstimate,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: !_isStartupWarmup,
    );
    final acceptedSample = reconciledSample.sample;

    if (!_sampleConfirmationGate.shouldEmit(
      candidate: acceptedSample,
      previousAcceptedSample: previousAcceptedSample,
      isStartupWarmup: _isStartupWarmup,
    )) {
      return null;
    }

    _lastAcceptedSample = acceptedSample;
    _acceptedStreamSampleCount++;

    final filteredSpeed = _filterSpeed(
      acceptedSample,
      previousAcceptedSample,
      resetFilter: reconciledSample.resetFilter,
    );
    final accuracy = _accuracyFor(acceptedSample);
    return ProcessedSpeedSample(
      speed: CurrentSpeed(filteredSpeed.isNegative ? 0 : filteredSpeed, accuracy.clamp(0.0, 1.0)),
      acceptedSample: acceptedSample,
    );
  }

  bool get _isStartupWarmup => _acceptedStreamSampleCount < config.startupWarmupAcceptedSamples;

  SpeedSampleValidation? _resolveCandidateValidation({
    required Position position,
    required ValidPositionSample positionSample,
    required bool hasUnknownSpeedAccuracy,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
  }) {
    if (hasUnknownSpeedAccuracy) {
      return _createFallbackCandidateValidation(
        currentSample: positionSample,
        previousAcceptedSample: previousAcceptedSample,
        enforceAccelerationLimit: enforceAccelerationLimit,
      );
    }

    return _speedSampleValidator.validatePlatformSample(
      speed: position.speed,
      speedAccuracy: position.speedAccuracy,
      positionSample: positionSample,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
    );
  }

  SpeedSampleValidation? _createFallbackCandidateValidation({
    required ValidPositionSample currentSample,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
  }) {
    final estimate = _positionDeltaSpeedEstimator.estimate();
    if (estimate == null) {
      return null;
    }

    return _speedSampleValidator.validatePositionDeltaSample(
      speed: estimate.speed,
      speedAccuracy: estimate.speedAccuracy,
      positionSample: currentSample,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
    );
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
