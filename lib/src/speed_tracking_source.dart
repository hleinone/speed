import 'package:speed/src/speed_tracker/models.dart';

abstract interface class SpeedTrackingSource {
  Stream<Speed> get stream;

  Future<bool> openAppSettings();

  Future<bool> openLocationSettings();
}

enum SpeedTrackingFailureKind {
  permissionDenied,
  permissionDeniedForever,
  locationServicesDisabled,
  preciseLocationRequired,
  unexpected,
}

final class SpeedTrackingException implements Exception {
  const SpeedTrackingException(this.kind, {this.cause, this.stackTrace});

  final SpeedTrackingFailureKind kind;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'SpeedTrackingException($kind, cause: $cause)';
}
