import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker.dart';

void main() {
  group('Speed', () {
    test(
      'current speed exposes value, accuracy, status, and unit conversion',
      () {
        const speed = Speed.current(10, 0.75);

        expect(speed.status, SpeedStatus.current);
        expect(speed.isCurrent, isTrue);
        expect(speed.value, 10);
        expect(speed.accuracy, 0.75);
        expect(speed.getAs(SpeedUnit.kilometersPerHour), 36);
      },
    );

    test('unavailable speed has no value and cannot be converted', () {
      const speed = Speed.unavailable();

      expect(speed.status, SpeedStatus.unavailable);
      expect(speed.isCurrent, isFalse);
      expect(speed.value, isNull);
      expect(speed.accuracy, 0);
      expect(() => speed.getAs(SpeedUnit.metersPerSecond), throwsStateError);
    });
  });

  group('SpeedTracker.normalizeSpeedAccuracy', () {
    test('uses fallback noise and low confidence for zero accuracy', () {
      final estimate = SpeedTracker.normalizeSpeedAccuracy(0);

      expect(estimate.isKnown, isFalse);
      expect(estimate.standardDeviation, SpeedTracker.fallbackSpeedAccuracy);
      expect(estimate.measurementNoise, 4.0);
      expect(estimate.confidence, SpeedTracker.unknownSpeedConfidence);
    });

    test('treats negative, NaN, and infinite accuracy as unknown', () {
      const unknownValues = [
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final speedAccuracy in unknownValues) {
        final estimate = SpeedTracker.normalizeSpeedAccuracy(speedAccuracy);

        expect(estimate.isKnown, isFalse);
        expect(estimate.standardDeviation, SpeedTracker.fallbackSpeedAccuracy);
        expect(estimate.measurementNoise, 4.0);
        expect(estimate.confidence, SpeedTracker.unknownSpeedConfidence);
      }
    });

    test('preserves positive accuracy and existing confidence formula', () {
      final estimate = SpeedTracker.normalizeSpeedAccuracy(1.25);

      expect(estimate.isKnown, isTrue);
      expect(estimate.standardDeviation, 1.25);
      expect(estimate.measurementNoise, closeTo(1.5625, 0.000001));
      expect(estimate.confidence, closeTo(0.75, 0.000001));
    });
  });

  group('SpeedTracker.validateSpeedSample', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    SpeedSampleValidation validate({
      double speed = 10,
      DateTime? timestamp,
      double horizontalAccuracy = 5,
      double speedAccuracy = 0.5,
      AcceptedSpeedSample? previousAcceptedSample,
    }) {
      return SpeedTracker.validateSpeedSample(
        speed: speed,
        timestamp: timestamp ?? now,
        horizontalAccuracy: horizontalAccuracy,
        speedAccuracy: speedAccuracy,
        now: now,
        previousAcceptedSample: previousAcceptedSample,
      );
    }

    AcceptedSpeedSample acceptedSample({
      double speed = 10,
      DateTime? timestamp,
      double horizontalAccuracy = 5,
      double speedAccuracy = 0.5,
    }) {
      return AcceptedSpeedSample(
        speed: speed,
        timestamp: timestamp ?? now,
        horizontalAccuracy: horizontalAccuracy,
        speedAccuracy: SpeedTracker.normalizeSpeedAccuracy(speedAccuracy),
      );
    }

    test('accepts a fresh, accurate, finite first sample', () {
      final validation = validate();

      expect(validation.isAccepted, isTrue);
      expect(validation.rejectionReason, isNull);
      expect(validation.acceptedSample?.speed, 10);
      expect(validation.acceptedSample?.timestamp, now);
    });

    test('rejects stale and far-future timestamps', () {
      final staleValidation = validate(
        timestamp: now.subtract(const Duration(seconds: 6)),
      );
      final futureValidation = validate(
        timestamp: now.add(const Duration(seconds: 2)),
      );

      expect(staleValidation.isAccepted, isFalse);
      expect(
        staleValidation.rejectionReason,
        SpeedSampleRejectionReason.staleTimestamp,
      );
      expect(futureValidation.isAccepted, isFalse);
      expect(
        futureValidation.rejectionReason,
        SpeedSampleRejectionReason.futureTimestamp,
      );
    });

    test('rejects zero, non-finite, and excessive horizontal accuracy', () {
      const invalidHorizontalAccuracies = [
        -1.0,
        0.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        50.1,
      ];

      for (final horizontalAccuracy in invalidHorizontalAccuracies) {
        final validation = validate(horizontalAccuracy: horizontalAccuracy);

        expect(validation.isAccepted, isFalse);
        expect(
          validation.rejectionReason,
          SpeedSampleRejectionReason.invalidHorizontalAccuracy,
        );
      }
    });

    test('rejects negative, NaN, and infinite speeds', () {
      const invalidSpeeds = [
        -1.0,
        double.nan,
        double.infinity,
        double.negativeInfinity,
      ];

      for (final speed in invalidSpeeds) {
        final validation = validate(speed: speed);

        expect(validation.isAccepted, isFalse);
        expect(
          validation.rejectionReason,
          SpeedSampleRejectionReason.invalidSpeed,
        );
      }
    });

    test('accepts plausible speed changes between accepted samples', () {
      final previousSample = acceptedSample(
        speed: 10,
        timestamp: now.subtract(const Duration(seconds: 1)),
      );

      final validation = validate(
        speed: 17,
        previousAcceptedSample: previousSample,
      );

      expect(validation.isAccepted, isTrue);
      expect(validation.rejectionReason, isNull);
    });

    test('rejects a large one-sample speed spike', () {
      final previousSample = acceptedSample(
        speed: 10,
        timestamp: now.subtract(const Duration(seconds: 1)),
      );

      final validation = validate(
        speed: 30,
        previousAcceptedSample: previousSample,
      );

      expect(validation.isAccepted, isFalse);
      expect(
        validation.rejectionReason,
        SpeedSampleRejectionReason.implausibleAcceleration,
      );
    });

    test(
      'accepts first valid stream sample when no previous valid sample exists',
      () {
        final validation = validate(speed: 80);

        expect(validation.isAccepted, isTrue);
        expect(validation.rejectionReason, isNull);
      },
    );
  });

  group('SpeedTracker.stream freshness watchdog', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('valid accepted stream sample emits current speed', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness.addPosition(_position(speed: 10, timestamp: now));
      await pumpEventQueue();

      expect(harness.emittedSpeeds, hasLength(1));
      expect(harness.emittedSpeeds.single.status, SpeedStatus.current);
      expect(harness.emittedSpeeds.single.value, 10);
    });

    test('emits unavailable when the accepted sample becomes stale', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness.addPosition(
        _position(
          speed: 10,
          timestamp: now.subtract(SpeedTracker.maxSampleAge),
        ),
      );
      await pumpEventQueue();

      expect(harness.emittedSpeeds.map((speed) => speed.status), [
        SpeedStatus.current,
        SpeedStatus.unavailable,
      ]);
      expect(harness.emittedSpeeds.last.accuracy, 0);
    });

    test('rejected samples do not postpone the stale timeout', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness
        ..addPosition(
          _position(
            speed: 10,
            timestamp: now.subtract(SpeedTracker.maxSampleAge),
          ),
        )
        ..addPosition(_position(speed: 200, timestamp: now));
      await pumpEventQueue();

      expect(harness.emittedSpeeds.map((speed) => speed.status), [
        SpeedStatus.current,
        SpeedStatus.unavailable,
      ]);
    });

    test('new accepted samples postpone a pending stale timeout', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness
        ..addPosition(
          _position(
            speed: 10,
            timestamp: now.subtract(SpeedTracker.maxSampleAge),
          ),
        )
        ..addPosition(
          _position(
            speed: 10.1,
            timestamp: now.subtract(const Duration(seconds: 4)),
          ),
        );
      await pumpEventQueue();

      expect(harness.emittedSpeeds.map((speed) => speed.status), [
        SpeedStatus.current,
        SpeedStatus.current,
      ]);
    });
  });
}

Position _position({
  required double speed,
  required DateTime timestamp,
  double accuracy = 5,
  double speedAccuracy = 0.5,
}) {
  return Position(
    longitude: 0,
    latitude: 0,
    timestamp: timestamp,
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: speed,
    speedAccuracy: speedAccuracy,
  );
}

class _SpeedTrackerStreamHarness {
  final DateTime now;
  final StreamController<Position> _positionController;
  final Completer<void> _positionStreamRequested = Completer<void>();
  final List<Speed> emittedSpeeds = [];
  late final SpeedTracker _speedTracker;
  StreamSubscription<Speed>? _subscription;

  _SpeedTrackerStreamHarness({required this.now})
    : _positionController = StreamController<Position>(sync: true) {
    _speedTracker = SpeedTracker(
      clock: () => now,
      permissionChecker: () async => true,
      currentPositionProvider: (_) async =>
          _position(speed: 0, timestamp: now, accuracy: 0),
      positionStreamProvider: (_) {
        if (!_positionStreamRequested.isCompleted) {
          _positionStreamRequested.complete();
        }
        return _positionController.stream;
      },
    );
  }

  Future<void> start() async {
    _subscription = _speedTracker.stream.listen(emittedSpeeds.add);
    await _positionStreamRequested.future;
  }

  void addPosition(Position position) {
    _positionController.add(position);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _positionController.close();
  }
}
