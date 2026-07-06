import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/util/kalman_filter.dart';

class SpeedTracker {
  static const double fallbackSpeedAccuracy = 2.0;
  static const double unknownSpeedConfidence = 0.25;
  static const double maxSpeedAccuracyError = 5.0;
  static const double maxHorizontalAccuracyError = 50.0;

  /// Process noise for the Kalman filter. A lower value means more smoothing but less responsiveness.
  final double processNoise;

  SpeedTracker({this.processNoise = 0.1});

  Stream<Speed> get stream async* {
    late final StreamController<Speed> controller;
    StreamSubscription<Position>? positionStreamSubscription;

    /// The Kalman filter instance for smoothing speed.
    late final KalmanFilter kalmanFilter;

    final LocationSettings locationSettings;

    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    } else if (Platform.isIOS || Platform.isMacOS) {
      locationSettings = AppleSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    } else {
      locationSettings = const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    }

    final hasPermission = await _checkPermissions();
    if (!hasPermission) {
      yield* Stream.error('Location permission denied');
      return;
    }

    final initialPosition = await Geolocator.getCurrentPosition(locationSettings: locationSettings);
    final initialSpeedAccuracy = normalizeSpeedAccuracy(initialPosition.speedAccuracy);
    // Initialize the filter with the first measurement.
    kalmanFilter = KalmanFilter(
      initialMeasurement: initialPosition.speed, // Initial state is the first measured speed.
      initialMeasurementNoise: initialSpeedAccuracy.measurementNoise,
      processNoise: processNoise,
    );

    void onListen() {
      positionStreamSubscription = Geolocator.getPositionStream(locationSettings: locationSettings).listen(
        (position) {
          final rawSpeed = position.speed;
          double filteredSpeed;

          final speedAccuracy = normalizeSpeedAccuracy(position.speedAccuracy);

          // Update the filter with the new measurement.
          filteredSpeed = kalmanFilter.update(rawSpeed, speedAccuracy.measurementNoise);

          // Use the same combined accuracy logic as before.
          final double speedConfidence = speedAccuracy.confidence;
          final double positionConfidence =
              1.0 - (min(position.accuracy, maxHorizontalAccuracyError) / maxHorizontalAccuracyError);
          final double finalAccuracy = speedConfidence * positionConfidence;

          if (!controller.isClosed) {
            controller.add(
              Speed(
                filteredSpeed.isNegative ? 0 : filteredSpeed, // Ensure speed is not negative
                finalAccuracy.clamp(0.0, 1.0),
              ),
            );
          }
        },
        onError: (error) {
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
      );
    }

    void onCancel() {
      debugPrint('Cancelled speed tracking');
      positionStreamSubscription?.cancel();
    }

    controller = StreamController<Speed>(
      onListen: onListen,
      onPause: () => positionStreamSubscription?.pause(),
      onResume: () => positionStreamSubscription?.resume(),
      onCancel: onCancel,
    );

    yield* controller.stream;
  }

  static SpeedAccuracyEstimate normalizeSpeedAccuracy(double speedAccuracy) {
    if (speedAccuracy.isFinite && speedAccuracy > 0) {
      return SpeedAccuracyEstimate(
        standardDeviation: speedAccuracy,
        confidence: 1.0 - (min(speedAccuracy, maxSpeedAccuracyError) / maxSpeedAccuracyError),
        isKnown: true,
      );
    }

    return const SpeedAccuracyEstimate(
      standardDeviation: fallbackSpeedAccuracy,
      confidence: unknownSpeedConfidence,
      isKnown: false,
    );
  }

  Future<bool> _checkPermissions() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission != LocationPermission.always && permission != LocationPermission.whileInUse) {
      debugPrint('permission: $permission');
      return false;
    }

    var accuracy = LocationAccuracyStatus.precise;
    if (Platform.isAndroid || Platform.isIOS) {
      accuracy = await Geolocator.getLocationAccuracy();
    }

    if (Platform.isIOS && accuracy == LocationAccuracyStatus.reduced) {
      accuracy = await Geolocator.requestTemporaryFullAccuracy(purposeKey: 'SpeedPurposeKey');
    }

    debugPrint('permission: $permission, accuracy: $accuracy');

    return accuracy == LocationAccuracyStatus.precise;
  }
}

class SpeedAccuracyEstimate {
  final double standardDeviation;
  final double confidence;
  final bool isKnown;

  const SpeedAccuracyEstimate({required this.standardDeviation, required this.confidence, required this.isKnown});

  double get measurementNoise => standardDeviation * standardDeviation;
}

class Speed {
  /// Speed in meters per second
  final double value;

  /// Accuracy of the speed measurement, ranging from 0.0 (worst) to 1.0 (best)
  final double accuracy;

  const Speed(this.value, this.accuracy);

  double getAs(SpeedUnit unit, [int precision = 1]) {
    return double.parse((value * unit._factor).toStringAsFixed(precision));
  }
}

enum SpeedUnit {
  kilometersPerHour,
  milesPerHour,
  metersPerSecond,
  footPerSecond,
  knots;

  double get _factor {
    switch (this) {
      case SpeedUnit.kilometersPerHour:
        return 3.600000;
      case SpeedUnit.milesPerHour:
        return 2.236936;
      case SpeedUnit.metersPerSecond:
        return 1;
      case SpeedUnit.footPerSecond:
        return 3.280840;
      case SpeedUnit.knots:
        return 1.943844;
    }
  }

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
