import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'renderer.dart';
import 'storyboard.dart';

void main() {
  final generator = StoreScreenshotGenerator(outputDirectory: Directory('build/store-screenshots'));

  group('store screenshots', () {
    setUpAll(generator.prepare);

    for (final target in screenshotTargets) {
      for (final locale in screenshotLocales) {
        for (final scenario in screenshotScenarios) {
          testWidgets(
            '${target.id} · ${locale.id} · ${scenario.id}',
            (tester) => generator.generate(tester, target, locale, scenario),
            timeout: const Timeout(Duration(minutes: 2)),
          );
        }
      }
    }

    tearDownAll(generator.finish);
  });
}
