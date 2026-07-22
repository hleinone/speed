# Speed

Simple app for displaying the current speed of the device using the GPS sensor.

## Store screenshots

Generate the localized App Store and Google Play screenshots with:

```sh
./scripts/generate_store_screenshots.sh
```

The command runs the screenshot matrix in one Flutter test process, rendering both the app UI and branded layouts with deterministic speed streams. It does not need a simulator, GPS, location permission, network access, or store credentials. It creates 40 store-ready, 24-bit RGB PNG files under `build/store-screenshots/`:

- App Store: English and Finnish assets for 6.9-inch iPhone and 13-inch iPad.
- Google Play: English and Finnish assets for phones, 7-inch tablets, and 10-inch tablets.
- `index.html`: a contact sheet for visual review.

The generated directory is ignored by Git. Edit `tool/store_screenshots/storyboard.dart` to change scenarios, localized marketing copy, device targets, or output names. The generator derives the output count from that configuration and fails on missing translations, duplicate paths, invalid dimensions, or unsupported Google Play aspect ratios.
