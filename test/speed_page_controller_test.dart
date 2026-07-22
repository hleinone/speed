import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/speed_page_controller.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracking_source.dart';
import 'package:speed/src/speed_unit_store.dart';

void main() {
  group('SpeedPageController tracking state', () {
    test('starts acquiring and becomes current', () async {
      final speedStream = StreamController<Speed>(sync: true);
      final controller = _controller(_FakeTrackingSource([speedStream.stream]));
      addTearDown(() async {
        controller.dispose();
        await speedStream.close();
      });

      controller.start();
      expect(controller.state, isA<SpeedPageAcquiring>());
      await pumpEventQueue();
      speedStream.add(const CurrentSpeed(12, 0.8));

      final state = controller.state as SpeedPageCurrent;
      expect(state.speed, isA<CurrentSpeed>());
      expect(state.speed.value, 12);
      expect(state.speed.accuracy, 0.8);
    });

    test('becomes unavailable when the stream completes after a current speed', () async {
      final speedStream = StreamController<Speed>(sync: true);
      final controller = _controller(_FakeTrackingSource([speedStream.stream]));
      addTearDown(controller.dispose);

      controller.start();
      await pumpEventQueue();
      speedStream.add(const CurrentSpeed(12, 0.8));
      expect(controller.state, isA<SpeedPageCurrent>());

      await speedStream.close();
      await pumpEventQueue();

      expect(controller.state, isA<SpeedPageUnavailable>());
    });

    test('maps unavailable speed and an empty stream to unavailable', () async {
      final unavailableController = _controller(_FakeTrackingSource([Stream.value(const UnavailableSpeed())]));
      final emptyController = _controller(_FakeTrackingSource([const Stream<Speed>.empty()]));
      addTearDown(unavailableController.dispose);
      addTearDown(emptyController.dispose);

      unavailableController.start();
      emptyController.start();
      await pumpEventQueue();

      expect(unavailableController.state, isA<SpeedPageUnavailable>());
      expect(emptyController.state, isA<SpeedPageUnavailable>());
    });

    test('maps all typed tracking failures to explicit page states', () async {
      final cases = <SpeedTrackingFailureKind, Matcher>{
        SpeedTrackingFailureKind.permissionDenied: isA<SpeedPagePermissionDenied>().having(
          (state) => state.isPermanent,
          'isPermanent',
          isFalse,
        ),
        SpeedTrackingFailureKind.permissionDeniedForever: isA<SpeedPagePermissionDenied>().having(
          (state) => state.isPermanent,
          'isPermanent',
          isTrue,
        ),
        SpeedTrackingFailureKind.locationServicesDisabled: isA<SpeedPageLocationDisabled>(),
        SpeedTrackingFailureKind.preciseLocationRequired: isA<SpeedPagePreciseLocationRequired>(),
        SpeedTrackingFailureKind.unexpected: isA<SpeedPageFailure>(),
      };

      for (final entry in cases.entries) {
        final controller = _controller(
          _FakeTrackingSource([Stream<Speed>.error(SpeedTrackingException(entry.key, cause: StateError('failure')))]),
        );
        controller.start();
        await pumpEventQueue();

        expect(controller.state, entry.value, reason: entry.key.name);
        controller.dispose();
      }
    });

    test('maps an untyped stream error to a generic failure', () async {
      final error = StateError('GPS unavailable');
      final controller = _controller(_FakeTrackingSource([Stream<Speed>.error(error)]));
      addTearDown(controller.dispose);

      controller.start();
      await pumpEventQueue();

      final state = controller.state as SpeedPageFailure;
      expect(state.error, same(error));
    });

    test('retry cancels the old attempt and subscribes to a fresh stream', () async {
      final firstCanceled = Completer<void>();
      final first = StreamController<Speed>.broadcast(sync: true, onCancel: firstCanceled.complete);
      final second = StreamController<Speed>.broadcast(sync: true);
      final source = _FakeTrackingSource([first.stream, second.stream]);
      final controller = _controller(source);
      addTearDown(() async {
        controller.dispose();
        if (!first.isClosed) {
          await first.close();
        }
        await second.close();
      });

      controller.start();
      await pumpEventQueue();
      first.add(const CurrentSpeed(5, 0.5));
      expect((controller.state as SpeedPageCurrent).speed.value, 5);

      await controller.retry();
      await firstCanceled.future;
      expect(controller.state, isA<SpeedPageAcquiring>());
      expect(source.streamCalls, 2);

      second.add(const CurrentSpeed(10, 0.9));
      first.add(const CurrentSpeed(99, 1));
      expect((controller.state as SpeedPageCurrent).speed.value, 10);

      await first.close();
      await pumpEventQueue();
      expect((controller.state as SpeedPageCurrent).speed.value, 10);
    });

    test('cancels the active speed subscription when disposed', () async {
      final subscriptionCanceled = Completer<void>();
      final speedStream = StreamController<Speed>(onCancel: subscriptionCanceled.complete);
      final controller = _controller(_FakeTrackingSource([speedStream.stream]));
      controller.start();
      await pumpEventQueue();

      controller.dispose();

      await subscriptionCanceled.future;
      await speedStream.close();
    });
  });

  group('SpeedPageController settings recovery', () {
    test('retries once on resume after app settings opened successfully', () async {
      final source = _FakeTrackingSource([
        Stream<Speed>.error(const SpeedTrackingException(SpeedTrackingFailureKind.permissionDeniedForever)),
        const Stream<Speed>.empty(),
      ], appSettingsOpened: true);
      final controller = _controller(source);
      addTearDown(controller.dispose);
      controller.start();
      await pumpEventQueue();

      expect(await controller.openAppSettings(), isTrue);
      expect(source.streamCalls, 1);
      controller.onAppResumed();
      await pumpEventQueue();

      expect(source.streamCalls, 2);
      expect(controller.state, isA<SpeedPageUnavailable>());

      controller.onAppResumed();
      await pumpEventQueue();
      expect(source.streamCalls, 2);
    });

    test('does not retry on ordinary resume or after settings failed to open', () async {
      final source = _FakeTrackingSource([const Stream<Speed>.empty()], appSettingsOpened: false);
      final controller = _controller(source);
      addTearDown(controller.dispose);
      controller.start();
      await pumpEventQueue();

      controller.onAppResumed();
      expect(await controller.openAppSettings(), isFalse);
      controller.onAppResumed();
      await pumpEventQueue();

      expect(source.streamCalls, 1);
    });

    test('opens location settings through the tracking source', () async {
      final source = _FakeTrackingSource([const Stream<Speed>.empty()], locationSettingsOpened: true);
      final controller = _controller(source);
      addTearDown(controller.dispose);

      expect(await controller.openLocationSettings(), isTrue);
      expect(source.openLocationSettingsCalls, 1);
    });

    test('reports a thrown settings error as an unsuccessful action', () async {
      final source = _FakeTrackingSource([
        const Stream<Speed>.empty(),
      ], appSettingsError: Exception('settings unavailable'));
      final controller = _controller(source);
      addTearDown(controller.dispose);

      expect(await controller.openAppSettings(), isFalse);
      controller.onAppResumed();
      await pumpEventQueue();

      expect(source.streamCalls, 0);
    });
  });

  group('SpeedPageController speed unit persistence', () {
    test('loads the stored speed unit', () async {
      final store = _FakeSpeedUnitStore(unit: SpeedUnit.knots);
      final controller = SpeedPageController(
        trackingSource: _FakeTrackingSource([const Stream<Speed>.empty()]),
        speedUnitStore: store,
      );
      addTearDown(controller.dispose);

      controller.start();
      await pumpEventQueue();

      expect(controller.speedUnit, SpeedUnit.knots);
      expect(store.loadCalls, 1);
    });

    test('an initial unit bypasses the stored unit', () async {
      final store = _FakeSpeedUnitStore(unit: SpeedUnit.knots);
      final controller = SpeedPageController(
        trackingSource: _FakeTrackingSource([const Stream<Speed>.empty()]),
        speedUnitStore: store,
        initialSpeedUnit: SpeedUnit.milesPerHour,
      );
      addTearDown(controller.dispose);

      controller.start();
      await pumpEventQueue();

      expect(controller.speedUnit, SpeedUnit.milesPerHour);
      expect(store.loadCalls, 0);
    });

    test('selects and persists the exact unit', () async {
      final store = _FakeSpeedUnitStore();
      final controller = SpeedPageController(
        trackingSource: _FakeTrackingSource([const Stream<Speed>.empty()]),
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
      final controller = SpeedPageController(
        trackingSource: _FakeTrackingSource([const Stream<Speed>.empty()]),
        speedUnitStore: store,
      );
      addTearDown(controller.dispose);
      controller.start();

      controller.selectSpeedUnit(SpeedUnit.footPerSecond);
      loadCompleter.complete(SpeedUnit.knots);
      await pumpEventQueue();

      expect(controller.speedUnit, SpeedUnit.footPerSecond);
    });

    test('preference failures do not become tracking failures', () async {
      final speedStream = StreamController<Speed>();
      final controller = SpeedPageController(
        trackingSource: _FakeTrackingSource([speedStream.stream]),
        speedUnitStore: _FakeSpeedUnitStore(loadError: StateError('load failed')),
      );
      addTearDown(() async {
        controller.dispose();
        await speedStream.close();
      });

      controller.start();
      await pumpEventQueue();

      expect(controller.state, isA<SpeedPageAcquiring>());
    });
  });
}

SpeedPageController _controller(_FakeTrackingSource source) {
  return SpeedPageController(
    trackingSource: source,
    speedUnitStore: _FakeSpeedUnitStore(),
    initialSpeedUnit: SpeedUnit.metersPerSecond,
  );
}

class _FakeTrackingSource implements SpeedTrackingSource {
  _FakeTrackingSource(
    this.streams, {
    this.appSettingsOpened = true,
    this.locationSettingsOpened = true,
    this.appSettingsError,
  });

  final List<Stream<Speed>> streams;
  final bool appSettingsOpened;
  final bool locationSettingsOpened;
  final Exception? appSettingsError;
  int streamCalls = 0;
  int openLocationSettingsCalls = 0;

  @override
  Stream<Speed> get stream {
    final index = streamCalls++;
    return streams[index];
  }

  @override
  Future<bool> openAppSettings() async {
    final error = appSettingsError;
    if (error != null) {
      throw error;
    }
    return appSettingsOpened;
  }

  @override
  Future<bool> openLocationSettings() async {
    openLocationSettingsCalls += 1;
    return locationSettingsOpened;
  }
}

class _FakeSpeedUnitStore implements SpeedUnitStore {
  _FakeSpeedUnitStore({this.unit = SpeedUnit.metersPerSecond, Future<SpeedUnit>? loadFuture, this.loadError})
    : _loadFuture = loadFuture;

  final Future<SpeedUnit>? _loadFuture;
  final Object? loadError;
  final List<SpeedUnit> savedUnits = [];
  SpeedUnit unit;
  int loadCalls = 0;

  @override
  Future<SpeedUnit> load() {
    loadCalls++;
    final error = loadError;
    if (error != null) {
      return Future.error(error);
    }
    return _loadFuture ?? Future.value(unit);
  }

  @override
  Future<void> save(SpeedUnit unit) async {
    savedUnits.add(unit);
    this.unit = unit;
  }
}
