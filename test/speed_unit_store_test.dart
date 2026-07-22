import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_unit_store.dart';

void main() {
  const store = SharedPreferencesSpeedUnitStore();
  const preferenceKey = 'selected_speed_unit';
  const legacyUnitsByIndex = {
    0: SpeedUnit.kilometersPerHour,
    1: SpeedUnit.milesPerHour,
    2: SpeedUnit.metersPerSecond,
    3: SpeedUnit.footPerSecond,
    4: SpeedUnit.knots,
  };

  group('SharedPreferencesSpeedUnitStore', () {
    test('defaults to meters per second when no preference exists', () async {
      SharedPreferences.setMockInitialValues({});

      expect(await store.load(), SpeedUnit.metersPerSecond);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(preferenceKey), isFalse);
    });

    test('loads every valid stored unit name', () async {
      for (final unit in SpeedUnit.values) {
        SharedPreferences.setMockInitialValues({preferenceKey: unit.name});

        expect(await store.load(), unit, reason: unit.name);
      }
    });

    test('saves the stable unit name', () async {
      SharedPreferences.setMockInitialValues({});

      await store.save(SpeedUnit.milesPerHour);

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.get(preferenceKey), SpeedUnit.milesPerHour.name);
    });

    test('migrates every valid legacy index to its stable unit name', () async {
      for (final entry in legacyUnitsByIndex.entries) {
        SharedPreferences.setMockInitialValues({preferenceKey: entry.key});

        expect(await store.load(), entry.value, reason: 'legacy index ${entry.key}');
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.get(preferenceKey), entry.value.name);
      }
    });

    test('defaults without rewriting invalid legacy indexes', () async {
      for (final index in [-1, 5, 999]) {
        SharedPreferences.setMockInitialValues({preferenceKey: index});

        expect(await store.load(), SpeedUnit.metersPerSecond);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.get(preferenceKey), index);
      }
    });

    test('defaults without rewriting unknown unit names', () async {
      for (final name in ['', 'unknown']) {
        SharedPreferences.setMockInitialValues({preferenceKey: name});

        expect(await store.load(), SpeedUnit.metersPerSecond);
        final preferences = await SharedPreferences.getInstance();
        expect(preferences.get(preferenceKey), name);
      }
    });

    test('defaults without rewriting unsupported value types', () async {
      SharedPreferences.setMockInitialValues({preferenceKey: true});

      expect(await store.load(), SpeedUnit.metersPerSecond);
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.get(preferenceKey), isTrue);
    });
  });
}
