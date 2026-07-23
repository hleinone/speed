import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);

  group('SpeedSampleValidator speed accuracy normalization', () {
    const validator = SpeedSampleValidator();

    test('uses fallback noise and low confidence for zero accuracy', () {
      final estimate = validator.normalizeSpeedAccuracy(0);

      expect(estimate.isKnown, isFalse);
      expect(estimate.standardDeviation, config.fallbackSpeedAccuracy);
      expect(estimate.measurementNoise, 4.0);
      expect(estimate.confidence, config.unknownSpeedConfidence);
    });

    test('treats negative, NaN, and infinite accuracy as unknown', () {
      const unknownValues = [-1.0, double.nan, double.infinity, double.negativeInfinity];

      for (final speedAccuracy in unknownValues) {
        final estimate = validator.normalizeSpeedAccuracy(speedAccuracy);

        expect(estimate.isKnown, isFalse);
        expect(estimate.standardDeviation, config.fallbackSpeedAccuracy);
        expect(estimate.measurementNoise, 4.0);
        expect(estimate.confidence, config.unknownSpeedConfidence);
      }
    });

    test('preserves positive accuracy and existing confidence formula', () {
      final estimate = validator.normalizeSpeedAccuracy(1.25);

      expect(estimate.isKnown, isTrue);
      expect(estimate.standardDeviation, 1.25);
      expect(estimate.measurementNoise, closeTo(1.5625, 0.000001));
      expect(estimate.confidence, closeTo(0.75, 0.000001));
    });
  });

  group('SpeedSampleValidator platform samples', () {
    test('accepts a valid sample and fixes its source', () {
      final validation = _validatePlatform(now: now);

      expect(validation, isA<SpeedSampleAccepted>());
      final sample = (validation as SpeedSampleAccepted).sample;
      expect(sample.speed, 10);
      expect(sample.timestamp, now);
      expect(sample.source, SpeedSampleSource.platform);
      expect(sample.speedAccuracy.isKnown, isTrue);
    });

    test('rejects invalid speeds', () {
      const invalidSpeeds = [-1.0, double.nan, double.infinity, double.negativeInfinity];

      for (final speed in invalidSpeeds) {
        expect(_validatePlatform(now: now, speed: speed), _isRejectedFor(SpeedSampleRejectionReason.invalidSpeed));
      }
    });

    test('rejects unknown platform speed accuracy', () {
      const unknownAccuracies = [0.0, -1.0, double.nan, double.infinity, double.negativeInfinity];

      for (final speedAccuracy in unknownAccuracies) {
        expect(
          _validatePlatform(now: now, speedAccuracy: speedAccuracy),
          _isRejectedFor(SpeedSampleRejectionReason.invalidSpeedAccuracy),
        );
      }
    });

    test('accepts unknown horizontal accuracy', () {
      final validation = _validatePlatform(now: now, horizontalAccuracy: 0);

      expect(validation, isA<SpeedSampleAccepted>());
      expect((validation as SpeedSampleAccepted).sample.horizontalAccuracy, 0);
    });

    test('rejects zero-confidence speed and horizontal accuracy', () {
      expect(
        _validatePlatform(now: now, speedAccuracy: 5),
        _isRejectedFor(SpeedSampleRejectionReason.insufficientConfidence),
      );
      expect(
        _validatePlatform(now: now, horizontalAccuracy: 50),
        _isRejectedFor(SpeedSampleRejectionReason.insufficientConfidence),
      );
    });

    test('rejects non-increasing timestamps', () {
      final previousSample = _acceptedSample(speed: 10, timestamp: now);

      final validation = _validatePlatform(now: now, previousAcceptedSample: previousSample);

      expect(validation, _isRejectedFor(SpeedSampleRejectionReason.nonIncreasingTimestamp));
    });

    test('enforces acceleration unless explicitly disabled', () {
      final previousSample = _acceptedSample(speed: 10, timestamp: now);
      final timestamp = now.add(const Duration(seconds: 1));

      expect(
        _validatePlatform(now: timestamp, speed: 30, previousAcceptedSample: previousSample),
        _isRejectedFor(SpeedSampleRejectionReason.implausibleAcceleration),
      );
      expect(
        _validatePlatform(
          now: timestamp,
          speed: 30,
          previousAcceptedSample: previousSample,
          enforceAccelerationLimit: false,
        ),
        isA<SpeedSampleAccepted>(),
      );
    });
  });

  group('SpeedSampleValidator position-delta samples', () {
    test('accepts estimated accuracy and fixes the source', () {
      final validation = _validatePositionDelta(now: now);

      expect(validation, isA<SpeedSampleAccepted>());
      final sample = (validation as SpeedSampleAccepted).sample;
      expect(sample.speed, 4);
      expect(sample.source, SpeedSampleSource.positionDelta);
      expect(sample.speedAccuracy.isKnown, isFalse);
    });

    test('rejects invalid speeds', () {
      const invalidSpeeds = [-1.0, double.nan, double.infinity, double.negativeInfinity];

      for (final speed in invalidSpeeds) {
        expect(_validatePositionDelta(now: now, speed: speed), _isRejectedFor(SpeedSampleRejectionReason.invalidSpeed));
      }
    });

    test('requires known horizontal accuracy', () {
      final validation = _validatePositionDelta(now: now, horizontalAccuracy: 0);

      expect(validation, _isRejectedFor(SpeedSampleRejectionReason.invalidHorizontalAccuracy));
    });

    test('rejects zero-confidence estimated accuracy', () {
      final validation = _validatePositionDelta(
        now: now,
        speedAccuracy: const SpeedAccuracyEstimate(standardDeviation: 2, confidence: 0, isKnown: false),
      );

      expect(validation, _isRejectedFor(SpeedSampleRejectionReason.insufficientConfidence));
    });

    test('rejects non-increasing timestamps', () {
      final previousSample = _acceptedSample(speed: 4, timestamp: now);

      final validation = _validatePositionDelta(now: now, previousAcceptedSample: previousSample);

      expect(validation, _isRejectedFor(SpeedSampleRejectionReason.nonIncreasingTimestamp));
    });

    test('enforces acceleration unless explicitly disabled', () {
      final previousSample = _acceptedSample(speed: 4, timestamp: now);
      final timestamp = now.add(const Duration(seconds: 1));

      expect(
        _validatePositionDelta(now: timestamp, speed: 30, previousAcceptedSample: previousSample),
        _isRejectedFor(SpeedSampleRejectionReason.implausibleAcceleration),
      );
      expect(
        _validatePositionDelta(
          now: timestamp,
          speed: 30,
          previousAcceptedSample: previousSample,
          enforceAccelerationLimit: false,
        ),
        isA<SpeedSampleAccepted>(),
      );
    });
  });
}

SpeedSampleValidation _validatePlatform({
  required DateTime now,
  double speed = 10,
  double speedAccuracy = 0.5,
  double horizontalAccuracy = 5,
  AcceptedSpeedSample? previousAcceptedSample,
  bool enforceAccelerationLimit = true,
}) {
  return const SpeedSampleValidator().validatePlatformSample(
    speed: speed,
    speedAccuracy: speedAccuracy,
    positionSample: _positionSample(timestamp: now, horizontalAccuracy: horizontalAccuracy),
    previousAcceptedSample: previousAcceptedSample,
    enforceAccelerationLimit: enforceAccelerationLimit,
  );
}

SpeedSampleValidation _validatePositionDelta({
  required DateTime now,
  double speed = 4,
  SpeedAccuracyEstimate speedAccuracy = const SpeedAccuracyEstimate(
    standardDeviation: 2,
    confidence: 0.125,
    isKnown: false,
  ),
  double horizontalAccuracy = 5,
  AcceptedSpeedSample? previousAcceptedSample,
  bool enforceAccelerationLimit = true,
}) {
  return const SpeedSampleValidator().validatePositionDeltaSample(
    speed: speed,
    speedAccuracy: speedAccuracy,
    positionSample: _positionSample(timestamp: now, horizontalAccuracy: horizontalAccuracy),
    previousAcceptedSample: previousAcceptedSample,
    enforceAccelerationLimit: enforceAccelerationLimit,
  );
}

ValidPositionSample _positionSample({required DateTime timestamp, required double horizontalAccuracy}) {
  return ValidPositionSample(latitude: 0, longitude: 0, timestamp: timestamp, horizontalAccuracy: horizontalAccuracy);
}

AcceptedSpeedSample _acceptedSample({required double speed, required DateTime timestamp}) {
  return AcceptedSpeedSample(
    speed: speed,
    timestamp: timestamp,
    horizontalAccuracy: 5,
    speedAccuracy: const SpeedAccuracyEstimate(standardDeviation: 0.5, confidence: 0.9, isKnown: true),
  );
}

Matcher _isRejectedFor(SpeedSampleRejectionReason reason) {
  return isA<SpeedSampleRejected>().having((validation) => validation.reason, 'reason', reason);
}
