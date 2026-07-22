import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';

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
}

Position _position({required double longitude, required DateTime timestamp}) {
  return Position(
    longitude: longitude,
    latitude: 0,
    timestamp: timestamp,
    accuracy: 5,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}
