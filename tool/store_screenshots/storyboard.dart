enum ScreenshotStore {
  appStore('app-store'),
  googlePlay('google-play');

  const ScreenshotStore(this.directoryName);

  final String directoryName;
}

enum ScreenshotPlatform { ios, android }

class ScreenshotLocale {
  const ScreenshotLocale({
    required this.id,
    required this.appLocale,
    required this.appStoreDirectory,
    required this.googlePlayDirectory,
  });

  final String id;
  final String appLocale;
  final String appStoreDirectory;
  final String googlePlayDirectory;

  String directoryFor(ScreenshotStore store) => switch (store) {
    ScreenshotStore.appStore => appStoreDirectory,
    ScreenshotStore.googlePlay => googlePlayDirectory,
  };
}

class LocalizedScreenshotCopy {
  const LocalizedScreenshotCopy({required this.caption, required this.altText});

  final String caption;
  final String altText;
}

class ScreenshotScenario {
  const ScreenshotScenario({
    required this.order,
    required this.id,
    required this.speedMetersPerSecond,
    required this.accuracy,
    required this.speedUnit,
    required this.openUnitMenu,
    required this.copy,
  });

  final int order;
  final String id;
  final double speedMetersPerSecond;
  final double accuracy;
  final String speedUnit;
  final bool openUnitMenu;
  final Map<String, LocalizedScreenshotCopy> copy;

  String get fileName => '${order.toString().padLeft(2, '0')}-$id.png';
}

class ScreenshotTarget {
  const ScreenshotTarget({
    required this.id,
    required this.store,
    required this.platform,
    required this.deviceClass,
    required this.outputDirectory,
    required this.width,
    required this.height,
    required this.devicePixelRatio,
    required this.captioned,
  });

  final String id;
  final ScreenshotStore store;
  final ScreenshotPlatform platform;
  final String deviceClass;
  final String outputDirectory;
  final int width;
  final int height;
  final double devicePixelRatio;
  final bool captioned;

  double get logicalWidth => width / devicePixelRatio;
  double get logicalHeight => height / devicePixelRatio;

  String outputPath(ScreenshotLocale locale) => '${store.directoryName}/${locale.directoryFor(store)}/$outputDirectory';
}

const screenshotLocales = [
  ScreenshotLocale(id: 'en', appLocale: 'en', appStoreDirectory: 'en-US', googlePlayDirectory: 'en-US'),
  ScreenshotLocale(id: 'fi', appLocale: 'fi', appStoreDirectory: 'fi', googlePlayDirectory: 'fi-FI'),
];

const screenshotScenarios = [
  ScreenshotScenario(
    order: 1,
    id: 'speed-at-a-glance',
    speedMetersPerSecond: 82 / 3.6,
    accuracy: 0.96,
    speedUnit: 'kilometersPerHour',
    openUnitMenu: false,
    copy: {
      'en': LocalizedScreenshotCopy(
        caption: 'Your speed at a glance',
        altText: 'Speed app showing 82 km/h and a strong GPS signal.',
      ),
      'fi': LocalizedScreenshotCopy(
        caption: 'Nopeutesi yhdellä silmäyksellä',
        altText: 'Speed-sovellus näyttää nopeuden 82 km/h ja vahvan GPS-signaalin.',
      ),
    },
  ),
  ScreenshotScenario(
    order: 2,
    id: 'choose-your-unit',
    speedMetersPerSecond: 15,
    accuracy: 0.88,
    speedUnit: 'metersPerSecond',
    openUnitMenu: true,
    copy: {
      'en': LocalizedScreenshotCopy(
        caption: 'Choose the unit that fits',
        altText: 'The unit menu offers km/h, mph, m/s, fps, and knots.',
      ),
      'fi': LocalizedScreenshotCopy(
        caption: 'Valitse sopiva yksikkö',
        altText: 'Yksikkövalikossa ovat km/h, mi/h, m/s, ft/s ja solmut.',
      ),
    },
  ),
  ScreenshotScenario(
    order: 3,
    id: 'gps-signal-quality',
    speedMetersPerSecond: 42 / 2.236936,
    accuracy: 0.68,
    speedUnit: 'milesPerHour',
    openUnitMenu: false,
    copy: {
      'en': LocalizedScreenshotCopy(
        caption: 'See GPS signal quality',
        altText: 'Speed app showing 42 mph with medium GPS signal quality.',
      ),
      'fi': LocalizedScreenshotCopy(
        caption: 'Näe GPS-signaalin laatu',
        altText: 'Speed-sovellus näyttää nopeuden 42 mi/h ja keskitasoisen GPS-signaalin.',
      ),
    },
  ),
  ScreenshotScenario(
    order: 4,
    id: 'roads-to-open-water',
    speedMetersPerSecond: 18 / 1.943844,
    accuracy: 0.92,
    speedUnit: 'knots',
    openUnitMenu: false,
    copy: {
      'en': LocalizedScreenshotCopy(
        caption: 'From roads to open water',
        altText: 'Speed app showing a speed of 18 knots.',
      ),
      'fi': LocalizedScreenshotCopy(
        caption: 'Maantiellä ja vesillä',
        altText: 'Speed-sovellus näyttää nopeuden 18 solmua.',
      ),
    },
  ),
];

const screenshotTargets = [
  ScreenshotTarget(
    id: 'app-store-iphone-6.9',
    store: ScreenshotStore.appStore,
    platform: ScreenshotPlatform.ios,
    deviceClass: 'iPhone 6.9-inch',
    outputDirectory: 'iphone-6.9',
    width: 1320,
    height: 2868,
    devicePixelRatio: 3,
    captioned: true,
  ),
  ScreenshotTarget(
    id: 'app-store-ipad-13',
    store: ScreenshotStore.appStore,
    platform: ScreenshotPlatform.ios,
    deviceClass: 'iPad 13-inch',
    outputDirectory: 'ipad-13',
    width: 2064,
    height: 2752,
    devicePixelRatio: 2,
    captioned: true,
  ),
  ScreenshotTarget(
    id: 'google-play-phone',
    store: ScreenshotStore.googlePlay,
    platform: ScreenshotPlatform.android,
    deviceClass: 'Android phone',
    outputDirectory: 'phone',
    width: 1080,
    height: 1920,
    devicePixelRatio: 3,
    captioned: true,
  ),
  ScreenshotTarget(
    id: 'google-play-tablet-7',
    store: ScreenshotStore.googlePlay,
    platform: ScreenshotPlatform.android,
    deviceClass: 'Android 7-inch tablet',
    outputDirectory: 'seven-inch-tablet',
    width: 1080,
    height: 1920,
    // 600 logical pixels wide models Android's compact tablet class.
    devicePixelRatio: 1.8,
    captioned: false,
  ),
  ScreenshotTarget(
    id: 'google-play-tablet-10',
    store: ScreenshotStore.googlePlay,
    platform: ScreenshotPlatform.android,
    deviceClass: 'Android 10-inch tablet',
    outputDirectory: 'ten-inch-tablet',
    width: 1440,
    height: 2560,
    devicePixelRatio: 2,
    captioned: false,
  ),
];

const captionHeightFraction = 0.15;

int get screenshotCount => screenshotLocales.length * screenshotScenarios.length * screenshotTargets.length;

List<String> validateStoryboard() {
  final errors = <String>[];
  final localeIds = <String>{};
  final orders = <int>{};
  final names = <String>{};
  final targetIds = <String>{};
  final outputPaths = <String>{};

  if (captionHeightFraction <= 0 || captionHeightFraction > 0.15) {
    errors.add('Caption height must be greater than 0 and at most 15%.');
  }
  if (screenshotLocales.isEmpty || screenshotScenarios.isEmpty || screenshotTargets.isEmpty) {
    errors.add('Locales, scenarios, and targets must not be empty.');
  }

  for (final locale in screenshotLocales) {
    if (locale.id.trim().isEmpty || !localeIds.add(locale.id)) {
      errors.add('Locale IDs must be non-empty and unique: ${locale.id}.');
    }
  }

  for (final scenario in screenshotScenarios) {
    if (!orders.add(scenario.order)) {
      errors.add('Duplicate scenario order: ${scenario.order}.');
    }
    if (!names.add(scenario.fileName)) {
      errors.add('Duplicate scenario file name: ${scenario.fileName}.');
    }
    if (scenario.accuracy < 0 || scenario.accuracy > 1) {
      errors.add('${scenario.id} has an accuracy outside 0...1.');
    }
    if (scenario.speedMetersPerSecond < 0) {
      errors.add('${scenario.id} has a negative speed.');
    }
    final missingLocales = localeIds.difference(scenario.copy.keys.toSet());
    if (missingLocales.isNotEmpty) {
      errors.add('${scenario.id} is missing copy for ${missingLocales.join(', ')}.');
    }
    for (final locale in screenshotLocales) {
      final localizedCopy = scenario.copy[locale.id];
      if (localizedCopy == null) continue;
      if (localizedCopy.caption.trim().isEmpty || localizedCopy.altText.trim().isEmpty) {
        errors.add('${scenario.id} has empty ${locale.id} copy.');
      }
    }
  }

  for (final target in screenshotTargets) {
    if (target.id.trim().isEmpty || !targetIds.add(target.id)) {
      errors.add('Target IDs must be non-empty and unique: ${target.id}.');
    }
    if (target.width <= 0 || target.height <= 0 || target.devicePixelRatio <= 0) {
      errors.add('${target.id} has invalid dimensions or pixel ratio.');
    }
    if (target.store == ScreenshotStore.googlePlay) {
      final ratio = target.height / target.width;
      if ((ratio - (16 / 9)).abs() > 0.001) {
        errors.add('${target.id} must use a 9:16 portrait aspect ratio.');
      }
      if (target.width < 1080) {
        errors.add('${target.id} must be at least 1080 pixels wide.');
      }
    }
    for (final locale in screenshotLocales) {
      for (final scenario in screenshotScenarios) {
        final path = '${target.outputPath(locale)}/${scenario.fileName}';
        if (!outputPaths.add(path)) {
          errors.add('Duplicate screenshot output path: $path.');
        }
      }
    }
  }

  return errors;
}
