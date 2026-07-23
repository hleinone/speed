import 'package:flutter/material.dart';
import 'package:speed/src/generated/l10n/l10n.dart';
import 'package:speed/src/speed_page.dart';

void main() {
  runApp(const SpeedApp());
}

class SpeedApp extends StatelessWidget {
  const SpeedApp({
    super.key,
    this.locale,
    this.home = const SpeedPage(),
    this.themeMode,
    this.fontFamily,
    this.debugShowCheckedModeBanner = true,
  });

  final Locale? locale;
  final Widget home;
  final ThemeMode? themeMode;
  final String? fontFamily;
  final bool debugShowCheckedModeBanner;

  ThemeData _buildTheme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: brightness),
    fontFamily: fontFamily,
    dropdownMenuTheme: const DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(border: InputBorder.none, contentPadding: EdgeInsets.zero),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Speed',
      debugShowCheckedModeBanner: debugShowCheckedModeBanner,
      locale: locale,
      theme: _buildTheme(Brightness.light),
      darkTheme: _buildTheme(Brightness.dark),
      themeMode: themeMode ?? ThemeMode.system,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: home,
    );
  }
}
