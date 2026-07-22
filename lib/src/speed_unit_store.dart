import 'package:shared_preferences/shared_preferences.dart';
import 'package:speed/src/speed_tracker/models.dart';

abstract interface class SpeedUnitStore {
  Future<SpeedUnit> load();

  Future<void> save(SpeedUnit unit);
}

class SharedPreferencesSpeedUnitStore implements SpeedUnitStore {
  const SharedPreferencesSpeedUnitStore();

  static const _preferenceKey = 'selected_speed_unit';

  @override
  Future<SpeedUnit> load() async {
    final preferences = await SharedPreferences.getInstance();
    final index = preferences.getInt(_preferenceKey);
    if (index == null || index < 0 || index >= SpeedUnit.values.length) {
      return SpeedUnit.metersPerSecond;
    }
    return SpeedUnit.values[index];
  }

  @override
  Future<void> save(SpeedUnit unit) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_preferenceKey, unit.index);
  }
}
