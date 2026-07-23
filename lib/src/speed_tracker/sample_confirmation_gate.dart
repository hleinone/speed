import 'dart:math';

import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/speed_sample_validator.dart';
import 'package:speed/src/util/duration_extensions.dart';

const double _fallbackMinTolerance = 1.0;
const double _fallbackSpeedFactor = 0.35;
const double _startupJumpMinTolerance = 1.0;
const double _startupJumpSpeedFactor = 0.20;

final class SampleConfirmationGate {
  final SpeedSampleValidator _speedSampleValidator = const SpeedSampleValidator();
  AcceptedSpeedSample? _pendingFallbackSample;
  AcceptedSpeedSample? _pendingStartupJumpSample;

  bool shouldEmit({
    required AcceptedSpeedSample candidate,
    required AcceptedSpeedSample? previousAcceptedSample,
    required bool isStartupWarmup,
  }) {
    if (!_shouldEmitStartupSample(candidate, previousAcceptedSample, isStartupWarmup)) {
      _pendingFallbackSample = null;
      return false;
    }

    _pendingStartupJumpSample = null;
    return _shouldEmitFallbackSample(candidate, previousAcceptedSample);
  }

  void reset() {
    _pendingFallbackSample = null;
    _pendingStartupJumpSample = null;
  }

  bool _shouldEmitStartupSample(
    AcceptedSpeedSample candidate,
    AcceptedSpeedSample? previousAcceptedSample,
    bool isStartupWarmup,
  ) {
    if (candidate.source != SpeedSampleSource.platform || !isStartupWarmup || previousAcceptedSample == null) {
      return true;
    }

    final elapsedSeconds = candidate.timestamp.difference(previousAcceptedSample.timestamp).inFractionalSeconds;
    if (elapsedSeconds <= 0 ||
        _speedSampleValidator.hasPlausibleSpeedChange(
          previousSample: previousAcceptedSample,
          speed: candidate.speed,
          speedAccuracy: candidate.speedAccuracy,
          elapsedSeconds: elapsedSeconds,
        )) {
      return true;
    }

    final pendingStartupJumpSample = _pendingStartupJumpSample;
    if (pendingStartupJumpSample != null && _matchesPendingStartupJump(candidate, pendingStartupJumpSample)) {
      return true;
    }

    _pendingStartupJumpSample = candidate;
    return false;
  }

  bool _matchesPendingStartupJump(AcceptedSpeedSample candidate, AcceptedSpeedSample pendingStartupJumpSample) {
    final tolerance = max(_startupJumpMinTolerance, pendingStartupJumpSample.speed * _startupJumpSpeedFactor);
    return (candidate.speed - pendingStartupJumpSample.speed).abs() <= tolerance;
  }

  bool _shouldEmitFallbackSample(AcceptedSpeedSample candidate, AcceptedSpeedSample? previousAcceptedSample) {
    if (candidate.source == SpeedSampleSource.platform || candidate.speed == 0 || previousAcceptedSample != null) {
      _pendingFallbackSample = null;
      return true;
    }

    final pendingFallbackSample = _pendingFallbackSample;
    if (pendingFallbackSample == null) {
      _pendingFallbackSample = candidate;
      return false;
    }

    final tolerance = max(_fallbackMinTolerance, pendingFallbackSample.speed * _fallbackSpeedFactor);
    if ((candidate.speed - pendingFallbackSample.speed).abs() <= tolerance) {
      _pendingFallbackSample = null;
      return true;
    }

    _pendingFallbackSample = candidate;
    return false;
  }
}
