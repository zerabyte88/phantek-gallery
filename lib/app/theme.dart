import 'package:flutter/material.dart';

/// Central theme definitions for Phantek Gallery.
class AppTheme {
  AppTheme._();

  // Brand seed colour—warm sunlight amber.
  static const Color _sunlightSeed = Color(0xFFF59E0B);

  static const _switchTheme = SwitchThemeData(
    overlayColor: WidgetStatePropertyAll(Colors.transparent),
    splashRadius: 0,
  );

  static final _iconButtonTheme = IconButtonThemeData(
    style: IconButton.styleFrom(
      splashFactory: NoSplash.splashFactory,
      overlayColor: Colors.transparent,
      highlightColor: Colors.transparent,
    ),
  );

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _sunlightSeed,
          brightness: Brightness.light,
          primary: const Color(0xFFF59E0B),
          secondary: const Color(0xFFD97706),
          surface: const Color(0xFFFFFFFF),
          outline: const Color(0xFFFDE68A),
          outlineVariant: const Color(0xFFFEF3C7),
        ),
        brightness: Brightness.light,
        splashFactory: InkRipple.splashFactory,
        switchTheme: _switchTheme,
        iconButtonTheme: _iconButtonTheme,
        scaffoldBackgroundColor: const Color(0xFFFFFDF5),
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
          backgroundColor: const Color(0xFF78350F),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFFDE68A)),
          ),
        ),
      );

  static const Color _snowfallSeed = Color(0xFF38BDF8);

  static ThemeData get amoledSnowfall => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _snowfallSeed,
          brightness: Brightness.dark,
          surface: const Color(0xFF0D1830),
          primary: const Color(0xFF38BDF8),
          secondary: const Color(0xFF0284C7),
          outline: const Color(0xFF1F3254),
          outlineVariant: const Color(0xFF1F3254),
        ),
        brightness: Brightness.dark,
        splashFactory: InkRipple.splashFactory,
        switchTheme: _switchTheme,
        iconButtonTheme: _iconButtonTheme,
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
          color: Color(0xFF0D1830),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF0D1830),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF0D1830),
          contentTextStyle:
              const TextStyle(color: Color(0xFFF8FAFC), fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF1F3254)),
          ),
        ),
      );

  static const Color _midnightSeed = Color(0xFFA78BFA);

  static ThemeData get amoledMidnight => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _midnightSeed,
          brightness: Brightness.dark,
          surface: const Color(0xFF130E20),
          primary: const Color(0xFFA78BFA),
          secondary: const Color(0xFF818CF8),
          outline: const Color(0xFF2E2248),
          outlineVariant: const Color(0xFF1F1830),
        ),
        brightness: Brightness.dark,
        splashFactory: InkRipple.splashFactory,
        switchTheme: _switchTheme,
        iconButtonTheme: _iconButtonTheme,
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
          color: Color(0xFF130E20),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF130E20),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF130E20),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF2E2248)),
          ),
        ),
      );

  static ThemeData get dark => amoledSnowfall;
  static ThemeData get amoled => amoledMidnight;

  static const Color _sakuraSeed = Color(0xFFF472B6);

  static ThemeData get amoledSakura => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _sakuraSeed,
          brightness: Brightness.dark,
          surface: const Color(0xFF140D13),
          primary: const Color(0xFFF472B6),
          secondary: const Color(0xFFFDA4AF),
          outline: const Color(0xFF381525),
          outlineVariant: const Color(0xFF220C17),
        ),
        brightness: Brightness.dark,
        splashFactory: InkRipple.splashFactory,
        switchTheme: _switchTheme,
        iconButtonTheme: _iconButtonTheme,
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
          color: Color(0xFF140D13),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF140D13),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF140D13),
          contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF381525)),
          ),
        ),
      );

  static const Color _pureDarkSeed = Color(0xFF3B82F6);

  static ThemeData get amoledPure => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _pureDarkSeed,
          brightness: Brightness.dark,
          surface: const Color(0xFF111620),
          primary: const Color(0xFF3B82F6),
          secondary: const Color(0xFF60A5FA),
          outline: const Color(0xFF283042),
          outlineVariant: const Color(0xFF18181B),
        ),
        brightness: Brightness.dark,
        splashFactory: InkRipple.splashFactory,
        switchTheme: _switchTheme,
        iconButtonTheme: _iconButtonTheme,
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
          color: Color(0xFF111620),
        ),
        dialogTheme: const DialogThemeData(
          backgroundColor: Color(0xFF111620),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: Colors.black,
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: const Color(0xFF111620),
          contentTextStyle:
              const TextStyle(color: Color(0xFFFAFAFA), fontSize: 14),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFF283042)),
          ),
        ),
      );

  static const Color _cleanLightSeed = Color(0xFF2563EB);

  static ThemeData get cleanLight => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: _cleanLightSeed,
          brightness: Brightness.light,
          surface: const Color(0xFFFFFFFF),
          primary: const Color(0xFF2563EB),
          secondary: const Color(0xFF0E7C86),
          outline: const Color(0xFFD5DEEE),
          outlineVariant: const Color(0xFFE6EDF8),
        ),
        brightness: Brightness.light,
        splashFactory: InkRipple.splashFactory,
        switchTheme: _switchTheme,
        iconButtonTheme: _iconButtonTheme,
        scaffoldBackgroundColor: const Color(0xFFEDF2FA),
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
            side: const BorderSide(color: Color(0xFFD5DEEE)),
          ),
        ),
      );
}
