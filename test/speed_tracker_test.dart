import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/speed_tracker.dart';

void main() {
  group('SpeedTracker.normalizeSpeedAccuracy', () {
    test('uses fallback noise and low confidence for zero accuracy', () {
      final estimate = SpeedTracker.normalizeSpeedAccuracy(0);

      expect(estimate.isKnown, isFalse);
      expect(estimate.standardDeviation, SpeedTracker.fallbackSpeedAccuracy);
      expect(estimate.measurementNoise, 4.0);
      expect(estimate.confidence, SpeedTracker.unknownSpeedConfidence);
    });

    test('treats negative, NaN, and infinite accuracy as unknown', () {
      const unknownValues = [
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final speedAccuracy in unknownValues) {
        final estimate = SpeedTracker.normalizeSpeedAccuracy(speedAccuracy);

        expect(estimate.isKnown, isFalse);
        expect(estimate.standardDeviation, SpeedTracker.fallbackSpeedAccuracy);
        expect(estimate.measurementNoise, 4.0);
        expect(estimate.confidence, SpeedTracker.unknownSpeedConfidence);
      }
    });

    test('preserves positive accuracy and existing confidence formula', () {
      final estimate = SpeedTracker.normalizeSpeedAccuracy(1.25);

      expect(estimate.isKnown, isTrue);
      expect(estimate.standardDeviation, 1.25);
      expect(estimate.measurementNoise, closeTo(1.5625, 0.000001));
      expect(estimate.confidence, closeTo(0.75, 0.000001));
    });
  });

  group('SpeedTracker.validateSpeedSample', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    SpeedSampleValidation validate({
      double speed = 10,
      DateTime? timestamp,
      double horizontalAccuracy = 5,
      double speedAccuracy = 0.5,
      AcceptedSpeedSample? previousAcceptedSample,
    }) {
      return SpeedTracker.validateSpeedSample(
        speed: speed,
        timestamp: timestamp ?? now,
        horizontalAccuracy: horizontalAccuracy,
        speedAccuracy: speedAccuracy,
        now: now,
        previousAcceptedSample: previousAcceptedSample,
      );
    }

    AcceptedSpeedSample acceptedSample({
      double speed = 10,
      DateTime? timestamp,
      double horizontalAccuracy = 5,
      double speedAccuracy = 0.5,
    }) {
      return AcceptedSpeedSample(
        speed: speed,
        timestamp: timestamp ?? now,
        horizontalAccuracy: horizontalAccuracy,
        speedAccuracy: SpeedTracker.normalizeSpeedAccuracy(speedAccuracy),
      );
    }

    test('accepts a fresh, accurate, finite first sample', () {
      final validation = validate();

      expect(validation.isAccepted, isTrue);
      expect(validation.rejectionReason, isNull);
      expect(validation.acceptedSample?.speed, 10);
      expect(validation.acceptedSample?.timestamp, now);
    });

    test('rejects stale and far-future timestamps', () {
      final staleValidation = validate(
        timestamp: now.subtract(const Duration(seconds: 6)),
      );
      final futureValidation = validate(
        timestamp: now.add(const Duration(seconds: 2)),
      );

      expect(staleValidation.isAccepted, isFalse);
      expect(
        staleValidation.rejectionReason,
        SpeedSampleRejectionReason.staleTimestamp,
      );
      expect(futureValidation.isAccepted, isFalse);
      expect(
        futureValidation.rejectionReason,
        SpeedSampleRejectionReason.futureTimestamp,
      );
    });

    test('rejects zero, non-finite, and excessive horizontal accuracy', () {
      const invalidHorizontalAccuracies = [
        -1.0,
        0.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        50.1,
      ];

      for (final horizontalAccuracy in invalidHorizontalAccuracies) {
        final validation = validate(horizontalAccuracy: horizontalAccuracy);

        expect(validation.isAccepted, isFalse);
        expect(
          validation.rejectionReason,
          SpeedSampleRejectionReason.invalidHorizontalAccuracy,
        );
      }
    });

    test('rejects negative, NaN, and infinite speeds', () {
      const invalidSpeeds = [
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final speed in invalidSpeeds) {
        final validation = validate(speed: speed);

        expect(validation.isAccepted, isFalse);
        expect(
          validation.rejectionReason,
          SpeedSampleRejectionReason.invalidSpeed,
        );
      }
    });

    test('accepts plausible speed changes between accepted samples', () {
      final previousSample = acceptedSample(
        speed: 10,
        timestamp: now.subtract(const Duration(seconds: 1)),
      );

      final validation = validate(
        speed: 17,
        previousAcceptedSample: previousSample,
      );

      expect(validation.isAccepted, isTrue);
      expect(validation.rejectionReason, isNull);
    });

    test('rejects a large one-sample speed spike', () {
      final previousSample = acceptedSample(
        speed: 10,
        timestamp: now.subtract(const Duration(seconds: 1)),
      );

      final validation = validate(
        speed: 30,
        previousAcceptedSample: previousSample,
      );

      expect(validation.isAccepted, isFalse);
      expect(
        validation.rejectionReason,
        SpeedSampleRejectionReason.implausibleAcceleration,
      );
    });

    test(
      'accepts first valid stream sample when no previous valid sample exists',
      () {
        final validation = validate(speed: 80);

        expect(validation.isAccepted, isTrue);
        expect(validation.rejectionReason, isNull);
      },
    );
  });
}
