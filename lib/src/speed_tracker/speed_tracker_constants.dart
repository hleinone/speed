const double fallbackSpeedAccuracy = 2.0;
const double unknownSpeedConfidence = 0.25;
const double unknownHorizontalAccuracyConfidence = 0.25;
const double maxSpeedAccuracyError = 5.0;
const double maxAcceptedHorizontalAccuracy = 50.0;
const double maxPlausibleAcceleration = 8.0;
const double fallbackSpeedConfidence = unknownSpeedConfidence * 0.5;

const Duration maxSampleAge = Duration(seconds: 5);
const Duration positionUpdateInterval = Duration(seconds: 1);
const Duration freshnessTimeout = Duration(seconds: 10);
const Duration maxFutureSampleSkew = Duration(seconds: 1);

const int startupWarmupAcceptedSamples = 3;
