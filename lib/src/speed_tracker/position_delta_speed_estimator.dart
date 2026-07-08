import 'dart:math';

import 'package:geolocator/geolocator.dart';
import 'package:speed/src/speed_tracker/models.dart';
import 'package:speed/src/speed_tracker/position_sample_validator.dart';
import 'package:speed/src/speed_tracker/speed_tracker_constants.dart' as config;

const double _stationarySpeedEpsilon = 0.2;
const double _rmsResidualFloor = 1.5;
const double _maxRmsResidual = 8.0;
const double _rmsResidualAccuracyFactor = 0.75;
const double _maxResidualFloor = 3.0;
const double _maxResidual = 12.0;
const double _maxResidualAccuracyFactor = 1.5;
const double _minTravelDistance = 5.0;
const double _travelResidualFactor = 3.0;
const double _stationaryClusterFloor = 3.0;
const double _minDirectionAlignment = 0.5;
const double _maxSegmentSpeedFactor = 3.0;
const double _segmentSpeedAccuracyFactor = 2.0;

const Duration _regressionWindow = Duration(seconds: 5);
const Duration _minRegressionSpan = Duration(seconds: 3);

const int _minRegressionSamples = 4;

class PositionDeltaSpeedEstimator {
  final List<ValidPositionSample> _samples = [];

  bool addSample(ValidPositionSample sample) {
    if (!sample.hasKnownHorizontalAccuracy) {
      return false;
    }

    if (_samples.isNotEmpty && !sample.timestamp.isAfter(_samples.last.timestamp)) {
      return false;
    }

    _samples.add(sample);
    _samples.removeWhere((historySample) => sample.timestamp.difference(historySample.timestamp) > _regressionWindow);
    return true;
  }

  void removeLastSample() {
    if (_samples.isNotEmpty) {
      _samples.removeLast();
    }
  }

  FallbackSpeedEstimate? estimate() {
    if (_samples.length < _minRegressionSamples) {
      return null;
    }

    final firstSample = _samples.first;
    final lastSample = _samples.last;
    final elapsed = lastSample.timestamp.difference(firstSample.timestamp);
    if (elapsed < _minRegressionSpan) {
      return null;
    }

    final origin = _samples.first;
    final regressionPoints = _samples
        .map((sample) {
          final t = sample.timestamp.difference(origin.timestamp).inMicroseconds / Duration.microsecondsPerSecond;
          final x =
              Geolocator.distanceBetween(origin.latitude, origin.longitude, origin.latitude, sample.longitude) *
              (sample.longitude >= origin.longitude ? 1 : -1);
          final y =
              Geolocator.distanceBetween(origin.latitude, origin.longitude, sample.latitude, origin.longitude) *
              (sample.latitude >= origin.latitude ? 1 : -1);
          final weight = 1 / (sample.horizontalAccuracy * sample.horizontalAccuracy);
          return _FallbackRegressionPoint(t: t, x: x, y: y, weight: weight);
        })
        .toList(growable: false);

    final regression = _fitRegression(regressionPoints);
    if (regression == null) {
      return null;
    }

    final medianHorizontalAccuracy = _medianHorizontalAccuracy(_samples);
    final fittedSpeed = sqrt((regression.xSlope * regression.xSlope) + (regression.ySlope * regression.ySlope));
    final elapsedSeconds = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    if (fittedSpeed < _stationarySpeedEpsilon) {
      if (!_isStationaryCluster(regressionPoints, medianHorizontalAccuracy)) {
        return null;
      }
    } else {
      if (!_hasAcceptableFit(regression, medianHorizontalAccuracy, fittedSpeed * elapsedSeconds)) {
        return null;
      }
      if (!_hasConsistentSegments(regressionPoints, regression, fittedSpeed)) {
        return null;
      }
    }

    final speed = fittedSpeed < _stationarySpeedEpsilon ? 0.0 : fittedSpeed;
    final speedAccuracy = SpeedAccuracyEstimate(
      standardDeviation: max(
        config.fallbackSpeedAccuracy,
        (firstSample.horizontalAccuracy + lastSample.horizontalAccuracy) / elapsedSeconds,
      ),
      confidence: config.fallbackSpeedConfidence,
      isKnown: false,
    );

    return FallbackSpeedEstimate(speed: speed, speedAccuracy: speedAccuracy);
  }

  _FallbackRegressionResult? _fitRegression(List<_FallbackRegressionPoint> points) {
    final xRegression = _weightedLinearRegression(points, (point) => point.x);
    final yRegression = _weightedLinearRegression(points, (point) => point.y);
    if (xRegression == null || yRegression == null) {
      return null;
    }

    var weightSum = 0.0;
    var weightedSquaredResidualSum = 0.0;
    var maxResidual = 0.0;
    for (final point in points) {
      final xResidual = point.x - xRegression.valueAt(point.t);
      final yResidual = point.y - yRegression.valueAt(point.t);
      final residual = sqrt((xResidual * xResidual) + (yResidual * yResidual));
      weightSum += point.weight;
      weightedSquaredResidualSum += point.weight * residual * residual;
      maxResidual = max(maxResidual, residual);
    }

    if (weightSum <= 0) {
      return null;
    }

    return _FallbackRegressionResult(
      xSlope: xRegression.slope,
      xIntercept: xRegression.intercept,
      ySlope: yRegression.slope,
      yIntercept: yRegression.intercept,
      weightedRmsResidual: sqrt(weightedSquaredResidualSum / weightSum),
      maxResidual: maxResidual,
    );
  }

  _FallbackAxisRegression? _weightedLinearRegression(
    List<_FallbackRegressionPoint> points,
    double Function(_FallbackRegressionPoint) value,
  ) {
    var weightSum = 0.0;
    var weightedTimeSum = 0.0;
    var weightedValueSum = 0.0;
    for (final point in points) {
      weightSum += point.weight;
      weightedTimeSum += point.weight * point.t;
      weightedValueSum += point.weight * value(point);
    }

    if (weightSum <= 0) {
      return null;
    }

    final meanTime = weightedTimeSum / weightSum;
    final meanValue = weightedValueSum / weightSum;
    var covariance = 0.0;
    var variance = 0.0;
    for (final point in points) {
      final centeredTime = point.t - meanTime;
      covariance += point.weight * centeredTime * (value(point) - meanValue);
      variance += point.weight * centeredTime * centeredTime;
    }

    if (variance <= 0) {
      return null;
    }
    final slope = covariance / variance;
    return _FallbackAxisRegression(slope: slope, intercept: meanValue - (slope * meanTime));
  }

  bool _hasAcceptableFit(
    _FallbackRegressionResult regression,
    double medianHorizontalAccuracy,
    double fittedTravelDistance,
  ) {
    final rmsResidualLimit = min(
      _maxRmsResidual,
      max(_rmsResidualFloor, medianHorizontalAccuracy * _rmsResidualAccuracyFactor),
    );
    if (regression.weightedRmsResidual > rmsResidualLimit) {
      return false;
    }

    final maxResidualLimit = min(
      _maxResidual,
      max(_maxResidualFloor, medianHorizontalAccuracy * _maxResidualAccuracyFactor),
    );
    if (regression.maxResidual > maxResidualLimit) {
      return false;
    }

    final minTravelDistance = max(_minTravelDistance, regression.weightedRmsResidual * _travelResidualFactor);
    return fittedTravelDistance >= minTravelDistance;
  }

  bool _hasConsistentSegments(
    List<_FallbackRegressionPoint> points,
    _FallbackRegressionResult regression,
    double fittedSpeed,
  ) {
    final directionX = regression.xSlope / fittedSpeed;
    final directionY = regression.ySlope / fittedSpeed;
    final maxSegmentSpeed = max(
      fittedSpeed * _maxSegmentSpeedFactor,
      fittedSpeed + (config.fallbackSpeedAccuracy * _segmentSpeedAccuracyFactor),
    );
    final segmentCount = points.length - 1;
    final requiredAlignedSegments = max(3, (segmentCount * 0.75).ceil());
    var alignedSegments = 0;

    for (var i = 1; i < points.length; i++) {
      final previous = points[i - 1];
      final current = points[i];
      final elapsedSeconds = current.t - previous.t;
      if (elapsedSeconds <= 0) {
        return false;
      }

      final xVelocity = (current.x - previous.x) / elapsedSeconds;
      final yVelocity = (current.y - previous.y) / elapsedSeconds;
      final segmentSpeed = sqrt((xVelocity * xVelocity) + (yVelocity * yVelocity));
      if (segmentSpeed > maxSegmentSpeed) {
        return false;
      }

      if (segmentSpeed > 0) {
        final alignment = ((xVelocity * directionX) + (yVelocity * directionY)) / segmentSpeed;
        if (alignment >= _minDirectionAlignment) {
          alignedSegments++;
        }
      }
    }

    return alignedSegments >= requiredAlignedSegments;
  }

  bool _isStationaryCluster(List<_FallbackRegressionPoint> points, double medianHorizontalAccuracy) {
    final maxClusterSpan = max(_stationaryClusterFloor, medianHorizontalAccuracy);
    for (var i = 0; i < points.length; i++) {
      final first = points[i];
      for (var j = i + 1; j < points.length; j++) {
        final second = points[j];
        final xDelta = second.x - first.x;
        final yDelta = second.y - first.y;
        if (sqrt((xDelta * xDelta) + (yDelta * yDelta)) > maxClusterSpan) {
          return false;
        }
      }
    }
    return true;
  }

  double _medianHorizontalAccuracy(List<ValidPositionSample> samples) {
    final accuracies = samples.map((sample) => sample.horizontalAccuracy).toList(growable: false)..sort();
    final middle = accuracies.length ~/ 2;
    if (accuracies.length.isOdd) {
      return accuracies[middle];
    }
    return (accuracies[middle - 1] + accuracies[middle]) / 2;
  }
}

class FallbackSpeedEstimate {
  final double speed;
  final SpeedAccuracyEstimate speedAccuracy;

  const FallbackSpeedEstimate({required this.speed, required this.speedAccuracy});
}

class _FallbackRegressionResult {
  final double xSlope;
  final double xIntercept;
  final double ySlope;
  final double yIntercept;
  final double weightedRmsResidual;
  final double maxResidual;

  const _FallbackRegressionResult({
    required this.xSlope,
    required this.xIntercept,
    required this.ySlope,
    required this.yIntercept,
    required this.weightedRmsResidual,
    required this.maxResidual,
  });
}

class _FallbackAxisRegression {
  final double slope;
  final double intercept;

  const _FallbackAxisRegression({required this.slope, required this.intercept});

  double valueAt(double t) => intercept + (slope * t);
}

class _FallbackRegressionPoint {
  final double t;
  final double x;
  final double y;
  final double weight;

  const _FallbackRegressionPoint({required this.t, required this.x, required this.y, required this.weight});
}
