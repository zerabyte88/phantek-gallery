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

  static ThemeData get amoled => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
          surface: Colors.black,
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.black,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Color(0xFF111111),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF141414),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
      );

  static const Color _sakuraSeed = Color(0xFFFF7597);

  static ThemeData get amoledSakura => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _sakuraSeed,
          brightness: Brightness.dark,
          surface: Colors.black,
          primary: const Color(0xFFFF7597),
        ),
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        canvasColor: Colors.black,
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Colors.black,
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Color(0xFF181014),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF1F1218),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
      );
}
