import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:speed/main.dart';
import 'package:speed/src/display_wake_lock.dart';
import 'package:speed/src/speed_page.dart';
import 'package:speed/src/speed_tracker.dart';
import 'package:speed/src/speed_unit_localization.dart';

import 'storyboard.dart';

class StoreScreenshotGenerator {
  StoreScreenshotGenerator({required this.outputDirectory});

  final Directory outputDirectory;
  var _completed = 0;

  Future<void> prepare() async {
    final configurationErrors = validateStoryboard();
    if (configurationErrors.isNotEmpty) {
      throw StateError('Invalid screenshot storyboard:\n${configurationErrors.join('\n')}');
    }

    if (outputDirectory.existsSync()) {
      outputDirectory.deleteSync(recursive: true);
    }
    outputDirectory.createSync(recursive: true);
    await _loadRobotoFonts();
  }

  Future<void> generate(
    WidgetTester tester,
    ScreenshotTarget target,
    ScreenshotLocale locale,
    ScreenshotScenario scenario,
  ) async {
    stdout.writeln(
      '[${_completed + 1}/$screenshotCount] Rendering '
      '${target.id} · ${locale.id} · ${scenario.id}',
    );
    try {
      await _configureView(tester, target);
      await _captureScreenshot(tester, target, locale, scenario);
      _completed += 1;
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  void finish() {
    if (_completed != screenshotCount) {
      throw StateError('Generated $_completed of $screenshotCount configured screenshots.');
    }
    _writeContactSheet();
    stdout.writeln('Generated $_completed store screenshots in ${outputDirectory.path}.');
  }

  Future<void> _configureView(WidgetTester tester, ScreenshotTarget target) async {
    // The app is laid out at the device's logical size, then scaled into this
    // physical-size canvas so text and controls retain realistic density.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(target.width.toDouble(), target.height.toDouble());
    debugDefaultTargetPlatformOverride = switch (target.platform) {
      ScreenshotPlatform.ios => TargetPlatform.iOS,
      ScreenshotPlatform.android => TargetPlatform.android,
    };
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<void> _captureScreenshot(
    WidgetTester tester,
    ScreenshotTarget target,
    ScreenshotLocale locale,
    ScreenshotScenario scenario,
  ) async {
    final captureKey = GlobalKey(debugLabel: 'store screenshot canvas');
    await tester.pumpWidget(RepaintBoundary(key: captureKey, child: _storeCanvas(target, locale, scenario)));
    await tester.pumpAndSettle();

    if (scenario.openUnitMenu) {
      final unitMenu = find.byType(DropdownMenu<SpeedUnit>);
      expect(unitMenu, findsOneWidget);
      await tester.tap(unitMenu);
      await tester.pumpAndSettle();
      expect(find.text(_speedUnit(scenario.speedUnit).localizedTitle(tester.element(unitMenu))), findsWidgets);
    }

    final file = File('${outputDirectory.path}/${target.outputPath(locale)}/${scenario.fileName}');
    file.parent.createSync(recursive: true);
    await expectLater(find.byKey(captureKey), matchesGoldenFile(file.absolute.path));

    final decoded = image.decodePng(file.readAsBytesSync());
    if (decoded == null) {
      throw StateError('Could not decode generated PNG: ${file.path}.');
    }
    if (decoded.width != target.width || decoded.height != target.height) {
      throw StateError(
        '${target.id} rendered at ${decoded.width}x${decoded.height}; '
        'expected ${target.width}x${target.height}.',
      );
    }
    final rgbBytes = decoded.getBytes(order: image.ChannelOrder.rgb);
    final rgb = image.Image.fromBytes(
      width: decoded.width,
      height: decoded.height,
      bytes: rgbBytes.buffer,
      bytesOffset: rgbBytes.offsetInBytes,
      numChannels: 3,
      order: image.ChannelOrder.rgb,
    );
    file.writeAsBytesSync(image.encodePng(rgb, level: 6, filter: image.PngFilter.sub), flush: true);
  }

  Widget _storeCanvas(ScreenshotTarget target, ScreenshotLocale locale, ScreenshotScenario scenario) {
    if (!target.captioned) {
      return _rawAppCanvas(target, locale, scenario);
    }

    final width = target.width.toDouble();
    final height = target.height.toDouble();
    final horizontalPadding = width * 0.07;
    final bottomPadding = width * 0.07;
    final captionHeight = height * captionHeightFraction;
    final availableWidth = width - horizontalPadding * 2;
    final availableHeight = height - captionHeight - bottomPadding;
    final scale = _minimum(availableWidth / width, availableHeight / height);
    final appWidth = width * scale;
    final appHeight = height * scale;
    final appY = captionHeight + (availableHeight - appHeight) / 2;
    final radius = width * 0.045;
    final copy = scenario.copy[locale.id]!;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff090b0e), Color(0xff2c3138)],
          ),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              top: 0,
              left: horizontalPadding,
              right: horizontalPadding,
              height: captionHeight,
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    copy.caption,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    textScaler: TextScaler.noScaling,
                    style: TextStyle(
                      color: Colors.white,
                      fontFamily: 'StoreRoboto',
                      fontSize: width * 0.065,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: (width - appWidth) / 2,
              top: appY,
              width: appWidth,
              height: appHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
                child: FittedBox(
                  alignment: Alignment.topLeft,
                  fit: BoxFit.fill,
                  clipBehavior: Clip.hardEdge,
                  child: SizedBox(width: width, height: height, child: _rawAppCanvas(target, locale, scenario)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rawAppCanvas(ScreenshotTarget target, ScreenshotLocale locale, ScreenshotScenario scenario) => ClipRect(
    child: Align(
      alignment: Alignment.topLeft,
      child: Transform.scale(
        alignment: Alignment.topLeft,
        scale: target.devicePixelRatio,
        child: SizedBox(
          width: target.logicalWidth,
          height: target.logicalHeight,
          child: SpeedApp(
            locale: Locale(locale.appLocale),
            themeMode: ThemeMode.light,
            fontFamily: 'StoreRoboto',
            debugShowCheckedModeBanner: false,
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(disableAnimations: true, boldText: false),
                child: SpeedPage(
                  screenAwake: const _NoOpScreenAwake(),
                  trackingSource: _StaticSpeedTrackingSource(
                    CurrentSpeed(scenario.speedMetersPerSecond, scenario.accuracy),
                  ),
                  initialSpeedUnit: _speedUnit(scenario.speedUnit),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> _loadRobotoFonts() async {
    final flutterRoot = _findFlutterRoot();
    final fontDirectory = Directory('${flutterRoot.path}/bin/cache/artifacts/material_fonts');
    final loader = FontLoader('StoreRoboto');
    for (final name in ['Roboto-Regular.ttf', 'Roboto-Medium.ttf', 'Roboto-Bold.ttf']) {
      final bytes = File('${fontDirectory.path}/$name').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    final materialIcons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(ByteData.sublistView(File('${fontDirectory.path}/MaterialIcons-Regular.otf').readAsBytesSync())),
      );
    await Future.wait([loader.load(), materialIcons.load()]);
  }

  Directory _findFlutterRoot() {
    var directory = File(Platform.resolvedExecutable).parent;
    while (directory.parent.path != directory.path) {
      if (File('${directory.path}/bin/flutter').existsSync()) {
        return directory;
      }
      directory = directory.parent;
    }
    throw StateError('Could not locate the Flutter SDK from ${Platform.resolvedExecutable}.');
  }

  void _writeContactSheet() {
    final sections = <String>[];
    for (final target in screenshotTargets) {
      for (final locale in screenshotLocales) {
        final directory = target.outputPath(locale);
        final cards = screenshotScenarios.map((scenario) {
          final copy = scenario.copy[locale.id]!;
          final imagePath = '$directory/${scenario.fileName}';
          return '''
          <figure>
            <a href="$imagePath"><img src="$imagePath" alt="${_escapeHtml(copy.altText)}"></a>
            <figcaption><strong>${scenario.order}. ${_escapeHtml(copy.caption)}</strong><br>${_escapeHtml(copy.altText)}</figcaption>
          </figure>''';
        }).join();
        sections.add('''
      <section>
        <h2>${_escapeHtml(target.store.directoryName)} · ${_escapeHtml(locale.directoryFor(target.store))} · ${_escapeHtml(target.deviceClass)}</h2>
        <div class="grid">$cards</div>
      </section>''');
      }
    }

    File('${outputDirectory.path}/index.html').writeAsStringSync('''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Speed store screenshots</title>
  <style>
    :root { color-scheme: light dark; font-family: system-ui, sans-serif; }
    body { margin: 0 auto; max-width: 1500px; padding: 24px; }
    h1 { margin-bottom: 8px; }
    h2 { margin-top: 40px; font-size: 18px; }
    .grid { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 18px; }
    figure { margin: 0; }
    img { background: #ddd; border-radius: 10px; display: block; height: 420px; max-width: 100%; object-fit: contain; width: 100%; }
    figcaption { font-size: 13px; line-height: 1.4; margin-top: 8px; }
    @media (max-width: 900px) { .grid { grid-template-columns: repeat(2, minmax(0, 1fr)); } }
  </style>
</head>
<body>
  <h1>Speed store screenshots</h1>
  <p>$screenshotCount store-ready assets: ${screenshotScenarios.length} scenarios, ${screenshotLocales.length} locales, and ${screenshotTargets.length} device classes.</p>
  ${sections.join()}
</body>
</html>
''', flush: true);
  }
}

class _NoOpScreenAwake implements ScreenAwake {
  const _NoOpScreenAwake();

  @override
  Future<void> disable() async {}

  @override
  Future<void> enable() async {}
}

class _StaticSpeedTrackingSource implements SpeedTrackingSource {
  const _StaticSpeedTrackingSource(this.speed);

  final Speed speed;

  @override
  Stream<Speed> get stream => Stream.multi((controller) => controller.add(speed));

  @override
  Future<bool> openAppSettings() async => false;

  @override
  Future<bool> openLocationSettings() async => false;
}

SpeedUnit _speedUnit(String name) => SpeedUnit.values.singleWhere((unit) => unit.name == name);

String _escapeHtml(String value) => const HtmlEscape(HtmlEscapeMode.element).convert(value);

double _minimum(double first, double second) => first < second ? first : second;
