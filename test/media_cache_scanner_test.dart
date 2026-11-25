import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/models/settings_model.dart';
import 'package:phantek_gallery/core/providers/media_provider.dart';
import 'package:phantek_gallery/core/providers/settings_provider.dart';
import 'package:phantek_gallery/core/services/media_cache_service.dart';
import 'package:phantek_gallery/core/services/media_scanner_service.dart';

class _FakeSettingsNotifier extends SettingsNotifier {
  _FakeSettingsNotifier(this._initial);

  final SettingsModel _initial;

  @override
  SettingsModel build() => _initial;
}

class _FakeMediaScannerService extends MediaScannerService {
  int scanCalls = 0;
  Completer<List<MediaItem>>? nextCompleter;
  List<MediaItem> nextItems = const [];

  @override
  Future<List<MediaItem>> scanAll({
    List<String> excludedFolders = const [],
    void Function(int loaded, int total)? onProgress,
  }) {
    scanCalls++;
    final completer = nextCompleter;
    if (completer != null) {
      return completer.future;
    }
    return Future.value(nextItems);
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('phantek_media_cache_test_');
    MediaCacheService.instance.testDirectoryOverride = tempDir;
  });

  tearDown(() async {
    MediaCacheService.instance.testDirectoryOverride = null;
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('MediaScannerService.parseNativeScanResults', () {
    test('maps photos and videos while filtering trash, excluded, and unsupported videos', () {
      const dateMs = 1700000000000;
      const dateAddedMs = 1700000500000;

      final raw = <dynamic>[
        {
          'id': '101',
          'path': '/storage/emulated/0/DCIM/Camera/IMG_001.jpg',
          'name': 'IMG_001.jpg',
          'dateMs': dateMs,
          'dateAddedMs': dateAddedMs,
          'size': 204800,
          'isVideo': false,
          'durationMs': null,
          'width': 3000,
          'height': 4000,
          'mimeType': 'image/jpeg',
        },
        {
          'id': '102',
          'path': '/storage/emulated/0/Movies/clip.mkv',
          'name': 'clip.mkv',
          'dateMs': dateMs,
          'dateAddedMs': dateAddedMs,
          'size': 1048576,
          'isVideo': true,
          'durationMs': 12500,
          'width': 1920,
          'height': 1080,
          'mimeType': null,
        },
        // Filtered: trash
        {
          'id': '103',
          'path': '/storage/emulated/0/DCIM/.trash/deleted.jpg',
          'name': 'deleted.jpg',
          'dateMs': dateMs,
          'dateAddedMs': dateAddedMs,
          'size': 100,
          'isVideo': false,
          'width': 100,
          'height': 100,
        },
        // Filtered: excluded folder
        {
          'id': '104',
          'path': '/storage/emulated/0/Private/secret.png',
          'name': 'secret.png',
          'dateMs': dateMs,
          'dateAddedMs': dateAddedMs,
          'size': 100,
          'isVideo': false,
          'width': 100,
          'height': 100,
        },
        // Filtered: unsupported video format
        {
          'id': '105',
          'path': '/storage/emulated/0/Movies/odd.rmvb',
          'name': 'odd.rmvb',
          'dateMs': dateMs,
          'dateAddedMs': dateAddedMs,
          'size': 100,
          'isVideo': true,
          'durationMs': 5000,
          'width': 640,
          'height': 480,
          'mimeType': 'application/vnd.rn-realmedia-vbr',
        },
      ];

      final items = MediaScannerService.parseNativeScanResults(
        raw,
        excludedFolders: const ['/storage/emulated/0/Private'],
      );

      expect(items, hasLength(2));

      final photo = items[0];
      expect(photo.id, '101');
      expect(photo.name, 'IMG_001.jpg');
      expect(photo.date, DateTime.fromMillisecondsSinceEpoch(dateMs));
      expect(photo.dateAdded, DateTime.fromMillisecondsSinceEpoch(dateAddedMs));
      expect(photo.size, 204800);
      expect(photo.isVideo, isFalse);
      expect(photo.duration, isNull);
      expect(photo.width, 3000);
      expect(photo.height, 4000);
      expect(photo.mimeType, 'image/jpeg');

      final video = items[1];
      expect(video.id, '102');
      expect(video.isVideo, isTrue);
      expect(video.duration, const Duration(milliseconds: 12500));
      expect(video.mimeType, 'video/x-matroska');
    });
  });

  group('MediaCacheService (isolate compute)', () {
    test('round-trips MediaItems via save() and load()', () async {
      final items = [
        MediaItem(
          id: '1',
          path: '/storage/emulated/0/DCIM/a.jpg',
          name: 'a.jpg',
          date: DateTime(2025, 1, 2, 3, 4, 5),
          dateAdded: DateTime(2025, 1, 2, 4, 5, 6),
          size: 12345,
          isVideo: false,
          width: 1080,
          height: 1920,
          mimeType: 'image/jpeg',
        ),
        MediaItem(
          id: '2',
          path: '/storage/emulated/0/Movies/b.mp4',
          name: 'b.mp4',
          date: DateTime(2025, 2, 3, 4, 5, 6),
          dateAdded: DateTime(2025, 2, 3, 5, 6, 7),
          size: 987654,
          isVideo: true,
          duration: const Duration(milliseconds: 42500),
          width: 1920,
          height: 1080,
          mimeType: 'video/mp4',
        ),
      ];

      expect(await MediaCacheService.instance.load(), isNull);
      await MediaCacheService.instance.save(items);
      final loaded = await MediaCacheService.instance.load();

      expect(loaded, equals(items));
    });
  });

  group('MediaListNotifier scan deduplication', () {
    test('coalesces concurrent startup background refresh and explicit refresh()', () async {
      final cachedItem = MediaItem(
        id: 'cached_1',
        path: '/storage/emulated/0/DCIM/cached.jpg',
        name: 'cached.jpg',
        date: DateTime(2025, 1, 1),
        size: 100,
        isVideo: false,
      );
      await MediaCacheService.instance.save([cachedItem]);

      final freshItems = [
        cachedItem,
        MediaItem(
          id: 'fresh_2',
          path: '/storage/emulated/0/DCIM/fresh.jpg',
          name: 'fresh.jpg',
          date: DateTime(2025, 1, 2),
          size: 200,
          isVideo: false,
        ),
      ];

      final scanner = _FakeMediaScannerService();
      final completer = Completer<List<MediaItem>>();
      scanner.nextCompleter = completer;

      final container = ProviderContainer(
        overrides: [
          settingsNotifierProvider.overrideWith(
            () => _FakeSettingsNotifier(const SettingsModel()),
          ),
          mediaScannerProvider.overrideWithValue(scanner),
        ],
      );
      addTearDown(container.dispose);

      // 1. Initial build returns cached items and schedules _backgroundRefresh.
      final initial = await container.read(mediaListProvider.future);
      expect(initial, [cachedItem]);

      // 2. Trigger explicit refresh() concurrently with the startup microtask refresh.
      final refresh1 = container.read(mediaListProvider.notifier).refresh();
      final refresh2 = container.read(mediaListProvider.notifier).refresh();

      // Let microtasks run so _backgroundRefresh + refresh() both enter _scan().
      await Future<void>.delayed(Duration.zero);
      expect(scanner.scanCalls, 1);

      // Delete cached_1 while scan is in flight to ensure deletions are preserved.
      container.read(mediaListProvider.notifier).removeItems(['cached_1']);

      completer.complete(freshItems);
      await Future.wait([refresh1, refresh2]);

      expect(scanner.scanCalls, 1);
      final current = container.read(mediaListProvider).value;
      expect(current?.map((e) => e.id).toList(), ['fresh_2']);

      // 3. After completion, a subsequent refresh triggers a new scan.
      scanner.nextCompleter = null;
      scanner.nextItems = freshItems;
      await container.read(mediaListProvider.notifier).refresh();
      expect(scanner.scanCalls, 2);

      // Allow fire-and-forget cache save compute() to complete before tearDown.
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
  });
}
