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

  SpeedSampleValidation validate({
    required double speed,
    required DateTime timestamp,
    required double horizontalAccuracy,
    required double speedAccuracy,
    required DateTime now,
    AcceptedSpeedSample? previousAcceptedSample,
    bool enforceAccelerationLimit = true,
  }) {
    return validateAcceptedSample(
      speed: speed,
      timestamp: timestamp,
      horizontalAccuracy: horizontalAccuracy,
      speedAccuracy: normalizeSpeedAccuracy(speedAccuracy),
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      allowUnknownHorizontalAccuracy: false,
      allowUnknownSpeedAccuracy: false,
      source: SpeedSampleSource.platform,
      now: now,
    );
  }

  SpeedSampleValidation validateAcceptedSample({
    required double speed,
    required DateTime timestamp,
    required double horizontalAccuracy,
    required SpeedAccuracyEstimate speedAccuracy,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
    required bool allowUnknownHorizontalAccuracy,
    required bool allowUnknownSpeedAccuracy,
    required SpeedSampleSource source,
    DateTime? now,
  }) {
    if (!speed.isFinite || speed < 0) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidSpeed);
    }

    final receivedAt = now;
    if (receivedAt != null) {
      if (timestamp.difference(receivedAt) > config.maxFutureSampleSkew) {
        return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.futureTimestamp);
      }

      if (receivedAt.difference(timestamp) > config.maxSampleAge) {
        return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.staleTimestamp);
      }
    }

    final hasKnownHorizontalAccuracy = PositionSampleValidator.isKnownHorizontalAccuracy(horizontalAccuracy);
    final hasAllowedUnknownHorizontalAccuracy =
        allowUnknownHorizontalAccuracy && PositionSampleValidator.isUnknownHorizontalAccuracy(horizontalAccuracy);
    if (!hasKnownHorizontalAccuracy && !hasAllowedUnknownHorizontalAccuracy) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidHorizontalAccuracy);
    }

    if (!speedAccuracy.isKnown && (!allowUnknownSpeedAccuracy || source != SpeedSampleSource.positionDelta)) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.invalidSpeedAccuracy);
    }

    if (speedAccuracy.confidence <= 0 ||
        PositionSampleValidator.horizontalAccuracyConfidence(horizontalAccuracy) <= 0) {
      return const SpeedSampleValidation.rejected(SpeedSampleRejectionReason.insufficientConfidence);
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
