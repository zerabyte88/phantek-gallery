import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/app/theme.dart';
import 'package:phantek_gallery/core/enums/filter_option.dart';
import 'package:phantek_gallery/core/enums/sort_option.dart';
import 'package:phantek_gallery/core/models/album.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/core/providers/media_provider.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/core/services/trash_service.dart';
import 'package:phantek_gallery/core/utils/media_utils.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/album_grid_item.dart';
import 'package:phantek_gallery/features/gallery/presentation/album_detail_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/filter_sort_bar.dart';
import 'package:phantek_gallery/features/settings/presentation/settings_screen.dart';
import 'package:phantek_gallery/features/update/data/update_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Phantek Gallery Core Unit Tests', () {
    test('MediaUtils formatting tests', () {
      expect(MediaUtils.formatSize(500), '500 B');
      expect(MediaUtils.formatSize(1024 * 500), '500.0 KB');
      expect(MediaUtils.formatSize(1024 * 1024 * 5), '5.0 MB');
      expect(MediaUtils.formatDuration(const Duration(minutes: 2, seconds: 45)), '02:45');
      expect(MediaUtils.formatDuration(const Duration(hours: 1, minutes: 5, seconds: 2)), '1:05:02');

      final dt = DateTime(DateTime.now().year, 9, 15, 15, 40);
      expect(MediaUtils.formatViewerDate(dt), 'September 15');
      expect(MediaUtils.formatViewerTime(dt), '3:40 PM');
    });

    test('MediaItem model properties and albumName inference', () {
      final item = MediaItem(
        id: '123',
        path: '/storage/emulated/0/DCIM/test.mp4',
        name: 'test.mp4',
        date: DateTime(2026, 1, 1),
        size: 1048576,
        isVideo: true,
        width: 1920,
        height: 1080,
      );

      expect(item.resolution, '1920x1080');
      expect(item.isVideo, isTrue);
      expect(item.albumName, 'DCIM');

      final fbItem = MediaItem(
        id: '124',
        path: '/storage/emulated/0/Pictures/Facebook/pic.jpg',
        name: 'pic.jpg',
        date: DateTime(2026, 1, 2),
        size: 500,
        isVideo: false,
      );
      expect(fbItem.albumName, 'Facebook');

      final dlItem = MediaItem(
        id: '125',
        path: '/storage/emulated/0/Download/clip.mp4',
        name: 'clip.mp4',
        date: DateTime(2026, 1, 3),
        size: 500,
        isVideo: true,
      );
      expect(dlItem.albumName, 'Download');

      final customItem = MediaItem(
        id: '126',
        path: '/storage/emulated/0/DCIM/Camera/photo.jpg',
        name: 'photo.jpg',
        date: DateTime(2026, 1, 4),
        size: 500,
        isVideo: false,
        album: 'Vacation',
      );
      expect(customItem.albumName, 'Vacation');
    });

    test('groupMediaIntoAlbums groups and sorts correctly', () {
      final item1 = MediaItem(
        id: '1',
        path: '/storage/emulated/0/DCIM/img1.jpg',
        name: 'img1.jpg',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      );
      final item2 = MediaItem(
        id: '2',
        path: '/storage/emulated/0/DCIM/img2.jpg',
        name: 'img2.jpg',
        date: DateTime(2026, 1, 10),
        size: 100,
        isVideo: false,
      );
      final item3 = MediaItem(
        id: '3',
        path: '/storage/emulated/0/Download/video.mp4',
        name: 'video.mp4',
        date: DateTime(2026, 1, 5),
        size: 200,
        isVideo: true,
      );

      final albumsAZ =
          groupMediaIntoAlbums([item1, item2, item3], sort: SortOption.nameAZ);
      expect(albumsAZ.length, 2);
      expect(albumsAZ[0].name, 'DCIM');
      expect(albumsAZ[0].itemCount, 2);
      expect(albumsAZ[1].name, 'Download');
      expect(albumsAZ[1].itemCount, 1);

      final albumsNewest =
          groupMediaIntoAlbums([item1, item2, item3], sort: SortOption.newest);
      expect(albumsNewest[0].name, 'DCIM');
    });

    test('SettingsModel defaults', () {
      const settings = SettingsModel();
      expect(settings.gridColumns, 3);
      expect(settings.albumGridColumns, 3);
      expect(settings.enableTrash, isTrue);
      expect(settings.hardwareAcceleration, isTrue);
      expect(settings.autoCheckUpdate, isTrue);
      expect(settings.defaultSort, SortOption.newest);
      expect(settings.defaultFilter, FilterOption.all);
    });

    testWidgets('FilterSortBar displays filter chips and 3-dots popup menu', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: FilterSortBar(),
            ),
          ),
        ),
      );

      // Verify filter chips exist
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Videos'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);

      // Verify 3-dots sort button exists
      expect(find.byIcon(Icons.more_vert), findsOneWidget);

      // Tap 3-dots button and verify sort options appear
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();

      expect(find.text('Newest First'), findsOneWidget);
      expect(find.text('Oldest First'), findsOneWidget);
      expect(find.text('Name A → Z'), findsOneWidget);
      expect(find.text('Name Z → A'), findsOneWidget);

      // Tap one of the options
      await tester.tap(find.text('Oldest First'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Menu closes
      expect(find.text('Oldest First'), findsNothing);
    });

    test('TrashService moveToTrash and restore lifecycle with temp file', () async {
      final tempDir = await Directory.systemTemp.createTemp('trash_test_');
      try {
        final testFile = File('${tempDir.path}/photo.jpg');
        await testFile.writeAsString('dummy photo content');
        expect(await testFile.exists(), isTrue);

        final service = TrashService();
        final item = await service.moveToTrash(
          id: 'test_1',
          sourcePath: testFile.path,
          isVideo: false,
        );

        expect(item.id, 'test_1');
        expect(await testFile.exists(), isFalse);
        expect(await File(item.trashPath).exists(), isTrue);

        final items = await service.getItems();
        expect(items.any((e) => e.id == 'test_1'), isTrue);

        await service.restore('test_1');
        expect(await testFile.exists(), isTrue);
        expect(await File(item.trashPath).exists(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets('AlbumGridItem displays album title and count', (tester) async {
      final item = MediaItem(
        id: '1',
        path: '/storage/emulated/0/DCIM/photo.jpg',
        name: 'photo.jpg',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      );
      final album = Album(
        name: 'DCIM',
        items: [item],
        coverItem: item,
      );

      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 160,
                child: AlbumGridItem(
                  album: album,
                  onTap: () => tapped = true,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('DCIM'), findsOneWidget);
      expect(find.text('1 items'), findsOneWidget);

      await tester.tap(find.text('DCIM'));
      expect(tapped, isTrue);
    });

    testWidgets('AlbumDetailScreen renders album title and empty state', (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: AlbumDetailScreen(albumName: 'Facebook'),
          ),
        ),
      );

      expect(find.text('Facebook'), findsOneWidget);
      expect(find.text('No media in Facebook'), findsOneWidget);
    });

    testWidgets('SettingsScreen Grid Columns dialog updates column count', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      // Verify Grid Columns and Albums Grid Columns tiles are visible with default "3 columns"
      expect(find.text('Grid Columns'), findsOneWidget);
      expect(find.text('Albums Grid Columns'), findsOneWidget);
      expect(find.text('3 columns'), findsNWidgets(2));

      // Tap Grid Columns tile to open dialog
      await tester.tap(find.text('Grid Columns'));
      await tester.pumpAndSettle();

      // Dialog opens showing options
      expect(find.text('Select Grid Columns'), findsOneWidget);
      expect(find.text('2 columns'), findsOneWidget);
      expect(find.text('4 columns'), findsOneWidget);
      expect(find.text('5 columns'), findsOneWidget);

      // Select "4 columns"
      await tester.tap(find.text('4 columns'));
      await tester.pumpAndSettle();

      // Dialog closes and subtitle updates to "4 columns"
      expect(find.text('Select Grid Columns'), findsNothing);
      expect(find.text('4 columns'), findsOneWidget);

      // Verify Albums Grid Columns tile is visible with default "3 columns"
      expect(find.text('Albums Grid Columns'), findsOneWidget);

      // Tap Albums Grid Columns tile to open dialog
      await tester.tap(find.text('Albums Grid Columns'));
      await tester.pumpAndSettle();

      // Dialog opens showing options
      expect(find.text('Select Albums Grid Columns'), findsOneWidget);
      expect(find.text('2 columns'), findsOneWidget);

      // Select "2 columns"
      await tester.tap(find.text('2 columns'));
      await tester.pumpAndSettle();

      // Dialog closes and subtitle updates
      expect(find.text('Select Albums Grid Columns'), findsNothing);
      expect(find.text('2 columns'), findsOneWidget);
    });

    test('AppThemeMode labels and AppTheme amoled definitions', () {
      expect(AppThemeMode.amoled.label, 'AMOLED');
      expect(AppThemeMode.amoledSakura.label, 'AMOLED Sakura 🌸');
      expect(AppTheme.amoled.scaffoldBackgroundColor, Colors.black);
      expect(AppTheme.amoledSakura.scaffoldBackgroundColor, Colors.black);
    });

    testWidgets('AppBar badge 10-tap Easter Egg unlocks AMOLED Sakura theme', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      // Verify Theme tile has default "System"
      expect(find.text('System'), findsOneWidget);

      // Tap Theme tile to open dialog
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      // AMOLED is available, but AMOLED Sakura 🌸 is NOT available before Easter egg
      expect(find.text('AMOLED'), findsOneWidget);
      expect(find.text('AMOLED Sakura 🌸'), findsNothing);

      // Close dialog by tapping first option (System)
      await tester.tap(find.byType(SimpleDialogOption).first);
      await tester.pumpAndSettle();

      // Verify developer avatar does NOT trigger easter egg
      final avatarFinder = find.byKey(const ValueKey('developer_avatar'));
      await tester.scrollUntilVisible(avatarFinder, 200);
      await tester.pumpAndSettle();
      for (var i = 0; i < 10; i++) {
        await tester.tap(avatarFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();
      expect(SettingsService.instance.settings.isSakuraUnlocked, isFalse);

      // Scroll back up to AppBar
      await tester.scrollUntilVisible(find.text('Theme'), -200);
      await tester.pumpAndSettle();

      // Find AppBar badge
      final badgeFinder = find.byKey(const ValueKey('settings_appbar_badge_easter_egg'));
      expect(badgeFinder, findsOneWidget);

      // Tap AppBar badge 10 times
      for (var i = 0; i < 10; i++) {
        await tester.tap(badgeFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // SnackBar shows Easter Egg Unlocked
      expect(find.textContaining('Easter Egg Unlocked!'), findsOneWidget);
      expect(SettingsService.instance.settings.isSakuraUnlocked, isTrue);

      // Open Theme dialog again
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      // Now AMOLED Sakura 🌸 is in the dialog!
      expect(find.text('AMOLED Sakura 🌸'), findsNWidgets(2)); // in dialog + in subtitle
    });

    test('MediaListNotifier optimistic removeItems and restoreItems', () async {
      final container = ProviderContainer(
        overrides: [
          mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
        ],
      );
      addTearDown(container.dispose);

      final initial = await container.read(mediaListProvider.future);
      expect(initial.length, 3);

      // Optimistically remove 2 items
      container.read(mediaListProvider.notifier).removeItems(['item_1', 'item_2']);
      final afterRemove = container.read(mediaListProvider).value!;
      expect(afterRemove.length, 1);
      expect(afterRemove.first.id, 'item_3');

      // Restore items
      container.read(mediaListProvider.notifier).restoreItems(['item_1']);
      await container.read(mediaListProvider.notifier).refresh();
      final afterRefresh = container.read(mediaListProvider).value!;
      // item_1 restored and scanned back, item_2 still in deletedIds
      expect(afterRefresh.map((e) => e.id).toSet(), containsAll({'item_1', 'item_3'}));
      expect(afterRefresh.any((e) => e.id == 'item_2'), isFalse);
    });

    test('UpdateService selectBestApkAsset picks correct 64-bit and 32-bit variant', () {
      final assets = [
        {'name': 'Phantek-Gallery-armeabi-v7a.apk', 'browser_download_url': 'https://example.com/v7a.apk'},
        {'name': 'Phantek-Gallery-arm64-v8a.apk', 'browser_download_url': 'https://example.com/arm64.apk'},
      ];

      // On 64-bit ARM device:
      final selected64 = UpdateService.selectBestApkAsset(assets, 'arm64-v8a');
      expect(selected64['name'], 'Phantek-Gallery-arm64-v8a.apk');
      expect(selected64['browser_download_url'], 'https://example.com/arm64.apk');

      // On 32-bit ARM device:
      final selected32 = UpdateService.selectBestApkAsset(assets, 'armeabi-v7a');
      expect(selected32['name'], 'Phantek-Gallery-armeabi-v7a.apk');
      expect(selected32['browser_download_url'], 'https://example.com/v7a.apk');

      // Fallback to universal when specific ABI is missing:
      final universalAssets = [
        {'name': 'app-release.apk', 'browser_download_url': 'https://example.com/app-release.apk'},
      ];
      final selectedUniversal = UpdateService.selectBestApkAsset(universalAssets, 'arm64-v8a');
      expect(selectedUniversal['name'], 'app-release.apk');
    });
  });
}

class _MockMediaListNotifier extends MediaListNotifier {
  @override
  Future<List<MediaItem>> build() async {
    final mockItems = [
      MediaItem(id: 'item_1', path: '/a/1.jpg', name: '1.jpg', date: DateTime.now(), size: 10, isVideo: false),
      MediaItem(id: 'item_2', path: '/a/2.jpg', name: '2.jpg', date: DateTime.now(), size: 20, isVideo: false),
      MediaItem(id: 'item_3', path: '/a/3.mp4', name: '3.mp4', date: DateTime.now(), size: 30, isVideo: true),
    ];
    return mockItems.where((e) => !deletedIds.contains(e.id)).toList();
  }

  @override
  Future<void> refresh() async {
    final mockItems = [
      MediaItem(id: 'item_1', path: '/a/1.jpg', name: '1.jpg', date: DateTime.now(), size: 10, isVideo: false),
      MediaItem(id: 'item_2', path: '/a/2.jpg', name: '2.jpg', date: DateTime.now(), size: 20, isVideo: false),
      MediaItem(id: 'item_3', path: '/a/3.mp4', name: '3.mp4', date: DateTime.now(), size: 30, isVideo: true),
    ];
    state = AsyncData(mockItems.where((e) => !deletedIds.contains(e.id)).toList());
  }
}

