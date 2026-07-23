class AcceptedSpeedSample {
  final double speed;
  final DateTime timestamp;
  final double horizontalAccuracy;
  final SpeedAccuracyEstimate speedAccuracy;
  final SpeedSampleSource source;
  final double positionConsistencyConfidence;

  const AcceptedSpeedSample({
    required this.speed,
    required this.timestamp,
    required this.horizontalAccuracy,
    required this.speedAccuracy,
    this.source = SpeedSampleSource.platform,
    this.positionConsistencyConfidence = 1.0,
  });

  AcceptedSpeedSample withPositionConsistencyConfidence(double confidence) {
    return AcceptedSpeedSample(
      speed: speed,
      timestamp: timestamp,
      horizontalAccuracy: horizontalAccuracy,
      speedAccuracy: speedAccuracy,
      source: source,
      positionConsistencyConfidence: confidence,
    );
  }
}

sealed class SpeedSampleValidation {
  const SpeedSampleValidation._();

  const factory SpeedSampleValidation.accepted(AcceptedSpeedSample sample) = SpeedSampleAccepted;

  const factory SpeedSampleValidation.rejected(SpeedSampleRejectionReason reason) = SpeedSampleRejected;
}

final class SpeedSampleAccepted extends SpeedSampleValidation {
  const SpeedSampleAccepted(this.sample) : super._();

  final AcceptedSpeedSample sample;
}

final class SpeedSampleRejected extends SpeedSampleValidation {
  const SpeedSampleRejected(this.reason) : super._();

  final SpeedSampleRejectionReason reason;
}

enum SpeedSampleRejectionReason {
  invalidSpeed,
  invalidSpeedAccuracy,
  invalidHorizontalAccuracy,
  insufficientConfidence,
  nonIncreasingTimestamp,
  implausibleAcceleration,
}

enum SpeedSampleSource { platform, positionDelta }

class SpeedAccuracyEstimate {
  final double standardDeviation;
  final double confidence;
  final bool isKnown;

  const SpeedAccuracyEstimate({required this.standardDeviation, required this.confidence, required this.isKnown});

  double get measurementNoise => standardDeviation * standardDeviation;
}

sealed class Speed {
  const Speed._();
}

final class CurrentSpeed extends Speed {
  /// Speed in meters per second.
  final double value;

  /// Accuracy of the speed measurement, ranging from 0.0 (worst) to 1.0 (best).
  final double accuracy;

  const CurrentSpeed(this.value, this.accuracy) : super._();

  double getAs(SpeedUnit unit) => value * unit._factor;
}

final class UnavailableSpeed extends Speed {
  const UnavailableSpeed() : super._();
}

enum SpeedUnit {
  kilometersPerHour(3.600000),
  milesPerHour(2.236936),
  metersPerSecond(1),
  feetPerSecond(3.280840),
  knots(1.943844);

  final double _factor;

  const SpeedUnit(this._factor);
}
