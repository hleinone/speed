import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter/foundation.dart';
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
      bool enforceAccelerationLimit = true,
    }) {
      return SpeedTracker.validateSpeedSample(
        speed: speed,
        timestamp: timestamp ?? now,
        horizontalAccuracy: horizontalAccuracy,
        speedAccuracy: speedAccuracy,
        now: now,
        previousAcceptedSample: previousAcceptedSample,
        enforceAccelerationLimit: enforceAccelerationLimit,
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
      'accepts a large one-sample speed spike when acceleration limit is disabled',
      () {
        final previousSample = acceptedSample(
          speed: 10,
          timestamp: now.subtract(const Duration(seconds: 1)),
        );

        final validation = validate(
          speed: 30,
          previousAcceptedSample: previousSample,
          enforceAccelerationLimit: false,
        );

        expect(validation.isAccepted, isTrue);
        expect(validation.rejectionReason, isNull);
        expect(validation.acceptedSample?.speed, 30);
      },
    );

    test(
      'accepts first valid stream sample when no previous valid sample exists',
      () {
        final validation = validate(speed: 80);

        expect(validation.isAccepted, isTrue);
        expect(validation.rejectionReason, isNull);
      },
    );
  });

  group('SpeedTracker.createLocationSettings', () {
    test(
      'requests one-second Android position updates without a stream time limit',
      () {
        final locationSettings = SpeedTracker.createLocationSettings(
          TargetPlatform.android,
        );

        expect(locationSettings, isA<AndroidSettings>());
        final androidSettings = locationSettings as AndroidSettings;
        expect(androidSettings.accuracy, LocationAccuracy.bestForNavigation);
        expect(androidSettings.distanceFilter, 0);
        expect(
          androidSettings.intervalDuration,
          SpeedTracker.positionUpdateInterval,
        );
        expect(androidSettings.timeLimit, isNull);
      },
    );
  });

  group('SpeedTracker.stream position-delta fallback', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test(
      'stores the first ambiguous zero sample without emitting speed',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        harness.addPosition(
          _position(
            speed: 0,
            speedAccuracy: 0,
            timestamp: now.subtract(const Duration(seconds: 1)),
          ),
        );
        await pumpEventQueue();

        expect(harness.emittedSpeeds, isEmpty);
      },
    );

    test(
      'uses regression fallback for stable ambiguous zero movement',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        for (var i = 0; i < 4; i++) {
          harness.addPosition(
            _eastwardPosition(
              metersEast: 4.0 * i,
              speed: 0,
              speedAccuracy: 0,
              timestamp: now.subtract(Duration(seconds: 4 - i)),
            ),
          );
        }
        await pumpEventQueue();

        expect(harness.emittedSpeeds, isEmpty);

        harness.addPosition(
          _eastwardPosition(
            metersEast: 16,
            speed: 0,
            speedAccuracy: 0,
            timestamp: now,
          ),
        );
        await pumpEventQueue();

        expect(harness.emittedSpeeds, hasLength(1));
        expect(harness.emittedSpeeds.single.value, closeTo(4, 0.1));
        expect(
          harness.emittedSpeeds.single.accuracy,
          closeTo(SpeedTracker.fallbackSpeedConfidence * 0.9, 0.000001),
        );
        expect(
          harness.emittedSpeeds.single.accuracy,
          lessThan(SpeedTracker.unknownSpeedConfidence),
        );
      },
    );

    test(
      'does not clamp stable low fallback movement inside GPS accuracy to zero',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        for (var i = 0; i < 4; i++) {
          harness.addPosition(
            _eastwardPosition(
              metersEast: 3.0 * i,
              speed: 0,
              speedAccuracy: 0,
              timestamp: now.subtract(Duration(seconds: 4 - i)),
            ),
          );
        }
        await pumpEventQueue();

        expect(harness.emittedSpeeds, isEmpty);

        harness.addPosition(
          _eastwardPosition(
            metersEast: 12,
            speed: 0,
            speedAccuracy: 0,
            timestamp: now,
          ),
        );
        await pumpEventQueue();

        expect(harness.emittedSpeeds, hasLength(1));
        expect(harness.emittedSpeeds.single.value, closeTo(3, 0.1));
      },
    );

    test(
      'uses zero fallback speed for a stationary regression window',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        for (var i = 0; i < 4; i++) {
          harness.addPosition(
            _position(
              speed: 0,
              speedAccuracy: 0,
              timestamp: now.subtract(Duration(seconds: 3 - i)),
            ),
          );
        }
        await pumpEventQueue();

        expect(harness.emittedSpeeds, hasLength(1));
        expect(harness.emittedSpeeds.single.value, 0);
        expect(
          harness.emittedSpeeds.single.accuracy,
          closeTo(SpeedTracker.fallbackSpeedConfidence * 0.9, 0.000001),
        );
      },
    );

    test(
      'uses zero fallback speed below the stationary speed epsilon',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        for (var i = 0; i < 4; i++) {
          harness.addPosition(
            _eastwardPosition(
              metersEast: 0.1 * i,
              speed: 0,
              speedAccuracy: 0,
              timestamp: now.subtract(Duration(seconds: 3 - i)),
            ),
          );
        }
        await pumpEventQueue();

        expect(harness.emittedSpeeds, hasLength(1));
        expect(harness.emittedSpeeds.single.value, 0);
      },
    );

    test('withholds fallback speed for stationary GPS jitter', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      const offsets = [0.0, 4.0, -4.0, 3.0, -3.0];

      await harness.start();
      for (var i = 0; i < offsets.length; i++) {
        harness.addPosition(
          _eastwardPosition(
            metersEast: offsets[i],
            speed: 0,
            speedAccuracy: 0,
            timestamp: now.subtract(Duration(seconds: offsets.length - 1 - i)),
          ),
        );
      }
      await pumpEventQueue();

      expect(harness.emittedSpeeds, isEmpty);
    });

    test(
      'withholds fallback speed for a bad GPS jump before any accepted speed',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        const offsets = [0.0, 2.0, 100.0, 6.0, 8.0];

        await harness.start();
        for (var i = 0; i < offsets.length; i++) {
          harness.addPosition(
            _eastwardPosition(
              metersEast: offsets[i],
              speed: 0,
              speedAccuracy: 0,
              timestamp: now.subtract(
                Duration(seconds: offsets.length - 1 - i),
              ),
            ),
          );
        }
        await pumpEventQueue();

        expect(harness.emittedSpeeds, isEmpty);
      },
    );

    test('recovers fallback speed after a bad GPS jump ages out', () async {
      var currentNow = now;
      final harness = _SpeedTrackerStreamHarness(
        now: now,
        clock: () => currentNow,
      );
      addTearDown(harness.dispose);

      const badOffsets = [0.0, 2.0, 100.0, 6.0, 8.0];

      await harness.start();
      for (var i = 0; i < badOffsets.length; i++) {
        currentNow = now.add(Duration(seconds: i));
        harness.addPosition(
          _eastwardPosition(
            metersEast: badOffsets[i],
            speed: 0,
            speedAccuracy: 0,
            timestamp: currentNow,
          ),
        );
      }
      await pumpEventQueue();

      expect(harness.emittedSpeeds, isEmpty);

      for (var i = 0; i < 6; i++) {
        currentNow = now.add(Duration(seconds: 6 + i));
        harness.addPosition(
          _eastwardPosition(
            metersEast: 2.0 * i,
            speed: 0,
            speedAccuracy: 0,
            timestamp: currentNow,
          ),
        );
      }
      await pumpEventQueue();

      expect(harness.emittedSpeeds, hasLength(1));
      expect(harness.emittedSpeeds.single.value, closeTo(2, 0.1));
    });

    test('trusts platform zero speed when speed accuracy is known', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness.addPosition(
        _position(speed: 0, speedAccuracy: 0.5, timestamp: now),
      );
      await pumpEventQueue();

      expect(harness.emittedSpeeds, hasLength(1));
      expect(harness.emittedSpeeds.single.value, 0);
      expect(
        harness.emittedSpeeds.single.accuracy,
        greaterThan(SpeedTracker.fallbackSpeedConfidence),
      );
    });

    test('emits a platform first sample immediately', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness.addPosition(
        _position(speed: 8, speedAccuracy: 0.5, timestamp: now),
      );
      await pumpEventQueue();

      expect(harness.emittedSpeeds, hasLength(1));
      expect(harness.emittedSpeeds.single.value, 8);
    });

    test(
      'trusts non-zero platform speed even when speed accuracy is unknown',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        harness
          ..addPosition(
            _position(
              speed: 0,
              speedAccuracy: 0,
              timestamp: now.subtract(const Duration(seconds: 1)),
            ),
          )
          ..addPosition(
            _position(
              longitude: 0.0001,
              speed: 8,
              speedAccuracy: 0,
              timestamp: now,
            ),
          );
        await pumpEventQueue();

        expect(harness.emittedSpeeds, hasLength(1));
        expect(harness.emittedSpeeds.single.value, 8);
      },
    );

    test('does not fallback for non-increasing position timestamps', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness
        ..addPosition(_position(speed: 0, speedAccuracy: 0, timestamp: now))
        ..addPosition(
          _position(
            longitude: 0.0001,
            speed: 0,
            speedAccuracy: 0,
            timestamp: now,
          ),
        );
      await pumpEventQueue();

      expect(harness.emittedSpeeds, isEmpty);
    });

    test('does not fallback before the minimum sample count', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      for (var i = 0; i < 3; i++) {
        harness.addPosition(
          _eastwardPosition(
            metersEast: 4.0 * i,
            speed: 0,
            speedAccuracy: 0,
            timestamp: now.subtract(Duration(seconds: 3 - i)),
          ),
        );
      }
      await pumpEventQueue();

      expect(harness.emittedSpeeds, isEmpty);
    });

    test('does not fallback before the minimum regression span', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      final offsets = [
        const Duration(seconds: 2),
        const Duration(milliseconds: 1500),
        const Duration(seconds: 1),
        Duration.zero,
      ];
      for (var i = 0; i < offsets.length; i++) {
        harness.addPosition(
          _eastwardPosition(
            metersEast: 4.0 * i,
            speed: 0,
            speedAccuracy: 0,
            timestamp: now.subtract(offsets[i]),
          ),
        );
      }
      await pumpEventQueue();

      expect(harness.emittedSpeeds, isEmpty);
    });

    test(
      'does not fallback when elapsed time exceeds freshness timeout',
      () async {
        var currentNow = now;
        final harness = _SpeedTrackerStreamHarness(
          now: now,
          clock: () => currentNow,
        );
        addTearDown(harness.dispose);

        await harness.start();
        harness.addPosition(
          _position(speed: 0, speedAccuracy: 0, timestamp: now),
        );
        await pumpEventQueue();

        currentNow = now.add(
          SpeedTracker.freshnessTimeout + const Duration(seconds: 1),
        );
        harness.addPosition(
          _position(
            longitude: 0.0001,
            speed: 0,
            speedAccuracy: 0,
            timestamp: currentNow,
          ),
        );
        await pumpEventQueue();

        expect(harness.emittedSpeeds, isEmpty);
      },
    );

    test('prunes samples older than the fallback regression window', () async {
      var currentNow = now;
      final harness = _SpeedTrackerStreamHarness(
        now: now,
        clock: () => currentNow,
      );
      addTearDown(harness.dispose);

      await harness.start();
      harness.addPosition(
        _eastwardPosition(
          metersEast: 1000,
          speed: 0,
          speedAccuracy: 0,
          timestamp: currentNow,
        ),
      );

      for (var i = 0; i < 5; i++) {
        currentNow = now.add(Duration(seconds: 6 + i));
        harness.addPosition(
          _eastwardPosition(
            metersEast: 2.0 * i,
            speed: 0,
            speedAccuracy: 0,
            timestamp: currentNow,
          ),
        );
      }
      await pumpEventQueue();

      expect(harness.emittedSpeeds, hasLength(1));
      expect(harness.emittedSpeeds.single.value, closeTo(2, 0.1));
    });

    test(
      'withholds an implausible fallback outlier in the regression window',
      () async {
        var currentNow = now;
        final harness = _SpeedTrackerStreamHarness(
          now: now,
          clock: () => currentNow,
        );
        addTearDown(harness.dispose);

        await harness.start();
        for (var i = 0; i < 3; i++) {
          currentNow = now.add(Duration(seconds: i));
          harness.addPosition(
            _eastwardPosition(
              metersEast: 2.0 * i,
              speed: 2,
              speedAccuracy: 0.5,
              timestamp: currentNow,
            ),
          );
        }

        currentNow = now.add(const Duration(seconds: 3));
        harness.addPosition(
          _eastwardPosition(
            metersEast: 1000,
            speed: 0,
            speedAccuracy: 0,
            timestamp: currentNow,
          ),
        );

        currentNow = now.add(const Duration(seconds: 4));
        harness.addPosition(
          _eastwardPosition(
            metersEast: 8,
            speed: 0,
            speedAccuracy: 0,
            timestamp: currentNow,
          ),
        );
        await pumpEventQueue();

        expect(harness.emittedSpeeds, hasLength(3));
        expect(
          harness.emittedSpeeds.where((speed) => (speed.value ?? 0) > 20),
          isEmpty,
        );
        expect(harness.emittedSpeeds.last.value, closeTo(2, 0.1));
      },
    );
  });

  group('SpeedTracker.stream freshness watchdog', () {
    final now = DateTime.utc(2026, 1, 1, 12);

    test('starts from the position stream and emits a current speed', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness.addPosition(_position(speed: 10, timestamp: now));
      await pumpEventQueue();

      expect(harness.emittedSpeeds, hasLength(1));
      expect(harness.emittedSpeeds.single.status, SpeedStatus.current);
      expect(harness.emittedSpeeds.single.value, 10);
    });

    test(
      'emits startup speed jumps during warm-up instead of rejecting them',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        harness
          ..addPosition(
            _position(
              speed: 0,
              timestamp: now.subtract(const Duration(seconds: 2)),
            ),
          )
          ..addPosition(
            _position(
              speed: 30,
              timestamp: now.subtract(const Duration(seconds: 1)),
            ),
          );
        await pumpEventQueue();

        expect(harness.emittedSpeeds.map((speed) => speed.value), [0, 30]);
      },
    );

    test(
      'warm-up samples use raw speed instead of Kalman-smoothed speed',
      () async {
        final harness = _SpeedTrackerStreamHarness(now: now);
        addTearDown(harness.dispose);

        await harness.start();
        harness
          ..addPosition(
            _position(
              speed: 0,
              timestamp: now.subtract(const Duration(seconds: 2)),
            ),
          )
          ..addPosition(
            _position(
              speed: 30,
              timestamp: now.subtract(const Duration(seconds: 1)),
            ),
          );
        await pumpEventQueue();

        expect(harness.emittedSpeeds.last.value, 30);
      },
    );

    test('re-enables acceleration rejection after warm-up samples', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness
        ..addPosition(
          _position(
            speed: 0,
            timestamp: now.subtract(const Duration(seconds: 3)),
          ),
        )
        ..addPosition(
          _position(
            speed: 30,
            timestamp: now.subtract(const Duration(seconds: 2)),
          ),
        )
        ..addPosition(
          _position(
            speed: 30.5,
            timestamp: now.subtract(const Duration(seconds: 1)),
          ),
        )
        ..addPosition(_position(speed: 100, timestamp: now));
      await pumpEventQueue();

      expect(harness.emittedSpeeds.map((speed) => speed.value), [0, 30, 30.5]);
    });

    test('keeps basic validation active during warm-up', () async {
      final harness = _SpeedTrackerStreamHarness(now: now);
      addTearDown(harness.dispose);

      await harness.start();
      harness
        ..addPosition(_position(speed: -1, timestamp: now))
        ..addPosition(
          _position(
            speed: 10,
            timestamp: now.subtract(const Duration(seconds: 6)),
          ),
        )
        ..addPosition(
          _position(speed: 10, timestamp: now.add(const Duration(seconds: 2))),
        )
        ..addPosition(_position(speed: 10, timestamp: now, accuracy: 50.1))
        ..addPosition(_position(speed: 10, timestamp: now))
        ..addPosition(_position(speed: 12, timestamp: now));
      await pumpEventQueue();

      expect(harness.emittedSpeeds.map((speed) => speed.value), [10]);
    });

    test('does not emit unavailable before the freshness timeout', () {
      fakeAsync((async) {
        final harness = _SpeedTrackerStreamHarness(
          now: now,
          clock: async.getClock(now).now,
        );

        harness.startListening();
        async.flushMicrotasks();
        harness.addPosition(_position(speed: 10, timestamp: now));
        async.flushMicrotasks();

        async.elapse(
          SpeedTracker.freshnessTimeout - const Duration(milliseconds: 1),
        );
        async.flushMicrotasks();

        unawaited(harness.dispose());
        async.flushMicrotasks();

        expect(harness.emittedSpeeds.map((speed) => speed.status), [
          SpeedStatus.current,
        ]);
      });
    });

    test('emits unavailable when the freshness timeout elapses', () {
      fakeAsync((async) {
        final harness = _SpeedTrackerStreamHarness(
          now: now,
          clock: async.getClock(now).now,
        );

        harness.startListening();
        async.flushMicrotasks();
        harness.addPosition(_position(speed: 10, timestamp: now));
        async.flushMicrotasks();

        async.elapse(SpeedTracker.freshnessTimeout);
        async.flushMicrotasks();

        unawaited(harness.dispose());
        async.flushMicrotasks();

        expect(harness.emittedSpeeds.map((speed) => speed.status), [
          SpeedStatus.current,
          SpeedStatus.unavailable,
        ]);
        expect(harness.emittedSpeeds.last.accuracy, 0);
      });
    });

    test('rejected samples do not postpone the freshness timeout', () {
      fakeAsync((async) {
        final harness = _SpeedTrackerStreamHarness(
          now: now,
          clock: async.getClock(now).now,
        );

        harness.startListening();
        async.flushMicrotasks();
        harness.addPosition(_position(speed: 10, timestamp: now));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));
        harness.addPosition(
          _position(
            speed: 10,
            timestamp: now.add(const Duration(seconds: 5)),
            accuracy: 50.1,
          ),
        );
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));
        async.flushMicrotasks();

        unawaited(harness.dispose());
        async.flushMicrotasks();

        expect(harness.emittedSpeeds.map((speed) => speed.status), [
          SpeedStatus.current,
          SpeedStatus.unavailable,
        ]);
      });
    });

    test('new accepted samples postpone a pending freshness timeout', () {
      fakeAsync((async) {
        final harness = _SpeedTrackerStreamHarness(
          now: now,
          clock: async.getClock(now).now,
        );

        harness.startListening();
        async.flushMicrotasks();
        harness.addPosition(_position(speed: 10, timestamp: now));
        async.flushMicrotasks();

        async.elapse(const Duration(seconds: 5));
        harness.addPosition(
          _position(
            speed: 10.1,
            timestamp: now.add(const Duration(seconds: 5)),
          ),
        );
        async.flushMicrotasks();

        async.elapse(
          SpeedTracker.freshnessTimeout - const Duration(milliseconds: 1),
        );
        async.flushMicrotasks();

        expect(harness.emittedSpeeds.map((speed) => speed.status), [
          SpeedStatus.current,
          SpeedStatus.current,
        ]);

        async.elapse(const Duration(milliseconds: 1));
        async.flushMicrotasks();

        unawaited(harness.dispose());
        async.flushMicrotasks();

        expect(harness.emittedSpeeds.map((speed) => speed.status), [
          SpeedStatus.current,
          SpeedStatus.current,
          SpeedStatus.unavailable,
        ]);
      });
    });
  });
}

const _metersPerLongitudeDegreeAtEquator = 111319.49079327358;

Position _eastwardPosition({
  required double metersEast,
  required double speed,
  required DateTime timestamp,
  double accuracy = 5,
  double speedAccuracy = 0.5,
}) {
  return _position(
    longitude: metersEast / _metersPerLongitudeDegreeAtEquator,
    speed: speed,
    timestamp: timestamp,
    accuracy: accuracy,
    speedAccuracy: speedAccuracy,
  );
}

Position _position({
  double latitude = 0,
  double longitude = 0,
  required double speed,
  required DateTime timestamp,
  double accuracy = 5,
  double speedAccuracy = 0.5,
}) {
  return Position(
    longitude: longitude,
    latitude: latitude,
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
  final SpeedTrackerClock _clock;
  final StreamController<Position> _positionController;
  final Completer<void> _positionStreamRequested = Completer<void>();
  final List<Speed> emittedSpeeds = [];
  late final SpeedTracker _speedTracker;
  StreamSubscription<Speed>? _subscription;

  _SpeedTrackerStreamHarness({required DateTime now, SpeedTrackerClock? clock})
    : _clock = clock ?? (() => now),
      _positionController = StreamController<Position>(sync: true) {
    _speedTracker = SpeedTracker(
      clock: _clock,
      permissionChecker: () async => true,
      positionStreamProvider: (_) {
        if (!_positionStreamRequested.isCompleted) {
          _positionStreamRequested.complete();
        }
        return _positionController.stream;
      },
    );
  }

  Future<void> start() async {
    startListening();
    await _positionStreamRequested.future;
  }

  void startListening() {
    _subscription = _speedTracker.stream.listen(emittedSpeeds.add);
  }

  void addPosition(Position position) {
    _positionController.add(position);
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
    await _positionController.close();
  }
}
