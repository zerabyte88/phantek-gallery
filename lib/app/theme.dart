import 'package:flutter/material.dart';

/// Central theme definitions for Phantek Gallery.
class AppTheme {
  AppTheme._();

  // Brand seed colour—deep indigo-purple that works for a media gallery.
  static const Color _seed = Color(0xFF6B48FF);

  static const _switchTheme = SwitchThemeData(
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
    splashRadius: 0,
  );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
        splashFactory: InkSparkle.splashFactory,
        switchTheme: _switchTheme,
        appBarTheme: const AppBarTheme(centerTitle: false, elevation: 0),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );

  static const Color _snowfallSeed = Color(0xFF38BDF8);

  static ThemeData get amoledSnowfall => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _snowfallSeed,
          brightness: Brightness.dark,
          surface: const Color(0xFF0C1322),
          primary: const Color(0xFF38BDF8),
          secondary: const Color(0xFF0284C7),
          outline: const Color(0xFF1E293B),
          outlineVariant: const Color(0xFF1E293B),
        ),
        brightness: Brightness.dark,
        splashFactory: InkSparkle.splashFactory,
        switchTheme: _switchTheme,
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
          color: Color(0xFF0C1322),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF0C1322),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF0C1322),
          contentTextStyle:
              const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF1E293B)),
          ),
        ),
      );

  static ThemeData get amoledMidnight => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _seed,
          brightness: Brightness.dark,
          surface: Colors.black,
        ),
        brightness: Brightness.dark,
        splashFactory: InkSparkle.splashFactory,
        switchTheme: _switchTheme,
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
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF16181B),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
          ),
        ),
      );

  static ThemeData get dark => amoledSnowfall;
  static ThemeData get amoled => amoledMidnight;

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
        splashFactory: InkSparkle.splashFactory,
        switchTheme: _switchTheme,
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
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF1E1016),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: const Color(0xFFFF7597).withValues(alpha: 0.35),
            ),
          ),
        ),
      );

  static const Color _toolkitSeed = Color(0xFF2563EB);

  static ThemeData get amoledPure => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _toolkitSeed,
          brightness: Brightness.dark,
          surface: const Color(0xFF121214),
          primary: const Color(0xFF2563EB),
          outline: const Color(0xFF27272A),
          outlineVariant: const Color(0xFF18181B),
        ),
        brightness: Brightness.dark,
        splashFactory: InkSparkle.splashFactory,
        switchTheme: _switchTheme,
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
          color: Color(0xFF121214),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF121214),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF121214),
          contentTextStyle:
              const TextStyle(color: Color(0xFFFAFAFA), fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF27272A)),
          ),
        ),
      );

  static ThemeData get cleanLight => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _toolkitSeed,
          brightness: Brightness.light,
          surface: const Color(0xFFFFFFFF),
          primary: const Color(0xFF2563EB),
          outline: const Color(0xFFE2E8F0),
          outlineVariant: const Color(0xFFF1F5F9),
        ),
        brightness: Brightness.light,
        splashFactory: InkSparkle.splashFactory,
        switchTheme: _switchTheme,
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        canvasColor: const Color(0xFFFFFFFF),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          backgroundColor: Color(0xFFFFFFFF),
        ),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          color: Color(0xFFFFFFFF),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFFFFFFFF),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Color(0xFFFFFFFF),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF0F172A),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE2E8F0)),
          ),
        ),
      );
}
