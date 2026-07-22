import 'dart:math';

import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;

class SpeedSampleValidator {
  const SpeedSampleValidator();

  SpeedAccuracyEstimate normalizeSpeedAccuracy(double speedAccuracy) {
    if (isKnownSpeedAccuracy(speedAccuracy)) {
      return SpeedAccuracyEstimate(
        standardDeviation: speedAccuracy,
        confidence: 1.0 - (min(speedAccuracy, config.maxSpeedAccuracyError) / config.maxSpeedAccuracyError),
        isKnown: true,
      );
    }

    return const SpeedAccuracyEstimate(
      standardDeviation: config.fallbackSpeedAccuracy,
      confidence: config.unknownSpeedConfidence,
      isKnown: false,
    );
  }

  bool isKnownSpeedAccuracy(double speedAccuracy) => speedAccuracy.isFinite && speedAccuracy > 0;

  bool hasUnknownSpeedAccuracy(double speedAccuracy) => !isKnownSpeedAccuracy(speedAccuracy);

  SpeedSampleValidation validatePlatformSample({
    required double speed,
    required double speedAccuracy,
    required ValidPositionSample positionSample,
    AcceptedSpeedSample? previousAcceptedSample,
    bool enforceAccelerationLimit = true,
  }) {
    if (!_isValidSpeed(speed)) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidSpeed);
    }

    final normalizedSpeedAccuracy = normalizeSpeedAccuracy(speedAccuracy);
    if (!normalizedSpeedAccuracy.isKnown) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidSpeedAccuracy);
    }

    return _validateSample(
      speed: speed,
      positionSample: positionSample,
      speedAccuracy: normalizedSpeedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      source: SpeedSampleSource.platform,
    );
  }

  SpeedSampleValidation validatePositionDeltaSample({
    required double speed,
    required SpeedAccuracyEstimate speedAccuracy,
    required ValidPositionSample positionSample,
    AcceptedSpeedSample? previousAcceptedSample,
    bool enforceAccelerationLimit = true,
  }) {
    if (!_isValidSpeed(speed)) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidSpeed);
    }

    if (!positionSample.hasKnownHorizontalAccuracy) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidHorizontalAccuracy);
    }

    return _validateSample(
      speed: speed,
      positionSample: positionSample,
      speedAccuracy: speedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      source: SpeedSampleSource.positionDelta,
    );
  }

  SpeedSampleValidation _validateSample({
    required double speed,
    required ValidPositionSample positionSample,
    required SpeedAccuracyEstimate speedAccuracy,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
    required SpeedSampleSource source,
  }) {
    if (speedAccuracy.confidence <= 0 ||
        PositionSampleValidator.horizontalAccuracyConfidence(positionSample.horizontalAccuracy) <= 0) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.insufficientConfidence);
    }

    final acceptedSample = AcceptedSpeedSample(
      speed: speed,
      timestamp: positionSample.timestamp,
      horizontalAccuracy: positionSample.horizontalAccuracy,
      speedAccuracy: speedAccuracy,
      source: source,
    );
    final previousSample = previousAcceptedSample;
    if (previousSample == null) {
      return SpeedSampleValidation.accepted(acceptedSample);
    }

    final elapsedSeconds =
        positionSample.timestamp.difference(previousSample.timestamp).inMicroseconds / Duration.microsecondsPerSecond;
    if (elapsedSeconds <= 0) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.nonIncreasingTimestamp);
    }

    if (!enforceAccelerationLimit) {
      return SpeedSampleValidation.accepted(acceptedSample);
    }

    if (!hasPlausibleSpeedChange(
      previousSample: previousSample,
      speed: speed,
      speedAccuracy: speedAccuracy,
      elapsedSeconds: elapsedSeconds,
    )) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.implausibleAcceleration);
    }

    return SpeedSampleValidation.accepted(acceptedSample);
  }

  bool _isValidSpeed(double speed) => speed.isFinite && speed >= 0;

  bool hasPlausibleSpeedChange({
    required AcceptedSpeedSample previousSample,
    required double speed,
    required SpeedAccuracyEstimate speedAccuracy,
    required double elapsedSeconds,
  }) {
    return (speed - previousSample.speed).abs() <=
        allowedSpeedChange(
          previousSample: previousSample,
          speedAccuracy: speedAccuracy,
          elapsedSeconds: elapsedSeconds,
        );
  }

  double allowedSpeedChange({
    required AcceptedSpeedSample previousSample,
    required SpeedAccuracyEstimate speedAccuracy,
    required double elapsedSeconds,
  }) {
    return (config.maxPlausibleAcceleration * elapsedSeconds) +
        previousSample.speedAccuracy.standardDeviation +
        speedAccuracy.standardDeviation;
  }
}
