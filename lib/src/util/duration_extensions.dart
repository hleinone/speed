extension DurationFractionalSeconds on Duration {
  double get inFractionalSeconds => inMicroseconds / Duration.microsecondsPerSecond;
}
