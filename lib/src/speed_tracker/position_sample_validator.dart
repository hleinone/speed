import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;

class PositionSampleValidator {
  const PositionSampleValidator();

  ValidPositionSample? validate(Position position, DateTime now) {
    if (!position.latitude.isFinite || position.latitude < -90 || position.latitude > 90) {
      return null;
    }

    if (!position.longitude.isFinite || position.longitude < -180 || position.longitude > 180) {
      return null;
    }

    if (position.timestamp.difference(now) > config.maxFutureSampleSkew) {
      return null;
    }

    if (now.difference(position.timestamp) > config.maxSampleAge) {
      return null;
    }

    if (!isKnownHorizontalAccuracy(position.accuracy) && !isUnknownHorizontalAccuracy(position.accuracy)) {
      return null;
    }

    return ValidPositionSample(
      latitude: position.latitude,
      longitude: position.longitude,
      timestamp: position.timestamp,
      horizontalAccuracy: position.accuracy,
    );
  }

  static bool isKnownHorizontalAccuracy(double horizontalAccuracy) {
    return horizontalAccuracy.isFinite &&
        horizontalAccuracy > 0 &&
        horizontalAccuracy <= config.maxAcceptedHorizontalAccuracy;
  }

  static bool isUnknownHorizontalAccuracy(double horizontalAccuracy) => horizontalAccuracy == 0;

  static double horizontalAccuracyConfidence(double horizontalAccuracy) {
    if (isUnknownHorizontalAccuracy(horizontalAccuracy)) {
      return config.unknownHorizontalAccuracyConfidence;
    }

    if (!isKnownHorizontalAccuracy(horizontalAccuracy)) {
      return 0;
    }

    return 1.0 -
        (horizontalAccuracy.clamp(0.0, config.maxAcceptedHorizontalAccuracy) / config.maxAcceptedHorizontalAccuracy);
  }
}

class ValidPositionSample {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double horizontalAccuracy;

  const ValidPositionSample({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.horizontalAccuracy,
  });

  bool get hasKnownHorizontalAccuracy => PositionSampleValidator.isKnownHorizontalAccuracy(horizontalAccuracy);
}
