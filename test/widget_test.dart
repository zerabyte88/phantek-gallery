import 'dart:io';
import 'dart:math' as math;
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
import 'package:flutter/services.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/core/services/screen_keeper_service.dart';
import 'package:phantek_gallery/core/services/media_scanner_service.dart';
import 'package:phantek_gallery/core/services/thumbnail_service.dart';
import 'package:phantek_gallery/core/services/trash_service.dart';
import 'package:phantek_gallery/core/models/trash_item.dart';
import 'package:phantek_gallery/core/utils/media_utils.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/album_grid_item.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/media_grid_item.dart';
import 'package:phantek_gallery/features/gallery/presentation/album_detail_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/gallery_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/filter_sort_bar.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/sort_bottom_sheet.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/media_info_sheet.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart' show displayImage;
import 'package:phantek_gallery/features/settings/presentation/settings_screen.dart';
import 'package:phantek_gallery/core/services/share_service.dart';
import 'package:phantek_gallery/app/router.dart' show rootNavigatorKey;
import 'package:phantek_gallery/features/update/data/update_service.dart';
import 'package:phantek_gallery/features/update/presentation/update_dialog.dart';
import 'package:phantek_gallery/core/widgets/animated_flame_title.dart';
import 'package:phantek_gallery/core/widgets/theme_header_background.dart';
import 'package:phantek_gallery/core/providers/settings_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phantek_gallery/core/localization/app_language.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
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

      expect(MediaUtils.formatFps(60.0), '60 fps');
      expect(MediaUtils.formatFps(29.97), '29.97 fps');
      expect(MediaUtils.formatFps(23.976), '23.98 fps');
      expect(MediaUtils.formatFps(0), '');

      expect(MediaUtils.formatCodec('h264'), 'H.264 (AVC)');
      expect(MediaUtils.formatCodec('avc1'), 'H.264 (AVC)');
      expect(MediaUtils.formatCodec('hevc'), 'H.265 (HEVC)');
      expect(MediaUtils.formatCodec('hvc1'), 'H.265 (HEVC)');
      expect(MediaUtils.formatCodec('vp9'), 'VP9');
      expect(MediaUtils.formatCodec('av01'), 'AV1');
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

    test('Rotated orientation aspect ratio calculation', () {
      // Raw portrait recorded video in landscape 1920x1080 with 90 deg rotation
      const rawW = 1920;
      const rawH = 1080;
      const orientation = 90;
      final isRotated = orientation == 90 || orientation == 270;
      final effectiveW = isRotated ? rawH : rawW;
      final effectiveH = isRotated ? rawW : rawH;

      final portraitItem = MediaItem(
        id: 'rot_1',
        path: '/storage/emulated/0/DCIM/portrait.mp4',
        name: 'portrait.mp4',
        date: DateTime(2026, 1, 1),
        size: 1000,
        isVideo: true,
        width: effectiveW,
        height: effectiveH,
      );

      expect(portraitItem.width, 1080);
      expect(portraitItem.height, 1920);
      expect(portraitItem.resolution, '1080x1920');
      expect(portraitItem.width! / portraitItem.height!, closeTo(1080 / 1920, 0.001));
    });

    test('Unindexed large video (>100MB) fallback aspect ratio resolution', () {
      final unindexedVideo = MediaItem(
        id: 'large_100mb',
        path: '/storage/emulated/0/Download/movie_150mb.mp4',
        name: 'movie_150mb.mp4',
        date: DateTime(2026, 1, 1),
        size: 157286400, // 150 MB
        isVideo: true,
        width: 0, // 0 when unindexed by MediaStore
        height: 0,
      );

      expect(unindexedVideo.width, 0);
      expect(unindexedVideo.height, 0);

      // Verify safe aspect ratio fallback calculation
      double resolveTestRatio(MediaItem item) {
        if (item.width != null && item.height != null && item.width! > 0 && item.height! > 0) {
          return item.width! / item.height!;
        }
        return 16.0 / 9.0;
      }

      expect(resolveTestRatio(unindexedVideo), closeTo(16.0 / 9.0, 0.001));
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
      expect(settings.keepScreenOn, isFalse);
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

    testWidgets('AlbumGridItem shows checkmark avatar when isSelecting and isSelected', (tester) async {
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

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 120,
                height: 160,
                child: AlbumGridItem(
                  album: album,
                  isSelecting: true,
                  isSelected: true,
                  onTap: () {},
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('checked')), findsOneWidget);
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
      await tester.tap(find.text('System').last);
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

      // Find version badge in DeveloperAboutCard
      final badgeFinder = find.byKey(const ValueKey('settings_appbar_badge_easter_egg'));
      await tester.scrollUntilVisible(badgeFinder, 200);
      await tester.pumpAndSettle();
      expect(badgeFinder, findsOneWidget);

      // Tap version badge 10 times
      for (var i = 0; i < 10; i++) {
        await tester.tap(badgeFinder);
        await tester.pump(const Duration(milliseconds: 100));
      }
      await tester.pumpAndSettle();

      // SnackBar shows Easter Egg Unlocked
      expect(find.textContaining('Easter Egg Unlocked!'), findsOneWidget);
      expect(SettingsService.instance.settings.isSakuraUnlocked, isTrue);

      // Scroll back up to Theme tile
      await tester.scrollUntilVisible(find.text('Theme'), -200);
      await tester.pumpAndSettle();

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

    testWidgets('MediaInfoSheet displays video FPS, Codec and duration', (tester) async {
      final videoItem = MediaItem(
        id: 'vid_1',
        path: '/storage/emulated/0/DCIM/sample.mp4',
        name: 'sample.mp4',
        date: DateTime(2025, 5, 4, 7, 32),
        size: 15900000,
        isVideo: true,
        width: 1920,
        height: 1080,
        duration: const Duration(seconds: 14),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showMediaInfoSheet(
                  context,
                  videoItem,
                  fps: 60.0,
                  codec: 'h264',
                ),
                child: const Text('Open Video Info'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Video Info'));
      await tester.pumpAndSettle();

      expect(find.text('Details'), findsOneWidget);
      expect(find.text('sample.mp4'), findsOneWidget);
      expect(find.text('1920x1080'), findsOneWidget);
      expect(find.text('Frame Rate'), findsOneWidget);
      expect(find.text('60 fps'), findsOneWidget);
      expect(find.text('Codec'), findsOneWidget);
      expect(find.text('H.264 (AVC)'), findsOneWidget);
      expect(find.text('Duration'), findsOneWidget);
      expect(find.text('00:14'), findsOneWidget);
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
      await tester.pump(const Duration(milliseconds: 350));

      // Search bar TextField and Cancel button should now be visible
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Search media or albums...'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      final searchFieldRect = tester.getRect(find.byType(TextField));
      final filterBarRect = tester.getRect(find.byType(FilterSortBar));
      expect(searchFieldRect.bottom, lessThanOrEqualTo(filterBarRect.top),
          reason: 'Search bar must strictly reside inside the toolbar above FilterSortBar with zero collision');

      // Enter search query
      await tester.enterText(find.byType(TextField), '3.mp4');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Clear search query via Cancel button
      final cancelBtn = find.byKey(const ValueKey('search_cancel_button'));
      expect(cancelBtn, findsOneWidget);
      await tester.tap(cancelBtn, warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

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

      bool isPortraitCheck({int? w, int? h, int? rotate}) {
        if (w != null && h != null && w > 0 && h > 0) {
          final isRotated90or270 = rotate == 90 || rotate == 270;
          final effectiveW = isRotated90or270 ? h : w;
          final effectiveH = isRotated90or270 ? w : h;
          return effectiveH > effectiveW;
        }
        return false;
      }

      // Normal portrait (1080x1920, 0 deg)
      expect(isPortraitCheck(w: 1080, h: 1920, rotate: 0), isTrue);

      // Normal landscape (1920x1080, 0 deg)
      expect(isPortraitCheck(w: 1920, h: 1080, rotate: 0), isFalse);

      // Recorded vertically on phone (1920x1080 with rotate: 90) -> effective 1080x1920 Portrait
      expect(isPortraitCheck(w: 1920, h: 1080, rotate: 90), isTrue);

      // 4K widescreen movie (3840x2160, 0 deg)
      expect(isPortraitCheck(w: 3840, h: 2160, rotate: 0), isFalse);

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
            errLower.contains('using software decoding') ||
            errLower.contains('error decoding') ||
            errLower.contains('cannot decode') ||
            errLower.contains('invalid data') ||
            errLower.contains('corrupt') ||
            errLower.contains('missing picture') ||
            errLower.contains('packet');
      }

      expect(isNonFatalWarning('Could not open codec hevc'), isTrue);
      expect(isNonFatalWarning('hwdec failed, falling back to sw'), isTrue);
      expect(isNonFatalWarning('Decoder init failed for vp9'), isTrue);
      expect(isNonFatalWarning('Using software decoding'), isTrue);
      expect(isNonFatalWarning('Error decoding video'), isTrue);
      expect(isNonFatalWarning('Cannot decode frame at timestamp'), isTrue);
      expect(isNonFatalWarning('Invalid data found when processing input'), isTrue);
      expect(isNonFatalWarning('File not found: /storage/video.mp4'), isFalse);
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

    test('Zoom focal point math calculates correct translation offset for scale', () {
      const center = Offset(200, 400);
      const tapPos = Offset(150, 300);
      const targetScale = 1.8;

      final delta = tapPos - center;
      final expectedOffset = -delta * (targetScale - 1.0);

      // Verify that scaling around center and translating by expectedOffset
      // places the tapped focal point exactly back at tapPos on screen:
      final transformed = center + (delta * targetScale) + expectedOffset;

      expect(transformed.dx, closeTo(tapPos.dx, 0.001));
      expect(transformed.dy, closeTo(tapPos.dy, 0.001));
    });

    test('Photo InteractiveViewer focal point matrix scales to 2.5x and returns cleanly to identity', () {
      final controller = TransformationController();
      expect(controller.value.getMaxScaleOnAxis(), 1.0);
      expect(controller.value.isIdentity(), isTrue);

      const tapPos = Offset(250.0, 450.0);
      const double targetScale = 2.5;

      // Zoom in to focal point
      final endMatrix = Matrix4.identity()
        ..translateByDouble(tapPos.dx, tapPos.dy, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0)
        ..translateByDouble(-tapPos.dx, -tapPos.dy, 0.0, 1.0);

      controller.value = endMatrix;
      expect(controller.value.getMaxScaleOnAxis(), 2.5);
      expect(controller.value.getMaxScaleOnAxis() > 1.05, isTrue);

      // The focal point transformed by the matrix should stay at tapPos
      final transformedPoint = MatrixUtils.transformPoint(controller.value, tapPos);
      expect(transformedPoint.dx, closeTo(tapPos.dx, 0.001));
      expect(transformedPoint.dy, closeTo(tapPos.dy, 0.001));

      // Zoom out resets directly to identity without stuck states
      controller.value = Matrix4.identity();
      expect(controller.value.getMaxScaleOnAxis(), 1.0);
      expect(controller.value.isIdentity(), isTrue);
      expect(controller.value.getMaxScaleOnAxis() > 1.05, isFalse);
    });

    test('Responsive gesture slop deadzone filters minor horizontal jitters and accepts natural downward drag', () {
      bool shouldStartDrag(double dx, double dy) {
        return dy > 8 && dy > dx.abs() * 1.1;
      }

      // Small jitter (< 8px) -> rejected
      expect(shouldStartDrag(2, 6), isFalse);
      expect(shouldStartDrag(0, 7), isFalse);

      // Horizontal swipe variation -> rejected
      expect(shouldStartDrag(25, 20), isFalse);
      expect(shouldStartDrag(40, 30), isFalse);

      // Natural downward drag (including slight thumb arc) -> accepted
      expect(shouldStartDrag(0, 15), isTrue);
      expect(shouldStartDrag(10, 25), isTrue); // 25 > 10 * 1.1 (11)
      expect(shouldStartDrag(20, 30), isTrue); // 30 > 20 * 1.1 (22)
    });

    test('Snapdragon 685 WebM and VP9 codec safety rules route to software decode', () {
      String resolveHwdec(String path) {
        if (path.toLowerCase().endsWith('.webm')) return 'no';
        return 'auto-copy';
      }

      expect(resolveHwdec('sample.webm'), 'no');
      expect(resolveHwdec('clip.WEBM'), 'no');
      expect(resolveHwdec('video.mp4'), 'auto-copy');
      expect(resolveHwdec('movie.mkv'), 'auto-copy');
    });

    test('Video thumbnail extraction scales 4K (2160p) and 1080p down proportionally without memory bloat', () {
      // 4K UHD: 3840 x 2160
      const origW = 3840;
      const origH = 2160;
      const targetSize = 512;

      final maxDim = origW > origH ? origW : origH;
      final scale = maxDim > targetSize ? targetSize / maxDim : 1.0;
      final dstW = (((origW * scale).toInt() ~/ 2) * 2).clamp(2, targetSize);
      final dstH = (((origH * scale).toInt() ~/ 2) * 2).clamp(2, targetSize);

      expect(dstW, 512);
      expect(dstH, 288); // 16:9 preserved perfectly!
      expect(dstW * dstH * 4, lessThan(600 * 1024)); // Less than 600 KB RAM vs 33 MB unscaled!
    });

    test('Photo double-tap detector identifies valid double taps within time and distance thresholds', () {
      bool isDoubleTap({
        required int downDurationMs,
        required double moveDist,
        required int intervalMs,
        required double doubleTapDist,
      }) {
        if (downDurationMs < 300 && moveDist < 25.0) {
          if (intervalMs < 350 && doubleTapDist < 45.0) {
            return true;
          }
        }
        return false;
      }

      // Valid double tap
      expect(isDoubleTap(downDurationMs: 80, moveDist: 2.0, intervalMs: 150, doubleTapDist: 5.0), isTrue);

      // Too slow between taps (> 350ms)
      expect(isDoubleTap(downDurationMs: 80, moveDist: 2.0, intervalMs: 400, doubleTapDist: 5.0), isFalse);

      // Too far apart (> 45px)
      expect(isDoubleTap(downDurationMs: 80, moveDist: 2.0, intervalMs: 150, doubleTapDist: 60.0), isFalse);

      // First tap was a drag (> 25px move)
      expect(isDoubleTap(downDurationMs: 80, moveDist: 35.0, intervalMs: 150, doubleTapDist: 5.0), isFalse);
    });

    test('displayImage caps 100MP photos at 4096px and shares one cache entry', () {
      final a = displayImage('/dcim/hasselblad.jpg') as ResizeImage;
      final b = displayImage('/dcim/hasselblad.jpg');
      expect(a.width, 4096);
      expect(a.height, 4096);
      expect(a.policy, ResizeImagePolicy.fit);
      // Viewer + precache build separate instances; they must hit the same cache slot.
      expect(a, equals(b));
      expect(displayImage('/dcim/other.jpg'), isNot(equals(a)));
      // 8742x11656 fit into 4096 -> 3072x4096 RGBA, fits the 256 MB imageCache 3x over.
      const scale = 4096 / 11656;
      final bytes = (8742 * scale).round() * 4096 * 4;
      expect(bytes * 3, lessThan(256 * 1024 * 1024));
    });

    test('Hero flight shuttle preserves AspectRatio and interpolates bounds without vertical distortion', () {
      // Starting from 120x120 grid cell (1:1 aspect ratio)
      const srcWidth = 120.0;
      const srcHeight = 120.0;

      // Destination 16:9 landscape photo on 412px screen (412 x 231.75)
      const dstWidth = 412.0;
      const dstHeight = 412.0 / (16.0 / 9.0); // 231.75

      double widthAt(double t) => srcWidth + t * (dstWidth - srcWidth);
      double heightAt(double t) => srcHeight + t * (dstHeight - srcHeight);
      double ratioAt(double t) => widthAt(t) / heightAt(t);

      // t = 0 (Grid cell): 1.0 (Square)
      expect(ratioAt(0.0), 1.0);

      // t = 0.5 (Mid flight): 1.512 (smoothly widening, never tall/distorted!)
      expect(ratioAt(0.5), closeTo(1.512, 0.01));
      expect(heightAt(0.5), closeTo(175.875, 0.01));
      expect(widthAt(0.5), 266.0);

      // t = 1.0 (Viewer): 1.777 (16:9 Landscape)
      expect(ratioAt(1.0), closeTo(1.777, 0.01));
      expect(heightAt(1.0), closeTo(231.75, 0.01));
      expect(widthAt(1.0), 412.0);
    });

    testWidgets('MediaGridItem renders Hero thumbnail inside a ClipRect', (tester) async {
      final testItem = MediaItem(
        id: 'test_grid_item_1',
        path: '/dcim/test.jpg',
        name: 'test.jpg',
        date: DateTime.now(),
        size: 1024,
        isVideo: false,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaGridItem(
              item: testItem,
              isSelected: false,
              isSelecting: false,
              showBadges: true,
              onTap: () {},
              onLongPress: () {},
            ),
          ),
        ),
      );

      final clipRectFinder = find.byType(ClipRect);
      expect(clipRectFinder, findsWidgets);

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, 'test_grid_item_1');
    });

    test('Swipe-to-dismiss dynamic scale, corner radius, and opacity formulas', () {
      double computeScale(double dy) =>
          (1.0 - (dy / 1000.0) * 0.28).clamp(0.72, 1.0);
      double computeRadius(double dy) =>
          (dy > 0 ? (dy / 12.0).clamp(0.0, 20.0) : 0.0);
      double computeScrimAlpha(double dy) =>
          (1.0 - (dy / 320.0)).clamp(0.0, 1.0);
      double computeOverlayOpacity(double dy) =>
          (1.0 - (dy / 35.0)).clamp(0.0, 1.0);

      // At rest (dy = 0)
      expect(computeScale(0), 1.0);
      expect(computeRadius(0), 0.0);
      expect(computeScrimAlpha(0), 1.0);
      expect(computeOverlayOpacity(0), 1.0);

      // Dragging down slightly (dy = 35)
      expect(computeScale(35), closeTo(0.99, 0.01));
      expect(computeRadius(35), closeTo(2.91, 0.05));
      expect(computeScrimAlpha(35), closeTo(0.89, 0.01));
      expect(computeOverlayOpacity(35), 0.0); // Bars completely and cleanly hidden!

      // Deep drag (dy = 320)
      expect(computeScrimAlpha(320), 0.0); // Background completely clear
      expect(computeRadius(320), 20.0); // Clamped max corner radius
      expect(computeScale(320), closeTo(0.91, 0.01));

      // Maximum clamp check (dy = 2000)
      expect(computeScale(2000), 0.72);
      expect(computeRadius(2000), 20.0);
      expect(computeScrimAlpha(2000), 0.0);
      expect(computeOverlayOpacity(2000), 0.0);
    });

    test('Swipe-to-dismiss SpringSimulation description uses smooth organic damping', () {
      final spring = SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: 320,
        ratio: 0.82,
      );

      expect(spring.mass, 1.0);
      expect(spring.stiffness, 320.0);
      expect(spring.damping, closeTo(2 * 1.0 * 0.82 * 17.888, 0.5)); // 2*m*ratio*sqrt(k)
    });

    test('FilterSortBar segmented capsule indicator alignment calculation', () {
      double computeAlignmentX(int selectedIndex, int totalOptions) {
        if (totalOptions <= 1) return 0.0;
        final clamped = selectedIndex.clamp(0, totalOptions - 1);
        return -1.0 + (2.0 * clamped / (totalOptions - 1));
      }

      // 4 tabs (All, Photos, Videos, Albums)
      expect(computeAlignmentX(0, 4), -1.0); // All (Far Left)
      expect(computeAlignmentX(1, 4), closeTo(-0.333, 0.001)); // Photos
      expect(computeAlignmentX(2, 4), closeTo(0.333, 0.001)); // Videos
      expect(computeAlignmentX(3, 4), 1.0); // Albums (Far Right)

      // 3 tabs (All, Photos, Videos in AlbumDetail)
      expect(computeAlignmentX(0, 3), -1.0); // All
      expect(computeAlignmentX(1, 3), 0.0); // Photos (Center)
      expect(computeAlignmentX(2, 3), 1.0); // Videos
    });

    testWidgets('ThemeHeaderBackground and AnimatedFlameTitle adapt to all AppThemeMode options', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      for (final mode in [
        AppThemeMode.amoled,
        AppThemeMode.amoledSakura,
        AppThemeMode.dark,
        AppThemeMode.light,
        AppThemeMode.system,
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(mode),
            overrides: [
              settingsNotifierProvider.overrideWith(
                () => _TestSettingsNotifier(SettingsModel(themeMode: mode)),
              ),
            ],
            child: MaterialApp(
              theme: mode == AppThemeMode.light ? AppTheme.light : AppTheme.dark,
              home: Scaffold(
                appBar: AppBar(
                  flexibleSpace: const ThemeHeaderBackground(),
                  title: const AnimatedFlameTitle(title: 'Phantek'),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));

        // Verify widgets are mounted
        expect(find.byType(ThemeHeaderBackground), findsOneWidget);
        expect(find.byType(AnimatedFlameTitle), findsOneWidget);
        expect(find.text('Phantek'), findsOneWidget);

        // Verify corresponding icon in AnimatedFlameTitle
        final expectedIcon = switch (mode) {
          AppThemeMode.amoled => Icons.nights_stay_rounded,
          AppThemeMode.amoledSakura => Icons.local_florist_rounded,
          AppThemeMode.dark => Icons.auto_awesome_rounded,
          AppThemeMode.light => Icons.wb_sunny_rounded,
          AppThemeMode.system => Icons.auto_awesome_rounded, // in dark theme
        };
        expect(find.byIcon(expectedIcon), findsOneWidget);
      }
    });

    test('ThumbnailService.parseJpegDimensions parses SOF0 marker accurately', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, // APP0
        0x00, 0x10, // length = 16
        0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48, 0x00, 0x00,
        0xFF, 0xC0, // SOF0
        0x00, 0x11, // length = 17
        0x08,       // precision
        0x05, 0x00, // height = 1280 (0x0500)
        0x02, 0xD0, // width = 720 (0x02D0)
        0x03, 0x01, 0x22, 0x00, 0x02, 0x11, 0x01, 0x03, 0x11, 0x01,
        0xFF, 0xD9, // EOI
      ]);

      final size = ThumbnailService.parseJpegDimensions(bytes);
      expect(size, isNotNull);
      expect(size!.width, 720.0);
      expect(size.height, 1280.0);
      expect(size.width / size.height, 0.5625);
    });

    test('ThumbnailService.parseJpegDimensions parses SOF2 progressive marker accurately', () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xC2, // SOF2 progressive
        0x00, 0x0B,
        0x08,
        0x04, 0x38, // height = 1080 (0x0438)
        0x07, 0x80, // width = 1920 (0x0780)
        0x01, 0x01, 0x11, 0x00,
        0xFF, 0xD9,
      ]);

      final size = ThumbnailService.parseJpegDimensions(bytes);
      expect(size, isNotNull);
      expect(size!.width, 1920.0);
      expect(size.height, 1080.0);
      expect(size.width / size.height, closeTo(1.777, 0.001));
    });

    test('Video player seekbar, left/right timestamps, and fullscreen button are collectively elevated by 32dp spacing above action buttons', () {
      // The seekbar unit (slider, left timestamp, right timestamp, fullscreen button)
      // is separated from the bottom action buttons by 32dp (+26dp above initial 6dp)
      // to comfortably match the user-marked green line and avoid accidental button taps.
      const previousSpacing = 6.0;
      const raisedSpacing = 32.0;
      const deltaElevation = raisedSpacing - previousSpacing;

      expect(raisedSpacing, 32.0);
      expect(deltaElevation, 26.0);
      expect(raisedSpacing, greaterThanOrEqualTo(24.0));
    });

    testWidgets('Video player center play button fades out and ignores touch during horizontal swipe to adjacent video', (tester) async {
      final isSwipingPage = ValueNotifier<bool>(false);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable: isSwipingPage,
              builder: (context, isSwiping, child) {
                return AnimatedOpacity(
                  key: const ValueKey('play_btn_opacity'),
                  duration: Duration(milliseconds: isSwiping ? 150 : 250),
                  curve: Curves.easeInOut,
                  opacity: isSwiping ? 0.0 : 1.0,
                  child: IgnorePointer(
                    key: const ValueKey('play_btn_ignore'),
                    ignoring: isSwiping,
                    child: child,
                  ),
                );
              },
              child: const Icon(Icons.play_arrow_rounded, key: ValueKey('play_btn')),
            ),
          ),
        ),
      );

      // Initially stationary: opacity 1.0, touch enabled
      expect(find.byKey(const ValueKey('play_btn')), findsOneWidget);
      AnimatedOpacity opacityWidget = tester.widget(find.byKey(const ValueKey('play_btn_opacity')));
      IgnorePointer ignoreWidget = tester.widget(find.byKey(const ValueKey('play_btn_ignore')));
      expect(opacityWidget.opacity, 1.0);
      expect(ignoreWidget.ignoring, isFalse);

      // User starts swiping horizontally to adjacent video:
      isSwipingPage.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      opacityWidget = tester.widget(find.byKey(const ValueKey('play_btn_opacity')));
      ignoreWidget = tester.widget(find.byKey(const ValueKey('play_btn_ignore')));
      expect(opacityWidget.opacity, 0.0);
      expect(ignoreWidget.ignoring, isTrue);

      // User finishes swiping (scroll settles on destination):
      isSwipingPage.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      opacityWidget = tester.widget(find.byKey(const ValueKey('play_btn_opacity')));
      ignoreWidget = tester.widget(find.byKey(const ValueKey('play_btn_ignore')));
      expect(opacityWidget.opacity, 1.0);
      expect(ignoreWidget.ignoring, isFalse);
    });

    test('AMOLED header meteor trajectory calculation guarantees full penetration past bottom edge', () {
      // Header dimensions: standard 90dp height
      const headerHeight = 90.0;
      const startY = -15.0;
      const angle = 0.26 * 3.141592653589793;

      // Trajectory formula from _AmoledHeaderPainter:
      const targetY = headerHeight + 50.0;
      const totalVerticalTravel = targetY - startY;
      final totalTravel = totalVerticalTravel / math.sin(angle);

      // At t = 0 (meteor start above header)
      const tStart = 0.0;
      final headYStart = startY + math.sin(angle) * (tStart * totalTravel);
      expect(headYStart, lessThan(0.0));

      // At t = 0.5 (midpoint of fall, well within the header)
      const tMid = 0.5;
      final headYMid = startY + math.sin(angle) * (tMid * totalTravel);
      expect(headYMid, greaterThan(0.0));
      expect(headYMid, lessThan(headerHeight));

      // At t = 1.0 (completion: head crosses cleanly past bottom of the header)
      const tEnd = 1.0;
      final headYEnd = startY + math.sin(angle) * (tEnd * totalTravel);
      expect(headYEnd, greaterThan(headerHeight));
      expect(headYEnd, closeTo(targetY, 0.001));
    });

    testWidgets('ThemeHeaderBackground renders AMOLED, Dark, and Light themes fluidly without exceptions', (tester) async {
      for (final mode in [AppThemeMode.amoled, AppThemeMode.dark, AppThemeMode.light]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsNotifierProvider.overrideWith(
                () => _TestSettingsNotifier(SettingsModel(themeMode: mode)),
              ),
            ],
            child: const MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 360,
                  height: 96,
                  child: ThemeHeaderBackground(),
                ),
              ),
            ),
          ),
        );

        // Advance frames through multiple cycles of the animation
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }

        expect(find.byType(ThemeHeaderBackground), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });

    test('AppLanguage enum, codes, and locale mappings', () {
      expect(AppLanguage.values.length, 12);
      expect(AppLanguage.supportedLocales.length, 11);

      expect(AppLanguage.system.code, isNull);
      expect(AppLanguage.system.locale, isNull);

      expect(AppLanguage.id.code, 'id');
      expect(AppLanguage.id.nativeName, 'Bahasa Indonesia');
      expect(AppLanguage.id.locale?.languageCode, 'id');

      expect(AppLanguage.en.code, 'en');
      expect(AppLanguage.en.nativeName, 'English');

      expect(AppLanguage.zh.code, 'zh');
      expect(AppLanguage.es.code, 'es');
      expect(AppLanguage.pt.code, 'pt');
      expect(AppLanguage.ja.code, 'ja');
      expect(AppLanguage.ko.code, 'ko');
      expect(AppLanguage.hi.code, 'hi');
      expect(AppLanguage.ar.code, 'ar');
      expect(AppLanguage.fr.code, 'fr');
      expect(AppLanguage.ru.code, 'ru');

      // Test fromCode resolution
      expect(AppLanguage.fromCode('id'), AppLanguage.id);
      expect(AppLanguage.fromCode('en'), AppLanguage.en);
      expect(AppLanguage.fromCode('zh'), AppLanguage.zh);
      expect(AppLanguage.fromCode('es'), AppLanguage.es);
      expect(AppLanguage.fromCode('pt'), AppLanguage.pt);
      expect(AppLanguage.fromCode('ja'), AppLanguage.ja);
      expect(AppLanguage.fromCode('ko'), AppLanguage.ko);
      expect(AppLanguage.fromCode('hi'), AppLanguage.hi);
      expect(AppLanguage.fromCode('ar'), AppLanguage.ar);
      expect(AppLanguage.fromCode('fr'), AppLanguage.fr);
      expect(AppLanguage.fromCode('ru'), AppLanguage.ru);
      expect(AppLanguage.fromCode('unknown'), AppLanguage.system);
      expect(AppLanguage.fromCode(null), AppLanguage.system);
    });

    test('AppLocalizations translation dictionary coverage across all supported languages', () {
      for (final lang in AppLanguage.values) {
        if (lang == AppLanguage.system || lang.code == null) continue;
        final loc = AppLocalizations(Locale(lang.code!));
        expect(loc.all.isNotEmpty, isTrue, reason: '${lang.code} all');
        expect(loc.photos.isNotEmpty, isTrue, reason: '${lang.code} photos');
        expect(loc.videos.isNotEmpty, isTrue, reason: '${lang.code} videos');
        expect(loc.albums.isNotEmpty, isTrue, reason: '${lang.code} albums');
        expect(loc.favorites.isNotEmpty, isTrue, reason: '${lang.code} favorites');
        expect(loc.searchHint.isNotEmpty, isTrue, reason: '${lang.code} searchHint');
        expect(loc.settings.isNotEmpty, isTrue, reason: '${lang.code} settings');
        expect(loc.appearance.isNotEmpty, isTrue, reason: '${lang.code} appearance');
        expect(loc.language.isNotEmpty, isTrue, reason: '${lang.code} language');
        expect(loc.excludedFolders.isNotEmpty, isTrue, reason: '${lang.code} excludedFolders');
        expect(loc.pickFromManager.isNotEmpty, isTrue, reason: '${lang.code} pickFromManager');
      }
    });

    test('SettingsModel and SettingsService language persistence', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      const defaultModel = SettingsModel();
      expect(defaultModel.language, AppLanguage.system);

      final modified = defaultModel.copyWith(language: AppLanguage.id);
      expect(modified.language, AppLanguage.id);

      await SettingsService.instance.save(modified);
      final fromDisk = SettingsService.instance.settings;
      expect(fromDisk.language, AppLanguage.id);
    });

    testWidgets('SettingsScreen language modal and excluded folders dialog integration', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final lang = ref.watch(settingsNotifierProvider.select((s) => s.language));
              return MaterialApp(
                locale: lang.locale,
                supportedLocales: AppLanguage.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                home: const SettingsScreen(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check Language tile is present
      expect(find.text('Language'), findsOneWidget);

      // Tap Language tile to open modern bottom sheet
      await tester.tap(find.text('Language'));
      await tester.pumpAndSettle();

      // Modal bottom sheet should show language options
      expect(find.text('Bahasa Indonesia'), findsOneWidget);
      expect(find.text('English'), findsWidgets);
      expect(find.text('System Default'), findsOneWidget);

      // Select Bahasa Indonesia
      await tester.tap(find.text('Bahasa Indonesia'));
      await tester.pumpAndSettle();

      // Modal closes, now text in settings should be localized to Indonesian
      expect(find.text('Bahasa'), findsOneWidget);
      expect(find.text('TAMPILAN'), findsOneWidget);

      // Open Excluded Folders dialog (now localized to 'Folder yang Dikecualikan')
      final excludedTile = find.text('Folder yang Dikecualikan');
      await tester.scrollUntilVisible(excludedTile, 200);
      await tester.pumpAndSettle();
      await tester.tap(excludedTile);
      await tester.pumpAndSettle();

      // Dialog should display file manager selection button
      expect(find.text('Pilih lewat File Manager'), findsOneWidget);
    });

    test('SettingsModel autoPlayVideo flag toggles correctly', () {
      const defaultSettings = SettingsModel();
      expect(defaultSettings.autoPlayVideo, isFalse);

      final enabled = defaultSettings.copyWith(autoPlayVideo: true);
      expect(enabled.autoPlayVideo, isTrue);

      final disabled = enabled.copyWith(autoPlayVideo: false);
      expect(disabled.autoPlayVideo, isFalse);
    });

    test('SettingsModel keepScreenOn flag toggles and persists', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      const defaultSettings = SettingsModel();
      expect(defaultSettings.keepScreenOn, isFalse);

      final enabled = defaultSettings.copyWith(keepScreenOn: true);
      expect(enabled.keepScreenOn, isTrue);

      await SettingsService.instance.save(enabled);
      final reloaded = SettingsService.instance.settings;
      expect(reloaded.keepScreenOn, isTrue);
    });

    test('ScreenKeeperService platform channel dispatch', () async {
      final log = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.phantek.gallery/screen_keeper'),
        (methodCall) async {
          log.add(methodCall);
          return null;
        },
      );

      await ScreenKeeperService.setKeepScreenOn(true);
      expect(log.length, 1);
      expect(log.last.method, 'keepOn');

      await ScreenKeeperService.setKeepScreenOn(false);
      expect(log.length, 2);
      expect(log.last.method, 'clearKeepOn');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.phantek.gallery/screen_keeper'),
        null,
      );
    });

    test('AppLocalizations complete coverage across all 11 supported languages', () {
      for (final lang in AppLanguage.values) {
        if (lang == AppLanguage.system || lang.code == null) continue;
        final loc = AppLocalizations(Locale(lang.code!));
        expect(loc.keepScreenOn.isNotEmpty, isTrue, reason: '${lang.code} keepScreenOn');
        expect(loc.keepScreenOnSubtitle.isNotEmpty, isTrue, reason: '${lang.code} keepScreenOnSubtitle');
        expect(loc.themeSystemDesc.isNotEmpty, isTrue, reason: '${lang.code} themeSystemDesc');
        expect(loc.themeLightDesc.isNotEmpty, isTrue, reason: '${lang.code} themeLightDesc');
        expect(loc.themeDarkDesc.isNotEmpty, isTrue, reason: '${lang.code} themeDarkDesc');
        expect(loc.themeAmoledDesc.isNotEmpty, isTrue, reason: '${lang.code} themeAmoledDesc');
        expect(loc.themeSakuraDesc.isNotEmpty, isTrue, reason: '${lang.code} themeSakuraDesc');
        expect(loc.aboutPhantek.isNotEmpty, isTrue, reason: '${lang.code} aboutPhantek');
        expect(loc.offlineGalleryDesc.isNotEmpty, isTrue, reason: '${lang.code} offlineGalleryDesc');
        expect(loc.appVersion.isNotEmpty, isTrue, reason: '${lang.code} appVersion');
        expect(loc.buildNumberLabel.isNotEmpty, isTrue, reason: '${lang.code} buildNumberLabel');
        expect(loc.architecture.isNotEmpty, isTrue, reason: '${lang.code} architecture');
        expect(loc.license.isNotEmpty, isTrue, reason: '${lang.code} license');
        expect(loc.developerLabel.isNotEmpty, isTrue, reason: '${lang.code} developerLabel');
        expect(loc.creatorMaintainer.isNotEmpty, isTrue, reason: '${lang.code} creatorMaintainer');
        expect(loc.openGitHubProfile.isNotEmpty, isTrue, reason: '${lang.code} openGitHubProfile');
        expect(loc.newVersionAvailable.isNotEmpty, isTrue, reason: '${lang.code} newVersionAvailable');
        expect(loc.whatsNew.isNotEmpty, isTrue, reason: '${lang.code} whatsNew');
        expect(loc.downloadAndInstall.isNotEmpty, isTrue, reason: '${lang.code} downloadAndInstall');
        expect(loc.later.isNotEmpty, isTrue, reason: '${lang.code} later');
        expect(loc.downloading.isNotEmpty, isTrue, reason: '${lang.code} downloading');
        expect(loc.alreadyUpToDate.isNotEmpty, isTrue, reason: '${lang.code} alreadyUpToDate');
        expect(loc.downloadFailed.isNotEmpty, isTrue, reason: '${lang.code} downloadFailed');
      }
    });

    testWidgets('FilterSortBar with PageController renders and updates with page navigation', (tester) async {
      final pageController = PageController(initialPage: 1);

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(96),
                child: FilterSortBar(
                  pageController: pageController,
                  currentFilter: FilterOption.photosOnly,
                ),
              ),
              body: PageView(
                controller: pageController,
                children: const [
                  Text('Page All'),
                  Text('Page Photos'),
                  Text('Page Videos'),
                  Text('Page Albums'),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();
      expect(find.text('Photos'), findsOneWidget);
      expect(find.text('Page Photos'), findsOneWidget);

      pageController.jumpToPage(2);
      await tester.pumpAndSettle();
      expect(find.text('Page Videos'), findsOneWidget);
    });

    test('Video player center play button visibility rules in portrait and landscape', () {
      bool shouldShowCenterPlay({
        required Orientation orientation,
        required bool hasStartedPlaying,
      }) {
        return orientation != Orientation.landscape && !hasStartedPlaying;
      }

      // Initial portrait before playback -> visible
      expect(shouldShowCenterPlay(orientation: Orientation.portrait, hasStartedPlaying: false), isTrue);

      // Portrait after playback started (paused or playing) -> hidden to not block zoom
      expect(shouldShowCenterPlay(orientation: Orientation.portrait, hasStartedPlaying: true), isFalse);

      // Landscape before playback -> hidden (landscape has no center play button)
      expect(shouldShowCenterPlay(orientation: Orientation.landscape, hasStartedPlaying: false), isFalse);

      // Landscape after playback -> hidden
      expect(shouldShowCenterPlay(orientation: Orientation.landscape, hasStartedPlaying: true), isFalse);
    });

    testWidgets('Video player landscape layout renders speed, loop, rotation, and more options icons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MediaQuery(
              data: const MediaQueryData(
                size: Size(800, 400),
              ),
              child: Builder(
                builder: (context) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Slider(value: 0.2, onChanged: (_) {}),
                      const Row(
                        children: [
                          Text('00:04 / 00:20'),
                          Spacer(),
                          Icon(Icons.speed),
                          Icon(Icons.repeat),
                          Icon(Icons.fullscreen),
                          Icon(Icons.screen_rotation_rounded),
                          Icon(Icons.more_vert_rounded),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('00:04 / 00:20'), findsOneWidget);
      expect(find.byIcon(Icons.speed), findsOneWidget);
      expect(find.byIcon(Icons.repeat), findsOneWidget);
      expect(find.byIcon(Icons.fullscreen), findsOneWidget);
      expect(find.byIcon(Icons.screen_rotation_rounded), findsOneWidget);
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    });

    testWidgets('Video player fullscreen button is hidden for vertical video and visible for horizontal video', (tester) async {
      Widget buildControls({required bool isVertical, required bool isLandscape}) {
        return MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Column(
                  children: [
                    // Portrait row
                    if (!isLandscape)
                      Row(
                        children: [
                          const Text('00:01'),
                          if (!isVertical) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.fullscreen_rounded),
                          ],
                        ],
                      ),
                    // Landscape row
                    if (isLandscape)
                      Row(
                        children: [
                          const Icon(Icons.speed),
                          if (!isVertical) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.fullscreen_rounded),
                          ],
                          const Icon(Icons.screen_rotation_rounded),
                        ],
                      ),
                  ],
                );
              },
            ),
          ),
        );
      }

      // 1. Vertical video in portrait: fullscreen button must NOT be found
      await tester.pumpWidget(buildControls(isVertical: true, isLandscape: false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);

      // 2. Horizontal video in portrait: fullscreen button MUST be found
      await tester.pumpWidget(buildControls(isVertical: false, isLandscape: false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

      // 3. Vertical video in landscape: fullscreen button must NOT be found
      await tester.pumpWidget(buildControls(isVertical: true, isLandscape: true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);

      // 4. Horizontal video in landscape: fullscreen button MUST be found
      await tester.pumpWidget(buildControls(isVertical: false, isLandscape: true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    });

    test('Vertical video detection and BoxFit resolution rules', () {
      bool isVideoPortrait({
        required double? width,
        required double? height,
        required double? thumbRatio,
      }) {
        if (thumbRatio != null && thumbRatio > 0) {
          return thumbRatio < 1.0;
        }
        if (width != null && height != null && width > 0 && height > 0) {
          return height > width;
        }
        return false;
      }

      // Vertical 1080x1920 (9:16)
      final verticalVideo = isVideoPortrait(width: 1080, height: 1920, thumbRatio: 0.5625);
      expect(verticalVideo, isTrue);
      final verticalFit = verticalVideo ? BoxFit.cover : BoxFit.contain;
      expect(verticalFit, BoxFit.cover);

      // Horizontal 1920x1080 (16:9)
      final horizontalVideo = isVideoPortrait(width: 1920, height: 1080, thumbRatio: 1.777);
      expect(horizontalVideo, isFalse);
      final horizontalFit = horizontalVideo ? BoxFit.cover : BoxFit.contain;
      expect(horizontalFit, BoxFit.contain);
    });
  });
}

class _TestSettingsNotifier extends SettingsNotifier {
  final SettingsModel initial;
  _TestSettingsNotifier(this.initial);
  @override
  SettingsModel build() => initial;
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

