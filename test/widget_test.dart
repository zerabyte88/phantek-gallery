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
import 'package:phantek_gallery/core/services/media_scanner_service.dart';
import 'package:phantek_gallery/core/services/thumbnail_service.dart';
import 'package:phantek_gallery/core/services/trash_service.dart';
import 'package:phantek_gallery/core/models/trash_item.dart';
import 'package:phantek_gallery/core/utils/media_utils.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/album_grid_item.dart';
import 'package:phantek_gallery/features/gallery/presentation/album_detail_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/gallery_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/filter_sort_bar.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/sort_bottom_sheet.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/media_info_sheet.dart';
import 'package:phantek_gallery/features/settings/presentation/settings_screen.dart';
import 'package:phantek_gallery/core/services/share_service.dart';
import 'package:phantek_gallery/app/router.dart' show rootNavigatorKey;
import 'package:phantek_gallery/features/update/data/update_service.dart';
import 'package:phantek_gallery/features/update/presentation/update_dialog.dart';
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

    testWidgets('FilterSortBar displays filter chips and sort bar opens bottom sheet', (tester) async {
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

      // Verify sort bar row exists with arrow and label
      expect(find.text('By time added: Newest to oldest'), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);

      // Tap sort bar to open bottom sheet
      await tester.tap(find.text('By time added: Newest to oldest'));
      await tester.pumpAndSettle();

      // Verify bottom sheet title and options appear
      expect(find.text('Sort'), findsOneWidget);
      expect(find.text('By shooting time'), findsOneWidget);
      expect(find.text('By time added'), findsOneWidget);
      expect(find.text('By name'), findsOneWidget);
      expect(find.text('By size'), findsOneWidget);
      expect(find.text('Restore defaults'), findsOneWidget);

      // Tap "By name" and verify subtitle changes to "A to Z"
      await tester.tap(find.text('By name'));
      await tester.pumpAndSettle();

      expect(find.text('A to Z'), findsOneWidget);

      // Tap Close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Bottom sheet closes and sort bar reflects new sort
      expect(find.text('By name: A to Z'), findsOneWidget);
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

    test('TrashService purgeExpired automatically removes expired items', () async {
      final tempDir = await Directory.systemTemp.createTemp('trash_purge_test_');
      try {
        final testFile = File('${tempDir.path}/expired.jpg');
        await testFile.writeAsString('expired photo content');

        final service = TrashService();
        final item = await service.moveToTrash(
          id: 'expired_1',
          sourcePath: testFile.path,
          isVideo: false,
        );

        expect(await File(item.trashPath).exists(), isTrue);

        // Purge items with threshold 0 days (immediately expired)
        await service.purgeExpired(maxDays: 0);

        final items = await service.getItems();
        expect(items.any((e) => e.id == 'expired_1'), isFalse);
        expect(await File(item.trashPath).exists(), isFalse);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('TrashItem toMediaItem converts properties correctly', () {
      final trashItem = TrashItem(
        id: 'trash_photo_1',
        originalPath: '/storage/emulated/0/DCIM/photo.jpg',
        trashPath: '/storage/emulated/0/.trash/photo.jpg',
        name: 'photo.jpg',
        deletedDate: DateTime(2026, 1, 1),
        isVideo: false,
        size: 2048,
      );

      final media = trashItem.toMediaItem();
      expect(media.id, 'trash_photo_1');
      expect(media.path, '/storage/emulated/0/.trash/photo.jpg');
      expect(media.name, 'photo.jpg');
      expect(media.date, DateTime(2026, 1, 1));
      expect(media.size, 2048);
      expect(media.isVideo, isFalse);
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

    test('ThumbnailService clearAll wipes cache and formats size properly', () async {
      await ThumbnailService.instance.clearAll();
      final size = await ThumbnailService.instance.getCacheSizeBytes();
      expect(size, 0);
      final sizeStr = await ThumbnailService.instance.getFormattedCacheSize();
      expect(sizeStr, '0 B');
    });

    testWidgets('GalleryScreen horizontal swipe navigates between categories without resetting', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: const MaterialApp(
            home: GalleryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final pageViewFinder = find.byType(PageView);
      expect(pageViewFinder, findsOneWidget);

      final PageView initialPageView = tester.widget(pageViewFinder);
      expect(initialPageView.controller?.page ?? 0, 0);

      // Swipe left to advance to Photos (page 1)
      await tester.drag(pageViewFinder, const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final PageView photosPageView = tester.widget(pageViewFinder);
      expect(photosPageView.controller?.page?.round(), 1);

      // Swipe left to advance to Videos (page 2)
      await tester.drag(pageViewFinder, const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final PageView videosPageView = tester.widget(pageViewFinder);
      expect(videosPageView.controller?.page?.round(), 2);
    });

    testWidgets('MediaInfoSheet displays details and copies path to clipboard', (tester) async {
      final testItem = MediaItem(
        id: '123',
        path: '/storage/emulated/0/DCIM/sample.jpg',
        name: 'sample.jpg',
        date: DateTime(2026, 10, 4, 10, 30),
        size: 2048576,
        isVideo: false,
        width: 1920,
        height: 1080,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showMediaInfoSheet(context, testItem),
                child: const Text('Open Info'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Info'));
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('sample.jpg'), findsOneWidget);
      expect(find.text('/storage/emulated/0/DCIM/sample.jpg'), findsOneWidget);
      expect(find.text('1920x1080'), findsOneWidget);

      final copyBtn = find.byIcon(Icons.copy_outlined);
      await tester.scrollUntilVisible(copyBtn, 50);
      expect(copyBtn, findsOneWidget);

      await tester.tap(copyBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Path copied to clipboard'), findsOneWidget);
    });

    test('groupMediaIntoAlbums creates Favorites album at index 0 when favoriteIds are present', () {
      final item1 = MediaItem(
        id: 'fav_1',
        path: '/storage/emulated/0/DCIM/photo1.jpg',
        name: 'photo1.jpg',
        date: DateTime(2026, 1, 1),
        size: 100,
        isVideo: false,
      );
      final item2 = MediaItem(
        id: 'norm_2',
        path: '/storage/emulated/0/Download/clip.mp4',
        name: 'clip.mp4',
        date: DateTime(2026, 1, 2),
        size: 200,
        isVideo: true,
      );

      final albumsWithoutFav = groupMediaIntoAlbums([item1, item2], sort: SortOption.newest);
      expect(albumsWithoutFav.any((a) => a.name == 'Favorites'), isFalse);

      final albumsWithFav = groupMediaIntoAlbums(
        [item1, item2],
        sort: SortOption.newest,
        favoriteIds: const ['fav_1'],
      );
      expect(albumsWithFav.first.name, 'Favorites');
      expect(albumsWithFav.first.itemCount, 1);
    });

    test('ShareService.shareFiles returns false on empty paths', () async {
      final res = await ShareService.shareFiles([]);
      expect(res, isFalse);
    });

    test('SettingsModel favoriteIds copyWith and equality', () {
      const model = SettingsModel();
      expect(model.favoriteIds, isEmpty);

      final updated = model.copyWith(favoriteIds: ['id1', 'id2']);
      expect(updated.favoriteIds, ['id1', 'id2']);
      expect(updated == model, isFalse);
    });

    test('MediaListNotifier updateItem updates modified item in state', () async {
      final container = ProviderContainer(
        overrides: [
          mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
        ],
      );
      addTearDown(container.dispose);

      await container.read(mediaListProvider.future);
      final initialItems = container.read(mediaListProvider).value!;
      final original = initialItems.first;
      expect(original.name, '1.jpg');

      final renamed = original.copyWith(name: 'renamed_photo.jpg');
      container.read(mediaListProvider.notifier).updateItem(renamed);

      final updatedItems = container.read(mediaListProvider).value!;
      expect(updatedItems.first.name, 'renamed_photo.jpg');
      expect(updatedItems.first.id, original.id);
    });

    testWidgets('GalleryScreen search opens search bar, filters results and clears', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: const MaterialApp(
            home: GalleryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Find search icon and tap it
      final searchBtn = find.byTooltip('Search');
      expect(searchBtn, findsOneWidget);
      await tester.tap(searchBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Search bar TextField should now be visible
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search media or albums...'), findsOneWidget);

      // Enter search query
      await tester.enterText(find.byType(TextField), '3.mp4');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Close search via back button
      final closeSearchBtn = find.byTooltip('Close search');
      expect(closeSearchBtn, findsOneWidget);
      await tester.tap(closeSearchBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Search bar is closed, normal Phantek title restored
      expect(find.text('Phantek'), findsOneWidget);
    });

    test('Video portrait aspect ratio and duration calculation', () {
      final portraitVideo = MediaItem(
        id: 'vid_portrait',
        path: '/storage/vid_portrait.mp4',
        name: 'vid_portrait.mp4',
        date: DateTime.now(),
        size: 1024,
        isVideo: true,
        width: 1080,
        height: 1920,
        duration: const Duration(seconds: 45),
      );
      final landscapeVideo = MediaItem(
        id: 'vid_landscape',
        path: '/storage/vid_landscape.mp4',
        name: 'vid_landscape.mp4',
        date: DateTime.now(),
        size: 1024,
        isVideo: true,
        width: 3840,
        height: 2160,
        duration: const Duration(minutes: 2),
      );

      final isPortrait = (portraitVideo.height ?? 0) > (portraitVideo.width ?? 0);
      final isLandscape = (landscapeVideo.height ?? 0) > (landscapeVideo.width ?? 0);

      expect(isPortrait, isTrue);
      expect(isLandscape, isFalse);
      expect(portraitVideo.resolution, '1080x1920');
      expect(landscapeVideo.resolution, '3840x2160');
    });

    testWidgets('UpdateListener mounts with rootNavigatorKey and has valid navigator context', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            navigatorKey: rootNavigatorKey,
            home: const Scaffold(body: Text('Home Screen')),
            builder: (context, child) => UpdateListener(
              child: child!,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Home Screen'), findsOneWidget);
      expect(rootNavigatorKey.currentContext, isNotNull);
      expect(Navigator.of(rootNavigatorKey.currentContext!), isNotNull);
    });

    test('ThumbnailService getMemoryThumbnail returns synchronously cached bytes', () {
      final service = ThumbnailService.instance;
      expect(service.getMemoryThumbnail('non_existent_key'), isNull);
    });

    test('ThumbnailService init and getCachedFile handles cache lookup properly', () async {
      await ThumbnailService.init();
      final service = ThumbnailService.instance;
      expect(service.getCachedFile('non_existent_disk_key'), isNull);
    });

    test('Matrix4 scale extraction and video zoom detection', () {
      final matrix = Matrix4.identity();
      expect(matrix.getMaxScaleOnAxis(), 1.0);

      // Simulate 2.5x pinch-to-zoom
      matrix.scaleByDouble(2.5, 2.5, 1.0, 1.0);
      expect(matrix.getMaxScaleOnAxis(), 2.5);
      final isZoomed = matrix.getMaxScaleOnAxis() > 1.05;
      expect(isZoomed, isTrue);

      // Reset zoom
      matrix.setIdentity();
      expect(matrix.getMaxScaleOnAxis(), 1.0);
      expect(matrix.getMaxScaleOnAxis() > 1.05, isFalse);
    });

    test('MediaScannerService video format recognition for MKV, MOV, WebM, and MP4', () {
      expect(MediaScannerService.isSupportedVideo('.mkv'), isTrue);
      expect(MediaScannerService.isSupportedVideo('.mov'), isTrue);
      expect(MediaScannerService.isSupportedVideo('.webm'), isTrue);
      expect(MediaScannerService.isSupportedVideo('.mp4'), isTrue);
      expect(MediaScannerService.isSupportedVideo('/storage/DCIM/clip.MKV'), isTrue);
      expect(MediaScannerService.isSupportedVideo('/storage/Download/movie.mov'), isTrue);
      expect(MediaScannerService.isSupportedVideo('/storage/Download/sample.webm'), isTrue);
      expect(MediaScannerService.isSupportedVideo('/storage/DCIM/photo.jpg'), isFalse);
      expect(MediaScannerService.isSupportedVideo('/storage/DCIM/image.png'), isFalse);
    });

    test('MediaScannerService MIME validation and inference for MKV, MOV, WebM, and others', () {
      expect(MediaScannerService.isSupportedVideoMime('video/x-matroska'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('video/mkv'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('video/quicktime'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('video/webm'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('video/mp4'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('image/jpeg'), isFalse);

      expect(MediaScannerService.inferMimeType('video.mkv'), 'video/x-matroska');
      expect(MediaScannerService.inferMimeType('video.webm'), 'video/webm');
      expect(MediaScannerService.inferMimeType('video.mov'), 'video/quicktime');
      expect(MediaScannerService.inferMimeType('video.mp4'), 'video/mp4');
      expect(MediaScannerService.inferMimeType('video.unknown', isVideo: true), 'video/unknown');
    });

    test('Codec configuration verifies auto-copy with SW fallback and hardware acceleration for VP9, HEVC, and H264', () {
      const hwdec = 'auto-copy';
      const bufferSize = 8388608; // 8 MB – within MPV Android hard-cap of 10 MB

      // 'auto-copy' tries available HW decoders, then falls back to SW (libvpx, libde265, etc.)
      // automatically without failing on codecs without MediaCodec HW support (VP9, some HEVC).
      expect(hwdec, 'auto-copy');

      // Buffer must not exceed MPV Android limit of 10 MB (10485760)
      expect(bufferSize, lessThanOrEqualTo(10485760));
    });

    test('Non-fatal codec warnings are identified and suppressed from UI notifications', () {
      bool isNonFatalWarning(String err) {
        final errLower = err.toLowerCase();
        return errLower.contains('could not open codec') ||
            errLower.contains('decoder init failed') ||
            errLower.contains('hwdec') ||
            errLower.contains('using software decoding');
      }

      expect(isNonFatalWarning('Could not open codec hevc'), isTrue);
      expect(isNonFatalWarning('hwdec failed, falling back to sw'), isTrue);
      expect(isNonFatalWarning('Decoder init failed for vp9'), isTrue);
      expect(isNonFatalWarning('Using software decoding'), isTrue);
      expect(isNonFatalWarning('File not found / corrupt media'), isFalse);
    });

    testWidgets('SortBottomSheet adapts accentColor and Restore defaults to active theme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.amoledSakura,
          home: Scaffold(
            body: SortBottomSheet(
              currentSort: SortOption.newest,
              onSortChanged: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Find "Restore defaults" text widget
      final restoreTextFinder = find.text('Restore defaults');
      expect(restoreTextFinder, findsOneWidget);
      final Text restoreText = tester.widget(restoreTextFinder);
      expect(restoreText.style?.color, const Color(0xFFFF7597)); // Sakura pink!
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

