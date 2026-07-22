import 'dart:math';

import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/position_delta_speed_estimator.dart';
import 'package:speed/src/speed_tracker/speed_sample_validator.dart';

const double _consistencySigmaFactor = 2.0;
const double _consistencyMinTolerance = 2.0;
const double _consistencyMinConfidenceFactor = 0.25;

const int _confirmedConflictCount = 2;

final class ReconciledSpeedSample {
  final AcceptedSpeedSample sample;
  final bool resetFilter;

  const ReconciledSpeedSample({required this.sample, this.resetFilter = false});
}

final class PlatformPositionReconciler {
  final SpeedSampleValidator _speedSampleValidator = const SpeedSampleValidator();
  var _conflictCount = 0;

  ReconciledSpeedSample reconcile({
    required AcceptedSpeedSample candidate,
    required FallbackSpeedEstimate? positionEstimate,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool enforceAccelerationLimit,
  }) {
    if (candidate.source != SpeedSampleSource.platform || positionEstimate == null) {
      _conflictCount = 0;
      return ReconciledSpeedSample(sample: candidate);
    }

    final consistency = _checkConsistency(platformSample: candidate, positionEstimate: positionEstimate);
    if (!consistency.isConflict) {
      _conflictCount = 0;
      return ReconciledSpeedSample(sample: candidate);
    }

    final penalizedPlatformSample = candidate.withPositionConsistencyConfidence(consistency.confidenceFactor);
    _conflictCount = min(_confirmedConflictCount, _conflictCount + 1);
    if (_conflictCount < _confirmedConflictCount) {
      return ReconciledSpeedSample(sample: penalizedPlatformSample);
    }

    final fallbackValidation = _speedSampleValidator.validateAcceptedSample(
      speed: positionEstimate.speed,
      timestamp: candidate.timestamp,
      horizontalAccuracy: candidate.horizontalAccuracy,
      speedAccuracy: positionEstimate.speedAccuracy,
      previousAcceptedSample: previousAcceptedSample,
      enforceAccelerationLimit: enforceAccelerationLimit,
      allowUnknownHorizontalAccuracy: false,
      allowUnknownSpeedAccuracy: true,
      source: SpeedSampleSource.positionDelta,
    );
    return switch (fallbackValidation) {
      SpeedSampleAccepted(:final sample) => ReconciledSpeedSample(sample: sample, resetFilter: true),
      SpeedSampleRejected() => ReconciledSpeedSample(sample: penalizedPlatformSample),
    };
  }

  _PlatformPositionConsistency _checkConsistency({
    required AcceptedSpeedSample platformSample,
    required FallbackSpeedEstimate positionEstimate,
  }) {
    final difference = (platformSample.speed - positionEstimate.speed).abs();
    final tolerance = max(
      _consistencyMinTolerance,
      _consistencySigmaFactor *
          sqrt(platformSample.speedAccuracy.measurementNoise + positionEstimate.speedAccuracy.measurementNoise),
    );

    if (difference <= tolerance) {
      return const _PlatformPositionConsistency(isConflict: false, confidenceFactor: 1.0);
    }

    return _PlatformPositionConsistency(
      isConflict: true,
      confidenceFactor: (tolerance / difference).clamp(_consistencyMinConfidenceFactor, 1.0),
    );
  }
}

final class _PlatformPositionConsistency {
  final bool isConflict;
  final double confidenceFactor;

  const _PlatformPositionConsistency({required this.isConflict, required this.confidenceFactor});
}
