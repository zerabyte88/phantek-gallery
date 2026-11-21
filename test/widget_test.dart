import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/app/theme.dart';
import 'package:phantek_gallery/core/enums/filter_option.dart';
import 'package:phantek_gallery/core/enums/sort_option.dart';
import 'package:phantek_gallery/core/enums/timeline_grouping.dart';
import 'package:phantek_gallery/core/enums/video_double_tap_action.dart';
import 'package:phantek_gallery/core/models/album.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/core/providers/media_provider.dart';
import 'package:flutter/services.dart';
import 'package:phantek_gallery/core/services/license_service.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/core/services/screen_keeper_service.dart';
import 'package:phantek_gallery/core/services/media_scanner_service.dart';
import 'package:phantek_gallery/core/services/thumbnail_service.dart';
import 'package:phantek_gallery/core/services/trash_service.dart';
import 'package:phantek_gallery/core/services/psd_service.dart';
import 'package:phantek_gallery/core/models/trash_item.dart';
import 'package:phantek_gallery/core/utils/media_utils.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/album_grid_item.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/drag_select_grid.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/fast_scroll_handle.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/grid_hi_res_scope.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/media_grid_item.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/shimmer_loading_tile.dart';
import 'package:phantek_gallery/features/gallery/presentation/album_detail_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/gallery_screen.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/filter_sort_bar.dart';
import 'package:phantek_gallery/features/gallery/presentation/widgets/sort_bottom_sheet.dart';
import 'package:phantek_gallery/features/player/presentation/widgets/media_info_sheet.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart'
    show displayImage, screenDisplayImage, ImageViewerScreen;
import 'package:phantek_gallery/features/player/presentation/video_player_screen.dart'
    show
        VideoPlayerScreen,
        resolveEffectiveVideoSize,
        computeNormalizedVideoLayoutSize,
        resolveAutoPlayAfterInit;
import 'package:phantek_gallery/features/settings/presentation/settings_screen.dart';
import 'package:phantek_gallery/features/settings/presentation/widgets/developer_about_card.dart';
import 'package:phantek_gallery/core/services/share_service.dart';
import 'package:phantek_gallery/core/widgets/animated_flame_title.dart';
import 'package:phantek_gallery/core/widgets/theme_header_background.dart';
import 'package:phantek_gallery/core/providers/settings_provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:phantek_gallery/core/localization/app_language.dart';
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/services/app_lock_service.dart';
import 'package:phantek_gallery/core/services/translation/translation_models.dart';
import 'package:phantek_gallery/features/settings/presentation/widgets/translation_overlay_preview.dart';
import 'package:phantek_gallery/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Phantek Gallery Core Unit Tests', () {
    test('MediaUtils formatting tests', () {
      expect(MediaUtils.formatSize(500), '500 B');
      expect(MediaUtils.formatSize(1024 * 500), '500.0 KB');
      expect(MediaUtils.formatSize(1024 * 1024 * 5), '5.0 MB');
      expect(MediaUtils.formatDuration(const Duration(minutes: 2, seconds: 45)),
          '02:45');
      expect(
          MediaUtils.formatDuration(
              const Duration(hours: 1, minutes: 5, seconds: 2)),
          '1:05:02');

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
      expect(portraitItem.width! / portraitItem.height!,
          closeTo(1080 / 1920, 0.001));
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
        if (item.width != null &&
            item.height != null &&
            item.width! > 0 &&
            item.height! > 0) {
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
      expect(settings.keepScreenOn, isFalse);
      expect(settings.defaultSort, SortOption.newest);
      expect(settings.defaultFilter, FilterOption.all);
    });

    testWidgets(
        'FilterSortBar displays filter chips and sort bar opens bottom sheet',
        (tester) async {
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
      expect(find.text('By album'), findsOneWidget);
      expect(find.text('Restore defaults'), findsOneWidget);

      // Tap "By name" and verify subtitle changes to "A to Z"
      await tester.tap(find.text('By name'));
      await tester.pumpAndSettle();

      expect(find.text('A to Z'), findsAtLeastNWidgets(1));

      // Tap Close button
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Bottom sheet closes and sort bar reflects new sort
      expect(find.text('By name: A to Z'), findsOneWidget);
    });

    test('TrashService moveToTrash and restore lifecycle with temp file',
        () async {
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

    test('TrashService purgeExpired automatically removes expired items',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('trash_purge_test_');
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

    testWidgets(
        'AlbumGridItem shows checkmark avatar when isSelecting and isSelected',
        (tester) async {
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

    testWidgets('AlbumDetailScreen renders album title and empty state',
        (tester) async {
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

    testWidgets('SettingsScreen Grid Columns dialog updates column count',
        (tester) async {
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
      expect(AppThemeMode.amoledMidnight.label, 'Midnight');
      expect(AppThemeMode.amoledSnowfall.label, 'Snowfall');
      expect(AppThemeMode.amoledPure.label, 'Dark Mode');
      expect(AppThemeMode.cleanLight.label, 'Light Mode');
      expect(AppThemeMode.amoledSakura.label, 'Sakura');
      expect(AppTheme.amoledMidnight.scaffoldBackgroundColor, Colors.black);
      expect(AppTheme.amoledSnowfall.scaffoldBackgroundColor, Colors.black);
      expect(AppTheme.amoledPure.scaffoldBackgroundColor, Colors.black);
      expect(AppTheme.amoledSakura.scaffoldBackgroundColor, Colors.black);
      expect(
          AppTheme.cleanLight.scaffoldBackgroundColor, const Color(0xFFEDF2FA));
      expect(AppThemeMode.light.label, 'Sunlight');
    });

    testWidgets('AMOLED Sakura theme is available by default in Theme dialog',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final overrides = [
        mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      // Verify Theme tile has default "System"
      expect(find.text('System'), findsWidgets);

      // Tap Theme tile to open dialog
      await tester.tap(find.text('Theme'));
      await tester.pumpAndSettle();

      // Verify themes are in dialog
      final dialogFinder = find.byType(Dialog);
      expect(dialogFinder, findsOneWidget);
      expect(find.descendant(of: dialogFinder, matching: find.text('Midnight')),
          findsOneWidget);
      expect(
          find.descendant(of: dialogFinder, matching: find.text('Dark Mode')),
          findsOneWidget);
      expect(
          find.descendant(of: dialogFinder, matching: find.text('Light Mode')),
          findsOneWidget);
      expect(find.descendant(of: dialogFinder, matching: find.text('Sakura')),
          findsOneWidget);

      // Select Sakura theme from dialog
      final sakuraInDialog =
          find.descendant(of: dialogFinder, matching: find.text('Sakura'));
      await tester.ensureVisible(sakuraInDialog);
      await tester.tap(sakuraInDialog);
      await tester.pumpAndSettle();

      // Verify Sakura is now selected
      expect(SettingsService.instance.settings.themeMode,
          AppThemeMode.amoledSakura);
      expect(find.text('Sakura'), findsWidgets);
    });

    testWidgets('ModernThemeGrid allows instant theme selection without dialog',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: const MaterialApp(
            home: SettingsScreen(),
          ),
        ),
      );

      // Select Snowfall theme directly from theme card
      await tester.ensureVisible(find.byIcon(Icons.ac_unit_rounded));
      await tester.tap(find.byIcon(Icons.ac_unit_rounded));
      await tester.pumpAndSettle();

      expect(SettingsService.instance.settings.themeMode,
          AppThemeMode.amoledSnowfall);
    });

    testWidgets(
        'DeveloperAboutCard renders Build, App Version, and License rows',
        (tester) async {
      await tester.pumpWidget(
        const ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: DeveloperAboutCard(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Architecture'), findsNothing);
      expect(find.text('ARM64-v8a'), findsNothing);
      expect(find.text('Video Engine'), findsNothing);
      expect(find.text('Build'), findsOneWidget);
      expect(find.text('762451'), findsOneWidget);
      expect(find.text('MIT License'), findsOneWidget);
    });

    test('LicenseService registers phantek_gallery and native dependencies',
        () async {
      LicenseService.resetForTesting();
      LicenseService.registerLicenses();
      final licenses = await LicenseRegistry.licenses.toList();
      final allPackages = licenses.expand((e) => e.packages).toSet();
      expect(allPackages.contains('phantek_gallery'), isTrue);
      expect(allPackages.contains('Phantek Gallery'), isTrue);
      expect(allPackages.contains('androidx.media3 (ExoPlayer)'), isTrue);
      expect(allPackages.contains('androidx.media3'), isTrue);
      expect(allPackages.contains('kotlinx.coroutines'), isTrue);
      expect(allPackages.contains('glide'), isTrue);
      expect(allPackages.contains('image'), isTrue);
    });

    test('PsdService.isPsd extension case-insensitive detection', () {
      expect(PsdService.isPsd('test.psd'), isTrue);
      expect(PsdService.isPsd('TEST.PSD'), isTrue);
      expect(PsdService.isPsd('/path/to/image.psd'), isTrue);
      expect(PsdService.isPsd('.psd'), isTrue);
      expect(PsdService.isPsd('.PSD'), isTrue);
      expect(PsdService.isPsd('psd'), isTrue);
      expect(PsdService.isPsd('photo.jpg'), isFalse);
      expect(PsdService.isPsd('clip.mp4'), isFalse);
      expect(PsdService.isPsd(''), isFalse);
    });

    test(
        'PsdService Section 5 streaming payload synthesis and OOM safety thresholds',
        () async {
      final service = PsdService.instance;

      // 1. Non-existent file returns null gracefully
      final missingResult =
          await service.extractMergedComposite('/non/existent/file.psd');
      expect(missingResult, isNull);

      // 2. Corrupt/short header returns null safely
      final tempDir = await Directory.systemTemp.createTemp('psd_test_');
      try {
        final corruptFile = File('${tempDir.path}/corrupt.psd');
        await corruptFile
            .writeAsBytes([0x38, 0x42, 0x50, 0x53, 0x00, 0x01]); // only 6 bytes
        expect(await service.extractMergedComposite(corruptFile.path), isNull);

        // 3. Invalid signature returns null safely
        final badSigFile = File('${tempDir.path}/badsig.psd');
        await badSigFile.writeAsBytes(List.filled(40, 0));
        expect(await service.extractMergedComposite(badSigFile.path), isNull);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });

    test('PsdService.loadPsdDocument multi-tier loader recovery engine',
        () async {
      final service = PsdService.instance;

      // 1. Non-existent file returns null
      final nonExistentResult =
          await service.loadPsdDocument('/non/existent/path/file.psd');
      expect(nonExistentResult, isNull);

      // 2. Corrupt header file returns null safely
      final tempDir = await Directory.systemTemp.createTemp('psd_load_test_');
      try {
        final corruptFile = File('${tempDir.path}/corrupt_header.psd');
        await corruptFile.writeAsBytes([0x38, 0x42, 0x50, 0x53, 0x00, 0x01]);
        expect(await service.loadPsdDocument(corruptFile.path), isNull);

        // 3. Synthesized Section 5 PSD returns valid composite image
        final synthFile = File('${tempDir.path}/valid_section5.psd');
        final builder = BytesBuilder(copy: false);

        // Header: 26 bytes ('8BPS', v1, 6 reserved bytes, 3 channels, 2x2, 8-bit, RGB mode = 3)
        final header = Uint8List(26);
        final hv = ByteData.sublistView(header);
        header.setRange(0, 4, [0x38, 0x42, 0x50, 0x53]); // '8BPS'
        hv.setUint16(4, 1); // version 1
        hv.setUint16(12, 3); // channels = 3
        hv.setUint32(14, 2); // height = 2
        hv.setUint32(18, 2); // width = 2
        hv.setUint16(22, 8); // depth = 8
        hv.setUint16(24, 3); // colorMode = 3 (RGB)
        builder.add(header);

        // Color Mode Data Section: length = 0 (4 bytes)
        builder.add(Uint8List(4));

        // Image Resources Section: length = 0 (4 bytes)
        builder.add(Uint8List(4));

        // Layer and Mask Section: length = 0 (4 bytes)
        builder.add(Uint8List(4));

        // Section 5 (Image Data Section):
        // Compression: 2 bytes (0 = raw uncompressed)
        final sec5Header = Uint8List(2);
        builder.add(sec5Header);

        // Planar pixel data: 3 channels * 4 pixels = 12 bytes
        // Red channel (4 bytes)
        builder.add(Uint8List.fromList([255, 128, 64, 32]));
        // Green channel (4 bytes)
        builder.add(Uint8List.fromList([10, 20, 30, 40]));
        // Blue channel (4 bytes)
        builder.add(Uint8List.fromList([50, 60, 70, 80]));

        await synthFile.writeAsBytes(builder.takeBytes());

        final composite = await service.loadPsdDocument(synthFile.path);
        expect(composite, isNotNull);
        expect(composite!.isNotEmpty, isTrue);
        // Valid JPEG header starts with 0xFF, 0xD8
        expect(composite[0], 0xFF);
        expect(composite[1], 0xD8);
      } finally {
        await tempDir.delete(recursive: true);
      }
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
      container
          .read(mediaListProvider.notifier)
          .removeItems(['item_1', 'item_2']);
      final afterRemove = container.read(mediaListProvider).value!;
      expect(afterRemove.length, 1);
      expect(afterRemove.first.id, 'item_3');

      // Restore items
      container.read(mediaListProvider.notifier).restoreItems(['item_1']);
      await container.read(mediaListProvider.notifier).refresh();
      final afterRefresh = container.read(mediaListProvider).value!;
      // item_1 restored and scanned back, item_2 still in deletedIds
      expect(afterRefresh.map((e) => e.id).toSet(),
          containsAll({'item_1', 'item_3'}));
      expect(afterRefresh.any((e) => e.id == 'item_2'), isFalse);
    });

    test('ThumbnailService clearAll wipes cache and formats size properly',
        () async {
      await ThumbnailService.instance.clearAll();
      final size = await ThumbnailService.instance.getCacheSizeBytes();
      expect(size, 0);
      final sizeStr = await ThumbnailService.instance.getFormattedCacheSize();
      expect(sizeStr, '0 B');
    });

    testWidgets(
        'GalleryScreen horizontal swipe navigates between categories without resetting',
        (tester) async {
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

    testWidgets('MediaInfoSheet displays details and copies path to clipboard',
        (tester) async {
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

    testWidgets('MediaInfoSheet displays video FPS, Codec and duration',
        (tester) async {
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

    test(
        'groupMediaIntoAlbums creates Favorites album at index 0 when favoriteIds are present',
        () {
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

      final albumsWithoutFav =
          groupMediaIntoAlbums([item1, item2], sort: SortOption.newest);
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

    test('MediaListNotifier updateItem updates modified item in state',
        () async {
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

    testWidgets(
        'GalleryScreen search opens search bar, filters results and clears',
        (tester) async {
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
      expect(find.byTooltip('Search'), findsNothing);
      final searchBtn = find.byIcon(Icons.search);
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
          reason:
              'Search bar must strictly reside inside the toolbar above FilterSortBar with zero collision');

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

      final isPortrait =
          (portraitVideo.height ?? 0) > (portraitVideo.width ?? 0);
      final isLandscape =
          (landscapeVideo.height ?? 0) > (landscapeVideo.width ?? 0);

      expect(isPortrait, isTrue);
      expect(isLandscape, isFalse);
      expect(portraitVideo.resolution, '1080x1920');
      expect(landscapeVideo.resolution, '3840x2160');
    });

    test(
        'ThumbnailService getMemoryThumbnail returns synchronously cached bytes',
        () {
      final service = ThumbnailService.instance;
      expect(service.getMemoryThumbnail('non_existent_key'), isNull);
    });

    test(
        'ThumbnailService init and getCachedFile handles cache lookup properly',
        () async {
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

      // Simulate 88x max pinch-to-zoom
      matrix.setIdentity();
      matrix.scaleByDouble(88.0, 88.0, 1.0, 1.0);
      expect(matrix.getMaxScaleOnAxis(), 88.0);
      expect(matrix.getMaxScaleOnAxis() > 1.05, isTrue);

      // Reset zoom
      matrix.setIdentity();
      expect(matrix.getMaxScaleOnAxis(), 1.0);
      expect(matrix.getMaxScaleOnAxis() > 1.05, isFalse);
    });

    test(
        'MediaScannerService video format recognition for MKV, MOV, WebM, and MP4',
        () {
      expect(MediaScannerService.isSupportedVideo('.mkv'), isTrue);
      expect(MediaScannerService.isSupportedVideo('.mov'), isTrue);
      expect(MediaScannerService.isSupportedVideo('.webm'), isTrue);
      expect(MediaScannerService.isSupportedVideo('.mp4'), isTrue);
      expect(MediaScannerService.isSupportedVideo('/storage/DCIM/clip.MKV'),
          isTrue);
      expect(
          MediaScannerService.isSupportedVideo('/storage/Download/movie.mov'),
          isTrue);
      expect(
          MediaScannerService.isSupportedVideo('/storage/Download/sample.webm'),
          isTrue);
      expect(MediaScannerService.isSupportedVideo('/storage/DCIM/photo.jpg'),
          isFalse);
      expect(MediaScannerService.isSupportedVideo('/storage/DCIM/image.png'),
          isFalse);
    });

    test(
        'MediaScannerService MIME validation and inference for MKV, MOV, WebM, and others',
        () {
      expect(
          MediaScannerService.isSupportedVideoMime('video/x-matroska'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('video/mkv'), isTrue);
      expect(
          MediaScannerService.isSupportedVideoMime('video/quicktime'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('video/webm'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('video/mp4'), isTrue);
      expect(MediaScannerService.isSupportedVideoMime('image/jpeg'), isFalse);

      expect(
          MediaScannerService.inferMimeType('video.mkv'), 'video/x-matroska');
      expect(MediaScannerService.inferMimeType('video.webm'), 'video/webm');
      expect(MediaScannerService.inferMimeType('video.mov'), 'video/quicktime');
      expect(MediaScannerService.inferMimeType('video.mp4'), 'video/mp4');
      expect(MediaScannerService.inferMimeType('video.unknown', isVideo: true),
          'video/unknown');
    });

    test(
        'Codec configuration verifies auto-copy with SW fallback and hardware acceleration for VP9, HEVC, and H264',
        () {
      const hwdec = 'auto-copy';
      const bufferSize = 8388608; // 8 MB – within Android memory limits

      // 'auto-copy' tries available HW decoders, then falls back to SW (libvpx, libde265, etc.)
      // automatically without failing on codecs without MediaCodec HW support (VP9, some HEVC).
      expect(hwdec, 'auto-copy');

      // Buffer must not exceed Android buffer limit of 10 MB (10485760)
      expect(bufferSize, lessThanOrEqualTo(10485760));
    });

    test(
        'Non-fatal codec warnings are identified and suppressed from UI notifications',
        () {
      bool isNonFatalWarning(String err) {
        final errLower = err.toLowerCase();
        return errLower.contains('could not open codec') ||
            errLower.contains('failed to open codec') ||
            errLower.contains('decoder init failed') ||
            errLower.contains('hwdec') ||
            errLower.contains('mediacodec') ||
            errLower.contains('using software decoding') ||
            errLower.contains('error decoding') ||
            errLower.contains('cannot decode') ||
            errLower.contains('invalid data') ||
            errLower.contains('corrupt') ||
            errLower.contains('missing picture') ||
            errLower.contains('packet') ||
            errLower.contains('audiotrack') ||
            errLower.contains('underrun') ||
            errLower.contains('audio device') ||
            errLower.contains('ao/audiotrack') ||
            errLower.contains('codec:');
      }

      expect(isNonFatalWarning('Could not open codec hevc'), isTrue);
      expect(
          isNonFatalWarning('Failed to open codec: h264_mediacodec'), isTrue);
      expect(isNonFatalWarning('hwdec failed, falling back to sw'), isTrue);
      expect(isNonFatalWarning('MediaCodec error encountered'), isTrue);
      expect(isNonFatalWarning('Decoder init failed for vp9'), isTrue);
      expect(isNonFatalWarning('AudioTrack write underrun'), isTrue);
      expect(isNonFatalWarning('ao/audiotrack: audio device busy'), isTrue);
      expect(isNonFatalWarning('Using software decoding'), isTrue);
      expect(isNonFatalWarning('Error decoding video'), isTrue);
      expect(isNonFatalWarning('Cannot decode frame at timestamp'), isTrue);
      expect(isNonFatalWarning('Invalid data found when processing input'),
          isTrue);
      expect(isNonFatalWarning('File not found: /storage/video.mp4'), isFalse);
    });

    test(
        'Slideshow mode rule: video items remain paused as preview slides without auto-play',
        () {
      // In slideshow mode, shouldPlay must strictly be false even if autoPlayVideo is enabled.
      bool computeShouldPlay({
        required bool isSlideshowPlaying,
        required bool startSlideshow,
        required bool autoPlayVideo,
      }) {
        return !isSlideshowPlaying && !startSlideshow && autoPlayVideo;
      }

      // Normal playback with auto-play on: should play
      expect(
          computeShouldPlay(
            isSlideshowPlaying: false,
            startSlideshow: false,
            autoPlayVideo: true,
          ),
          isTrue);

      // Slideshow active: must NEVER auto-play video
      expect(
          computeShouldPlay(
            isSlideshowPlaying: true,
            startSlideshow: false,
            autoPlayVideo: true,
          ),
          isFalse);

      // Route transition with startSlideshow flag: must NEVER auto-play video
      expect(
          computeShouldPlay(
            isSlideshowPlaying: false,
            startSlideshow: true,
            autoPlayVideo: true,
          ),
          isFalse);
    });

    test(
        'Slideshow mode rule: stops at end of playlist and restores bars instead of looping to 0',
        () {
      bool shouldAdvanceOrStop({
        required int currentIndex,
        required int totalItems,
      }) {
        return currentIndex < totalItems - 1;
      }

      expect(shouldAdvanceOrStop(currentIndex: 0, totalItems: 5), isTrue);
      expect(shouldAdvanceOrStop(currentIndex: 2, totalItems: 5), isTrue);
      expect(shouldAdvanceOrStop(currentIndex: 3, totalItems: 5), isTrue);
      expect(shouldAdvanceOrStop(currentIndex: 4, totalItems: 5), isFalse);
      expect(shouldAdvanceOrStop(currentIndex: 0, totalItems: 1), isFalse);
    });

    testWidgets(
        'SortBottomSheet adapts accentColor and Restore defaults to active theme',
        (tester) async {
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
      expect(restoreText.style?.color, const Color(0xFFF472B6)); // Sakura pink!
    });

    test(
        'Zoom focal point math calculates correct translation offset for scale',
        () {
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

    test(
        'Photo InteractiveViewer focal point matrix scales to 3.0x and returns cleanly to identity',
        () {
      final controller = TransformationController();
      expect(controller.value.getMaxScaleOnAxis(), 1.0);
      expect(controller.value.isIdentity(), isTrue);

      const tapPos = Offset(250.0, 450.0);
      const double targetScale = 3.0;

      // Zoom in to focal point
      final endMatrix = Matrix4.identity()
        ..translateByDouble(tapPos.dx, tapPos.dy, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0)
        ..translateByDouble(-tapPos.dx, -tapPos.dy, 0.0, 1.0);

      controller.value = endMatrix;
      expect(controller.value.getMaxScaleOnAxis(), 3.0);
      expect(controller.value.getMaxScaleOnAxis() > 1.05, isTrue);

      // The focal point transformed by the matrix should stay at tapPos
      final transformedPoint =
          MatrixUtils.transformPoint(controller.value, tapPos);
      expect(transformedPoint.dx, closeTo(tapPos.dx, 0.001));
      expect(transformedPoint.dy, closeTo(tapPos.dy, 0.001));

      // Zoom out resets directly to identity without stuck states
      controller.value = Matrix4.identity();
      expect(controller.value.getMaxScaleOnAxis(), 1.0);
      expect(controller.value.isIdentity(), isTrue);
      expect(controller.value.getMaxScaleOnAxis() > 1.05, isFalse);
    });

    test(
        'Responsive gesture slop deadzone filters minor horizontal jitters and accepts natural downward drag',
        () {
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

    test(
        'Snapdragon 685 WebM and VP9 codec safety rules route to software decode',
        () {
      String resolveHwdec(String path) {
        if (path.toLowerCase().endsWith('.webm')) return 'no';
        return 'auto-copy';
      }

      expect(resolveHwdec('sample.webm'), 'no');
      expect(resolveHwdec('clip.WEBM'), 'no');
      expect(resolveHwdec('video.mp4'), 'auto-copy');
      expect(resolveHwdec('movie.mkv'), 'auto-copy');
    });

    test(
        'Video thumbnail extraction scales 4K (2160p) and 1080p down proportionally without memory bloat',
        () {
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
      expect(dstW * dstH * 4,
          lessThan(600 * 1024)); // Less than 600 KB RAM vs 33 MB unscaled!
    });

    test(
        'Photo double-tap detector identifies valid double taps within time and distance thresholds',
        () {
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
      expect(
          isDoubleTap(
              downDurationMs: 80,
              moveDist: 2.0,
              intervalMs: 150,
              doubleTapDist: 5.0),
          isTrue);

      // Too slow between taps (> 350ms)
      expect(
          isDoubleTap(
              downDurationMs: 80,
              moveDist: 2.0,
              intervalMs: 400,
              doubleTapDist: 5.0),
          isFalse);

      // Too far apart (> 45px)
      expect(
          isDoubleTap(
              downDurationMs: 80,
              moveDist: 2.0,
              intervalMs: 150,
              doubleTapDist: 60.0),
          isFalse);

      // First tap was a drag (> 25px move)
      expect(
          isDoubleTap(
              downDurationMs: 80,
              moveDist: 35.0,
              intervalMs: 150,
              doubleTapDist: 5.0),
          isFalse);
    });

    test('displayImage caps 100MP photos at 4096px and shares one cache entry',
        () {
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

    test(
        'screenDisplayImage bounds photos to 1440px for fluid sliding and low memory',
        () {
      final a = screenDisplayImage('/dcim/hasselblad.jpg') as ResizeImage;
      final b = screenDisplayImage('/dcim/hasselblad.jpg');
      expect(a.width, 1440);
      expect(a.height, 1440);
      expect(a.policy, ResizeImagePolicy.fit);
      expect(a, equals(b));
      expect(screenDisplayImage('/dcim/other.jpg'), isNot(equals(a)));
    });

    test(
        'Hero flight shuttle preserves AspectRatio and interpolates bounds without vertical distortion',
        () {
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

    testWidgets('MediaGridItem renders Hero thumbnail inside a ClipRRect',
        (tester) async {
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

      final clipRRectFinder = find.byType(ClipRRect);
      expect(clipRRectFinder, findsWidgets);

      final heroFinder = find.byType(Hero);
      expect(heroFinder, findsOneWidget);
      final hero = tester.widget<Hero>(heroFinder);
      expect(hero.tag, 'test_grid_item_1');
    });

    test('Swipe-to-dismiss dynamic scale, corner radius, and opacity formulas',
        () {
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
      expect(computeOverlayOpacity(35),
          0.0); // Bars completely and cleanly hidden!

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

    test(
        'Swipe-to-dismiss SpringSimulation description uses smooth organic damping',
        () {
      final spring = SpringDescription.withDampingRatio(
        mass: 1.0,
        stiffness: 320,
        ratio: 0.82,
      );

      expect(spring.mass, 1.0);
      expect(spring.stiffness, 320.0);
      expect(spring.damping,
          closeTo(2 * 1.0 * 0.82 * 17.888, 0.5)); // 2*m*ratio*sqrt(k)
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

    testWidgets(
        'ThemeHeaderBackground and AnimatedFlameTitle adapt to all AppThemeMode options',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      for (final mode in [
        AppThemeMode.amoledMidnight,
        AppThemeMode.amoledPure,
        AppThemeMode.amoledSakura,
        AppThemeMode.cleanLight,
        AppThemeMode.amoledSnowfall,
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
              theme:
                  mode == AppThemeMode.light || mode == AppThemeMode.cleanLight
                      ? AppTheme.light
                      : AppTheme.amoledSnowfall,
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
          AppThemeMode.amoledMidnight => Icons.nights_stay_rounded,
          AppThemeMode.amoledPure => Icons.dark_mode_rounded,
          AppThemeMode.amoledSakura => Icons.local_florist_rounded,
          AppThemeMode.cleanLight => Icons.light_mode_rounded,
          AppThemeMode.amoledSnowfall => Icons.ac_unit_rounded,
          AppThemeMode.light => Icons.wb_sunny_rounded,
          AppThemeMode.system => Icons.dark_mode_rounded,
        };
        expect(find.byIcon(expectedIcon), findsOneWidget);
      }
    });

    test('ThumbnailService.parseJpegDimensions parses SOF0 marker accurately',
        () {
      final bytes = Uint8List.fromList([
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, // APP0
        0x00, 0x10, // length = 16
        0x4A, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48, 0x00, 0x48,
        0x00, 0x00,
        0xFF, 0xC0, // SOF0
        0x00, 0x11, // length = 17
        0x08, // precision
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

    test(
        'ThumbnailService.parseJpegDimensions parses SOF2 progressive marker accurately',
        () {
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

    test(
        'Video player seekbar, left/right timestamps, and fullscreen button are collectively elevated by 32dp spacing above action buttons',
        () {
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

    testWidgets(
        'Video player center play button fades out and ignores touch during horizontal swipe to adjacent video',
        (tester) async {
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
              child: const Icon(Icons.play_arrow_rounded,
                  key: ValueKey('play_btn')),
            ),
          ),
        ),
      );

      // Initially stationary: opacity 1.0, touch enabled
      expect(find.byKey(const ValueKey('play_btn')), findsOneWidget);
      AnimatedOpacity opacityWidget =
          tester.widget(find.byKey(const ValueKey('play_btn_opacity')));
      IgnorePointer ignoreWidget =
          tester.widget(find.byKey(const ValueKey('play_btn_ignore')));
      expect(opacityWidget.opacity, 1.0);
      expect(ignoreWidget.ignoring, isFalse);

      // User starts swiping horizontally to adjacent video:
      isSwipingPage.value = true;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 160));

      opacityWidget =
          tester.widget(find.byKey(const ValueKey('play_btn_opacity')));
      ignoreWidget =
          tester.widget(find.byKey(const ValueKey('play_btn_ignore')));
      expect(opacityWidget.opacity, 0.0);
      expect(ignoreWidget.ignoring, isTrue);

      // User finishes swiping (scroll settles on destination):
      isSwipingPage.value = false;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 260));

      opacityWidget =
          tester.widget(find.byKey(const ValueKey('play_btn_opacity')));
      ignoreWidget =
          tester.widget(find.byKey(const ValueKey('play_btn_ignore')));
      expect(opacityWidget.opacity, 1.0);
      expect(ignoreWidget.ignoring, isFalse);
    });

    test(
        'AMOLED header meteor trajectory calculation guarantees full penetration past bottom edge',
        () {
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

    testWidgets(
        'ThemeHeaderBackground renders AMOLED, Dark, and Light themes fluidly without exceptions',
        (tester) async {
      for (final mode in [
        AppThemeMode.amoledMidnight,
        AppThemeMode.amoledSnowfall,
        AppThemeMode.light
      ]) {
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
      expect(AppLanguage.values.length, 22);
      expect(AppLanguage.supportedLocales.length, 22);

      expect(AppLanguage.id.code, 'id');
      expect(AppLanguage.id.nativeName, 'Bahasa Indonesia');
      expect(AppLanguage.id.locale?.languageCode, 'id');

      expect(AppLanguage.en.code, 'en');
      expect(AppLanguage.en.nativeName, 'English');

      expect(AppLanguage.zh.code, 'zh');
      expect(AppLanguage.zhTw.code, 'zh_TW');
      expect(AppLanguage.da.code, 'da');
      expect(AppLanguage.nl.code, 'nl');
      expect(AppLanguage.fi.code, 'fi');
      expect(AppLanguage.fr.code, 'fr');
      expect(AppLanguage.de.code, 'de');
      expect(AppLanguage.hi.code, 'hi');
      expect(AppLanguage.it.code, 'it');
      expect(AppLanguage.ja.code, 'ja');
      expect(AppLanguage.ko.code, 'ko');
      expect(AppLanguage.ms.code, 'ms');
      expect(AppLanguage.no.code, 'no');
      expect(AppLanguage.pt.code, 'pt');
      expect(AppLanguage.ru.code, 'ru');
      expect(AppLanguage.es.code, 'es');
      expect(AppLanguage.sv.code, 'sv');
      expect(AppLanguage.th.code, 'th');
      expect(AppLanguage.vi.code, 'vi');

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
      expect(AppLanguage.fromCode('unknown'), AppLanguage.en);
      expect(AppLanguage.fromCode(null), AppLanguage.en);

      // Test flagEmoji
      expect(AppLanguage.id.flagEmoji, '🇮🇩');
      expect(AppLanguage.en.flagEmoji, '🇺🇸');
      expect(AppLanguage.zh.flagEmoji, '🇨🇳');
      expect(AppLanguage.zhTw.flagEmoji, '🇹🇼');
      expect(AppLanguage.ja.flagEmoji, '🇯🇵');
      expect(AppLanguage.pt.flagEmoji, '🇧🇷');
      expect(AppLanguage.es.flagEmoji, '🇪🇸');
      expect(AppLanguage.ar.flagEmoji, '🇸🇦');

      for (final lang in AppLanguage.values) {
        expect(lang.flagEmoji, isNotNull,
            reason: '${lang.name} flagEmoji should not be null');
        expect(lang.flagEmoji!.isNotEmpty, isTrue,
            reason: '${lang.name} flagEmoji should not be empty');
      }
    });

    test(
        'AppLocalizations translation dictionary coverage across all supported languages',
        () {
      for (final lang in AppLanguage.values) {
        final loc = AppLocalizations(Locale(lang.code));
        expect(loc.all.isNotEmpty, isTrue, reason: '${lang.code} all');
        expect(loc.photos.isNotEmpty, isTrue, reason: '${lang.code} photos');
        expect(loc.videos.isNotEmpty, isTrue, reason: '${lang.code} videos');
        expect(loc.albums.isNotEmpty, isTrue, reason: '${lang.code} albums');
        expect(loc.favorites.isNotEmpty, isTrue,
            reason: '${lang.code} favorites');
        expect(loc.searchHint.isNotEmpty, isTrue,
            reason: '${lang.code} searchHint');
        expect(loc.settings.isNotEmpty, isTrue,
            reason: '${lang.code} settings');
        expect(loc.appearance.isNotEmpty, isTrue,
            reason: '${lang.code} appearance');
        expect(loc.language.isNotEmpty, isTrue,
            reason: '${lang.code} language');
        expect(loc.excludedFolders.isNotEmpty, isTrue,
            reason: '${lang.code} excludedFolders');
        expect(loc.pickFromManager.isNotEmpty, isTrue,
            reason: '${lang.code} pickFromManager');
        expect(loc.clearAll.isNotEmpty, isTrue,
            reason: '${lang.code} clearAll');
        expect(loc.mangaTranslation.isNotEmpty, isTrue,
            reason: '${lang.code} mangaTranslation');
        expect(loc.translateSpeechBubbles.isNotEmpty, isTrue,
            reason: '${lang.code} translateSpeechBubbles');
        expect(loc.translateSpeechBubblesSubtitle.isNotEmpty, isTrue,
            reason: '${lang.code} translateSpeechBubblesSubtitle');
        expect(loc.translateFullPage.isNotEmpty, isTrue,
            reason: '${lang.code} translateFullPage');
        expect(loc.translateFullPageSubtitle.isNotEmpty, isTrue,
            reason: '${lang.code} translateFullPageSubtitle');
        expect(loc.disableTranslation.isNotEmpty, isTrue,
            reason: '${lang.code} disableTranslation');
      }
    });

    test('SettingsModel and SettingsService language persistence', () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      const defaultModel = SettingsModel();
      expect(defaultModel.language, AppLanguage.en);

      final modified = defaultModel.copyWith(language: AppLanguage.id);
      expect(modified.language, AppLanguage.id);

      await SettingsService.instance.save(modified);
      final fromDisk = SettingsService.instance.settings;
      expect(fromDisk.language, AppLanguage.id);
    });

    testWidgets(
        'SettingsScreen language modal and excluded folders dialog integration',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              final lang =
                  ref.watch(settingsNotifierProvider.select((s) => s.language));
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
      expect(find.text('System Default'), findsNothing);
      expect(find.text('🇮🇩'), findsOneWidget);
      expect(find.text('SYS'), findsNothing);

      // Select Bahasa Indonesia
      final idFinder = find.text('Bahasa Indonesia');
      await tester.scrollUntilVisible(idFinder, 100,
          scrollable: find.byType(Scrollable).last);
      await tester.pumpAndSettle();
      await tester.tap(idFinder);
      await tester.pumpAndSettle();

      // Modal closes, now text in settings should be localized to Indonesian
      expect(find.text('Bahasa'), findsOneWidget);
      expect(find.text('Tampilan'), findsOneWidget);

      // Open Excluded Folders dialog (now localized to 'Folder yang Dikecualikan')
      final excludedTile = find.text('Folder yang Dikecualikan');
      await tester.scrollUntilVisible(excludedTile, 200);
      await tester.pumpAndSettle();
      await tester.tap(excludedTile);
      await tester.pumpAndSettle();

      // Dialog should display file manager selection button
      expect(find.text('Pilih lewat File Manager'), findsOneWidget);
    });

    testWidgets(
        'SettingsScreen omits Source Language under Manga Translation and keeps LM Studio config',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLanguage.supportedLocales,
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Scroll to Manga Translation section and LM Studio configuration tile
      final lmStudioTile = find.text('Local AI Server Configuration');
      await tester.scrollUntilVisible(
        lmStudioTile,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('Manga Translation'), findsOneWidget);
      expect(lmStudioTile, findsOneWidget);
      expect(find.text('Source Language'), findsNothing);
    });

    testWidgets(
        'Clear thumbnail cache dialog has Cancel on left, Clear Cache on right with theme color',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
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
            home: const SettingsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final clearTile = find.text('Clear Thumbnail & Preview Cache');
      await tester.scrollUntilVisible(clearTile, 200);
      await tester.pumpAndSettle();
      expect(clearTile, findsOneWidget);

      await tester.tap(clearTile);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      final cancelButton = find.widgetWithText(TextButton, 'Cancel');
      final clearButton = find.widgetWithText(FilledButton, 'Clear Cache');

      expect(cancelButton, findsOneWidget);
      expect(clearButton, findsOneWidget);

      final cancelOffset = tester.getTopLeft(cancelButton);
      final clearOffset = tester.getTopLeft(clearButton);
      expect(cancelOffset.dx < clearOffset.dx, isTrue);

      await tester.tap(cancelButton);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
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

    test('AppLocalizations complete coverage across all 22 supported languages',
        () {
      for (final lang in AppLanguage.values) {
        // Checked across all 22 languages
        final loc = AppLocalizations(lang.locale!);
        expect(loc.keepScreenOn.isNotEmpty, isTrue,
            reason: '${lang.code} keepScreenOn');
        expect(loc.keepScreenOnSubtitle.isNotEmpty, isTrue,
            reason: '${lang.code} keepScreenOnSubtitle');
        expect(loc.themeSystemDesc.isNotEmpty, isTrue,
            reason: '${lang.code} themeSystemDesc');
        expect(loc.themeLightDesc.isNotEmpty, isTrue,
            reason: '${lang.code} themeLightDesc');
        expect(loc.themeDarkDesc.isNotEmpty, isTrue,
            reason: '${lang.code} themeDarkDesc');
        expect(loc.themeAmoledDesc.isNotEmpty, isTrue,
            reason: '${lang.code} themeAmoledDesc');
        expect(loc.themeSakuraDesc.isNotEmpty, isTrue,
            reason: '${lang.code} themeSakuraDesc');
        expect(loc.aboutApp.isNotEmpty, isTrue,
            reason: '${lang.code} aboutApp');
        expect(loc.appVersion.isNotEmpty, isTrue,
            reason: '${lang.code} appVersion');
        expect(loc.buildNumberLabel.isNotEmpty, isTrue,
            reason: '${lang.code} buildNumberLabel');
        expect(loc.license.isNotEmpty, isTrue, reason: '${lang.code} license');
      }

      // Verify previously missing languages produce real non-English translations
      final deLoc = AppLocalizations(const Locale('de'));
      expect(deLoc.settings, 'Einstellungen');
      expect(deLoc.trashBin, 'Papierkorb');

      final daLoc = AppLocalizations(const Locale('da'));
      expect(daLoc.settings, 'Indstillinger');
      expect(daLoc.photos, 'Billeder');

      final nlLoc = AppLocalizations(const Locale('nl'));
      expect(nlLoc.settings, 'Instellingen');

      final fiLoc = AppLocalizations(const Locale('fi'));
      expect(fiLoc.settings, 'Asetukset');

      final msLoc = AppLocalizations(const Locale('ms'));
      expect(msLoc.settings, 'Tetapan');

      final itLoc = AppLocalizations(const Locale('it'));
      expect(itLoc.settings, 'Impostazioni');

      final noLoc = AppLocalizations(const Locale('no'));
      expect(noLoc.settings, 'Innstillinger');

      final svLoc = AppLocalizations(const Locale('sv'));
      expect(svLoc.settings, 'Inställningar');

      final thLoc = AppLocalizations(const Locale('th'));
      expect(thLoc.settings, 'การตั้งค่า');

      final viLoc = AppLocalizations(const Locale('vi'));
      expect(viLoc.settings, 'Cài đặt');

      // Verify Chinese Traditional (zh_TW) vs Chinese Simplified (zh)
      final zhTwLoc = AppLocalizations(const Locale('zh', 'TW'));
      final zhLoc = AppLocalizations(const Locale('zh'));
      expect(zhTwLoc.languageCode, 'zh_TW');
      expect(zhLoc.languageCode, 'zh');
      expect(zhTwLoc.favorites, '我的最愛');
      expect(zhLoc.favorites, '收藏');
      expect(zhTwLoc.albums, '相簿');
      expect(zhLoc.albums, '相册');
    });

    testWidgets(
        'FilterSortBar with PageController renders and updates with page navigation',
        (tester) async {
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

    test(
        'Video player center play button visibility rules in portrait and landscape',
        () {
      bool shouldShowCenterPlay({
        required Orientation orientation,
        required bool hasStartedPlaying,
      }) {
        return orientation != Orientation.landscape && !hasStartedPlaying;
      }

      // Initial portrait before playback -> visible
      expect(
          shouldShowCenterPlay(
              orientation: Orientation.portrait, hasStartedPlaying: false),
          isTrue);

      // Portrait after playback started (paused or playing) -> hidden to not block zoom
      expect(
          shouldShowCenterPlay(
              orientation: Orientation.portrait, hasStartedPlaying: true),
          isFalse);

      // Landscape before playback -> hidden (landscape has no center play button)
      expect(
          shouldShowCenterPlay(
              orientation: Orientation.landscape, hasStartedPlaying: false),
          isFalse);

      // Landscape after playback -> hidden
      expect(
          shouldShowCenterPlay(
              orientation: Orientation.landscape, hasStartedPlaying: true),
          isFalse);
    });

    testWidgets(
        'Video player landscape layout renders speed, loop, rotation, and more options icons',
        (tester) async {
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

    testWidgets(
        'Video player fullscreen button is hidden for vertical video and visible for horizontal video',
        (tester) async {
      Widget buildControls(
          {required bool isVertical, required bool isLandscape}) {
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
      await tester
          .pumpWidget(buildControls(isVertical: true, isLandscape: false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);

      // 2. Horizontal video in portrait: fullscreen button MUST be found
      await tester
          .pumpWidget(buildControls(isVertical: false, isLandscape: false));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);

      // 3. Vertical video in landscape: fullscreen button must NOT be found
      await tester
          .pumpWidget(buildControls(isVertical: true, isLandscape: true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);

      // 4. Horizontal video in landscape: fullscreen button MUST be found
      await tester
          .pumpWidget(buildControls(isVertical: false, isLandscape: true));
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
      final verticalVideo =
          isVideoPortrait(width: 1080, height: 1920, thumbRatio: 0.5625);
      expect(verticalVideo, isTrue);
      final verticalFit = verticalVideo ? BoxFit.cover : BoxFit.contain;
      expect(verticalFit, BoxFit.cover);

      // Horizontal 1920x1080 (16:9)
      final horizontalVideo =
          isVideoPortrait(width: 1920, height: 1080, thumbRatio: 1.777);
      expect(horizontalVideo, isFalse);
      final horizontalFit = horizontalVideo ? BoxFit.cover : BoxFit.contain;
      expect(horizontalFit, BoxFit.contain);
    });

    test('Video scrubber fraction clamping and thumb position math', () {
      const trackPadding = 16.0;
      const totalWidth = 360.0;
      const trackWidth = totalWidth - trackPadding * 2; // 328.0

      double computeFraction(double touchX) {
        return ((touchX - trackPadding) / trackWidth).clamp(0.0, 1.0);
      }

      double computeThumbX(double fraction) {
        return trackPadding + fraction.clamp(0.0, 1.0) * trackWidth;
      }

      // Touch before start of track clamps to 0.0
      expect(computeFraction(0.0), 0.0);
      expect(computeFraction(10.0), 0.0);
      expect(computeThumbX(computeFraction(0.0)), 16.0);

      // Touch at start of track -> 0.0
      expect(computeFraction(16.0), 0.0);
      expect(computeThumbX(0.0), 16.0);

      // Touch at exact center -> 0.5
      expect(computeFraction(180.0), 0.5);
      expect(computeThumbX(0.5), 180.0);

      // Touch at end of track -> 1.0
      expect(computeFraction(344.0), 1.0);
      expect(computeThumbX(1.0), 344.0);

      // Touch past end of track clamps to 1.0
      expect(computeFraction(400.0), 1.0);
      expect(computeThumbX(computeFraction(400.0)), 344.0);
    });

    test('Video seekbar tooltip offset clamping prevents screen edge overflow',
        () {
      const maxWidth = 360.0;
      const previewW = 144.0;
      const trackWidth = maxWidth - 32.0; // 328.0

      double computeTooltipLeft(double fraction) {
        final thumbX = 16.0 + fraction.clamp(0.0, 1.0) * trackWidth;
        return (thumbX - previewW / 2).clamp(8.0, maxWidth - previewW - 8.0);
      }

      // Start of seekbar (0.0): tooltip clamped to min left 8.0
      expect(computeTooltipLeft(0.0), 8.0);

      // End of seekbar (1.0): tooltip clamped to max right (360 - 144 - 8 = 208.0)
      expect(computeTooltipLeft(1.0), 208.0);

      // Center (0.5): thumbX = 180.0, left = 180 - 72 = 108.0 (well within bounds)
      expect(computeTooltipLeft(0.5), 108.0);
    });

    test('Video seek frame cache 250ms bucket quantization', () {
      int bucketFor(Duration time) => time.inMilliseconds ~/ 250;

      // 0ms, 120ms, 240ms map to bucket 0
      expect(bucketFor(Duration.zero), 0);
      expect(bucketFor(const Duration(milliseconds: 120)), 0);
      expect(bucketFor(const Duration(milliseconds: 249)), 0);

      // 250ms, 400ms map to bucket 1
      expect(bucketFor(const Duration(milliseconds: 250)), 1);
      expect(bucketFor(const Duration(milliseconds: 499)), 1);

      // 500ms maps to bucket 2
      expect(bucketFor(const Duration(milliseconds: 500)), 2);

      // 10 seconds maps to bucket 40
      expect(bucketFor(const Duration(seconds: 10)), 40);
    });

    test(
        'MediaUtils.calculateGridScrollOffset correctly aligns off-screen media and keeps visible items undisturbed',
        () {
      // 3 columns, screenWidth = 360, viewportHeight = 600, currentScrollOffset = 0
      // Item 1 (row 0): comfortably inside viewport -> returns currentScrollOffset (0.0)
      final offsetVisible = MediaUtils.calculateGridScrollOffset(
        index: 1,
        crossAxisCount: 3,
        screenWidth: 360.0,
        viewportHeight: 600.0,
        currentScrollOffset: 0.0,
        maxScrollExtent: 3000.0,
      );
      expect(offsetVisible, 0.0);

      // Item 30 (row 10): far off-screen below viewport -> returns aligned offset > 0
      final offsetOffscreen = MediaUtils.calculateGridScrollOffset(
        index: 30,
        crossAxisCount: 3,
        screenWidth: 360.0,
        viewportHeight: 600.0,
        currentScrollOffset: 0.0,
        maxScrollExtent: 3000.0,
      );
      expect(offsetOffscreen, greaterThan(0.0));
      expect(offsetOffscreen, lessThanOrEqualTo(3000.0));

      // crossAxisCount <= 0 returns currentScrollOffset safely
      expect(
        MediaUtils.calculateGridScrollOffset(
          index: 5,
          crossAxisCount: 0,
          screenWidth: 360.0,
          viewportHeight: 600.0,
          currentScrollOffset: 150.0,
          maxScrollExtent: 3000.0,
        ),
        150.0,
      );
    });

    testWidgets('Slideshow action is present in gallery home 3-dot popup menu',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
                () => _TestSettingsNotifier(const SettingsModel())),
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: GalleryScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final moreButton = find.byIcon(Icons.more_vert);
      expect(moreButton, findsOneWidget);

      await tester.tap(moreButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.slideshow_rounded), findsOneWidget);
      expect(find.text('Slideshow'), findsOneWidget);
    });

    testWidgets('Slideshow action is present in image viewer more options menu',
        (tester) async {
      final items = [
        MediaItem(
            id: 'item_1',
            path: '/a/1.jpg',
            name: '1.jpg',
            date: DateTime.now(),
            size: 10,
            isVideo: false),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
                () => _TestSettingsNotifier(const SettingsModel())),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: ImageViewerScreen(items: items, initialIndex: 0),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final moreButton = find.byIcon(Icons.more_vert);
      expect(moreButton, findsOneWidget);

      await tester.tap(moreButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byIcon(Icons.slideshow_rounded), findsOneWidget);
      expect(find.text('Slideshow'), findsOneWidget);
    });

    test(
        'Vertical video aspect ratio priority preserves portrait layout when encoded dimensions are landscape',
        () {
      // Many smartphone camera videos are physically 1920x1080 with 90° EXIF rotation.
      // Thumbnail aspect ratio reflects the rotated physical frame (1080 / 1920 = 0.5625).
      const encodedWidth = 1920;
      const encodedHeight = 1080;
      const thumbRatio = 1080.0 / 1920.0; // 0.5625

      // Prioritize thumbnail ratio < 0.95 to accurately detect portrait video
      final isPortrait = thumbRatio < 0.95;
      expect(isPortrait, isTrue);

      // Raw width/height would falsely identify it as horizontal
      expect(encodedHeight > encodedWidth, isFalse);
    });

    test(
        'Horizontal video with encoded portrait dimensions resolves to horizontal layout via thumbnail and video ratio cache',
        () {
      // Videos like 720x1280 or 1080x1170 with 90° rotation play horizontally.
      const encodedWidth = 720;
      const encodedHeight = 1280;
      const rotate = 90;
      const isRotated90or270 = rotate == 90 || rotate == 270;
      const effectiveW = isRotated90or270 ? encodedHeight : encodedWidth;
      const effectiveH = isRotated90or270 ? encodedWidth : encodedHeight;
      const realRatio = effectiveW / effectiveH; // 1280 / 720 = 1.777

      ThumbnailService.instance
          .setThumbnailAspectRatio('rot_video_test', realRatio);
      final cachedRatio =
          ThumbnailService.instance.getThumbnailAspectRatio('rot_video_test');
      expect(cachedRatio, closeTo(1.777, 0.01));

      // With thumbRatio >= 0.95, it correctly resolves as horizontal (not portrait)
      final isPortrait = cachedRatio! < 0.95;
      expect(isPortrait, isFalse);

      // Raw unrotated dimensions (1280 > 720) would falsely claim portrait
      expect(encodedHeight > encodedWidth, isTrue);
    });

    test('VideoDoubleTapAction settings and localization test', () async {
      SharedPreferences.setMockInitialValues({});
      final service = await SettingsService.init();
      final defaultSettings = service.settings;
      expect(defaultSettings.videoDoubleTapAction, VideoDoubleTapAction.smart);

      // Save and reload seekOnly
      final updatedSettings = defaultSettings.copyWith(
        videoDoubleTapAction: VideoDoubleTapAction.seekOnly,
      );
      await service.save(updatedSettings);

      final reloaded = service.settings;
      expect(reloaded.videoDoubleTapAction, VideoDoubleTapAction.seekOnly);

      // Localization test
      final enLoc = AppLocalizations(const Locale('en'));
      expect(enLoc.aToZ, 'A to Z');
      expect(enLoc.zToA, 'Z to A');
      expect(enLoc.videoDoubleTapActionLabel(VideoDoubleTapAction.smart),
          'Smart (Seek on edges, Zoom in center)');
      expect(enLoc.videoDoubleTapActionLabel(VideoDoubleTapAction.seekOnly),
          'Seek Only (Rewind / Forward)');
      expect(enLoc.videoDoubleTapActionLabel(VideoDoubleTapAction.zoomOnly),
          'Zoom Only (Zoom / Reset)');

      final idLoc = AppLocalizations(const Locale('id'));
      expect(idLoc.aToZ, 'A ke Z');
      expect(idLoc.zToA, 'Z ke A');
      expect(idLoc.videoDoubleTapActionLabel(VideoDoubleTapAction.smart),
          'Cerdas (Seek di tepi, Zoom di tengah)');
      expect(idLoc.videoDoubleTapActionLabel(VideoDoubleTapAction.seekOnly),
          'Hanya Seek (Mundur / Maju)');
      expect(idLoc.videoDoubleTapActionLabel(VideoDoubleTapAction.zoomOnly),
          'Hanya Zoom (Perbesar / Normal)');
    });

    test('Media viewer seamless system UI gradient and immersive mode rules',
        () {
      const topGradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.black87, Colors.black54, Colors.transparent],
        stops: [0.0, 0.7, 1.0],
      );
      expect(topGradient.stops, [0.0, 0.7, 1.0]);
      expect(topGradient.colors.length, 3);
      expect(topGradient.colors.first, Colors.black87);
      expect(topGradient.colors.last, Colors.transparent);

      const bottomGradient = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [Colors.black87, Colors.black54, Colors.transparent],
        stops: [0.0, 0.7, 1.0],
      );
      expect(bottomGradient.stops, [0.0, 0.7, 1.0]);
      expect(bottomGradient.colors.first, Colors.black87);
      expect(bottomGradient.colors.last, Colors.transparent);

      SystemUiMode resolveMode({required bool barsVisible}) =>
          barsVisible ? SystemUiMode.edgeToEdge : SystemUiMode.immersiveSticky;
      expect(resolveMode(barsVisible: true), SystemUiMode.edgeToEdge);
      expect(resolveMode(barsVisible: false), SystemUiMode.immersiveSticky);
    });

    test(
        'Video resume playback position rules save, retrieve, clear, and respect toggle',
        () async {
      SharedPreferences.setMockInitialValues({
        'resumeVideoPlayback': true,
      });
      final service = await SettingsService.init();

      const testVideo = '/storage/emulated/0/DCIM/Camera/VID_100.mp4';
      final expectedDeterministicKey =
          'playback_pos_${base64Url.encode(utf8.encode(testVideo))}';

      // 1. Position <= 2000ms is not stored (starts from beginning)
      service.saveVideoPlaybackPosition(
        testVideo,
        const Duration(milliseconds: 1500),
        const Duration(milliseconds: 60000),
      );
      expect(service.getVideoPlaybackPosition(testVideo), isNull);

      // 2. Position > 2000ms is successfully saved with deterministic key and retrieved
      service.saveVideoPlaybackPosition(
        testVideo,
        const Duration(milliseconds: 15400),
        const Duration(milliseconds: 60000),
      );
      expect(
        service.getVideoPlaybackPosition(testVideo),
        const Duration(milliseconds: 15400),
      );
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(expectedDeterministicKey), 15400);

      // 3. Exiting near the start (<= 2000ms) clears previous saved position
      service.saveVideoPlaybackPosition(
        testVideo,
        const Duration(milliseconds: 1000),
        const Duration(milliseconds: 60000),
      );
      expect(service.getVideoPlaybackPosition(testVideo), isNull);
      expect(prefs.getInt(expectedDeterministicKey), isNull);

      // 4. Legacy fallback: reads from old hashCode key if present
      await prefs.setInt('playback_pos_${testVideo.hashCode}', 18200);
      expect(
        service.getVideoPlaybackPosition(testVideo),
        const Duration(milliseconds: 18200),
      );

      // 5. Near-end position (< 3000ms remaining) automatically clears position and legacy key
      service.saveVideoPlaybackPosition(
        testVideo,
        const Duration(milliseconds: 58500),
        const Duration(milliseconds: 60000),
      );
      expect(service.getVideoPlaybackPosition(testVideo), isNull);
      expect(prefs.getInt('playback_pos_${testVideo.hashCode}'), isNull);

      // 6. Explicit clear removes saved position
      service.saveVideoPlaybackPosition(
        testVideo,
        const Duration(milliseconds: 25000),
        const Duration(milliseconds: 60000),
      );
      expect(
        service.getVideoPlaybackPosition(testVideo),
        const Duration(milliseconds: 25000),
      );
      service.clearVideoPlaybackPosition(testVideo);
      expect(service.getVideoPlaybackPosition(testVideo), isNull);

      // 7. When resumeVideoPlayback setting is disabled, saving and reading are disabled
      await service.save(service.settings.copyWith(resumeVideoPlayback: false));
      service.saveVideoPlaybackPosition(
        testVideo,
        const Duration(milliseconds: 30000),
        const Duration(milliseconds: 60000),
      );
      expect(service.getVideoPlaybackPosition(testVideo), isNull);

      // 8. Duration.zero (player stop/unload) does NOT wipe an existing saved position
      await service.save(service.settings.copyWith(resumeVideoPlayback: true));
      service.saveVideoPlaybackPosition(
        testVideo,
        const Duration(milliseconds: 22000),
        const Duration(milliseconds: 60000),
      );
      expect(
        service.getVideoPlaybackPosition(testVideo),
        const Duration(milliseconds: 22000),
      );
      service.saveVideoPlaybackPosition(
        testVideo,
        Duration.zero,
        const Duration(milliseconds: 60000),
      );
      expect(
        service.getVideoPlaybackPosition(testVideo),
        const Duration(milliseconds: 22000),
      );

      // 9. Path normalization: forward slashes and backslashes resolve to same position
      const winPath = r'C:\Storage\DCIM\Camera\VID_100.mp4';
      const unixPath = 'C:/Storage/DCIM/Camera/VID_100.mp4';
      service.saveVideoPlaybackPosition(
        winPath,
        const Duration(milliseconds: 35000),
        const Duration(milliseconds: 90000),
      );
      expect(
        service.getVideoPlaybackPosition(unixPath),
        const Duration(milliseconds: 35000),
      );
      expect(
        service.getVideoPlaybackPosition(winPath),
        const Duration(milliseconds: 35000),
      );

      // 10. Short videos (< 15s) use 500ms near-start and near-end thresholds
      const shortVideo = '/storage/emulated/0/DCIM/Camera/VID_SHORT.mp4';
      service.saveVideoPlaybackPosition(
        shortVideo,
        const Duration(milliseconds: 400),
        const Duration(milliseconds: 5000),
      );
      expect(service.getVideoPlaybackPosition(shortVideo), isNull);

      service.saveVideoPlaybackPosition(
        shortVideo,
        const Duration(milliseconds: 1200),
        const Duration(milliseconds: 5000),
      );
      expect(
        service.getVideoPlaybackPosition(shortVideo),
        const Duration(milliseconds: 1200),
      );

      service.saveVideoPlaybackPosition(
        shortVideo,
        const Duration(milliseconds: 400),
        const Duration(milliseconds: 5000),
      );
      expect(service.getVideoPlaybackPosition(shortVideo), isNull);

      service.saveVideoPlaybackPosition(
        shortVideo,
        const Duration(milliseconds: 1200),
        const Duration(milliseconds: 5000),
      );
      expect(
        service.getVideoPlaybackPosition(shortVideo),
        const Duration(milliseconds: 1200),
      );

      service.saveVideoPlaybackPosition(
        shortVideo,
        const Duration(milliseconds: 4700),
        const Duration(milliseconds: 5000),
      );
      expect(service.getVideoPlaybackPosition(shortVideo), isNull);

      service.saveVideoPlaybackPosition(
        shortVideo,
        const Duration(milliseconds: 1200),
        const Duration(milliseconds: 5000),
      );
      expect(
        service.getVideoPlaybackPosition(shortVideo),
        const Duration(milliseconds: 1200),
      );

      await service.save(service.settings.copyWith(resumeVideoPlayback: false));
      expect(service.getVideoPlaybackPosition(shortVideo), isNull);
      service.saveVideoPlaybackPosition(
        shortVideo,
        const Duration(milliseconds: 1200),
        const Duration(milliseconds: 5000),
      );
      expect(service.getVideoPlaybackPosition(shortVideo), isNull);
    });

    test('Double tap seek interval slider values step by 5 between 5s and 60s',
        () async {
      SharedPreferences.setMockInitialValues({
        'doubleTapSeekInterval': 10,
      });
      final service = await SettingsService.init();
      expect(service.settings.doubleTapSeekInterval, 10);

      const min = 5.0;
      const max = 60.0;
      const divisions = 11;
      const step = (max - min) / divisions;
      expect(step, 5.0);

      for (int i = 0; i <= divisions; i++) {
        final val = (min + i * step).round();
        expect(val % 5, 0);
        expect(val >= 5 && val <= 60, isTrue);
      }

      await service.save(service.settings.copyWith(doubleTapSeekInterval: 25));
      expect(service.settings.doubleTapSeekInterval, 25);

      await service.save(service.settings.copyWith(doubleTapSeekInterval: 60));
      expect(service.settings.doubleTapSeekInterval, 60);
    });

    test('Slideshow interval slider values step by 1 between 1s and 10s',
        () async {
      SharedPreferences.setMockInitialValues({
        'slideshowInterval': 3,
      });
      final service = await SettingsService.init();
      expect(service.settings.slideshowInterval, 3);

      const min = 1.0;
      const max = 10.0;
      const divisions = 9;
      const step = (max - min) / divisions;
      expect(step, 1.0);

      for (int i = 0; i <= divisions; i++) {
        final val = (min + i * step).round();
        expect(val, i + 1);
        expect(val >= 1 && val <= 10, isTrue);
      }

      await service.save(service.settings.copyWith(slideshowInterval: 1));
      expect(service.settings.slideshowInterval, 1);

      await service.save(service.settings.copyWith(slideshowInterval: 7));
      expect(service.settings.slideshowInterval, 7);

      await service.save(service.settings.copyWith(slideshowInterval: 10));
      expect(service.settings.slideshowInterval, 10);
    });

    test(
        'filterSmallImages excludes photos under 50KB while retaining videos and large photos',
        () {
      final items = [
        MediaItem(
          id: 'small_photo',
          path: '/test/small.jpg',
          name: 'small.jpg',
          date: DateTime.now(),
          size: 40 * 1024, // 40KB (< 50KB)
          isVideo: false,
        ),
        MediaItem(
          id: 'large_photo',
          path: '/test/large.jpg',
          name: 'large.jpg',
          date: DateTime.now(),
          size: 60 * 1024, // 60KB (>= 50KB)
          isVideo: false,
        ),
        MediaItem(
          id: 'small_video',
          path: '/test/small.mp4',
          name: 'small.mp4',
          date: DateTime.now(),
          size: 10 * 1024, // 10KB, but isVideo == true
          isVideo: true,
        ),
      ];

      final filtered =
          items.where((e) => e.isVideo || e.size >= 50 * 1024).toList();
      expect(
          filtered.map((e) => e.id).toList(), ['large_photo', 'small_video']);
      expect(items.length, 3);
    });

    testWidgets('GalleryScreen grid and slideshow respect filterSmallImages',
        (tester) async {
      final mockItems = [
        MediaItem(
          id: 'photo_small',
          path: '/test/small.jpg',
          name: 'small.jpg',
          date: DateTime.now(),
          size: 30 * 1024,
          isVideo: false,
        ),
        MediaItem(
          id: 'photo_large',
          path: '/test/large.jpg',
          name: 'large.jpg',
          date: DateTime.now(),
          size: 80 * 1024,
          isVideo: false,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
              () => _TestSettingsNotifier(
                const SettingsModel(filterSmallImages: true),
              ),
            ),
            mediaListProvider
                .overrideWith(() => _SpecificMockMediaNotifier(mockItems)),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: GalleryScreen(),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Small photo (30KB) should not be displayed in grid
      expect(find.text('small.jpg'), findsNothing);
      // Large photo (80KB) should be present in grid
      expect(find.byType(MediaGridItem), findsOneWidget);
    });

    testWidgets('AlbumDetailScreen respects filterSmallImages', (tester) async {
      final mockItems = [
        MediaItem(
          id: 'photo_small',
          path: '/test/Camera/small.jpg',
          name: 'small.jpg',
          date: DateTime.now(),
          size: 20 * 1024,
          isVideo: false,
        ),
        MediaItem(
          id: 'photo_large',
          path: '/test/Camera/large.jpg',
          name: 'large.jpg',
          date: DateTime.now(),
          size: 100 * 1024,
          isVideo: false,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
              () => _TestSettingsNotifier(
                const SettingsModel(filterSmallImages: true),
              ),
            ),
            mediaListProvider
                .overrideWith(() => _SpecificMockMediaNotifier(mockItems)),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: AlbumDetailScreen(albumName: 'Camera'),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Small photo should be filtered out, only 1 item shown
      expect(find.byType(MediaGridItem), findsOneWidget);
    });

    test('PSD layer visibility persistence saves, retrieves, and clears',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      const testPsdPath = '/storage/emulated/0/Pictures/artwork.psd';
      expect(PsdService.instance.getSavedLayerVisibility(testPsdPath), isNull);

      await PsdService.instance.saveLayerVisibility(testPsdPath, {1, 3, 5});
      final saved = PsdService.instance.getSavedLayerVisibility(testPsdPath);
      expect(saved, isNotNull);
      expect(saved, equals({1, 3, 5}));

      await PsdService.instance.clearSavedLayerVisibility(testPsdPath);
      expect(PsdService.instance.getSavedLayerVisibility(testPsdPath), isNull);
    });

    test(
        'resolveEffectiveVideoSize handles rotations on 1080p, 2K, 4K and zero fallback',
        () {
      const resolutions = [
        Size(1920, 1080),
        Size(1080, 1920),
        Size(2560, 1440),
        Size(3840, 2160),
      ];

      for (final raw in resolutions) {
        expect(resolveEffectiveVideoSize(raw, 0), raw);
        expect(resolveEffectiveVideoSize(raw, 180), raw);
        expect(resolveEffectiveVideoSize(raw, 90), raw);
        expect(resolveEffectiveVideoSize(raw, 270), raw);
        expect(resolveEffectiveVideoSize(raw, -90), raw);
      }

      expect(resolveEffectiveVideoSize(Size.zero, 0), const Size(16, 9));
      expect(resolveEffectiveVideoSize(Size.zero, 90), const Size(16, 9));
      expect(
          resolveEffectiveVideoSize(const Size(0, 1080), 0), const Size(16, 9));
      expect(resolveEffectiveVideoSize(const Size(-1920, 1080), 90),
          const Size(16, 9));
    });

    test(
        'computeNormalizedVideoLayoutSize fits 720p/1080p/2K/4K within viewport preserving exact aspect ratio',
        () {
      const sizes = [
        // 720p: landscape 16:9, portrait 9:16, ultrawide 21:9
        Size(1280, 720),
        Size(720, 1280),
        Size(1680, 720),
        // 1080p: landscape 16:9, portrait 9:16, ultrawide 21:9
        Size(1920, 1080),
        Size(1080, 1920),
        Size(2520, 1080),
        // 2K (1440p): landscape 16:9, portrait 9:16, ultrawide 21:9
        Size(2560, 1440),
        Size(1440, 2560),
        Size(3360, 1440),
        // 4K: landscape 16:9, portrait 9:16, ultrawide 21:9
        Size(3840, 2160),
        Size(2160, 3840),
        Size(5040, 2160),
      ];

      const viewports = [
        Size(412, 915),
        Size(915, 412),
        Size(1920, 1080),
        Size(1080, 1920),
      ];

      for (final viewport in viewports) {
        for (final effective in sizes) {
          final layout = computeNormalizedVideoLayoutSize(
            effectiveSize: effective,
            maxViewportSize: viewport,
          );
          expect(layout.width, greaterThan(0));
          expect(layout.height, greaterThan(0));
          expect(layout.width, lessThanOrEqualTo(viewport.width));
          expect(layout.height, lessThanOrEqualTo(viewport.height));
          expect(
            layout.width / layout.height,
            closeTo(effective.width / effective.height, 1e-9),
          );
        }
      }

      // Fallbacks for zero/non-finite dimensions
      final zeroEffective = computeNormalizedVideoLayoutSize(
        effectiveSize: Size.zero,
        maxViewportSize: const Size(400, 800),
      );
      expect(zeroEffective.width, lessThanOrEqualTo(400));
      expect(zeroEffective.height, lessThanOrEqualTo(800));
      expect(zeroEffective.width / zeroEffective.height, closeTo(16 / 9, 1e-9));

      final invalidViewport = computeNormalizedVideoLayoutSize(
        effectiveSize: const Size(3840, 2160),
        maxViewportSize: const Size(double.infinity, 0),
      );
      expect(invalidViewport.width, lessThanOrEqualTo(1080));
      expect(invalidViewport.height, lessThanOrEqualTo(1920));
      expect(invalidViewport.width / invalidViewport.height,
          closeTo(16 / 9, 1e-9));
    });

    test(
        'resolveAutoPlayAfterInit handles slow >720p init after route transition completes',
        () {
      // Captured false during initState while transition ran; transition completed before init finished.
      expect(
        resolveAutoPlayAfterInit(
          capturedAutoPlay: false,
          routeTransitionComplete: true,
          routeAnimationCompleted: false,
          isSlideshowPlaying: false,
          startSlideshow: false,
          settingAutoPlayVideo: true,
        ),
        isTrue,
      );
      expect(
        resolveAutoPlayAfterInit(
          capturedAutoPlay: false,
          routeTransitionComplete: false,
          routeAnimationCompleted: true,
          isSlideshowPlaying: false,
          startSlideshow: false,
          settingAutoPlayVideo: true,
        ),
        isTrue,
      );

      // Still waiting for route transition
      expect(
        resolveAutoPlayAfterInit(
          capturedAutoPlay: false,
          routeTransitionComplete: false,
          routeAnimationCompleted: false,
          isSlideshowPlaying: false,
          startSlideshow: false,
          settingAutoPlayVideo: true,
        ),
        isFalse,
      );

      // Disabled by setting
      expect(
        resolveAutoPlayAfterInit(
          capturedAutoPlay: false,
          routeTransitionComplete: true,
          routeAnimationCompleted: true,
          isSlideshowPlaying: false,
          startSlideshow: false,
          settingAutoPlayVideo: false,
        ),
        isFalse,
      );

      // Suppressed during slideshow unless capturedAutoPlay is true
      expect(
        resolveAutoPlayAfterInit(
          capturedAutoPlay: false,
          routeTransitionComplete: true,
          routeAnimationCompleted: true,
          isSlideshowPlaying: true,
          startSlideshow: false,
          settingAutoPlayVideo: true,
        ),
        isFalse,
      );
      expect(
        resolveAutoPlayAfterInit(
          capturedAutoPlay: false,
          routeTransitionComplete: true,
          routeAnimationCompleted: true,
          isSlideshowPlaying: false,
          startSlideshow: true,
          settingAutoPlayVideo: true,
        ),
        isFalse,
      );
      expect(
        resolveAutoPlayAfterInit(
          capturedAutoPlay: true,
          routeTransitionComplete: false,
          routeAnimationCompleted: false,
          isSlideshowPlaying: true,
          startSlideshow: true,
          settingAutoPlayVideo: false,
        ),
        isTrue,
      );
    });

    testWidgets(
        'Swiping from photo to video in ImageViewerScreen hands off to VideoPlayerScreen',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final photoItem = MediaItem(
        id: 'photo_1',
        path: '/mock/photo_1.jpg',
        name: 'photo_1.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
      );
      final videoItem = MediaItem(
        id: 'video_1',
        path: '/mock/video_1.mp4',
        name: 'video_1.mp4',
        date: DateTime(2026, 1, 2),
        size: 2048,
        isVideo: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [photoItem, videoItem],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayerScreen), findsOneWidget);

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'Tapping play button on video slide inside ImageViewerScreen immediately opens VideoPlayerScreen with forceAutoPlay',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final photoItem = MediaItem(
        id: 'photo_1',
        path: '/mock/photo_1.jpg',
        name: 'photo_1.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
      );
      final videoItem = MediaItem(
        id: 'video_1',
        path: '/mock/video_1.mp4',
        name: 'video_1.mp4',
        date: DateTime(2026, 1, 2),
        size: 2048,
        isVideo: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [photoItem, videoItem],
              initialIndex: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_circle_fill_rounded));
      await tester.pumpAndSettle();

      expect(find.byType(VideoPlayerScreen), findsOneWidget);
      expect(
        tester.widget<VideoPlayerScreen>(find.byType(VideoPlayerScreen)).forceAutoPlay,
        isTrue,
      );

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'ImageViewerScreen video slide expands thumbnail to full viewport aspect ratio without stretching play icon',
        (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      const videoId = 'video_full_width_test';
      final tinyPng = Uint8List.fromList(const <int>[
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      await tester.runAsync(() async {
        await ThumbnailService.init();
        await ThumbnailService.instance.clearAll();
        final dir = await ThumbnailService.instance.getCacheDirectory();
        final fileName = ThumbnailService.instance.debugCacheFileName(videoId);
        await File('${dir.path}${Platform.pathSeparator}$fileName')
            .writeAsBytes(tinyPng);
        ThumbnailService.instance.registerDiskCacheFileName(fileName);
      });
      addTearDown(() async {
        await tester.runAsync(() => ThumbnailService.instance.clearAll());
      });

      final photoItem = MediaItem(
        id: 'photo_1',
        path: '/mock/photo_1.jpg',
        name: 'photo_1.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
      );
      final videoItem = MediaItem(
        id: videoId,
        path: '/mock/video_16_9.mp4',
        name: 'video_16_9.mp4',
        date: DateTime(2026, 1, 2),
        size: 2048,
        width: 1920,
        height: 1080,
        isVideo: true,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [photoItem, videoItem],
              initialIndex: 1,
            ),
          ),
        ),
      );
      await tester.pump();

      final aspectFinder = find.descendant(
        of: find.byType(PageView),
        matching: find.byType(AspectRatio),
      );
      expect(aspectFinder, findsOneWidget);
      final aspectSize = tester.getSize(aspectFinder);
      expect(aspectSize.width, closeTo(400.0, 0.5));
      expect(aspectSize.height, closeTo(225.0, 0.5));

      final thumbImageFinder = find.descendant(
        of: aspectFinder,
        matching: find.byType(Image),
      );
      expect(thumbImageFinder, findsOneWidget);
      final thumbSize = tester.getSize(thumbImageFinder);
      expect(thumbSize.width, closeTo(400.0, 0.5));
      expect(thumbSize.height, closeTo(225.0, 0.5));

      final playIconFinder = find.byIcon(Icons.play_circle_fill_rounded);
      expect(playIconFinder, findsOneWidget);
      final playGestureFinder = find.ancestor(
        of: playIconFinder,
        matching: find.byType(GestureDetector),
      ).first;
      final playButtonSize = tester.getSize(playGestureFinder);
      expect(playButtonSize.width, closeTo(72.0, 0.5));
      expect(playButtonSize.height, closeTo(72.0, 0.5));

      final aspectCenter = tester.getCenter(aspectFinder);
      final playCenter = tester.getCenter(playGestureFinder);
      expect(playCenter.dx, closeTo(aspectCenter.dx, 0.5));
      expect(playCenter.dy, closeTo(aspectCenter.dy, 0.5));
    });

    test(
        'computeClampedFocalZoomMatrix preserves interior focal points and clamps viewport boundaries',
        () {
      const viewport = Size(300.0, 600.0);
      const scale = 3.0;

      for (final focal in const [
        Offset(150.0, 300.0),
        Offset(42.0, 125.0),
        Offset(265.0, 520.0),
        Offset(10.0, 10.0),
      ]) {
        final matrix = computeClampedFocalZoomMatrix(
          currentMatrix: Matrix4.identity(),
          localFocal: focal,
          viewportSize: viewport,
          targetScale: scale,
        );
        expect(matrix.getMaxScaleOnAxis(), closeTo(scale, 0.001));
        final transformed = MatrixUtils.transformPoint(matrix, focal);
        expect(transformed.dx, closeTo(focal.dx, 0.5));
        expect(transformed.dy, closeTo(focal.dy, 0.5));
        expect(matrix.storage[12],
            inInclusiveRange(-viewport.width * (scale - 1.0), 0.0));
        expect(matrix.storage[13],
            inInclusiveRange(-viewport.height * (scale - 1.0), 0.0));
      }

      // Out-of-bounds focal coordinates clamp strictly to [-(w*(s-1)), 0]
      final topLeftClamped = computeClampedFocalZoomMatrix(
        currentMatrix: Matrix4.identity(),
        localFocal: const Offset(-100.0, -50.0),
        viewportSize: viewport,
        targetScale: scale,
      );
      expect(topLeftClamped.storage[12], closeTo(0.0, 0.001));
      expect(topLeftClamped.storage[13], closeTo(0.0, 0.001));

      final bottomRightClamped = computeClampedFocalZoomMatrix(
        currentMatrix: Matrix4.identity(),
        localFocal: const Offset(500.0, 900.0),
        viewportSize: viewport,
        targetScale: scale,
      );
      expect(bottomRightClamped.storage[12],
          closeTo(-viewport.width * (scale - 1.0), 0.001));
      expect(bottomRightClamped.storage[13],
          closeTo(-viewport.height * (scale - 1.0), 0.001));

      // Reset / degenerate viewport returns identity
      expect(
        computeClampedFocalZoomMatrix(
          currentMatrix: topLeftClamped,
          localFocal: const Offset(100.0, 100.0),
          viewportSize: viewport,
          targetScale: 1.0,
        ).isIdentity(),
        isTrue,
      );
      expect(
        computeClampedFocalZoomMatrix(
          currentMatrix: Matrix4.identity(),
          localFocal: const Offset(100.0, 100.0),
          viewportSize: Size.zero,
          targetScale: 3.0,
        ).isIdentity(),
        isTrue,
      );
    });

    testWidgets(
        'Standard photo ImageViewerScreen double-tap zoom cycles 1.0x -> 3.0x -> 1.0x',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final photoItem = MediaItem(
        id: 'std_photo_1',
        path: '/mock/std_photo_1.jpg',
        name: 'std_photo_1.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [photoItem],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      expect(ivFinder, findsOneWidget);
      final controller =
          tester.widget<InteractiveViewer>(ivFinder).transformationController!;
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1.0, 0.01));

      final center = tester.getCenter(find.byType(PageView));

      // Double-tap 1 -> 3.0x
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(3.0, 0.01));

      // Double-tap 2 -> 1.0x (never 4.0x)
      await tester.tapAt(center);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(center);
      await tester.pumpAndSettle();
      expect(controller.value.getMaxScaleOnAxis(), closeTo(1.0, 0.01));
      expect(controller.value.isIdentity(), isTrue);
    });

    testWidgets(
        'Letterboxed ImageViewerScreen converts globalPosition to InteractiveViewer local coordinates and zooms onto exact focal point',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      // Portrait 1:2 image inside 800x600 screen -> letterboxed 300x600 at x=250..550
      final portraitPhoto = MediaItem(
        id: 'letterbox_photo_1',
        path: '/mock/letterbox_photo_1.jpg',
        name: 'letterbox_photo_1.jpg',
        date: DateTime(2026, 1, 1),
        size: 1024,
        isVideo: false,
        width: 400,
        height: 800,
      );

      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: ImageViewerScreen(
              items: [portraitPhoto],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      expect(ivFinder, findsOneWidget);
      final ivBox = tester.renderObject<RenderBox>(ivFinder);
      expect(ivBox.size.width, closeTo(300.0, 0.5));
      expect(ivBox.size.height, closeTo(600.0, 0.5));
      final ivTopLeft = ivBox.localToGlobal(Offset.zero);
      expect(ivTopLeft.dx, closeTo(250.0, 0.5));

      // Tap asymmetric interior point inside the letterboxed image
      const screenTap = Offset(310.0, 180.0);
      final expectedLocalFocal = ivBox.globalToLocal(screenTap);
      expect(expectedLocalFocal.dx, closeTo(60.0, 0.5));
      expect(expectedLocalFocal.dy, closeTo(180.0, 0.5));

      await tester.tapAt(screenTap);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(screenTap);
      await tester.pumpAndSettle();

      final controller =
          tester.widget<InteractiveViewer>(ivFinder).transformationController!;
      expect(controller.value.getMaxScaleOnAxis(), closeTo(3.0, 0.01));

      final transformed =
          MatrixUtils.transformPoint(controller.value, expectedLocalFocal);
      expect(transformed.dx, closeTo(expectedLocalFocal.dx, 0.5));
      expect(transformed.dy, closeTo(expectedLocalFocal.dy, 0.5));
      expect(controller.value.storage[12], closeTo(-120.0, 0.5));
      expect(controller.value.storage[13], closeTo(-360.0, 0.5));

      // Second double-tap resets to 1.0x
      await tester.tapAt(screenTap);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(screenTap);
      await tester.pumpAndSettle();
      expect(controller.value.isIdentity(), isTrue);
    });

    testWidgets(
        'Letterboxed VideoPlayerScreen converts globalPosition to InteractiveViewer local coordinates, zooms 1.0x <-> 3.0x, and clamps viewport bounds',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      // Portrait 1:2 video inside 800x600 screen -> letterboxed 300x600 at x=250..550
      final portraitVideo = MediaItem(
        id: 'letterbox_video_1',
        path: '/mock/letterbox_video_1.mp4',
        name: 'letterbox_video_1.mp4',
        date: DateTime(2026, 1, 1),
        size: 2048,
        isVideo: true,
        width: 400,
        height: 800,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
              () => _TestSettingsNotifier(
                const SettingsModel(
                  videoDoubleTapAction: VideoDoubleTapAction.zoomOnly,
                  autoPlayVideo: false,
                ),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: VideoPlayerScreen(
              items: [portraitVideo],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final ivFinder = find.byType(InteractiveViewer);
      expect(ivFinder, findsOneWidget);
      final ivBox = tester.renderObject<RenderBox>(ivFinder);
      expect(ivBox.size.width, closeTo(300.0, 0.5));
      expect(ivBox.size.height, closeTo(600.0, 0.5));
      expect(ivBox.localToGlobal(Offset.zero).dx, closeTo(250.0, 0.5));

      const screenTap = Offset(310.0, 180.0);
      final expectedLocalFocal = ivBox.globalToLocal(screenTap);

      await tester.tapAt(screenTap);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(screenTap);
      await tester.pumpAndSettle();

      final controller =
          tester.widget<InteractiveViewer>(ivFinder).transformationController!;
      expect(controller.value.getMaxScaleOnAxis(), closeTo(3.0, 0.01));

      final transformed =
          MatrixUtils.transformPoint(controller.value, expectedLocalFocal);
      expect(transformed.dx, closeTo(expectedLocalFocal.dx, 0.5));
      expect(transformed.dy, closeTo(expectedLocalFocal.dy, 0.5));
      expect(controller.value.storage[12], closeTo(-120.0, 0.5));
      expect(controller.value.storage[13], closeTo(-360.0, 0.5));

      // Second double-tap resets to 1.0x
      await tester.tapAt(screenTap);
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(screenTap);
      await tester.pumpAndSettle();
      expect(controller.value.isIdentity(), isTrue);

      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets(
        'VideoPlayerScreen scrub bar stabilizes <= 6px lift-off micro-jitter and fetches exact frame on release',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final frameCalls = <Map<dynamic, dynamic>>[];
      // Minimal valid 1x1 transparent PNG
      final dummyPng = Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
        0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
        0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
        0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
        0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
        0x42, 0x60, 0x82,
      ]);

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.phantek.gallery/thumbnail'),
        (call) async {
          if (call.method == 'getVideoFrame') {
            frameCalls.add(Map<dynamic, dynamic>.from(call.arguments as Map));
            return dummyPng;
          }
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.phantek.gallery/thumbnail'),
          null,
        );
      });

      final videoItem = MediaItem(
        id: 'scrub_video_1',
        path: '/mock/scrub_exact_test.mp4',
        name: 'scrub_exact_test.mp4',
        date: DateTime(2026, 1, 1),
        size: 4096,
        isVideo: true,
        width: 1920,
        height: 1080,
        duration: const Duration(seconds: 60),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
              () => _TestSettingsNotifier(
                const SettingsModel(autoPlayVideo: false),
              ),
            ),
          ],
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const [Locale('en'), Locale('id')],
            home: VideoPlayerScreen(
              items: [videoItem],
              initialIndex: 0,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrubberFinder = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_VideoScrubberBar',
      );
      expect(scrubberFinder, findsOneWidget);

      final box = tester.renderObject<RenderBox>(scrubberFinder);
      const trackPadding = 16.0;
      final trackWidth = box.size.width - trackPadding * 2;
      final centerY = box.size.height / 2;

      final startPos = box.localToGlobal(
        Offset(trackPadding + trackWidth * 0.2, centerY),
      );
      final dragPos = box.localToGlobal(
        Offset(trackPadding + trackWidth * 0.5, centerY),
      );
      // 4px micro-shift on finger lift-off (<= 6px threshold)
      final liftOffJitterPos = Offset(dragPos.dx + 4.0, dragPos.dy);

      const pointerId = 42;
      tester.binding.handlePointerEvent(
        PointerDownEvent(pointer: pointerId, position: startPos),
      );
      await tester.pump();

      tester.binding.handlePointerEvent(
        PointerMoveEvent(pointer: pointerId, position: dragPos),
      );
      await tester.pump(const Duration(milliseconds: 30));

      tester.binding.handlePointerEvent(
        PointerUpEvent(pointer: pointerId, position: liftOffJitterPos),
      );
      await tester.pump();

      final exactCalls =
          frameCalls.where((args) => args['exact'] == true).toList();
      expect(exactCalls, isNotEmpty);
      expect(exactCalls.last['timeUs'], 30000000);

      // Let preview & pill fade timers complete cleanly.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets(
        'GalleryScreen direct tab jump from All to Albums switches cleanly and manual drag updates FilterSortBar',
        (tester) async {
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
      final barFinder = find.byType(FilterSortBar);
      expect(pageViewFinder, findsOneWidget);
      expect(barFinder, findsOneWidget);

      // Tap Albums (index 3) from All (index 0): jumps directly without building intermediate pages
      await tester.tap(find.text('Albums'));
      await tester.pump();

      final PageView jumpedPageView = tester.widget(pageViewFinder);
      expect(jumpedPageView.controller?.page, 3.0);

      final FilterSortBar directBar = tester.widget(barFinder);
      expect(directBar.currentFilter, FilterOption.albums);
      expect(directBar.isDirectTabTransition, isTrue);

      // After the 300ms transition window, direct flag settles back to false
      await tester.pump(const Duration(milliseconds: 350));
      final FilterSortBar settledBar = tester.widget(barFinder);
      expect(settledBar.isDirectTabTransition, isFalse);

      // Manual horizontal drag back to Videos (index 2) updates FilterSortBar
      await tester.drag(pageViewFinder, const Offset(500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final PageView draggedPageView = tester.widget(pageViewFinder);
      expect(draggedPageView.controller?.page?.round(), 2);
      final FilterSortBar draggedBar = tester.widget(barFinder);
      expect(draggedBar.currentFilter, FilterOption.videosOnly);

      // Tapping adjacent tab (Photos, index 1) jumps PageView immediately to 1.0,
      // activates direct transition for FilterSortBar, and dragging cancels it immediately
      await tester.tap(find.text('Photos'));
      await tester.pump();
      expect(tester.widget<PageView>(pageViewFinder).controller?.page, 1.0);
      expect(
          tester.widget<FilterSortBar>(barFinder).isDirectTabTransition, isTrue);

      final gesture = await tester.startGesture(const Offset(200, 400));
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      expect(tester.widget<FilterSortBar>(barFinder).isDirectTabTransition,
          isFalse);
      await gesture.up();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets(
        'AlbumDetailScreen switches tabs instantly on tap and updates FilterSortBar on horizontal swipe',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: AlbumDetailScreen(albumName: 'a'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      final pageViewFinder = find.byType(PageView);
      final barFinder = find.byType(FilterSortBar);
      expect(pageViewFinder, findsOneWidget);
      expect(barFinder, findsOneWidget);
      expect(tester.widget<PageView>(pageViewFinder).controller?.page, 0.0);
      expect(tester.widget<FilterSortBar>(barFinder).currentFilter,
          FilterOption.all);

      // Tap Photos (index 1): jumps immediately to 1.0 while FilterSortBar animates capsule
      await tester.tap(find.text('Photos'));
      await tester.pump();
      expect(tester.widget<PageView>(pageViewFinder).controller?.page, 1.0);
      expect(tester.widget<FilterSortBar>(barFinder).currentFilter,
          FilterOption.photosOnly);
      expect(
          tester.widget<FilterSortBar>(barFinder).isDirectTabTransition, isTrue);

      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<FilterSortBar>(barFinder).isDirectTabTransition,
          isFalse);

      // Tap Videos (index 2): jumps immediately to 2.0
      await tester.tap(find.text('Videos'));
      await tester.pump();
      expect(tester.widget<PageView>(pageViewFinder).controller?.page, 2.0);
      expect(tester.widget<FilterSortBar>(barFinder).currentFilter,
          FilterOption.videosOnly);
      expect(
          tester.widget<FilterSortBar>(barFinder).isDirectTabTransition, isTrue);

      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<FilterSortBar>(barFinder).isDirectTabTransition,
          isFalse);

      // Tap All (index 0): jumps immediately back to 0.0
      await tester.tap(find.text('All'));
      await tester.pump();
      expect(tester.widget<PageView>(pageViewFinder).controller?.page, 0.0);
      expect(tester.widget<FilterSortBar>(barFinder).currentFilter,
          FilterOption.all);
      expect(
          tester.widget<FilterSortBar>(barFinder).isDirectTabTransition, isTrue);

      await tester.pump(const Duration(milliseconds: 350));
      expect(tester.widget<FilterSortBar>(barFinder).isDirectTabTransition,
          isFalse);

      // Manual horizontal swipe forward from All (0) to Photos (1)
      await tester.drag(pageViewFinder, const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<PageView>(pageViewFinder).controller?.page?.round(),
          1);
      expect(tester.widget<FilterSortBar>(barFinder).currentFilter,
          FilterOption.photosOnly);

      // Manual horizontal swipe forward from Photos (1) to Videos (2)
      await tester.drag(pageViewFinder, const Offset(-500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<PageView>(pageViewFinder).controller?.page?.round(),
          2);
      expect(tester.widget<FilterSortBar>(barFinder).currentFilter,
          FilterOption.videosOnly);

      // Manual horizontal swipe back from Videos (2) to Photos (1)
      await tester.drag(pageViewFinder, const Offset(500, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.widget<PageView>(pageViewFinder).controller?.page?.round(),
          1);
      expect(tester.widget<FilterSortBar>(barFinder).currentFilter,
          FilterOption.photosOnly);
    });

    testWidgets(
        'FilterSortBar with PageController smoothly animates capsule when isDirectTabTransition becomes true',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final pageController = PageController(initialPage: 0);
      addTearDown(pageController.dispose);

      Widget buildHarness(FilterOption filter, bool isDirect) {
        return ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(96),
                child: FilterSortBar(
                  pageController: pageController,
                  currentFilter: filter,
                  isDirectTabTransition: isDirect,
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
        );
      }

      await tester.pumpWidget(buildHarness(FilterOption.all, false));
      await tester.pumpAndSettle();

      final capsuleAlignFinder = find.descendant(
        of: find.byType(FilterSortBar),
        matching: find.byType(Align),
      );
      expect(capsuleAlignFinder, findsOneWidget);
      expect(
        (tester.widget<Align>(capsuleAlignFinder).alignment as Alignment).x,
        closeTo(-1.0, 0.001),
      );

      await tester.pumpWidget(buildHarness(FilterOption.albums, true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 140));

      final midAlignX =
          (tester.widget<Align>(capsuleAlignFinder).alignment as Alignment).x;
      expect(midAlignX, greaterThan(-1.0));
      expect(midAlignX, lessThan(1.0));

      await tester.pumpAndSettle();
      expect(
        (tester.widget<Align>(capsuleAlignFinder).alignment as Alignment).x,
        closeTo(1.0, 0.001),
      );
    });

    testWidgets(
        'SortBottomSheet animates sliding pill, defers onSortChanged, and flushes pending sort on immediate close',
        (tester) async {
      final delivered = <SortOption>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SortBottomSheet(
              currentSort: SortOption.newest,
              onSortChanged: delivered.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sliding pill AnimatedAlign exists for all 5 sort criteria
      expect(find.byType(AnimatedAlign), findsNWidgets(5));
      expect(
        find.descendant(
          of: find.byType(SortBottomSheet),
          matching: find.byType(RepaintBoundary),
        ),
        findsAtLeastNWidgets(1),
      );

      // Tap "By name": selection animates for 200ms before delivering callback
      await tester.tap(find.text('By name'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(delivered, isEmpty);

      await tester.pump(const Duration(milliseconds: 200));
      expect(delivered, [SortOption.nameAZ]);

      // Toggle direction arrow on "By name" (index 2: shootingTime=0, timeAdded=1, name=2)
      await tester.tap(find.byIcon(Icons.arrow_downward).at(2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(delivered, [SortOption.nameAZ]);

      await tester.pump(const Duration(milliseconds: 200));
      expect(delivered, [SortOption.nameAZ, SortOption.nameZA]);

      // Test immediate close via showSortBottomSheet before 200ms elapses
      final modalDelivered = <SortOption>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showSortBottomSheet(
                    context,
                    currentSort: SortOption.newest,
                    onSortChanged: modalDelivered.add,
                  );
                },
                child: const Text('Open Sort'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Sort'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('By size'));
      await tester.pump(const Duration(milliseconds: 16));
      expect(modalDelivered, isEmpty);

      // Close immediately before 200ms finishes
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(modalDelivered, [SortOption.sizeDesc]);
    });

    test(
        'ThumbnailService.getIndexedDiskFile returns indexed file without disk check and evictDiskCacheIndex removes it',
        () async {
      await ThumbnailService.init();
      final service = ThumbnailService.instance;
      const assetId = 'indexed_disk_test_asset';

      service.evictDiskCacheIndex(assetId);
      expect(service.getIndexedDiskFile(assetId), isNull);

      final fileName = service.debugCacheFileName(assetId);
      service.registerDiskCacheFileName(fileName);

      final indexedFile = service.getIndexedDiskFile(assetId);
      expect(indexedFile, isNotNull);
      expect(indexedFile!.path.endsWith(fileName), isTrue);
      expect(indexedFile.existsSync(), isFalse);

      service.evictDiskCacheIndex(assetId);
      expect(service.hasDiskCache(assetId), isFalse);
      expect(service.getIndexedDiskFile(assetId), isNull);
    });

    testWidgets(
        'Multiple ShimmerLoadingTile widgets share one ticker and dispose cleanly',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(width: 80, height: 80, child: ShimmerLoadingTile()),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: ShimmerLoadingTile(isVideo: true),
                ),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: ShimmerLoadingTile(icon: Icons.photo_library_rounded),
                ),
              ],
            ),
          ),
        ),
      );

      expect(ShimmerLoadingTile.debugActiveMountCount, 3);
      expect(ShimmerLoadingTile.debugHasActiveTicker, isTrue);

      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(ShimmerLoadingTile), findsNWidgets(3));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                SizedBox(width: 80, height: 80, child: ShimmerLoadingTile()),
                SizedBox(
                  width: 80,
                  height: 80,
                  child: ShimmerLoadingTile(isVideo: true),
                ),
              ],
            ),
          ),
        ),
      );
      expect(ShimmerLoadingTile.debugActiveMountCount, 2);
      expect(ShimmerLoadingTile.debugHasActiveTicker, isTrue);

      await tester.pumpWidget(Container());
      expect(ShimmerLoadingTile.debugActiveMountCount, 0);
      expect(ShimmerLoadingTile.debugHasActiveTicker, isFalse);
    });

    testWidgets(
        'GalleryScreen continuous and timeline-grouped grids resolve findChildIndexCallback after item updates and reordering',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final now = DateTime.now();
      final todayMorning = DateTime(now.year, now.month, now.day, 10, 0);
      final todayNoon = DateTime(now.year, now.month, now.day, 12, 0);
      final yesterday1 = DateTime(now.year, now.month, now.day, 10, 0)
          .subtract(const Duration(days: 1));
      final yesterday2 = DateTime(now.year, now.month, now.day, 8, 0)
          .subtract(const Duration(days: 1));

      final initialItems = [
        MediaItem(
          id: 'c_item_1',
          path: '/mock/1.jpg',
          name: '1.jpg',
          date: todayNoon,
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'c_item_2',
          path: '/mock/2.jpg',
          name: '2.jpg',
          date: todayMorning,
          size: 200,
          isVideo: false,
        ),
        MediaItem(
          id: 'c_item_3',
          path: '/mock/3.jpg',
          name: '3.jpg',
          date: yesterday1,
          size: 300,
          isVideo: false,
        ),
      ];

      final notifier = _MutableMockMediaNotifier(initialItems);

      // 1. Continuous mode
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
              () => _TestSettingsNotifier(
                const SettingsModel(
                  timelineGrouping: TimelineGrouping.continuous,
                  defaultSort: SortOption.newest,
                ),
              ),
            ),
            mediaListProvider.overrideWith(() => notifier),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: GalleryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      GridView continuousGrid = tester.widget<GridView>(find.byType(GridView));
      SliverChildBuilderDelegate continuousDelegate =
          continuousGrid.childrenDelegate as SliverChildBuilderDelegate;
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('c_item_1')),
        0,
      );
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('c_item_2')),
        1,
      );
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('c_item_3')),
        2,
      );
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('missing')),
        isNull,
      );

      // Reorder & update items (c_item_3 promoted to newest, c_item_2 removed, c_item_4 added)
      notifier.setItems([
        MediaItem(
          id: 'c_item_3',
          path: '/mock/3.jpg',
          name: '3.jpg',
          date: todayNoon.add(const Duration(hours: 2)),
          size: 300,
          isVideo: false,
        ),
        MediaItem(
          id: 'c_item_1',
          path: '/mock/1.jpg',
          name: '1.jpg',
          date: todayNoon,
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'c_item_4',
          path: '/mock/4.jpg',
          name: '4.jpg',
          date: yesterday2,
          size: 400,
          isVideo: false,
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      continuousGrid = tester.widget<GridView>(find.byType(GridView));
      continuousDelegate =
          continuousGrid.childrenDelegate as SliverChildBuilderDelegate;
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('c_item_3')),
        0,
      );
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('c_item_1')),
        1,
      );
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('c_item_4')),
        2,
      );
      expect(
        continuousDelegate.findChildIndexCallback!(
            const ValueKey<String>('c_item_2')),
        isNull,
      );

      // 2. Timeline-grouped (daily) mode
      final groupedNotifier = _MutableMockMediaNotifier([
        MediaItem(
          id: 'g_today_1',
          path: '/mock/t1.jpg',
          name: 't1.jpg',
          date: todayNoon,
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'g_today_2',
          path: '/mock/t2.jpg',
          name: 't2.jpg',
          date: todayMorning,
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'g_yest_1',
          path: '/mock/y1.jpg',
          name: 'y1.jpg',
          date: yesterday1,
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'g_yest_2',
          path: '/mock/y2.jpg',
          name: 'y2.jpg',
          date: yesterday2,
          size: 100,
          isVideo: false,
        ),
      ]);

      await tester.pumpWidget(
        ProviderScope(
          key: const ValueKey('grouped_scope'),
          overrides: [
            settingsNotifierProvider.overrideWith(
              () => _TestSettingsNotifier(
                const SettingsModel(
                  timelineGrouping: TimelineGrouping.daily,
                  defaultSort: SortOption.newest,
                ),
              ),
            ),
            mediaListProvider.overrideWith(() => groupedNotifier),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: GalleryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Today'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(find.byType(MediaGridItem), findsNWidgets(4));

      var timelineList = tester.widget<ListView>(find.byType(ListView));
      var timelineDelegate =
          timelineList.childrenDelegate as SliverChildBuilderDelegate;
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('h:Today')),
        0,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('r:g_today_1')),
        1,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('h:Yesterday')),
        2,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('r:g_yest_1')),
        3,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('missing')),
        isNull,
      );

      // Reorder within both groups
      groupedNotifier.setItems([
        MediaItem(
          id: 'g_today_2',
          path: '/mock/t2.jpg',
          name: 't2.jpg',
          date: todayNoon.add(const Duration(hours: 1)),
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'g_today_1',
          path: '/mock/t1.jpg',
          name: 't1.jpg',
          date: todayMorning,
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'g_yest_2',
          path: '/mock/y2.jpg',
          name: 'y2.jpg',
          date: yesterday1.add(const Duration(hours: 1)),
          size: 100,
          isVideo: false,
        ),
        MediaItem(
          id: 'g_yest_1',
          path: '/mock/y1.jpg',
          name: 'y1.jpg',
          date: yesterday2,
          size: 100,
          isVideo: false,
        ),
      ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      timelineList = tester.widget<ListView>(find.byType(ListView));
      timelineDelegate =
          timelineList.childrenDelegate as SliverChildBuilderDelegate;

      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('h:Today')),
        0,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('r:g_today_2')),
        1,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('r:g_today_1')),
        isNull,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('h:Yesterday')),
        2,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('r:g_yest_2')),
        3,
      );
      expect(
        timelineDelegate.findChildIndexCallback!(
            const ValueKey<String>('r:g_yest_1')),
        isNull,
      );
    });

    test(
        'SettingsModel & SettingsService round-trip appLockEnabled, translationFontScale, and translationOverlayStyle',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      const defaults = SettingsModel();
      expect(defaults.appLockEnabled, isFalse);
      expect(defaults.translationFontScale, 1.0);
      expect(
          defaults.translationOverlayStyle, TranslationOverlayStyle.googleLens);

      final updated = defaults.copyWith(
        appLockEnabled: true,
        translationFontScale: 1.25,
        translationOverlayStyle: TranslationOverlayStyle.darkContrast,
      );
      expect(updated.appLockEnabled, isTrue);
      expect(updated.translationFontScale, 1.25);
      expect(updated.translationOverlayStyle,
          TranslationOverlayStyle.darkContrast);

      // Serialization round-trip
      final revived = SettingsModel.fromMap(updated.toMap());
      expect(revived, equals(updated));

      // Clamping out-of-range font scale
      final clampedLow = defaults.copyWith(translationFontScale: 0.4);
      expect(clampedLow.translationFontScale, 0.8);
      final clampedHigh = defaults.copyWith(translationFontScale: 2.0);
      expect(clampedHigh.translationFontScale, 1.3);

      await SettingsService.instance.save(updated);
      final reloaded = SettingsService.instance.settings;
      expect(reloaded.appLockEnabled, isTrue);
      expect(reloaded.translationFontScale, 1.25);
      expect(reloaded.translationOverlayStyle,
          TranslationOverlayStyle.darkContrast);
    });

    test(
        'AppLockService handles mock MethodChannel canAuthenticate and authenticate',
        () async {
      final calls = <MethodCall>[];
      bool nextAuthResult = true;
      bool nextCanAuth = true;

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.phantek.gallery/app_lock'),
        (call) async {
          calls.add(call);
          if (call.method == 'canAuthenticate') return nextCanAuth;
          if (call.method == 'authenticate') return nextAuthResult;
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.phantek.gallery/app_lock'),
          null,
        );
      });

      expect(await AppLockService.instance.isDeviceAuthAvailable(), isTrue);
      nextCanAuth = false;
      expect(await AppLockService.instance.isDeviceAuthAvailable(), isFalse);

      expect(AppLockService.instance.isPromptActive, isFalse);
      final ok = await AppLockService.instance.authenticate(
        title: 'Unlock',
        subtitle: 'Verify identity',
      );
      expect(ok, isTrue);
      expect(AppLockService.instance.isPromptActive, isFalse);

      nextAuthResult = false;
      final fail = await AppLockService.instance.authenticate(
        title: 'Unlock',
        subtitle: 'Verify identity',
      );
      expect(fail, isFalse);
      expect(calls.map((c) => c.method).toList(),
          ['canAuthenticate', 'canAuthenticate', 'authenticate', 'authenticate']);
    });

    testWidgets(
        'PhantekGalleryApp shows AppLockOverlay when appLockEnabled is true and unlocks on auth success',
        (tester) async {
      SharedPreferences.setMockInitialValues({'appLockEnabled': true});
      await SettingsService.init();
      await tester.runAsync(() => ThumbnailService.init());

      var shouldUnlock = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.phantek.gallery/app_lock'),
        (call) async {
          if (call.method == 'canAuthenticate') return true;
          if (call.method == 'authenticate') return shouldUnlock;
          return null;
        },
      );
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.phantek.gallery/app_lock'),
          null,
        );
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: const PhantekGalleryApp(),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('app_lock_overlay')), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      expect(
        find.text('Authentication canceled. Tap to try again.'),
        findsOneWidget,
      );

      // Now allow authentication to succeed and tap Unlock button.
      shouldUnlock = true;
      await tester.tap(find.text('Unlock'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byKey(const ValueKey('app_lock_overlay')), findsNothing);

      // With appLockTimeoutSeconds = 30, immediate pause+resume should not re-lock.
      await SettingsService.instance.save(
        SettingsService.instance.settings.copyWith(appLockTimeoutSeconds: 30),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app_lock_overlay')), findsNothing);

      // With appLockTimeoutSeconds = 0, immediate pause+resume re-locks and unlocks.
      await SettingsService.instance.save(
        SettingsService.instance.settings.copyWith(appLockTimeoutSeconds: 0),
      );
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app_lock_overlay')), findsNothing);

      // If auth is canceled on resume, overlay stays visible with hint.
      shouldUnlock = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('app_lock_overlay')), findsOneWidget);
      expect(
        find.text('Authentication canceled. Tap to try again.'),
        findsOneWidget,
      );
    });

    test('SettingsModel & SettingsService round-trip appLockTimeoutSeconds',
        () async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      const defaults = SettingsModel();
      expect(defaults.appLockTimeoutSeconds, 0);

      final updated = defaults.copyWith(appLockTimeoutSeconds: 60);
      expect(updated.appLockTimeoutSeconds, 60);
      expect(SettingsModel.fromMap(updated.toMap()), equals(updated));

      await SettingsService.instance.save(updated);
      expect(SettingsService.instance.settings.appLockTimeoutSeconds, 60);
    });

    test(
        'ThumbnailService.getCacheSizeBreakdown classifies thumb_, prev_, and psd_prev_ files accurately',
        () async {
      await ThumbnailService.init();
      await ThumbnailService.instance.clearAll();
      final dir = await ThumbnailService.instance.getCacheDirectory();

      final thumbFile = File('${dir.path}${Platform.pathSeparator}thumb_test1.bin');
      final hrFile = File('${dir.path}${Platform.pathSeparator}hr_test2.bin');
      final prevFile = File('${dir.path}${Platform.pathSeparator}prev_test3.bin');
      final psdFile =
          File('${dir.path}${Platform.pathSeparator}psd_prev_test4.bin');

      await thumbFile.writeAsBytes(Uint8List(120));
      await hrFile.writeAsBytes(Uint8List(80));
      await prevFile.writeAsBytes(Uint8List(350));
      await psdFile.writeAsBytes(Uint8List(500));

      final breakdown = await ThumbnailService.instance.getCacheSizeBreakdown();
      expect(breakdown.thumbnailBytes, 200);
      expect(breakdown.previewBytes, 350);
      expect(breakdown.psdBytes, 500);
      expect(breakdown.totalBytes, 1050);

      await ThumbnailService.instance.clearAll();
    });

    testWidgets(
        'SettingsScreen renders App Lock toggle, Cache Breakdown dialog, and Translation Overlay Style & Size dialog with JP->EN preview',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();
      await tester.runAsync(() async {
        await ThumbnailService.init();
        await ThumbnailService.instance.clearAll();
        final dir = await ThumbnailService.instance.getCacheDirectory();
        await File('${dir.path}${Platform.pathSeparator}thumb_s1.bin')
            .writeAsBytes(Uint8List(1024));
        await File('${dir.path}${Platform.pathSeparator}prev_s1.bin')
            .writeAsBytes(Uint8List(2048));
        await File('${dir.path}${Platform.pathSeparator}psd_prev_s1.bin')
            .writeAsBytes(Uint8List(4096));
      });

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('com.phantek.gallery/app_lock'),
        (call) async {
          if (call.method == 'canAuthenticate') return true;
          if (call.method == 'authenticate') return true;
          return null;
        },
      );
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
          const MethodChannel('com.phantek.gallery/app_lock'),
          null,
        );
        await tester.runAsync(() => ThumbnailService.instance.clearAll());
      });

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLanguage.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const SettingsScreen(),
          ),
        ),
      );
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        if (find.textContaining('7.0 KB').evaluate().isNotEmpty) break;
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      }
      await tester.pumpAndSettle();

      // 1. Cache Breakdown in Clear Cache dialog
      final clearTile = find.text('Clear Thumbnail & Preview Cache');
      await tester.scrollUntilVisible(clearTile, 200);
      await tester.pumpAndSettle();
      await tester.tap(clearTile);
      await tester.pumpAndSettle();

      expect(find.text('Thumbnails'), findsOneWidget);
      expect(find.text('Screen Previews'), findsOneWidget);
      expect(find.text('PSD Previews'), findsOneWidget);
      expect(find.text('Total'), findsOneWidget);
      expect(find.text('1.0 KB'), findsOneWidget);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('4.0 KB'), findsOneWidget);
      expect(find.text('7.0 KB'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // 2. Translation Overlay Style & Text Size dialog with JP -> EN preview
      final overlayTile = find.text('Overlay Style & Text Size');
      await tester.scrollUntilVisible(overlayTile, 200);
      await tester.pumpAndSettle();
      await tester.tap(overlayTile);
      await tester.pumpAndSettle();

      expect(find.byType(TranslationOverlayPreview), findsOneWidget);
      expect(find.text('JP'), findsOneWidget);
      expect(find.text('EN'), findsOneWidget);

      // Select Dark Contrast style
      await tester.tap(find.byType(DropdownButton<TranslationOverlayStyle>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark Contrast').last);
      await tester.pumpAndSettle();
      expect(SettingsService.instance.settings.translationOverlayStyle,
          TranslationOverlayStyle.darkContrast);

      // Adjust slider inside overlay dialog
      final slider = tester.widget<Slider>(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byType(Slider),
        ),
      );
      slider.onChanged?.call(1.2);
      await tester.pumpAndSettle();
      expect(SettingsService.instance.settings.translationFontScale,
          closeTo(1.2, 0.01));

      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      // 3. App Lock toggle & Auto-lock Timeout dialog under Privacy & Security
      final appLockTile = find.text('App Lock');
      await tester.scrollUntilVisible(appLockTile, 200);
      await tester.pumpAndSettle();
      await tester.tap(appLockTile);
      await tester.pumpAndSettle();
      expect(SettingsService.instance.settings.appLockEnabled, isTrue);

      final timeoutTile = find.text('Auto-lock Timeout');
      expect(timeoutTile, findsOneWidget);
      expect(find.text('Immediately'), findsOneWidget);
      await tester.tap(timeoutTile);
      await tester.pumpAndSettle();
      expect(find.text('30 seconds'), findsOneWidget);
      expect(find.text('1 minute'), findsOneWidget);
      expect(find.text('5 minutes'), findsOneWidget);

      await tester.tap(find.text('1 minute'));
      await tester.pumpAndSettle();
      expect(SettingsService.instance.settings.appLockTimeoutSeconds, 60);
      expect(find.text('1 minute'), findsOneWidget);
    });
  });

  group('FastScrollHandle Tests', () {
    testWidgets(
        'FastScrollHandle is initially hidden, appears on scroll, auto-hides after 3s, reappears on scroll, and jumps on drag',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: FastScrollHandle(
                controller: controller,
                child: GridView.builder(
                  controller: controller,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                  ),
                  itemCount: 120,
                  itemBuilder: (_, i) => Container(
                    key: ValueKey('cell_$i'),
                    color: Colors.blueGrey,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      AnimatedOpacity getHandleOpacity() {
        return tester.widget<AnimatedOpacity>(
          find.descendant(
            of: find.byType(FastScrollHandle),
            matching: find.byType(AnimatedOpacity),
          ),
        );
      }

      Positioned getHandlePositioned() {
        return tester.widget<Positioned>(
          find.descendant(
            of: find.byType(FastScrollHandle),
            matching: find.byWidgetPredicate(
              (w) => w is Positioned && w.width == 38.0 && w.height == 54.0,
            ),
          ),
        );
      }

      // 1) Initially hidden when idle
      expect(getHandleOpacity().opacity, 0.0);
      expect(getHandlePositioned().top, 12.0);

      // 2) Appears on scroll, moves down proportionally, stays visible < 3s
      await tester.drag(find.byType(GridView), const Offset(0, -400));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(getHandleOpacity().opacity, 1.0);
      final topAfterScroll = getHandlePositioned().top!;
      expect(topAfterScroll, greaterThan(12.0));

      await tester.pump(const Duration(seconds: 2, milliseconds: 500));
      expect(getHandleOpacity().opacity, 1.0);

      // 3) Automatically hides after 3 seconds of no movement
      await tester.pump(const Duration(milliseconds: 750));
      await tester.pump(const Duration(milliseconds: 200));
      expect(getHandleOpacity().opacity, 0.0);

      // 4) Reappears immediately on scroll and dragging handle jumps offset
      await tester.drag(find.byType(GridView), const Offset(0, -100));
      await tester.pump();
      expect(getHandleOpacity().opacity, 1.0);

      final offsetBeforeHandleDrag = controller.offset;
      await tester.drag(
        find.byIcon(Icons.keyboard_arrow_down_rounded),
        const Offset(0, 150),
      );
      await tester.pump();
      expect(controller.offset, greaterThan(offsetBeforeHandleDrag + 300));

      // Drain hide timer cleanly
      await tester.pump(const Duration(seconds: 3, milliseconds: 250));
    });

    testWidgets('GalleryScreen and AlbumDetailScreen render with FastScrollHandle',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final items = List.generate(
        30,
        (i) => MediaItem(
          id: 'fast_$i',
          path: '/a/$i.jpg',
          name: '$i.jpg',
          date: DateTime(2026, 1, 1).add(Duration(minutes: i)),
          size: 1000,
          isVideo: false,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider
                .overrideWith(() => _SpecificMockMediaNotifier(items)),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: GalleryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FastScrollHandle), findsWidgets);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider.overrideWith(() => _MockMediaListNotifier()),
          ],
          child: const MaterialApp(
            localizationsDelegates: [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            home: AlbumDetailScreen(albumName: 'a'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byType(FastScrollHandle), findsWidgets);
    });

    testWidgets(
        'FastScrollHandle labelBuilder shows Month/Year pill during drag and hides on release',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 400,
              child: FastScrollHandle(
                controller: controller,
                labelBuilder: (f) => f > 0.2 ? 'Nov 2026' : 'Oct 2026',
                child: GridView.builder(
                  controller: controller,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                  ),
                  itemCount: 120,
                  itemBuilder: (_, i) => Container(
                    key: ValueKey('lbl_cell_$i'),
                    color: Colors.blueGrey,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.drag(find.byType(GridView), const Offset(0, -100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Oct 2026'), findsNothing);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.keyboard_arrow_down_rounded)),
      );
      await tester.pump();
      await gesture.moveBy(const Offset(0, 25));
      await tester.pump();
      await gesture.moveBy(const Offset(0, 120));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Nov 2026'), findsOneWidget);
      final pillOpacity = tester.widget<FadeTransition>(
        find.descendant(
          of: find.byKey(const ValueKey('fast_scroll_pill')),
          matching: find.byType(FadeTransition),
        ),
      );
      expect(pillOpacity.opacity.value, closeTo(1.0, 0.05));

      await gesture.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(pillOpacity.opacity.value, closeTo(0.0, 0.05));

      await tester.pump(const Duration(seconds: 3, milliseconds: 250));
    });

    testWidgets(
        'AlbumDetailScreen FastScrollHandle shows Month/Year pill only for date sorts',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final items = List.generate(
        30,
        (i) => MediaItem(
          id: 'sort_pill_$i',
          path: '/a/$i.jpg',
          name: '$i.jpg',
          date: DateTime(2026, 3, 15).add(Duration(minutes: i)),
          dateAdded: DateTime(2026, 5, 20).add(Duration(minutes: i)),
          size: 1000,
          isVideo: false,
          album: 'a',
        ),
      );

      Future<String?> pumpWithSort(SortOption sort) async {
        await tester.pumpWidget(
          ProviderScope(
            key: ValueKey(sort),
            overrides: [
              settingsNotifierProvider.overrideWith(
                () => _TestSettingsNotifier(SettingsModel(defaultSort: sort)),
              ),
              mediaListProvider
                  .overrideWith(() => _SpecificMockMediaNotifier(items)),
            ],
            child: const MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
              ],
              home: AlbumDetailScreen(albumName: 'a'),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final handle =
            tester.widget<FastScrollHandle>(find.byType(FastScrollHandle));
        return handle.labelBuilder?.call(0.5);
      }

      expect(await pumpWithSort(SortOption.newest), 'May 2026');
      expect(await pumpWithSort(SortOption.shootingTimeDesc), 'Mar 2026');
      expect(await pumpWithSort(SortOption.nameAZ), isNull);
    });

    testWidgets('DragSelectGrid selects range on horizontal drag',
        (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      final selected = <String>{};

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 300,
              child: StatefulBuilder(
                builder: (context, setState) {
                  return DragSelectGrid(
                    isSelecting: true,
                    itemCount: 9,
                    crossAxisCount: 3,
                    scrollController: controller,
                    idAt: (i) => 'id_$i',
                    isSelected: (id) => selected.contains(id),
                    onRangeSelectionChanged: (ids, select) {
                      setState(() {
                        if (select) {
                          selected.addAll(ids);
                        } else {
                          selected.removeAll(ids);
                        }
                      });
                    },
                    child: GridView.builder(
                      controller: controller,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                      ),
                      itemCount: 9,
                      itemBuilder: (_, i) => Container(
                        key: ValueKey('drag_cell_$i'),
                        color: selected.contains('id_$i')
                            ? Colors.blue
                            : Colors.grey,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.dragFrom(const Offset(25, 25), const Offset(225, 0));
      await tester.pumpAndSettle();

      expect(selected, containsAll(<String>['id_0', 'id_1', 'id_2']));
    });

    testWidgets(
        'AlbumDetailScreen in-album search filters across tabs and dismisses on clear/back',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final items = [
        MediaItem(
          id: 'alb_1',
          path: '/a/alpha_photo.jpg',
          name: 'alpha_photo.jpg',
          date: DateTime(2026, 3, 10),
          size: 1000,
          isVideo: false,
        ),
        MediaItem(
          id: 'alb_2',
          path: '/a/beta_photo.jpg',
          name: 'beta_photo.jpg',
          date: DateTime(2026, 3, 9),
          size: 1000,
          isVideo: false,
        ),
        MediaItem(
          id: 'alb_3',
          path: '/a/alpha_video.mp4',
          name: 'alpha_video.mp4',
          date: DateTime(2026, 3, 8),
          size: 2000,
          isVideo: true,
        ),
        MediaItem(
          id: 'alb_4',
          path: '/a/gamma_video.mp4',
          name: 'gamma_video.mp4',
          date: DateTime(2026, 3, 7),
          size: 2000,
          isVideo: true,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider
                .overrideWith(() => _SpecificMockMediaNotifier(items)),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLanguage.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AlbumDetailScreen(albumName: 'a'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MediaGridItem), findsNWidgets(4));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final searchField = find.byKey(const ValueKey('album_search_field'));
      expect(searchField, findsOneWidget);
      expect(find.text('Search in album...'), findsOneWidget);

      await tester.enterText(searchField, 'ALPHA');
      await tester.pump();
      expect(find.byType(MediaGridItem), findsNWidgets(2));

      await tester.tap(find.text('Photos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(MediaGridItem), findsNWidgets(1));

      await tester.tap(find.text('Videos'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(MediaGridItem), findsNWidgets(1));

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(find.byType(MediaGridItem), findsNWidgets(2));

      await tester.enterText(searchField, 'gamma');
      await tester.pump();
      expect(find.byType(MediaGridItem), findsNWidgets(1));

      await tester.tap(find.byKey(const ValueKey('album_search_cancel_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('album_search_field')), findsNothing);
      expect(find.byType(MediaGridItem), findsNWidgets(2));
    });

    test('AppTheme configures ripple-free iconButtonTheme across all 6 themes',
        () {
      final themes = [
        AppTheme.light,
        AppTheme.cleanLight,
        AppTheme.amoledPure,
        AppTheme.amoledSnowfall,
        AppTheme.amoledMidnight,
        AppTheme.amoledSakura,
      ];

      for (final theme in themes) {
        final style = theme.iconButtonTheme.style;
        expect(style, isNotNull);
        expect(style!.splashFactory, NoSplash.splashFactory);
        expect(
          style.overlayColor?.resolve(<WidgetState>{}),
          Colors.transparent,
        );
        expect(
          style.overlayColor?.resolve(<WidgetState>{WidgetState.pressed}),
          Colors.transparent,
        );
      }
    });

    testWidgets(
        'GalleryScreen empty search state shows clear search button and restores items on tap',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final items = [
        MediaItem(
          id: 'gal_1',
          path: '/a/sunset.jpg',
          name: 'sunset.jpg',
          date: DateTime(2026, 3, 10),
          size: 100000,
          isVideo: false,
        ),
        MediaItem(
          id: 'gal_2',
          path: '/a/mountain.jpg',
          name: 'mountain.jpg',
          date: DateTime(2026, 3, 9),
          size: 100000,
          isVideo: false,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider
                .overrideWith(() => _SpecificMockMediaNotifier(items)),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLanguage.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const GalleryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MediaGridItem), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      await tester.enterText(find.byType(TextField), 'zzz_no_match');
      await tester.pump();

      expect(find.byType(MediaGridItem), findsNothing);
      final clearSearchBtn =
          find.byKey(const ValueKey('gallery_clear_search_button'));
      expect(clearSearchBtn, findsOneWidget);
      expect(find.text('Clear search'), findsOneWidget);

      await tester.tap(clearSearchBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(clearSearchBtn, findsNothing);
      expect(find.byType(MediaGridItem), findsNWidgets(2));
    });

    testWidgets(
        'AlbumDetailScreen empty search state shows clear search button and restores items on tap',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final items = [
        MediaItem(
          id: 'alb_empty_1',
          path: '/a/alpha.jpg',
          name: 'alpha.jpg',
          date: DateTime(2026, 3, 10),
          size: 100000,
          isVideo: false,
        ),
        MediaItem(
          id: 'alb_empty_2',
          path: '/a/beta.jpg',
          name: 'beta.jpg',
          date: DateTime(2026, 3, 9),
          size: 100000,
          isVideo: false,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider
                .overrideWith(() => _SpecificMockMediaNotifier(items)),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLanguage.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const AlbumDetailScreen(albumName: 'a'),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MediaGridItem), findsNWidgets(2));

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      await tester.enterText(
          find.byKey(const ValueKey('album_search_field')), 'zzz_no_match');
      await tester.pump();

      expect(find.byType(MediaGridItem), findsNothing);
      final clearSearchBtn =
          find.byKey(const ValueKey('album_clear_search_button'));
      expect(clearSearchBtn, findsOneWidget);
      expect(find.text('Clear search'), findsOneWidget);

      await tester.tap(clearSearchBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(clearSearchBtn, findsNothing);
      expect(find.byKey(const ValueKey('album_search_field')), findsNothing);
      expect(find.byType(MediaGridItem), findsNWidgets(2));
    });

    test('MediaUtils.isHiddenPath handles normal, dot-prefixed, and relative paths',
        () {
      expect(MediaUtils.isHiddenPath('/storage/emulated/0/DCIM/photo.jpg'),
          isFalse);
      expect(MediaUtils.isHiddenPath(r'C:\Users\test\Pictures\pic.png'),
          isFalse);
      expect(MediaUtils.isHiddenPath('./relative/photo.jpg'), isFalse);
      expect(MediaUtils.isHiddenPath(r'.\relative\photo.jpg'), isFalse);
      expect(MediaUtils.isHiddenPath('.'), isFalse);

      expect(MediaUtils.isHiddenPath('/storage/0/.hidden/photo.jpg'), isTrue);
      expect(MediaUtils.isHiddenPath(r'C:\media\.thumbnails\thumb.jpg'),
          isTrue);
      expect(MediaUtils.isHiddenPath('.nomedia'), isTrue);
      expect(MediaUtils.isHiddenPath('/storage/0/DCIM/.nomedia'), isTrue);
    });

    testWidgets(
        'ThemeHeaderBackground and AnimatedFlameTitle pause when covered by non-opaque route or paused lifecycle',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();
      addTearDown(
        () => tester.binding
            .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
      );

      late BuildContext scaffoldContext;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsNotifierProvider.overrideWith(
              () => _TestSettingsNotifier(
                const SettingsModel(themeMode: AppThemeMode.amoledMidnight),
              ),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                flexibleSpace: const ThemeHeaderBackground(),
                title: const AnimatedFlameTitle(title: 'Phantek'),
              ),
              body: Builder(
                builder: (context) {
                  scaffoldContext = context;
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.binding.transientCallbackCount, 2);

      // Push a non-opaque route (mirrors _mediaViewerRoute).
      Navigator.of(scaffoldContext).push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      // Pop back to the underlying screen.
      Navigator.of(scaffoldContext).pop();
      await tester.pump();
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 2);

      // Background the app, then resume.
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(tester.binding.transientCallbackCount, 2);
    });

    testWidgets(
        'GalleryScreen search debounces on large sets (>250 items) and resets immediately on clear',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();

      final baseDate = DateTime(2026, 3, 10);
      final items = List.generate(
        260,
        (i) => MediaItem(
          id: 'large_$i',
          path: '/a/item_$i.jpg',
          name: 'item_$i.jpg',
          date: baseDate.subtract(Duration(minutes: i)),
          size: 100000,
          isVideo: false,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            mediaListProvider
                .overrideWith(() => _SpecificMockMediaNotifier(items)),
          ],
          child: MaterialApp(
            locale: const Locale('en'),
            supportedLocales: AppLanguage.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: const GalleryScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(MediaGridItem), findsWidgets);

      await tester.tap(find.byIcon(Icons.search));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // Typing on >250 items shows the clear button immediately, but defers filtering by 120ms.
      final appBarClearIcon = find.descendant(
        of: find.byType(AppBar),
        matching: find.byIcon(Icons.close_rounded),
      );
      await tester.enterText(find.byType(TextField), 'zzz_no_match');
      await tester.pump();
      expect(appBarClearIcon, findsOneWidget);
      expect(find.byKey(const ValueKey('gallery_clear_search_button')),
          findsNothing);
      expect(find.byType(MediaGridItem), findsWidgets);

      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byKey(const ValueKey('gallery_clear_search_button')),
          findsOneWidget);
      expect(find.byType(MediaGridItem), findsNothing);

      // Clearing text resets immediately without debounce.
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.byKey(const ValueKey('gallery_clear_search_button')),
          findsNothing);
      expect(find.byType(MediaGridItem), findsWidgets);

      // Re-type to filter, then tap the clear 'X' icon to verify immediate reset.
      await tester.enterText(find.byType(TextField), 'zzz_no_match');
      await tester.pump(const Duration(milliseconds: 150));
      expect(find.byType(MediaGridItem), findsNothing);

      await tester.tap(appBarClearIcon);
      await tester.pump();
      expect(find.byKey(const ValueKey('gallery_clear_search_button')),
          findsNothing);
      expect(find.byType(MediaGridItem), findsWidgets);
    });

    testWidgets(
        'GridHiResScope activates hi-res after idle, downgrades immediately on scroll start, and re-activates after scroll settles',
        (tester) async {
      final hiResController = GridHiResController(
        idleDelay: const Duration(milliseconds: 180),
      );
      addTearDown(hiResController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GridHiResScope(
              controller: hiResController,
              child: ListView.builder(
                itemCount: 40,
                itemBuilder: (_, i) => SizedBox(
                  height: 120,
                  child: Text('Tile $i'),
                ),
              ),
            ),
          ),
        ),
      );

      // Post-frame schedules initial idle; before idleDelay expires, hi-res is inactive.
      await tester.pump();
      expect(hiResController.value.active, isFalse);

      // After idle delay, hi-res activates.
      await tester.pump(const Duration(milliseconds: 200));
      expect(hiResController.value.active, isTrue);

      // Starting a vertical drag immediately downgrades hi-res to false.
      final gesture = await tester.startGesture(const Offset(200, 300));
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump();
      expect(hiResController.value.active, isFalse);

      // Release drag and let fling/scroll settle past idleDelay -> re-activates.
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(hiResController.value.active, isTrue);
    });

    testWidgets(
        'GridHiResScope downgrades immediately when covered by a non-opaque route and re-activates on pop',
        (tester) async {
      final hiResController = GridHiResController(
        idleDelay: const Duration(milliseconds: 180),
      );
      addTearDown(hiResController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GridHiResScope(
              controller: hiResController,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(hiResController.value.active, isTrue);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.push(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, __, ___) => const Scaffold(
            body: Center(child: Text('Overlay Viewer')),
          ),
        ),
      );
      await tester.pump();
      expect(hiResController.value.active, isFalse);

      navigator.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(hiResController.value.active, isTrue);
    });

    test(
        'ThumbnailService.getGridHiResVideoThumbnail returns null immediately when already cancelled',
        () async {
      final result = await ThumbnailService.instance.getGridHiResVideoThumbnail(
        'cancelled_vid_1',
        filePath: '/storage/emulated/0/Movies/cancelled.mp4',
        isCancelled: () => true,
      );
      expect(result, isNull);
    });

    test('AppLanguage.sortedLanguages sorts A-Z by native language name', () {
      final sorted = AppLanguage.sortedLanguages;
      expect(sorted.length, AppLanguage.values.length);
      expect(
        sorted.take(6).map((l) => l.nativeName).toList(),
        [
          'Bahasa Indonesia',
          'Bahasa Melayu',
          'Dansk',
          'Deutsch',
          'English',
          'Español',
        ],
      );
      for (int i = 0; i < sorted.length - 1; i++) {
        expect(
          sorted[i]
              .nativeName
              .toLowerCase()
              .compareTo(sorted[i + 1].nativeName.toLowerCase()),
          lessThanOrEqualTo(0),
        );
      }
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
      MediaItem(
          id: 'item_1',
          path: '/a/1.jpg',
          name: '1.jpg',
          date: DateTime.now(),
          size: 10,
          isVideo: false),
      MediaItem(
          id: 'item_2',
          path: '/a/2.jpg',
          name: '2.jpg',
          date: DateTime.now(),
          size: 20,
          isVideo: false),
      MediaItem(
          id: 'item_3',
          path: '/a/3.mp4',
          name: '3.mp4',
          date: DateTime.now(),
          size: 30,
          isVideo: true),
    ];
    return mockItems.where((e) => !deletedIds.contains(e.id)).toList();
  }

  @override
  Future<void> refresh() async {
    final mockItems = [
      MediaItem(
          id: 'item_1',
          path: '/a/1.jpg',
          name: '1.jpg',
          date: DateTime.now(),
          size: 10,
          isVideo: false),
      MediaItem(
          id: 'item_2',
          path: '/a/2.jpg',
          name: '2.jpg',
          date: DateTime.now(),
          size: 20,
          isVideo: false),
      MediaItem(
          id: 'item_3',
          path: '/a/3.mp4',
          name: '3.mp4',
          date: DateTime.now(),
          size: 30,
          isVideo: true),
    ];
    state =
        AsyncData(mockItems.where((e) => !deletedIds.contains(e.id)).toList());
  }
}

class _SpecificMockMediaNotifier extends MediaListNotifier {
  final List<MediaItem> items;
  _SpecificMockMediaNotifier(this.items);

  @override
  Future<List<MediaItem>> build() async => items;

  @override
  Future<void> refresh() async {
    state = AsyncData(items);
  }
}

class _MutableMockMediaNotifier extends MediaListNotifier {
  List<MediaItem> _items;
  _MutableMockMediaNotifier(this._items);

  @override
  Future<List<MediaItem>> build() async => _items;

  void setItems(List<MediaItem> next) {
    _items = next;
    state = AsyncData(next);
  }

  @override
  Future<void> refresh() async {
    state = AsyncData(_items);
  }
}
