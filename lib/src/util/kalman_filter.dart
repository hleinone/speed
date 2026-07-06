class KalmanFilter {
  double _estimate;
  double _errorCovariance;
  final double processNoise;
  final double initialMeasurementNoise;

  KalmanFilter({required double initialMeasurement, this.initialMeasurementNoise = 4.0, this.processNoise = 1.0})
    : _estimate = initialMeasurement,
      _errorCovariance = initialMeasurementNoise;

  double update(double measurement, double measurementNoise, {Duration elapsedTime = const Duration(seconds: 1)}) {
    // Prediction update
    final elapsedMicroseconds = elapsedTime.inMicroseconds;
    final elapsedSeconds = elapsedMicroseconds <= 0 ? 0.0 : elapsedMicroseconds / Duration.microsecondsPerSecond;
    _errorCovariance += processNoise * elapsedSeconds;

    // Measurement update
    final kalmanGain = _errorCovariance / (_errorCovariance + measurementNoise);
    _estimate = _estimate + kalmanGain * (measurement - _estimate);
    _errorCovariance = (1 - kalmanGain) * _errorCovariance;

    return _estimate;
  }
}
