import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/utils/natural_sort.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/manga_folder_picker_sheet.dart';

MediaItem _item({
  required String id,
  required String path,
  required String name,
  bool isVideo = false,
  String? album,
}) {
  return MediaItem(
    id: id,
    path: path,
    name: name,
    date: DateTime(2026, 1, 1),
    size: 1024,
    isVideo: isVideo,
    album: album,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
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
    home: Scaffold(body: child),
  );
}

void main() {
  group('MangaFolderPickerSheet Unit Tests', () {
    test('Filtering excludes videos and PSD files', () {
      final items = [
        _item(
          id: '1',
          path: '/storage/emulated/0/Pictures/Berserk/01.jpg',
          name: '01.jpg',
        ),
        _item(
          id: '2',
          path: '/storage/emulated/0/Pictures/Berserk/trailer.mp4',
          name: 'trailer.mp4',
          isVideo: true,
        ),
        _item(
          id: '3',
          path: '/storage/emulated/0/Pictures/Berserk/cover.psd',
          name: 'cover.psd',
        ),
      ];

      final albums = MangaFolderPickerSheet.groupMangaAlbums(items);
      expect(albums.length, 1);
      expect(albums.first.items.length, 1);
      expect(albums.first.items.first.id, '1');
    });

    test('Grouping and natural sorting of albums', () {
      final items = [
        _item(
          id: 'm10',
          path: '/storage/emulated/0/Pictures/Manga 10/01.jpg',
          name: '01.jpg',
        ),
        _item(
          id: 'm1',
          path: '/storage/emulated/0/Pictures/Manga 1/01.jpg',
          name: '01.jpg',
        ),
        _item(
          id: 'm2',
          path: '/storage/emulated/0/Pictures/Manga 2/01.jpg',
          name: '01.jpg',
        ),
      ];

      final albums = MangaFolderPickerSheet.groupMangaAlbums(items);
      expect(albums.map((e) => e.name).toList(), [
        'Manga 1',
        'Manga 2',
        'Manga 10',
      ]);
    });

    test('Chapter extraction and natural sorting', () {
      final items = [
        _item(
          id: 'b10_1',
          path: '/storage/emulated/0/Manga/Berserk/Chapter 10/01.jpg',
          name: '01.jpg',
        ),
        _item(
          id: 'b1_1',
          path: '/storage/emulated/0/Manga/Berserk/Chapter 1/02.jpg',
          name: '02.jpg',
        ),
        _item(
          id: 'b1_2',
          path: '/storage/emulated/0/Manga/Berserk/Chapter 1/01.jpg',
          name: '01.jpg',
        ),
        _item(
          id: 'b2_1',
          path: '/storage/emulated/0/Manga/Berserk/Chapter 2/01.jpg',
          name: '01.jpg',
        ),
      ];

      final albums = MangaFolderPickerSheet.groupMangaAlbums(items);
      expect(albums.length, 1);
      final berserk = albums.first;
      expect(berserk.name, 'Berserk');
      expect(berserk.subfolders, ['Chapter 1', 'Chapter 2', 'Chapter 10']);
      expect(berserk.items.length, 4);
    });

    test('Flat album produces empty subfolder list', () {
      final items = [
        _item(
          id: 'op1',
          path: '/storage/emulated/0/Pictures/Solo Leveling/01.jpg',
          name: '01.jpg',
        ),
        _item(
          id: 'op2',
          path: '/storage/emulated/0/Pictures/Solo Leveling/02.jpg',
          name: '02.jpg',
        ),
      ];

      final albums = MangaFolderPickerSheet.groupMangaAlbums(items);
      expect(albums.length, 1);
      expect(albums.first.name, 'Solo Leveling');
      expect(albums.first.subfolders, isEmpty);
      expect(albums.first.items.length, 2);
    });

    test('compareMangaCanonical orders by immediate folder then filename', () {
      final items = [
        _item(
          id: '2',
          path: '/storage/emulated/0/Manga/Naruto/Chapter 2/01.jpg',
          name: '01.jpg',
        ),
        _item(
          id: '1_2',
          path: '/storage/emulated/0/Manga/Naruto/Chapter 1/02.jpg',
          name: '02.jpg',
        ),
        _item(
          id: '1_1',
          path: '/storage/emulated/0/Manga/Naruto/Chapter 1/01.jpg',
          name: '01.jpg',
        ),
      ]..sort(compareMangaCanonical);

      expect(items.map((e) => e.id).toList(), ['1_1', '1_2', '2']);
    });
  });

  group('MangaFolderPickerSheet Widget Tests', () {
    final testItems = [
      _item(
        id: 'b1_1',
        path: '/storage/emulated/0/Manga/Berserk/Chapter 1/01.jpg',
        name: '01.jpg',
      ),
      _item(
        id: 'b2_1',
        path: '/storage/emulated/0/Manga/Berserk/Chapter 2/01.jpg',
        name: '01.jpg',
      ),
      _item(
        id: 'b2_2',
        path: '/storage/emulated/0/Manga/Berserk/Chapter 2/02.jpg',
        name: '02.jpg',
      ),
      _item(
        id: 'op1',
        path: '/storage/emulated/0/Pictures/Solo Leveling/01.jpg',
        name: '01.jpg',
      ),
      _item(
        id: 'op2',
        path: '/storage/emulated/0/Pictures/Solo Leveling/02.jpg',
        name: '02.jpg',
      ),
    ];

    testWidgets('Renders header, counts, search bar, and manga tiles',
        (tester) async {
      await tester.pumpWidget(_wrap(MangaFolderPickerSheet(items: testItems)));
      await tester.pumpAndSettle();

      // Header title and count
      expect(find.text('Read Manga'), findsOneWidget);
      expect(find.text('2 manga folders'), findsOneWidget);

      // Search bar
      expect(find.byKey(const ValueKey('manga_picker_search_field')),
          findsOneWidget);

      // Albums
      expect(find.text('Berserk'), findsOneWidget);
      expect(find.text('2 Chapters • 3 pages'), findsOneWidget);

      expect(find.text('Solo Leveling'), findsOneWidget);
      expect(find.text('2 pages'), findsOneWidget);
    });

    testWidgets('Selection callback on flat album', (tester) async {
      List<MediaItem>? selectedItems;
      int? selectedIndex;

      await tester.pumpWidget(
        _wrap(
          MangaFolderPickerSheet(
            items: testItems,
            onSelectChapter: (items, index) {
              selectedItems = items;
              selectedIndex = index;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Solo Leveling'));
      await tester.pump();

      expect(selectedItems, isNotNull);
      expect(selectedItems!.length, 2);
      expect(selectedItems!.map((e) => e.name).toList(), ['01.jpg', '02.jpg']);
      expect(selectedIndex, 0);
    });

    testWidgets('Selection callback on specific chapter', (tester) async {
      List<MediaItem>? selectedItems;
      int? selectedIndex;

      await tester.pumpWidget(
        _wrap(
          MangaFolderPickerSheet(
            items: testItems,
            onSelectChapter: (items, index) {
              selectedItems = items;
              selectedIndex = index;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Berserk
      await tester.tap(find.text('Berserk'));
      await tester.pumpAndSettle();

      expect(find.text('Read All Chapters (3 pages)'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Chapter 1'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'Chapter 2'), findsOneWidget);

      // Select specific chapter (Chapter 2)
      await tester.tap(find.widgetWithText(ListTile, 'Chapter 2'));
      await tester.pump();

      expect(selectedItems, isNotNull);
      expect(selectedItems!.length, 2);
      expect(selectedItems!.every((e) => e.immediateFolderName == 'Chapter 2'),
          isTrue);
      expect(selectedIndex, 0);
    });

    testWidgets('Selection callback on Read All Chapters', (tester) async {
      List<MediaItem>? selectedItems;
      int? selectedIndex;

      await tester.pumpWidget(
        _wrap(
          MangaFolderPickerSheet(
            items: testItems,
            onSelectChapter: (items, index) {
              selectedItems = items;
              selectedIndex = index;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Expand Berserk
      await tester.tap(find.text('Berserk'));
      await tester.pumpAndSettle();

      // Tap Read All Chapters
      await tester.tap(find.text('Read All Chapters (3 pages)'));
      await tester.pump();

      expect(selectedItems, isNotNull);
      expect(selectedItems!.length, 3);
      expect(selectedIndex, 0);
    });

    testWidgets('Search bar filters by title and chapter name', (tester) async {
      await tester.pumpWidget(_wrap(MangaFolderPickerSheet(items: testItems)));
      await tester.pumpAndSettle();

      // Search by manga title
      await tester.enterText(
          find.byKey(const ValueKey('manga_picker_search_field')), 'Solo');
      await tester.pumpAndSettle();

      expect(find.text('Solo Leveling'), findsOneWidget);
      expect(find.text('Berserk'), findsNothing);

      // Search by chapter name
      await tester.enterText(
          find.byKey(const ValueKey('manga_picker_search_field')), 'Chapter 1');
      await tester.pumpAndSettle();

      expect(find.text('Berserk'), findsOneWidget);
      expect(find.text('Solo Leveling'), findsNothing);
      expect(find.widgetWithText(ListTile, 'Chapter 1'), findsOneWidget);

      // No matches
      await tester.enterText(
          find.byKey(const ValueKey('manga_picker_search_field')),
          'Nonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No manga matching "Nonexistent"'), findsOneWidget);

      // Clear search
      await tester.tap(find.byKey(const ValueKey('manga_picker_clear_search')));
      await tester.pumpAndSettle();

      expect(find.text('Berserk'), findsOneWidget);
      expect(find.text('Solo Leveling'), findsOneWidget);
    });

    testWidgets(
        'MangaFolderPickerSheet.show with empty list displays feedback pill',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MangaFolderPickerSheet.show(
                context,
                allItems: const [],
              ),
              child: const Text('Open Manga Picker'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Manga Picker'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      expect(find.text('No photos found'), findsOneWidget);
      expect(find.byType(MangaFolderPickerSheet), findsNothing);

      // Drain dismissal timer
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('Close button dismisses sheet', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => MangaFolderPickerSheet.show(
                context,
                allItems: testItems,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byType(MangaFolderPickerSheet), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('manga_picker_close_button')));
      await tester.pumpAndSettle();
      expect(find.byType(MangaFolderPickerSheet), findsNothing);
    });
  });
}
