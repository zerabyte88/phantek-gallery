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
  });
}
