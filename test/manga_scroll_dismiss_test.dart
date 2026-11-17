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
      id: 'page_$i',
      path: '/mock/manga/page_$i.jpg',
      name: 'page_$i.jpg',
      album: 'My Manga',
      date: DateTime(2026, 1, i + 1),
      isVideo: false,
      size: 1024 * 1024,
    ),
  );

  Widget buildViewer({bool mangaMode = false, List<MediaItem>? items}) {
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
          items: items ?? testItems,
          initialIndex: 0,
          initialMangaMode: mangaMode,
        ),
      ),
    );
  }

  group('Manga Mode Scroll Gesture Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();
    });

    testWidgets(
        'Downward scroll/drag in Manga Mode does NOT trigger dismiss pop',
        (tester) async {
      await tester.pumpWidget(buildViewer(mangaMode: true));
      await tester.pumpAndSettle();

      // Verify Manga mode is active with PageView
      expect(find.byType(PageView), findsOneWidget);
      expect(find.byType(ImageViewerScreen), findsOneWidget);

      // Perform downward drag gesture (which simulates scrolling up towards page 1)
      final center = tester.getCenter(find.byType(PageView));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();

      // Screen must still be present during drag
      expect(find.byType(ImageViewerScreen), findsOneWidget);

      // Release pointer with high velocity
      await gesture.up();
      await tester.pumpAndSettle();

      // Screen MUST NOT be popped
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('Downward drag in standard photo mode triggers dismiss pop',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProviderScope(
                      child: ImageViewerScreen(
                        items: testItems,
                        initialIndex: 0,
                        initialMangaMode: false,
                      ),
                    ),
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ));

      // Open viewer
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);

      // Drag down in standard mode
      final center = tester.getCenter(find.byType(PageView));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(0, 300));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      // In standard mode, downward drag popped the screen back to base
      expect(find.byType(ImageViewerScreen), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets(
        'Manga Mode displays separate manga title and animates page pill from top-center to top-left on focus',
        (tester) async {
      await tester.pumpWidget(buildViewer(mangaMode: true));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // 1. Action buttons in footer MUST NOT be present in Manga Mode
      expect(find.byIcon(Icons.share_outlined), findsNothing);
      expect(find.byIcon(Icons.favorite_border), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);

      // 2. Manga title is displayed in header separately from page number
      expect(find.text('My Manga'), findsOneWidget);
      expect(find.text('page_0.jpg'), findsOneWidget);

      // 3. Page counter pill has its own distinct text (not combined)
      expect(find.text('1 / 5'), findsOneWidget);

      // 4. Initially, pill is aligned at top center
      final alignFinder = find.ancestor(
        of: find.text('1 / 5'),
        matching: find.byType(AnimatedAlign),
      );
      expect(alignFinder, findsOneWidget);
      AnimatedAlign alignWidget = tester.widget<AnimatedAlign>(alignFinder);
      expect(alignWidget.alignment, Alignment.topCenter);

      // 5. Tap once on the screen to focus (hide header and footer)
      await tester.tap(find.byType(PageView));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Page pill now animates to top-left (kiri atas)
      alignWidget = tester.widget<AnimatedAlign>(alignFinder);
      expect(alignWidget.alignment, Alignment.topLeft);
      expect(find.text('1 / 5'), findsOneWidget);

      // 6. Tap again to bring bars back
      await tester.tap(find.byType(PageView));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Page pill animates back to top-center
      alignWidget = tester.widget<AnimatedAlign>(alignFinder);
      expect(alignWidget.alignment, Alignment.topCenter);
      expect(find.text('1 / 5'), findsOneWidget);
    });

    testWidgets(
        '74-item manga reader initializes at 1 / 74 and displays 74 / 74 at bottom',
        (tester) async {
      final items74 = List.generate(
        74,
        (i) => MediaItem(
          id: 'page_$i',
          path: '/mock/manga/page_$i.jpg',
          name: 'page_${i.toString().padLeft(3, '0')}.jpg',
          album: '74 Chapter Manga',
          date: DateTime(2026, 1, 1),
          isVideo: false,
          size: 1024 * 1024,
          width: 800,
          height: 1200,
        ),
      );

      await tester.pumpWidget(buildViewer(mangaMode: true, items: items74));
      await tester.pumpAndSettle();

      // Verify initial state
      expect(find.text('1 / 74'), findsOneWidget);

      // Scroll to bottom
      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      while (scrollable.position.pixels < scrollable.position.maxScrollExtent) {
        final prev = scrollable.position.pixels;
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();
        if (scrollable.position.pixels == prev) break;
      }
      await tester.pumpAndSettle();

      // Verify 74 / 74 is displayed at bottom
      expect(find.text('74 / 74'), findsOneWidget);
    });

    testWidgets('169-item manga reader at maxScrollExtent displays 169 / 169',
        (tester) async {
      final items169 = List.generate(
        169,
        (i) => MediaItem(
          id: 'page_$i',
          path: '/mock/manga/page_$i.jpg',
          name: 'page_${i.toString().padLeft(3, '0')}.jpg',
          album: '169 Chapter Manga',
          date: DateTime(2026, 1, 1),
          isVideo: false,
          size: 1024 * 1024,
          width: 800,
          height: 1200,
        ),
      );

      await tester.pumpWidget(buildViewer(mangaMode: true, items: items169));
      await tester.pumpAndSettle();

      expect(find.text('1 / 169'), findsOneWidget);

      final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
      while (scrollable.position.pixels < scrollable.position.maxScrollExtent) {
        final prev = scrollable.position.pixels;
        scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
        await tester.pump();
        if (scrollable.position.pixels == prev) break;
      }
      await tester.pumpAndSettle();

      expect(find.text('169 / 169'), findsOneWidget);
    });

    testWidgets(
        'Manga Mode double-tap zoom cycles 1.0x -> 3.0x -> 1.0x without popping',
        (tester) async {
      await tester.pumpWidget(buildViewer(mangaMode: true));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(find.text('1.0x'), findsOneWidget);

      final center = tester.getCenter(find.byType(PageView));

      // Double-tap 1 -> 3.0x
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('3.0x'), findsOneWidget);
      expect(find.text('4.0x'), findsNothing);

      // Double-tap 2 -> reset back to 1.0x (never zooms beyond 3.0x)
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();

      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets(
        'Manga Mode per-panel zoom pill buttons zoom in, zoom out, and reset cleanly',
        (tester) async {
      await tester.pumpWidget(buildViewer(mangaMode: true));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      final zoomIn = find.byKey(const ValueKey('manga_zoom_in_button'));
      final zoomOut = find.byKey(const ValueKey('manga_zoom_out_button'));
      final zoomReset = find.byKey(const ValueKey('manga_zoom_reset_button'));

      expect(zoomIn, findsOneWidget);
      expect(zoomOut, findsOneWidget);
      expect(zoomReset, findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);

      // Zoom in once -> 1.5x
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);

      // Zoom in again -> ~2.3x
      await tester.tap(zoomIn);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('1.0x'), findsNothing);
      expect(find.text('1.5x'), findsNothing);

      // Zoom out -> ~1.5x
      await tester.tap(zoomOut);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('1.5x'), findsOneWidget);

      // Tap reset badge -> 1.0x
      await tester.tap(zoomReset);
      await tester.pumpAndSettle();
      expect(find.byType(ImageViewerScreen), findsOneWidget);
      expect(find.text('1.0x'), findsOneWidget);
    });

    testWidgets(
        'Manga translating indicator renders centered Column with spinner above outlined text and no pill container',
        (tester) async {
      const label = 'Translating page...';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: buildTranslatingIndicatorForTest(label),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 150));

      final indicatorFinder =
          find.byKey(const ValueKey('manga_translating_indicator'));
      expect(indicatorFinder, findsOneWidget);

      final column = tester.widget<Column>(indicatorFinder);
      expect(column.mainAxisSize, MainAxisSize.min);
      expect(column.mainAxisAlignment, MainAxisAlignment.center);
      expect(column.crossAxisAlignment, CrossAxisAlignment.center);

      // Centered in parent
      expect(
        find.ancestor(
          of: indicatorFinder,
          matching: find.byType(Center),
        ),
        findsOneWidget,
      );

      // No horizontal Row and no pill Container / BoxDecoration / Border
      expect(
        find.descendant(of: indicatorFinder, matching: find.byType(Row)),
        findsNothing,
      );
      expect(
        find.descendant(of: indicatorFinder, matching: find.byType(Container)),
        findsNothing,
      );
      expect(
        find.descendant(
            of: indicatorFinder, matching: find.byType(DecoratedBox)),
        findsNothing,
      );

      // Spinner CustomPaint inside 28x28 SizedBox strictly above outlined text Stack
      final spinnerFinder = find.descendant(
        of: indicatorFinder,
        matching: find.byType(CustomPaint),
      );
      final textStackFinder = find.descendant(
        of: indicatorFinder,
        matching: find.byType(Stack),
      );
      expect(spinnerFinder, findsOneWidget);
      expect(textStackFinder, findsOneWidget);
      expect(tester.getSize(spinnerFinder), const Size(28, 28));

      final spinnerRect = tester.getRect(spinnerFinder);
      final textRect = tester.getRect(textStackFinder);
      expect(spinnerRect.bottom, lessThan(textRect.top));
      expect((spinnerRect.center.dx - textRect.center.dx).abs(), lessThan(1.0));

      // Outlined text has stroke (ExcludeSemantics) + fill layers
      expect(
        find.descendant(of: textStackFinder, matching: find.text(label)),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: textStackFinder,
          matching: find.byType(ExcludeSemantics),
        ),
        findsOneWidget,
      );

      // Pump additional animation frames cleanly without layout/overflow errors
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });
  });
}
