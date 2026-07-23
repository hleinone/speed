import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/src/speed_tracker/models.dart';

abstract interface class SpeedUnitStore {
  Future<SpeedUnit> load();

  Future<void> save(SpeedUnit unit);
}

class SharedPreferencesSpeedUnitStore implements SpeedUnitStore {
  const SharedPreferencesSpeedUnitStore();

  static const _preferenceKey = 'selected_speed_unit';
  static const _defaultUnit = SpeedUnit.metersPerSecond;
  static const _legacyUnitsByIndex = [
    SpeedUnit.kilometersPerHour,
    SpeedUnit.milesPerHour,
    SpeedUnit.metersPerSecond,
    SpeedUnit.footPerSecond,
    SpeedUnit.knots,
  ];

  @override
  Future<SpeedUnit> load() async {
    final preferences = await SharedPreferences.getInstance();
    final storedValue = preferences.get(_preferenceKey);
    if (storedValue is String) {
      return _unitFromName(storedValue);
    }
    if (storedValue is! int || storedValue < 0 || storedValue >= _legacyUnitsByIndex.length) {
      return _defaultUnit;
    }

    final unit = _legacyUnitsByIndex[storedValue];
    await preferences.setString(_preferenceKey, unit.name);
    return unit;
  }

  @override
  Future<void> save(SpeedUnit unit) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_preferenceKey, unit.name);
  }

  SpeedUnit _unitFromName(String name) => SpeedUnit.values.asNameMap()[name] ?? _defaultUnit;
}
