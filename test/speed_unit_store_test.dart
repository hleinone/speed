import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_unit_store.dart';

void main() {
  const store = SharedPreferencesSpeedUnitStore();

  group('SharedPreferencesSpeedUnitStore', () {
    test('defaults to meters per second when no preference exists', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await store.load(), SpeedUnit.metersPerSecond);
    });

    test('defaults to meters per second for an invalid stored index', () async {
      for (final index in [-1, 999]) {
        SharedPreferences.setMockInitialValues({'selected_speed_unit': index});

        expect(await store.load(), SpeedUnit.metersPerSecond);
      }
    });

    test('loads and saves a speed unit', () async {
      SharedPreferences.setMockInitialValues({'selected_speed_unit': SpeedUnit.knots.index});

      expect(await store.load(), SpeedUnit.knots);

      await store.save(SpeedUnit.milesPerHour);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getInt('selected_speed_unit'), SpeedUnit.milesPerHour.index);
    });
  });
}
