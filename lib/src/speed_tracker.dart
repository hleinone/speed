import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/speed_sample_processor.dart';
import 'package:speed/src/speed_tracker/speed_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;
import 'package:speed/src/speed_tracking_source.dart';

export 'package:speed/src/speed_tracker/models.dart';
export 'package:speed/src/speed_tracking_source.dart';

typedef SpeedTrackerClock = DateTime Function();

abstract interface class GeolocationGateway {
  Future<bool> isLocationServiceEnabled();

  Future<LocationPermission> checkPermission();

  Future<LocationPermission> requestPermission();

  Future<LocationAccuracyStatus> getLocationAccuracy();

  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({required String purposeKey});

  Stream<Position> getPositionStream(LocationSettings locationSettings);

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

class GeolocatorGateway implements GeolocationGateway {
  const GeolocatorGateway();

  @override
  Future<LocationPermission> checkPermission() => Geolocator.checkPermission();

  @override
  Future<LocationAccuracyStatus> getLocationAccuracy() => Geolocator.getLocationAccuracy();

  @override
  Stream<Position> getPositionStream(LocationSettings locationSettings) {
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  @override
  Future<bool> isLocationServiceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();

  @override
  Future<LocationPermission> requestPermission() => Geolocator.requestPermission();

  @override
  Future<LocationAccuracyStatus> requestTemporaryFullAccuracy({required String purposeKey}) {
    return Geolocator.requestTemporaryFullAccuracy(purposeKey: purposeKey);
  }
}

class SpeedTracker implements SpeedTrackingSource {
  static const double fallbackSpeedAccuracy = config.fallbackSpeedAccuracy;
  static const double unknownSpeedConfidence = config.unknownSpeedConfidence;
  static const double maxSpeedAccuracyError = config.maxSpeedAccuracyError;
  static const double maxAcceptedHorizontalAccuracy = config.maxAcceptedHorizontalAccuracy;
  static const double maxPlausibleAcceleration = config.maxPlausibleAcceleration;
  static const double fallbackSpeedConfidence = config.fallbackSpeedConfidence;
  static const Duration maxSampleAge = config.maxSampleAge;
  static const Duration positionUpdateInterval = config.positionUpdateInterval;
  static const Duration freshnessTimeout = config.freshnessTimeout;
  static const Duration maxFutureSampleSkew = config.maxFutureSampleSkew;
  static const int startupWarmupAcceptedSamples = config.startupWarmupAcceptedSamples;

  /// Process noise per second for the Kalman filter. A lower value means more smoothing but less responsiveness.
  final double processNoise;
  final SpeedTrackerClock _clock;
  final GeolocationGateway _geolocation;
  final TargetPlatform _platform;

  SpeedTracker({
    this.processNoise = 0.1,
    SpeedTrackerClock? clock,
    GeolocationGateway geolocation = const GeolocatorGateway(),
    TargetPlatform? platform,
  }) : _clock = clock ?? DateTime.now,
       _geolocation = geolocation,
       _platform = platform ?? defaultTargetPlatform;

  @override
  Stream<Speed> get stream async* {
    late final StreamController<Speed> controller;
    // Cancellation is centralized in cancelPositionStream(); the lint does not follow local function calls.
    // ignore: cancel_subscriptions
    StreamSubscription<Position>? positionStreamSubscription;
    Timer? freshnessTimer;
    Speed? lastEmittedSpeed;
    var hasTerminated = false;

    final locationSettings = createLocationSettings(_platform);
    final speedProcessor = SpeedSampleProcessor(processNoise: processNoise);

    try {
      await _ensureLocationAccess();
    } catch (error, stackTrace) {
      Error.throwWithStackTrace(_mapFailure(error, stackTrace), stackTrace);
    }

    Future<void> cancelPositionStream() async {
      final subscription = positionStreamSubscription;
      positionStreamSubscription = null;
      if (subscription == null) {
        return;
      }

      try {
        await subscription.cancel();
      } catch (error, stackTrace) {
        debugPrint('Failed to cancel position tracking: $error');
        debugPrintStack(stackTrace: stackTrace);
      }
    }

    void fail(Object error, StackTrace stackTrace) {
      if (hasTerminated || controller.isClosed) {
        return;
      }

      hasTerminated = true;
      freshnessTimer?.cancel();
      unawaited(cancelPositionStream());
      controller.addError(_mapFailure(error, stackTrace), stackTrace);
      unawaited(controller.close());
    }

    void emitUnavailable() {
      if (hasTerminated || controller.isClosed || lastEmittedSpeed is UnavailableSpeed) {
        return;
      }

      const unavailableSpeed = UnavailableSpeed();
      controller.add(unavailableSpeed);
      lastEmittedSpeed = unavailableSpeed;
    }

    void scheduleFreshnessWatchdog(AcceptedSpeedSample sample, DateTime now) {
      freshnessTimer?.cancel();
      final age = now.difference(sample.timestamp);
      final delay = freshnessTimeout - age;
      freshnessTimer = Timer(delay.isNegative ? Duration.zero : delay, emitUnavailable);
    }

    void emitCurrentSpeed(CurrentSpeed speed, AcceptedSpeedSample sample, DateTime now) {
      if (hasTerminated || controller.isClosed) {
        return;
      }

      scheduleFreshnessWatchdog(sample, now);
      controller.add(speed);
      lastEmittedSpeed = speed;
    }

    void finish() {
      if (hasTerminated || controller.isClosed) {
        return;
      }

      freshnessTimer?.cancel();
      emitUnavailable();
      hasTerminated = true;
      unawaited(controller.close());
    }

    void handlePosition(Position position) {
      if (hasTerminated) {
        return;
      }

      try {
        final now = _clock();
        final processedSample = speedProcessor.process(position, now);
        if (processedSample != null) {
          emitCurrentSpeed(processedSample.speed, processedSample.acceptedSample, now);
        }
      } catch (error, stackTrace) {
        fail(error, stackTrace);
      }
    }

    void onListen() {
      freshnessTimer = Timer(freshnessTimeout, emitUnavailable);
      try {
        positionStreamSubscription = _geolocation
            .getPositionStream(locationSettings)
            .listen(handlePosition, onError: fail, onDone: finish);
        if (hasTerminated) {
          unawaited(cancelPositionStream());
        }
      } catch (error, stackTrace) {
        fail(error, stackTrace);
      }
    }

    Future<void> onCancel() async {
      hasTerminated = true;
      freshnessTimer?.cancel();
      await cancelPositionStream();
    }

    controller = StreamController<Speed>(
      onListen: onListen,
      onPause: () => positionStreamSubscription?.pause(),
      onResume: () => positionStreamSubscription?.resume(),
      onCancel: onCancel,
    );

    yield* controller.stream;
  }

  @override
  Future<bool> openAppSettings() => _geolocation.openAppSettings();

  @override
  Future<bool> openLocationSettings() => _geolocation.openLocationSettings();

  Future<void> _ensureLocationAccess() async {
    if (!await _geolocation.isLocationServiceEnabled()) {
      throw const SpeedTrackingException(SpeedTrackingFailureKind.locationServicesDisabled);
    }

    var permission = await _geolocation.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await _geolocation.requestPermission();
    }

    switch (permission) {
      case LocationPermission.denied:
        throw const SpeedTrackingException(SpeedTrackingFailureKind.permissionDenied);
      case LocationPermission.deniedForever:
        throw const SpeedTrackingException(SpeedTrackingFailureKind.permissionDeniedForever);
      case LocationPermission.unableToDetermine:
        throw const SpeedTrackingException(SpeedTrackingFailureKind.unexpected);
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        break;
    }

    if (_platform != TargetPlatform.android && _platform != TargetPlatform.iOS) {
      return;
    }

    var accuracy = await _geolocation.getLocationAccuracy();
    if (_platform == TargetPlatform.iOS && accuracy == LocationAccuracyStatus.reduced) {
      accuracy = await _geolocation.requestTemporaryFullAccuracy(purposeKey: 'SpeedPurposeKey');
    }

    if (accuracy == LocationAccuracyStatus.reduced) {
      throw const SpeedTrackingException(SpeedTrackingFailureKind.preciseLocationRequired);
    }
  }

  SpeedTrackingException _mapFailure(Object error, StackTrace stackTrace) {
    if (error is SpeedTrackingException) {
      return error;
    }
    if (error is LocationServiceDisabledException) {
      return SpeedTrackingException(
        SpeedTrackingFailureKind.locationServicesDisabled,
        cause: error,
        stackTrace: stackTrace,
      );
    }
    if (error is PermissionDeniedException) {
      return SpeedTrackingException(SpeedTrackingFailureKind.permissionDenied, cause: error, stackTrace: stackTrace);
    }
    return SpeedTrackingException(SpeedTrackingFailureKind.unexpected, cause: error, stackTrace: stackTrace);
  }

  @visibleForTesting
  static LocationSettings createLocationSettings(TargetPlatform platform) {
    if (platform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
        intervalDuration: positionUpdateInterval,
      );
    }
    if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
      return AppleSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
    }
    return const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);
  }

  static SpeedAccuracyEstimate normalizeSpeedAccuracy(double speedAccuracy) {
    return const SpeedSampleValidator().normalizeSpeedAccuracy(speedAccuracy);
  }
}
