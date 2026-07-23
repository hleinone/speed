import 'package:flutter_test/flutter_test.dart';

import '../tool/store_screenshots/storyboard.dart';

void main() {
  test('configures the App Store iPhone target for the 6.5-inch slot', () {
    final target = screenshotTargets.singleWhere(
      (target) => target.id == 'app-store-iphone-6.5',
    );

    expect(target.deviceClass, 'iPhone 6.5-inch');
    expect(target.outputDirectory, 'iphone-6.5');
    expect((target.width, target.height), (1284, 2778));
    expect(validateStoryboard(), isEmpty);
  });

  test('rejects an unsupported 6.5-inch App Store portrait resolution', () {
    const invalidTarget = ScreenshotTarget(
      id: 'app-store-iphone-6.5',
      store: ScreenshotStore.appStore,
      platform: ScreenshotPlatform.ios,
      deviceClass: 'iPhone 6.5-inch',
      outputDirectory: 'iphone-6.5',
      width: 1320,
      height: 2868,
      devicePixelRatio: 3,
      captioned: true,
    );

    final errors = validateStoryboard(
      targets: [
        invalidTarget,
        ...screenshotTargets.where((target) => target.id != invalidTarget.id),
      ],
    );

    expect(
      errors,
      contains(
        'app-store-iphone-6.5 must use an accepted 6.5-inch App Store portrait resolution.',
      ),
    );
  });
}
