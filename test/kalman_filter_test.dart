import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/util/kalman_filter.dart';

void main() {
  group('KalmanFilter', () {
    test('uses initial measurement noise as starting uncertainty', () {
      final filter = KalmanFilter(
        initialMeasurement: 0,
        initialMeasurementNoise: 100,
        processNoise: 0,
      );

      final estimate = filter.update(10, 1);

      expect(estimate, closeTo(9.90099, 0.00001));
    });

    test('high measurement noise does not fully jump to a new measurement', () {
      final filter = KalmanFilter(
        initialMeasurement: 10,
        initialMeasurementNoise: 1,
        processNoise: 0,
      );

      final estimate = filter.update(20, 100);

      expect(estimate, closeTo(10.09901, 0.00001));
    });
  });
}
