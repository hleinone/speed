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

    test('default elapsed time adds one second of process noise', () {
      final filter = KalmanFilter(
        initialMeasurement: 0,
        initialMeasurementNoise: 1,
        processNoise: 2,
      );

      final estimate = filter.update(10, 1);

      expect(estimate, closeTo(7.5, 0.00001));
    });

    test('shorter elapsed time adds proportionally less process noise', () {
      final filter = KalmanFilter(
        initialMeasurement: 0,
        initialMeasurementNoise: 1,
        processNoise: 2,
      );

      final estimate = filter.update(
        10,
        1,
        elapsedTime: const Duration(milliseconds: 500),
      );

      expect(estimate, closeTo(6.66667, 0.00001));
    });

    test('longer elapsed time adds proportionally more process noise', () {
      final filter = KalmanFilter(
        initialMeasurement: 0,
        initialMeasurementNoise: 1,
        processNoise: 2,
      );

      final estimate = filter.update(
        10,
        1,
        elapsedTime: const Duration(seconds: 2),
      );

      expect(estimate, closeTo(8.33333, 0.00001));
    });

    test('zero and negative elapsed time add no process noise', () {
      final zeroElapsedFilter = KalmanFilter(
        initialMeasurement: 0,
        initialMeasurementNoise: 1,
        processNoise: 2,
      );
      final negativeElapsedFilter = KalmanFilter(
        initialMeasurement: 0,
        initialMeasurementNoise: 1,
        processNoise: 2,
      );

      final zeroElapsedEstimate = zeroElapsedFilter.update(
        10,
        1,
        elapsedTime: Duration.zero,
      );
      final negativeElapsedEstimate = negativeElapsedFilter.update(
        10,
        1,
        elapsedTime: const Duration(seconds: -1),
      );

      expect(zeroElapsedEstimate, closeTo(5, 0.00001));
      expect(negativeElapsedEstimate, closeTo(5, 0.00001));
    });
  });
}
