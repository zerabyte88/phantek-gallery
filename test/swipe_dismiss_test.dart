import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/media_grid_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';

void main() {
  testWidgets(
      'Swipe to dismiss retains active item page and Hero tag instead of resetting to initial item',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    final items = [
      MediaItem(
          id: 'itemA',
          path: '/test/a.jpg',
          name: 'a.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
      MediaItem(
          id: 'itemB',
          path: '/test/b.jpg',
          name: 'b.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
      MediaItem(
          id: 'itemC',
          path: '/test/c.jpg',
          name: 'c.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3),
                itemCount: items.length,
                itemBuilder: (ctx, i) => MediaGridItem(
                  key: ValueKey(items[i].id),
                  item: items[i],
                  isSelected: false,
                  isSelecting: false,
                  showBadges: false,
                  onTap: () {
                    Navigator.of(context).push(
                      PageRouteBuilder(
                        opaque: false,
                        barrierColor: Colors.transparent,
                        pageBuilder: (_, __, ___) =>
                            ImageViewerScreen(items: items, initialIndex: i),
                        transitionsBuilder: (_, __, ___, child) => child,
                        transitionDuration: const Duration(milliseconds: 300),
                        reverseTransitionDuration:
                            const Duration(milliseconds: 300),
                      ),
                    );
                  },
                  onLongPress: () {},
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 1. Tap itemA to open viewer
    await tester.tap(find.byKey(const ValueKey('itemA')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(ImageViewerScreen), findsOneWidget);

    // 2. Swipe horizontally from itemA -> itemB -> itemC
    final pageViewFinder = find.byType(PageView);
    expect(pageViewFinder, findsOneWidget);

    await tester.drag(pageViewFinder, const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    await tester.drag(pageViewFinder, const Offset(-500, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Verify itemC is the active item in ImageViewerScreen
    final viewerHeroes = tester
        .widgetList<Hero>(find.descendant(
            of: find.byType(ImageViewerScreen), matching: find.byType(Hero)))
        .map((h) => h.tag)
        .toList();
    expect(viewerHeroes.contains('itemC'), isTrue);
    expect(viewerHeroes.contains('itemA'), isFalse);

    // 3. Drag down to trigger swipe-to-dismiss (dy > 85)
    await tester.drag(find.byType(ImageViewerScreen), const Offset(0, 150));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // While popping, the PageView must remain on itemC (page ~ 2.0), not reset to page 0 (itemA)
    final pvs = find.byType(PageView);
    if (pvs.evaluate().isNotEmpty) {
      final pvWidget = tester.widget<PageView>(pvs.first);
      final page = pvWidget.controller?.page ?? 0.0;
      expect(page, greaterThanOrEqualTo(1.8));
    }

    await tester.pump(const Duration(milliseconds: 350));

    // Viewer is dismissed
    expect(find.byType(ImageViewerScreen), findsNothing);
  });

  testWidgets(
      'Rapid swipe followed immediately by downward dismiss pops the currently active item without skipping to adjacent next item',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    final items = [
      MediaItem(
          id: 'item1',
          path: '/test/1.jpg',
          name: '1.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
      MediaItem(
          id: 'item2',
          path: '/test/2.jpg',
          name: '2.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
      MediaItem(
          id: 'item3',
          path: '/test/3.jpg',
          name: '3.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.transparent,
                      pageBuilder: (_, __, ___) =>
                          ImageViewerScreen(items: items, initialIndex: 0),
                      transitionsBuilder: (_, __, ___, child) => child,
                      transitionDuration: const Duration(milliseconds: 300),
                      reverseTransitionDuration:
                          const Duration(milliseconds: 300),
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.byType(ImageViewerScreen), findsOneWidget);

    // Swipe horizontally to item2 (test screen width is 800)
    final pageView = find.byType(PageView);
    await tester.drag(pageView, const Offset(-800, 0));
    await tester.pumpAndSettle();

    // Verify item2 is active
    final heroesAt2 = tester
        .widgetList<Hero>(find.descendant(
            of: find.byType(ImageViewerScreen), matching: find.byType(Hero)))
        .map((h) => h.tag)
        .toList();
    expect(heroesAt2.contains('item2'), isTrue);
    expect(heroesAt2.contains('item3'), isFalse);

    // Fast diagonal downward flick (natural thumb arc with negative dx)
    await tester.drag(
        find.byType(ImageViewerScreen), const Offset(-30, 200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    // While popping, the active item MUST remain item2 and NOT advance to item3
    final pvs = find.byType(PageView);
    if (pvs.evaluate().isNotEmpty) {
      final pvWidget = tester.widget<PageView>(pvs.first);
      final page = pvWidget.controller?.page ?? 1.0;
      expect(page, closeTo(1.0, 0.2));
    }

    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerScreen), findsNothing);
  });

  testWidgets(
      'Consecutive rapid horizontal swipes land on expected page without being blocked',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    final items = [
      MediaItem(
          id: 'item1',
          path: '/test/1.jpg',
          name: '1.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
      MediaItem(
          id: 'item2',
          path: '/test/2.jpg',
          name: '2.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
      MediaItem(
          id: 'item3',
          path: '/test/3.jpg',
          name: '3.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
      MediaItem(
          id: 'item4',
          path: '/test/4.jpg',
          name: '4.jpg',
          date: DateTime.now(),
          size: 100,
          isVideo: false),
    ];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    PageRouteBuilder(
                      opaque: false,
                      barrierColor: Colors.transparent,
                      pageBuilder: (_, __, ___) =>
                          ImageViewerScreen(items: items, initialIndex: 0),
                      transitionsBuilder: (_, __, ___, child) => child,
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    final pageView = find.byType(PageView);
    expect(pageView, findsOneWidget);

    // Rapid horizontal swipe 1: item 0 -> item 1
    await tester.drag(pageView, const Offset(-800, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Rapid horizontal swipe 2: item 1 -> item 2
    await tester.drag(pageView, const Offset(-800, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Rapid horizontal swipe 3: item 2 -> item 3
    await tester.drag(pageView, const Offset(-800, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final heroesAt3 = tester
        .widgetList<Hero>(find.descendant(
            of: find.byType(ImageViewerScreen), matching: find.byType(Hero)))
        .map((h) => h.tag)
        .toList();
    expect(heroesAt3.contains('item4'), isTrue);
  });
}
