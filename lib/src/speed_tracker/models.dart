import 'package:flutter/widgets.dart';
import 'package:speed/src/generated/l10n/l10n.dart';

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
  staleTimestamp,
  futureTimestamp,
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

enum SpeedStatus { current, unavailable }

class Speed {
  /// Speed in meters per second
  final double? value;

  /// Accuracy of the speed measurement, ranging from 0.0 (worst) to 1.0 (best)
  final double accuracy;

  final SpeedStatus status;

  const Speed.current(double this.value, this.accuracy) : status = SpeedStatus.current;

  const Speed.unavailable() : value = null, accuracy = 0, status = SpeedStatus.unavailable;

  bool get isCurrent => status == SpeedStatus.current;

  double getAs(SpeedUnit unit, [int precision = 1]) {
    final currentValue = value;
    if (currentValue == null) {
      throw StateError('Speed is unavailable');
    }
    return double.parse((currentValue * unit._factor).toStringAsFixed(precision));
  }
}

enum SpeedUnit {
  kilometersPerHour(3.600000),
  milesPerHour(2.236936),
  metersPerSecond(1),
  footPerSecond(3.280840),
  knots(1.943844);

  final double _factor;

  const SpeedUnit(this._factor);

  String title(BuildContext context) {
    switch (this) {
      case SpeedUnit.kilometersPerHour:
        return L10n.of(context).kilometersPerHour;
      case SpeedUnit.milesPerHour:
        return L10n.of(context).milesPerHour;
      case SpeedUnit.metersPerSecond:
        return L10n.of(context).metersPerSecond;
      case SpeedUnit.footPerSecond:
        return L10n.of(context).footPerSecond;
      case SpeedUnit.knots:
        return L10n.of(context).knots;
    }
  }
}
