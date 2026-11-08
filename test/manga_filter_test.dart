import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/services/psd_service.dart';
import 'package:phantek_gallery/core/utils/natural_sort.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/media_grid_item.dart';

void main() {
  group('Manga Mode Video and PSD Exclusion Tests', () {
    final sampleItems = [
      MediaItem(
        id: '1',
        path: '/storage/emulated/0/DCIM/video_01.mp4',
        name: 'video_01.mp4',
        album: 'MangaCollection',
        date: DateTime(2026, 1, 1),
        size: 1024 * 1024,
        isVideo: true,
      ),
      MediaItem(
        id: '2',
        path: '/storage/emulated/0/Pictures/artwork.psd',
        name: 'artwork.psd',
        album: 'MangaCollection',
        date: DateTime(2026, 1, 1),
        size: 5 * 1024 * 1024,
        isVideo: false,
      ),
      MediaItem(
        id: '3',
        path: '/storage/emulated/0/Pictures/chapter_01/page_02.png',
        name: 'page_02.png',
        album: 'MangaCollection',
        date: DateTime(2026, 1, 1),
        size: 500 * 1024,
        isVideo: false,
      ),
      MediaItem(
        id: '4',
        path: '/storage/emulated/0/Pictures/chapter_01/page_01.jpg',
        name: 'page_01.jpg',
        album: 'MangaCollection',
        date: DateTime(2026, 1, 1),
        size: 450 * 1024,
        isVideo: false,
      ),
      MediaItem(
        id: '5',
        path: '/storage/emulated/0/Pictures/clip.mkv',
        name: 'clip.mkv',
        album: 'MangaCollection',
        date: DateTime(2026, 1, 1),
        size: 10 * 1024 * 1024,
        isVideo: true,
      ),
      MediaItem(
        id: '6',
        path: '/storage/emulated/0/Pictures/cover.PSD',
        name: 'cover.PSD',
        album: 'MangaCollection',
        date: DateTime(2026, 1, 1),
        size: 2 * 1024 * 1024,
        isVideo: false,
      ),
    ];

    test('Filters out all videos and PSD files (including uppercase extensions)', () {
      final mangaFiltered = sampleItems
          .where((e) => !e.isVideo && !PsdService.isPsd(e.path))
          .toList();

      expect(mangaFiltered.length, 2);
      expect(mangaFiltered.every((e) => !e.isVideo), isTrue);
      expect(mangaFiltered.every((e) => !PsdService.isPsd(e.path)), isTrue);
      expect(mangaFiltered.map((e) => e.name).toList(), containsAll(['page_01.jpg', 'page_02.png']));
    });

    test('compareMangaCanonical correctly sorts filtered manga pages naturally', () {
      final mangaFiltered = sampleItems
          .where((e) => !e.isVideo && !PsdService.isPsd(e.path))
          .toList()
        ..sort(compareMangaCanonical);

      expect(mangaFiltered[0].name, 'page_01.jpg');
      expect(mangaFiltered[1].name, 'page_02.png');
    });

    test('Returns empty list when collection contains only videos and PSDs', () {
      final nonMangaOnly = [
        sampleItems[0], // video
        sampleItems[1], // psd
        sampleItems[4], // video
        sampleItems[5], // PSD
      ];

      final filtered = nonMangaOnly
          .where((e) => !e.isVideo && !PsdService.isPsd(e.path))
          .toList();

      expect(filtered.isEmpty, isTrue);
    });

    test('compareMangaCanonical sorts chapters by folder name first, then filename', () {
      final multiChapterItems = [
        MediaItem(
          id: 'c2_p1',
          path: '/manga/Chapter 2/01.jpg',
          name: '01.jpg',
          album: 'Manga',
          date: DateTime(2026, 1, 1),
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'c1_p2',
          path: '/manga/Chapter 1/02.jpg',
          name: '02.jpg',
          album: 'Manga',
          date: DateTime(2026, 1, 1),
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'c1_p1',
          path: '/manga/Chapter 1/01.jpg',
          name: '01.jpg',
          album: 'Manga',
          date: DateTime(2026, 1, 1),
          size: 100,
          isVideo: false,
        ),
      ];

      final sorted = [...multiChapterItems]..sort(compareMangaCanonical);

      expect(sorted[0].id, 'c1_p1');
      expect(sorted[1].id, 'c1_p2');
      expect(sorted[2].id, 'c2_p1');
    });
  });

  group('MediaGridItem PSD Badge Tests', () {
    testWidgets('MediaGridItem renders PSD badge in bottom-right when showBadges is true', (tester) async {
      final psdItem = MediaItem(
        id: 'psd_item_1',
        path: '/storage/sample.psd',
        name: 'sample.psd',
        album: 'Artwork',
        date: DateTime(2026, 1, 1),
        size: 2048,
        isVideo: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGridItem(
              item: psdItem,
              isSelected: false,
              isSelecting: false,
              showBadges: true,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      expect(find.text('PSD'), findsOneWidget);
    });

    testWidgets('MediaGridItem does NOT render PSD badge when showBadges is false', (tester) async {
      final psdItem = MediaItem(
        id: 'psd_item_2',
        path: '/storage/sample.psd',
        name: 'sample.psd',
        album: 'Artwork',
        date: DateTime(2026, 1, 1),
        size: 2048,
        isVideo: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGridItem(
              item: psdItem,
              isSelected: false,
              isSelecting: false,
              showBadges: false,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      expect(find.text('PSD'), findsNothing);
    });

    testWidgets('MediaGridItem does NOT render PSD badge for non-PSD images', (tester) async {
      final imageItem = MediaItem(
        id: 'img_item_1',
        path: '/storage/sample.jpg',
        name: 'sample.jpg',
        album: 'Camera',
        date: DateTime(2026, 1, 1),
        size: 2048,
        isVideo: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGridItem(
              item: imageItem,
              isSelected: false,
              isSelecting: false,
              showBadges: true,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      expect(find.text('PSD'), findsNothing);
    });
  });
}
