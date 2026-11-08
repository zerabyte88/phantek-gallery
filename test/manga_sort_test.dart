import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/enums/filter_option.dart';
import 'package:phantek_gallery/core/enums/sort_option.dart';
import 'package:phantek_gallery/core/models/album.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/providers/media_provider.dart';

void main() {
  group('Manga Album & Chapter Sorting Tests', () {
    final items = [
      MediaItem(
        id: 'c2_p1',
        path: '/manga/Chapter 2/001.jpg',
        name: '001.jpg',
        album: 'Chapter 2',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      ),
      MediaItem(
        id: 'c1_p2',
        path: '/manga/Chapter 1/002.jpg',
        name: '002.jpg',
        album: 'Chapter 1',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      ),
      MediaItem(
        id: 'c1_p1',
        path: '/manga/Chapter 1/001.jpg',
        name: '001.jpg',
        album: 'Chapter 1',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      ),
      MediaItem(
        id: 'c1.1_p1',
        path: '/manga/Chapter 1.1/001.jpg',
        name: '001.jpg',
        album: 'Chapter 1.1',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      ),
      MediaItem(
        id: 'c10_p1',
        path: '/manga/Chapter 10/001.jpg',
        name: '001.jpg',
        album: 'Chapter 10',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      ),
    ];

    test('SortOption.albumAZ sorts chapters and pages in exact natural reading order', () {
      final sorted = applyFiltersAndSort(
        items,
        sort: SortOption.albumAZ,
        filter: FilterOption.all,
      );

      final order = sorted.map((e) => '${e.albumName}/${e.name}').toList();
      expect(order, [
        'Chapter 1/001.jpg',
        'Chapter 1/002.jpg',
        'Chapter 1.1/001.jpg',
        'Chapter 2/001.jpg',
        'Chapter 10/001.jpg',
      ]);
    });

    test('SortOption.albumZA sorts chapters descending but pages ascending', () {
      final sorted = applyFiltersAndSort(
        items,
        sort: SortOption.albumZA,
        filter: FilterOption.all,
      );

      final order = sorted.map((e) => '${e.albumName}/${e.name}').toList();
      expect(order, [
        'Chapter 10/001.jpg',
        'Chapter 2/001.jpg',
        'Chapter 1.1/001.jpg',
        'Chapter 1/001.jpg',
        'Chapter 1/002.jpg',
      ]);
    });

    test('groupMediaIntoAlbums respects natural album sort', () {
      final albums = groupMediaIntoAlbums(items, sort: SortOption.albumAZ);
      expect(albums.map((a) => a.name).toList(), [
        'Chapter 1',
        'Chapter 1.1',
        'Chapter 2',
        'Chapter 10',
      ]);
    });

    test('SortOption.fromCriterionAndDirection handles album criterion correctly', () {
      expect(
        SortOption.fromCriterionAndDirection(
            SortCriterion.album, SortDirection.ascending),
        SortOption.albumAZ,
      );
      expect(
        SortOption.fromCriterionAndDirection(
            SortCriterion.album, SortDirection.descending),
        SortOption.albumZA,
      );
    });

    test('MediaItem resolves nested parent album for manga with subfolders', () {
      final mangaItem = MediaItem(
        id: 'op_c1_p1',
        path: '/storage/emulated/0/Download/One Piece/Chapter 1/01.jpg',
        name: '01.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
      );

      expect(mangaItem.parentAlbumName, 'One Piece');
      expect(mangaItem.immediateFolderName, 'Chapter 1');
      expect(mangaItem.albumName, 'One Piece');

      final standardItem = MediaItem(
        id: 'dcim_cam_1',
        path: '/storage/emulated/0/DCIM/Camera/IMG_20260101.jpg',
        name: 'IMG_20260101.jpg',
        date: DateTime(2026, 1, 1),
        size: 2048,
        isVideo: false,
      );

      expect(standardItem.parentAlbumName, isNull);
      expect(standardItem.immediateFolderName, 'Camera');
      expect(standardItem.albumName, 'Camera');
    });

    test('groupMediaIntoAlbums groups nested chapters under the parent album', () {
      final mangaPages = [
        MediaItem(
          id: 'p1',
          path: '/storage/emulated/0/Download/Chainsaw Man/Chapter 1/01.jpg',
          name: '01.jpg',
          date: DateTime(2026, 1, 1),
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'p2',
          path: '/storage/emulated/0/Download/Chainsaw Man/Chapter 2/01.jpg',
          name: '01.jpg',
          date: DateTime(2026, 1, 2),
          size: 100,
          isVideo: false,
        ),
      ];

      final albums = groupMediaIntoAlbums(mangaPages);
      expect(albums.length, 1);
      expect(albums.first.name, 'Chainsaw Man');
      expect(albums.first.items.length, 2);
    });
  });
}
