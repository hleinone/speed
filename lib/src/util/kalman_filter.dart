class KalmanFilter {
  double _estimate;
  double _errorCovariance;
  final double processNoise;
  final double initialMeasurementNoise;

  KalmanFilter({
    required double initialMeasurement,
    this.initialMeasurementNoise = 4.0,
    this.processNoise = 1.0,
  }) : _estimate = initialMeasurement,
       _errorCovariance = initialMeasurementNoise;

  double update(double measurement, double measurementNoise) {
    // Prediction update
    _errorCovariance += processNoise;

    // Measurement update
    final kalmanGain = _errorCovariance / (_errorCovariance + measurementNoise);
    _estimate = _estimate + kalmanGain * (measurement - _estimate);
    _errorCovariance = (1 - kalmanGain) * _errorCovariance;

    return _estimate;
  }
}
