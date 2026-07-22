import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/platform_position_reconciler.dart';
import 'package:speed/src/speed_tracker/position_delta_speed_estimator.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';

void main() {
  final timestamp = DateTime.utc(2026, 1, 1, 12);

  group('PlatformPositionReconciler', () {
    test('keeps a platform candidate when no position estimate exists', () {
      final reconciler = PlatformPositionReconciler();
      final candidate = _sample(speed: 10, timestamp: timestamp);

      final result = _reconcile(reconciler, candidate: candidate);

      expect(result.sample, same(candidate));
      expect(result.resetFilter, isFalse);
    });

    test('keeps a platform candidate when it agrees with the position estimate', () {
      final reconciler = PlatformPositionReconciler();
      final candidate = _sample(speed: 10, timestamp: timestamp);

      final result = _reconcile(reconciler, candidate: candidate, positionSpeed: 10);

      expect(result.sample, same(candidate));
      expect(result.resetFilter, isFalse);
    });

    test('penalizes the first conflicting platform candidate', () {
      final reconciler = PlatformPositionReconciler();
      final candidate = _sample(speed: 10, timestamp: timestamp);

      final result = _reconcile(reconciler, candidate: candidate, positionSpeed: 0);

      expect(result.sample.source, SpeedSampleSource.platform);
      expect(result.sample.speed, 10);
      expect(result.sample.positionConsistencyConfidence, lessThan(1));
      expect(result.resetFilter, isFalse);
    });

    test('promotes a validated fallback after a repeated conflict', () {
      final reconciler = PlatformPositionReconciler();
      final candidate = _sample(speed: 10, timestamp: timestamp);

      _reconcile(reconciler, candidate: candidate, positionSpeed: 0);
      final result = _reconcile(reconciler, candidate: candidate, positionSpeed: 0);

      expect(result.sample.source, SpeedSampleSource.positionDelta);
      expect(result.sample.speed, 0);
      expect(result.resetFilter, isTrue);
    });

    test('keeps the penalized platform candidate when fallback validation fails', () {
      final reconciler = PlatformPositionReconciler();
      final candidate = _sample(speed: 10, timestamp: timestamp);
      final previousSample = _sample(speed: 10, timestamp: timestamp);

      _reconcile(reconciler, candidate: candidate, positionSpeed: 0);
      final result = _reconcile(
        reconciler,
        candidate: candidate,
        positionSpeed: 0,
        previousAcceptedSample: previousSample,
      );

      expect(result.sample.source, SpeedSampleSource.platform);
      expect(result.sample.positionConsistencyConfidence, lessThan(1));
      expect(result.resetFilter, isFalse);
    });

    test('agreement resets the consecutive conflict count', () {
      final reconciler = PlatformPositionReconciler();
      final candidate = _sample(speed: 10, timestamp: timestamp);

      _reconcile(reconciler, candidate: candidate, positionSpeed: 0);
      _reconcile(reconciler, candidate: candidate, positionSpeed: 10);
      final result = _reconcile(reconciler, candidate: candidate, positionSpeed: 0);

      expect(result.sample.source, SpeedSampleSource.platform);
      expect(result.resetFilter, isFalse);
    });

    test('a position-delta candidate resets the consecutive conflict count', () {
      final reconciler = PlatformPositionReconciler();
      final platformCandidate = _sample(speed: 10, timestamp: timestamp);
      final fallbackCandidate = _sample(speed: 4, timestamp: timestamp, source: SpeedSampleSource.positionDelta);

      _reconcile(reconciler, candidate: platformCandidate, positionSpeed: 0);
      final fallbackResult = _reconcile(reconciler, candidate: fallbackCandidate, positionSpeed: 0);
      final nextConflict = _reconcile(reconciler, candidate: platformCandidate, positionSpeed: 0);

      expect(fallbackResult.sample, same(fallbackCandidate));
      expect(nextConflict.sample.source, SpeedSampleSource.platform);
      expect(nextConflict.resetFilter, isFalse);
    });

    test('a missing estimate resets the consecutive conflict count', () {
      final reconciler = PlatformPositionReconciler();
      final candidate = _sample(speed: 10, timestamp: timestamp);

      _reconcile(reconciler, candidate: candidate, positionSpeed: 0);
      _reconcile(reconciler, candidate: candidate);
      final result = _reconcile(reconciler, candidate: candidate, positionSpeed: 0);

      expect(result.sample.source, SpeedSampleSource.platform);
      expect(result.resetFilter, isFalse);
    });
  });
}

ReconciledSpeedSample _reconcile(
  PlatformPositionReconciler reconciler, {
  required AcceptedSpeedSample candidate,
  double? positionSpeed,
  AcceptedSpeedSample? previousAcceptedSample,
}) {
  return reconciler.reconcile(
    candidate: candidate,
    positionSample: _positionSample(candidate),
    positionEstimate: positionSpeed == null
        ? null
        : FallbackSpeedEstimate(
            speed: positionSpeed,
            speedAccuracy: const SpeedAccuracyEstimate(standardDeviation: 2, confidence: 0.125, isKnown: false),
          ),
    previousAcceptedSample: previousAcceptedSample,
    enforceAccelerationLimit: true,
  );
}

ValidPositionSample _positionSample(AcceptedSpeedSample sample) {
  return ValidPositionSample(
    latitude: 0,
    longitude: 0,
    timestamp: sample.timestamp,
    horizontalAccuracy: sample.horizontalAccuracy,
    receivedAt: sample.timestamp,
  );
}

AcceptedSpeedSample _sample({
  required double speed,
  required DateTime timestamp,
  SpeedSampleSource source = SpeedSampleSource.platform,
}) {
  return AcceptedSpeedSample(
    speed: speed,
    timestamp: timestamp,
    horizontalAccuracy: 5,
    speedAccuracy: const SpeedAccuracyEstimate(standardDeviation: 0.5, confidence: 0.9, isKnown: true),
    source: source,
  );
}
