import 'package:flutter/material.dart';

/// Central theme definitions for Phantek Gallery.
class AppTheme {
  AppTheme._();

  // Brand seed colour—deep indigo-purple that works for a media gallery.
  static const Color _seed = Color(0xFF6B48FF);

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0E0E0E),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Color(0xFF0E0E0E),
        ),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      );
}
