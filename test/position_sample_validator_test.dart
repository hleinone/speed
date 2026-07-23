import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;

void main() {
  final now = DateTime.utc(2026, 1, 1, 12);
  const validator = PositionSampleValidator();

  group('PositionSampleValidator longitude boundaries', () {
    for (final longitude in [-180.0, 180.0]) {
      test('accepts $longitude degrees', () {
        final sample = validator.validate(_position(longitude: longitude, timestamp: now), now);

        expect(sample, isNotNull);
        expect(sample!.longitude, longitude);
      });
    }

    for (final longitude in [-180.000001, 180.000001]) {
      test('rejects $longitude degrees', () {
        final sample = validator.validate(_position(longitude: longitude, timestamp: now), now);

        expect(sample, isNull);
      });
    }

    for (final longitude in [double.nan, double.infinity, double.negativeInfinity]) {
      test('rejects non-finite longitude $longitude', () {
        final sample = validator.validate(_position(longitude: longitude, timestamp: now), now);

        expect(sample, isNull);
      });
    }
  });

  group('PositionSampleValidator freshness and accuracy', () {
    test('rejects stale and far-future timestamps', () {
      final staleSample = validator.validate(_position(timestamp: now.subtract(const Duration(seconds: 6))), now);
      final futureSample = validator.validate(_position(timestamp: now.add(const Duration(seconds: 2))), now);

      expect(staleSample, isNull);
      expect(futureSample, isNull);
    });

    test('accepts known and explicitly unknown horizontal accuracy', () {
      final knownSample = validator.validate(_position(timestamp: now, accuracy: 5), now);
      final unknownSample = validator.validate(_position(timestamp: now, accuracy: 0), now);

      expect(knownSample, isNotNull);
      expect(knownSample!.hasKnownHorizontalAccuracy, isTrue);
      expect(unknownSample, isNotNull);
      expect(unknownSample!.hasKnownHorizontalAccuracy, isFalse);
    });

    test('assigns horizontal confidence independently when accuracy is unknown', () {
      expect(PositionSampleValidator.horizontalAccuracyConfidence(0), config.unknownHorizontalAccuracyConfidence);
    });

    test('rejects invalid horizontal accuracy', () {
      const invalidAccuracies = [-1.0, double.nan, double.infinity, double.negativeInfinity, 50.1];

      for (final accuracy in invalidAccuracies) {
        expect(validator.validate(_position(timestamp: now, accuracy: accuracy), now), isNull);
      }
    });
  });
}

Position _position({double longitude = 0, required DateTime timestamp, double accuracy = 5}) {
  return Position(
    longitude: longitude,
    latitude: 0,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
