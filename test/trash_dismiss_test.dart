import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phantek_gallery/core/models/trash_item.dart';
import 'package:phantek_gallery/features/trash/presentation/trash_screen.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart';
import 'package:phantek_gallery/core/providers/trash_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phantek_gallery/app/router.dart';

class _FakeTrashNotifier extends TrashNotifier {
  _FakeTrashNotifier(this._items);
  final List<TrashItem> _items;

  @override
  Future<List<TrashItem>> build() async => _items;
}

void main() {
  testWidgets(
      'Trash grid items contain Hero widgets matching item.id for in and out transitions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    final testItems = [
      TrashItem(
        id: 'trash_photo_1',
        originalPath: '/original/photo1.jpg',
        trashPath: '/trash/photo1.jpg',
        name: 'photo1.jpg',
        deletedDate: DateTime.now(),
        isVideo: false,
      ),
      TrashItem(
        id: 'trash_video_1',
        originalPath: '/original/video1.mp4',
        trashPath: '/trash/video1.mp4',
        name: 'video1.mp4',
        deletedDate: DateTime.now(),
        isVideo: true,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trashProvider.overrideWith(() => _FakeTrashNotifier(testItems)),
        ],
        child: const MaterialApp(
          localizationsDelegates: [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: TrashScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify TrashScreen displays grid items
    expect(find.byType(TrashScreen), findsOneWidget);

    // Find Heroes in TrashScreen
    final heroesInTrash = tester
        .widgetList<Hero>(find.descendant(
            of: find.byType(TrashScreen), matching: find.byType(Hero)))
        .toList();

    // The grid items must have Hero widgets with tag matching trash item IDs
    final heroTags = heroesInTrash.map((h) => h.tag).toList();
    expect(heroTags.contains('trash_photo_1'), isTrue,
        reason:
            'trash_photo_1 should have a Hero widget for flight in/out animation');
    expect(heroTags.contains('trash_video_1'), isTrue,
        reason:
            'trash_video_1 should have a Hero widget for flight in/out animation');
  });

  testWidgets(
      'Tapping trash photo opens viewer with Hero and swipe down dismisses back to trash grid',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.init();

    final testItems = [
      TrashItem(
        id: 'trash_photo_1',
        originalPath: '/original/photo1.jpg',
        trashPath: '/trash/photo1.jpg',
        name: 'photo1.jpg',
        deletedDate: DateTime.now(),
        isVideo: false,
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          trashProvider.overrideWith(() => _FakeTrashNotifier(testItems)),
        ],
        child: MaterialApp(
          navigatorKey: rootNavigatorKey,
          onGenerateRoute: generateRoute,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: const TrashScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // 1. Verify grid item is present
    expect(find.byType(TrashScreen), findsOneWidget);
    final heroInGrid = find.descendant(
      of: find.byType(TrashScreen),
      matching:
          find.byWidgetPredicate((w) => w is Hero && w.tag == 'trash_photo_1'),
    );
    expect(heroInGrid, findsOneWidget);

    // 2. Tap grid item to open preview
    await tester.tap(heroInGrid);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // Viewer is opened and active Hero has 'trash_photo_1'
    expect(find.byType(ImageViewerScreen), findsOneWidget);
    final heroInViewer = find.descendant(
      of: find.byType(ImageViewerScreen),
      matching:
          find.byWidgetPredicate((w) => w is Hero && w.tag == 'trash_photo_1'),
    );
    expect(heroInViewer, findsOneWidget);

    // 3. Swipe down to dismiss
    await tester.drag(find.byType(ImageViewerScreen), const Offset(0, 150));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    // 4. Viewer should be popped and TrashScreen visible again with Hero on grid
    expect(find.byType(ImageViewerScreen), findsNothing);
    expect(find.byType(TrashScreen), findsOneWidget);
    expect(heroInGrid, findsOneWidget);
  });
}
