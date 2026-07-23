import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/speed_tracker/position_delta_speed_estimator.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';

const _metersPerLongitudeDegreeAtEquator = 111319.49079327358;

void main() {
  final timestamp = DateTime.utc(2026, 1, 1, 12);

  group('PositionDeltaSpeedEstimator antimeridian handling', () {
    test('keeps eastbound speed continuous across the antimeridian', () {
      final baseline = _estimateSpeed(timestamp: timestamp, originLongitude: 0, signedSpeed: 4);
      final crossing = _estimateSpeed(timestamp: timestamp, originLongitude: 179.99995, signedSpeed: 4);

      expect(baseline, isNotNull);
      expect(crossing, isNotNull);
      expect(crossing!.speed, closeTo(4, 0.001));
      expect(crossing.speed, closeTo(baseline!.speed, 0.001));
    });

    test('keeps westbound speed continuous across the antimeridian', () {
      final baseline = _estimateSpeed(timestamp: timestamp, originLongitude: 0, signedSpeed: -4);
      final crossing = _estimateSpeed(timestamp: timestamp, originLongitude: -179.99995, signedSpeed: -4);

      expect(baseline, isNotNull);
      expect(crossing, isNotNull);
      expect(crossing!.speed, closeTo(4, 0.001));
      expect(crossing.speed, closeTo(baseline!.speed, 0.001));
    });
  });
}

FallbackSpeedEstimate? _estimateSpeed({
  required DateTime timestamp,
  required double originLongitude,
  required double signedSpeed,
}) {
  final estimator = PositionDeltaSpeedEstimator();
  for (var second = 0; second < 4; second++) {
    final longitude = _wrapLongitude(originLongitude + ((signedSpeed * second) / _metersPerLongitudeDegreeAtEquator));
    estimator.addSample(
      ValidPositionSample(
        latitude: 0,
        longitude: longitude,
        timestamp: timestamp.add(Duration(seconds: second)),
        horizontalAccuracy: 1,
      ),
    );
  }
  return estimator.estimate();
}

double _wrapLongitude(double longitude) {
  if (longitude > 180) {
    return longitude - 360;
  }
  if (longitude < -180) {
    return longitude + 360;
  }
  return longitude;
}
