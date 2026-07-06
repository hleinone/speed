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
}
