// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final testItems = List.generate(
    5,
    (i) => MediaItem(
      id: 'img_$i',
      path: '/mock/path/img_$i.jpg',
      name: 'img_$i.jpg',
      date: DateTime(2026, 1, i + 1),
      isVideo: false,
      size: 1024 * 1024,
    ),
  );

  Widget buildViewer({int initialIndex = 0}) {
    return ProviderScope(
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('id')],
        home: ImageViewerScreen(
          items: testItems,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  group('Swipe-to-Dismiss Multi-Image Elimination Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();
    });

    testWidgets(
        'During downward drag-to-dismiss, adjacent pages are hidden and only current item is rendered',
        (tester) async {
      await tester.pumpWidget(buildViewer(initialIndex: 1));
      await tester.pumpAndSettle();

      // At rest, current item (img_1) has an active Hero
      expect(find.byType(Hero), findsOneWidget);

      // Begin downward drag (swipe-to-dismiss)
      final center = tester.getCenter(find.byType(PageView));
      final gesture = await tester.startGesture(center);

      // Drag downward by 60px (initiates _isDraggingDown)
      await gesture.moveBy(const Offset(0, 60));
      await tester.pump();

      // Verify that Hero for current item is still active
      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final heroWidget = tester.widget<Hero>(heroFinder);
      expect(heroWidget.tag, 'img_1');

      // Release gesture without reaching dismiss threshold
      await gesture.up();
      await tester.pumpAndSettle();

      // Restored smoothly
      expect(find.byType(Hero), findsOneWidget);
    });

    testWidgets(
        'Fast swipe followed by dismiss pop correctly snaps to target and excludes neighbors',
        (tester) async {
      await tester.pumpWidget(buildViewer(initialIndex: 0));
      await tester.pumpAndSettle();

      // Fling left to switch to page 1
      await tester.fling(find.byType(PageView), const Offset(-300, 0), 1000);
      await tester.pumpAndSettle();

      // Verify we are at img_1
      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, 'img_1');

      // Initiate downward swipe dismiss
      final center = tester.getCenter(find.byType(PageView));
      final gesture = await tester.startGesture(center);
      // Downward drag past dismiss threshold
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();

      // Exactly ONE Hero tag in flight, no ghost neighbor
      expect(find.byType(Hero), findsOneWidget);
      expect(tester.widget<Hero>(find.byType(Hero)).tag, 'img_1');

      await gesture.up();
      await tester.pumpAndSettle();
    });
  });
}
