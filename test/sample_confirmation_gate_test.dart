import 'package:flutter_test/flutter_test.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/sample_confirmation_gate.dart';

void main() {
  final start = DateTime.utc(2026, 1, 1, 12);

  group('SampleConfirmationGate startup confirmation', () {
    test('emits a plausible platform change during startup warm-up', () {
      final gate = SampleConfirmationGate();
      final previousSample = _sample(speed: 10, timestamp: start);
      final candidate = _sample(speed: 16, timestamp: start.add(const Duration(seconds: 1)));

      expect(_shouldEmit(gate, candidate, previousSample: previousSample), isTrue);
    });

    test('emits the second matching implausible startup jump', () {
      final gate = SampleConfirmationGate();
      final previousSample = _sample(speed: 0, timestamp: start);
      final firstJump = _sample(speed: 30, timestamp: start.add(const Duration(seconds: 1)));
      final matchingJump = _sample(speed: 30.5, timestamp: start.add(const Duration(seconds: 2)));

      expect(_shouldEmit(gate, firstJump, previousSample: previousSample), isFalse);
      expect(_shouldEmit(gate, matchingJump, previousSample: previousSample), isTrue);
    });

    test('replaces a non-matching pending startup jump', () {
      final gate = SampleConfirmationGate();
      final previousSample = _sample(speed: 0, timestamp: start);
      final firstJump = _sample(speed: 30, timestamp: start.add(const Duration(seconds: 1)));
      final differentJump = _sample(speed: 50, timestamp: start.add(const Duration(seconds: 2)));
      final matchingReplacement = _sample(speed: 50.5, timestamp: start.add(const Duration(seconds: 3)));

      expect(_shouldEmit(gate, firstJump, previousSample: previousSample), isFalse);
      expect(_shouldEmit(gate, differentJump, previousSample: previousSample), isFalse);
      expect(_shouldEmit(gate, matchingReplacement, previousSample: previousSample), isTrue);
    });

    test('emits an implausible platform change after startup warm-up', () {
      final gate = SampleConfirmationGate();
      final previousSample = _sample(speed: 0, timestamp: start);
      final candidate = _sample(speed: 50, timestamp: start.add(const Duration(seconds: 1)));

      expect(_shouldEmit(gate, candidate, previousSample: previousSample, isStartupWarmup: false), isTrue);
    });

    test('reset discards a pending startup jump', () {
      final gate = SampleConfirmationGate();
      final previousSample = _sample(speed: 0, timestamp: start);
      final firstJump = _sample(speed: 30, timestamp: start.add(const Duration(seconds: 1)));
      final matchingJump = _sample(speed: 30.5, timestamp: start.add(const Duration(seconds: 2)));

      expect(_shouldEmit(gate, firstJump, previousSample: previousSample), isFalse);
      gate.reset();

      expect(_shouldEmit(gate, matchingJump, previousSample: previousSample), isFalse);
    });
  });

  group('SampleConfirmationGate fallback confirmation', () {
    test('emits the second matching initial fallback', () {
      final gate = SampleConfirmationGate();
      final firstFallback = _sample(speed: 4, timestamp: start, source: SpeedSampleSource.positionDelta);
      final matchingFallback = _sample(
        speed: 4.5,
        timestamp: start.add(const Duration(seconds: 1)),
        source: SpeedSampleSource.positionDelta,
      );

      expect(_shouldEmit(gate, firstFallback), isFalse);
      expect(_shouldEmit(gate, matchingFallback), isTrue);
    });

    test('replaces a non-matching pending fallback', () {
      final gate = SampleConfirmationGate();
      final firstFallback = _sample(speed: 4, timestamp: start, source: SpeedSampleSource.positionDelta);
      final differentFallback = _sample(
        speed: 8,
        timestamp: start.add(const Duration(seconds: 1)),
        source: SpeedSampleSource.positionDelta,
      );
      final matchingReplacement = _sample(
        speed: 8.5,
        timestamp: start.add(const Duration(seconds: 2)),
        source: SpeedSampleSource.positionDelta,
      );

      expect(_shouldEmit(gate, firstFallback), isFalse);
      expect(_shouldEmit(gate, differentFallback), isFalse);
      expect(_shouldEmit(gate, matchingReplacement), isTrue);
    });

    test('emits a zero initial fallback immediately', () {
      final gate = SampleConfirmationGate();
      final candidate = _sample(speed: 0, timestamp: start, source: SpeedSampleSource.positionDelta);

      expect(_shouldEmit(gate, candidate), isTrue);
    });

    test('emits a fallback immediately when a previous sample exists', () {
      final gate = SampleConfirmationGate();
      final previousSample = _sample(speed: 3, timestamp: start);
      final candidate = _sample(
        speed: 4,
        timestamp: start.add(const Duration(seconds: 1)),
        source: SpeedSampleSource.positionDelta,
      );

      expect(_shouldEmit(gate, candidate, previousSample: previousSample), isTrue);
    });

    test('reset discards a pending fallback', () {
      final gate = SampleConfirmationGate();
      final firstFallback = _sample(speed: 4, timestamp: start, source: SpeedSampleSource.positionDelta);
      final matchingFallback = _sample(
        speed: 4.5,
        timestamp: start.add(const Duration(seconds: 1)),
        source: SpeedSampleSource.positionDelta,
      );

      expect(_shouldEmit(gate, firstFallback), isFalse);
      gate.reset();

      expect(_shouldEmit(gate, matchingFallback), isFalse);
    });
  });
}

bool _shouldEmit(
  SampleConfirmationGate gate,
  AcceptedSpeedSample candidate, {
  AcceptedSpeedSample? previousSample,
  bool isStartupWarmup = true,
}) {
  return gate.shouldEmit(
    candidate: candidate,
    previousAcceptedSample: previousSample,
    isStartupWarmup: isStartupWarmup,
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
