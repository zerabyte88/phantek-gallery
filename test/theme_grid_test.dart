// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/features/settings/presentation/widgets/modern_theme_grid.dart';

void main() {
  Widget buildTestWidget({
    required AppThemeMode currentTheme,
    required ValueChanged<AppThemeMode> onThemeSelected,
    Brightness brightness = Brightness.dark,
    Locale locale = const Locale('en'),
    double screenWidth = 400,
  }) {
    return MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
      ),
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('en'),
        Locale('id'),
      ],
      home: MediaQuery(
        data: MediaQueryData(size: Size(screenWidth, 800)),
        child: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(12),
            child: ModernThemeGrid(
              currentTheme: currentTheme,
              onThemeSelected: onThemeSelected,
            ),
          ),
        ),
      ),
    );
  }

  group('ModernThemeGrid Tests', () {
    testWidgets('Renders all 7 theme cards and badges correctly', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          currentTheme: AppThemeMode.system,
          onThemeSelected: (_) {},
        ),
      );
      await tester.pumpAndSettle();

      // Check badges: 1 Auto, 2 Static, 4 Live
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Static'), findsNWidgets(2));
      expect(find.text('Live'), findsNWidgets(4));

      // Check icons
      expect(find.byIcon(Icons.brightness_auto_rounded), findsOneWidget);
      expect(find.byIcon(Icons.light_mode_rounded), findsOneWidget);
      expect(find.byIcon(Icons.dark_mode_rounded), findsOneWidget);
      expect(find.byIcon(Icons.ac_unit_rounded), findsOneWidget);
      expect(find.byIcon(Icons.wb_sunny_rounded), findsOneWidget);
      expect(find.byIcon(Icons.nights_stay_rounded), findsOneWidget);
      expect(find.byIcon(Icons.local_florist_rounded), findsOneWidget);

      // Check localized titles (English)
      expect(find.text('System'), findsOneWidget);
      expect(find.text('Light Mode'), findsOneWidget);
      expect(find.text('Dark Mode'), findsOneWidget);
      expect(find.text('Snowfall'), findsOneWidget);
      expect(find.text('Sunlight'), findsOneWidget);
      expect(find.text('Midnight'), findsOneWidget);
      expect(find.text('Sakura'), findsOneWidget);
    });

    testWidgets('Tapping on a theme card fires onThemeSelected callback', (tester) async {
      AppThemeMode? selectedMode;

      await tester.pumpWidget(
        buildTestWidget(
          currentTheme: AppThemeMode.system,
          onThemeSelected: (mode) => selectedMode = mode,
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Midnight
      await tester.tap(find.byIcon(Icons.nights_stay_rounded));
      await tester.pumpAndSettle();
      expect(selectedMode, AppThemeMode.amoledMidnight);

      // Tap on Clean Light
      await tester.tap(find.byIcon(Icons.light_mode_rounded));
      await tester.pumpAndSettle();
      expect(selectedMode, AppThemeMode.cleanLight);

      // Tap on Sakura
      await tester.tap(find.byIcon(Icons.local_florist_rounded));
      await tester.pumpAndSettle();
      expect(selectedMode, AppThemeMode.amoledSakura);
    });

    testWidgets('Adapts to Indonesian localization seamlessly', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          currentTheme: AppThemeMode.system,
          onThemeSelected: (_) {},
          locale: const Locale('id'),
        ),
      );
      await tester.pumpAndSettle();

      // Indonesian localized titles
      expect(find.text('Sistem'), findsOneWidget);
      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Static'), findsNWidgets(2));
      expect(find.text('Live'), findsNWidgets(4));
    });

    testWidgets('Renders properly without overflow on compact screens', (tester) async {
      await tester.pumpWidget(
        buildTestWidget(
          currentTheme: AppThemeMode.amoledSnowfall,
          onThemeSelected: (_) {},
          screenWidth: 320, // narrow screen
          brightness: Brightness.light,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(ModernThemeGrid), findsOneWidget);
    });
  });
}
