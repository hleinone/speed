import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/speed_page_controller.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_unit_store.dart';

void main() {
  group('SpeedPageController', () {
    test('loads the stored speed unit', () async {
      final store = _FakeSpeedUnitStore(unit: SpeedUnit.knots);
      final controller = SpeedPageController(speedStream: const Stream<Speed>.empty(), speedUnitStore: store);
      addTearDown(controller.dispose);

      controller.start();
      await pumpEventQueue();

      expect(controller.speedUnit, SpeedUnit.knots);
      expect(store.loadCalls, 1);
    });

    test('an initial unit bypasses the stored unit', () async {
      final store = _FakeSpeedUnitStore(unit: SpeedUnit.knots);
      final controller = SpeedPageController(
        speedStream: const Stream<Speed>.empty(),
        speedUnitStore: store,
        initialSpeedUnit: SpeedUnit.milesPerHour,
      );
      addTearDown(controller.dispose);

      controller.start();
      await pumpEventQueue();

      expect(controller.speedUnit, SpeedUnit.milesPerHour);
      expect(store.loadCalls, 0);
    });

    test('updates speed and forwards stream errors', () async {
      final speedStream = StreamController<Speed>(sync: true);
      final expectedError = StateError('GPS unavailable');
      Object? reportedError;
      final controller = SpeedPageController(
        speedStream: speedStream.stream,
        speedUnitStore: _FakeSpeedUnitStore(),
        initialSpeedUnit: SpeedUnit.metersPerSecond,
        onError: (error, stackTrace) => reportedError = error,
      );
      addTearDown(() async {
        controller.dispose();
        await speedStream.close();
      });

      controller.start();
      speedStream
        ..add(const Speed.current(12, 0.8))
        ..addError(expectedError);

      expect(controller.speed, const TypeMatcher<Speed>());
      expect(controller.speed?.value, 12);
      expect(reportedError, same(expectedError));
    });

    test('selects and persists the exact unit', () async {
      final store = _FakeSpeedUnitStore();
      final controller = SpeedPageController(
        speedStream: const Stream<Speed>.empty(),
        speedUnitStore: store,
        initialSpeedUnit: SpeedUnit.metersPerSecond,
      );
      addTearDown(controller.dispose);
      controller.start();

      controller.selectSpeedUnit(SpeedUnit.kilometersPerHour);
      expect(controller.speedUnit, SpeedUnit.kilometersPerHour);
      await pumpEventQueue();

      expect(store.savedUnits, [SpeedUnit.kilometersPerHour]);
    });

    test('a late preference load does not overwrite a user selection', () async {
      final loadCompleter = Completer<SpeedUnit>();
      final store = _FakeSpeedUnitStore(loadFuture: loadCompleter.future);
      final controller = SpeedPageController(speedStream: const Stream<Speed>.empty(), speedUnitStore: store);
      addTearDown(controller.dispose);
      controller.start();

      controller.selectSpeedUnit(SpeedUnit.footPerSecond);
      loadCompleter.complete(SpeedUnit.knots);
      await pumpEventQueue();

      expect(controller.speedUnit, SpeedUnit.footPerSecond);
    });

    test('cancels the speed subscription when disposed', () async {
      final subscriptionCanceled = Completer<void>();
      final speedStream = StreamController<Speed>(onCancel: subscriptionCanceled.complete);
      final controller = SpeedPageController(
        speedStream: speedStream.stream,
        speedUnitStore: _FakeSpeedUnitStore(),
        initialSpeedUnit: SpeedUnit.metersPerSecond,
      );
      controller.start();

      controller.dispose();

      await subscriptionCanceled.future;
      await speedStream.close();
    });
  });
}

class _FakeSpeedUnitStore implements SpeedUnitStore {
  _FakeSpeedUnitStore({this.unit = SpeedUnit.metersPerSecond, Future<SpeedUnit>? loadFuture})
    : _loadFuture = loadFuture;

  final Future<SpeedUnit>? _loadFuture;
  final List<SpeedUnit> savedUnits = [];
  SpeedUnit unit;
  int loadCalls = 0;

  @override
  Future<SpeedUnit> load() {
    loadCalls++;
    return _loadFuture ?? Future.value(unit);
  }

  @override
  Future<void> save(SpeedUnit unit) async {
    savedUnits.add(unit);
    this.unit = unit;
  }
}
