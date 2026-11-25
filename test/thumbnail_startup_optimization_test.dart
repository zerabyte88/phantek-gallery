import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:phantek_gallery/core/services/thumbnail_service.dart';

const _thumbnailChannel = MethodChannel('com.phantek.gallery/thumbnail');

Future<void> _waitUntil(
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailService startup & queue optimizations', () {
    setUp(() async {
      await ThumbnailService.init();
      await ThumbnailService.instance.clearAll();
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_thumbnailChannel, null);
      await ThumbnailService.instance.clearAll();
    });

    test(
      'fast disk cache hit before disk index finishes bypasses saturated decode workers and populates caches',
      () async {
        final service = ThumbnailService.instance;
        final cacheDir = await service.getCacheDirectory();
        const cachedAssetId = 'cached_before_index_1';
        final expectedBytes =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4]);
        final cachedFile = File(
          p.join(cacheDir.path, service.debugCacheFileName(cachedAssetId)),
        );
        await cachedFile.writeAsBytes(expectedBytes);

        // Index has not completed yet (reset by clearAll).
        expect(service.debugIsDiskIndexReady, isFalse);
        expect(service.hasDiskCache(cachedAssetId), isFalse);

        final blockers = <String, Completer<Uint8List?>>{};
        final nativeCalls = <String>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_thumbnailChannel, (call) async {
          if (call.method == 'getImageThumbnail') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final id = args['assetId'] as String;
            nativeCalls.add(id);
            final completer = blockers[id];
            if (completer != null) return completer.future;
            return Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]);
          }
          return null;
        });

        // Saturate all 6 low-res decode workers.
        final blockerFutures = <Future<Uint8List?>>[];
        for (var i = 0; i < 6; i++) {
          final id = 'blocker_$i';
          blockers[id] = Completer<Uint8List?>();
          blockerFutures.add(
            service.getThumbnail(id, filePath: '/fake/$id.jpg'),
          );
        }
        await _waitUntil(() => nativeCalls.length == 6);

        // Fast disk-check path must resolve immediately without waiting for workers.
        final bytes = await service.getThumbnail(
          cachedAssetId,
          filePath: '/fake/$cachedAssetId.jpg',
        );
        expect(bytes, equals(expectedBytes));
        expect(service.hasDiskCache(cachedAssetId), isTrue);
        expect(service.getMemoryThumbnail(cachedAssetId), equals(expectedBytes));
        expect(nativeCalls.contains(cachedAssetId), isFalse);

        // Release blocked workers cleanly.
        for (final c in blockers.values) {
          c.complete(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
        }
        await Future.wait(blockerFutures);
      },
    );

    test(
      'non-blocking init indexes existing cache files asynchronously in background',
      () async {
        final service = ThumbnailService.instance;
        final cacheDir = await service.getCacheDirectory();
        const assetId = 'bg_indexed_asset';
        final fileName = service.debugCacheFileName(assetId);
        await File(p.join(cacheDir.path, fileName))
            .writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));

        expect(service.hasDiskCache(assetId), isFalse);

        await ThumbnailService.init();
        await _waitUntil(() => service.debugIsDiskIndexReady);

        expect(service.hasDiskCache(assetId), isTrue);
        expect(service.getIndexedDiskFile(assetId)?.path,
            endsWith(fileName));
      },
    );

    test(
      'low-res worker processes queued items in FIFO top-first order and skips cancelled items',
      () async {
        final service = ThumbnailService.instance;
        service.debugSetDiskIndexReady(true);

        final blockers = <String, Completer<Uint8List?>>{};
        final queuedCallOrder = <String>[];
        var blockerCalls = 0;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_thumbnailChannel, (call) async {
          if (call.method == 'getImageThumbnail') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final id = args['assetId'] as String;
            final blocker = blockers[id];
            if (blocker != null) {
              blockerCalls++;
              return blocker.future;
            }
            queuedCallOrder.add(id);
            return Uint8List.fromList([0xFF, 0xD8, id.codeUnitAt(0), 0xD9]);
          }
          return null;
        });

        // Occupy all 6 workers so subsequent requests wait in _queue.
        final blockerFutures = <Future<Uint8List?>>[];
        for (var i = 0; i < 6; i++) {
          final id = 'slot_$i';
          blockers[id] = Completer<Uint8List?>();
          blockerFutures.add(
            service.getThumbnail(id, filePath: '/fake/$id.jpg'),
          );
        }
        await _waitUntil(() => blockerCalls == 6);

        var cancelled2 = false;
        final top1Future =
            service.getThumbnail('top_1', filePath: '/fake/top_1.jpg');
        final cancelled2Future = service.getThumbnail(
          'cancelled_2',
          filePath: '/fake/cancelled_2.jpg',
          isCancelled: () => cancelled2,
        );
        final top3Future =
            service.getThumbnail('top_3', filePath: '/fake/top_3.jpg');
        final bottom4Future =
            service.getThumbnail('bottom_4', filePath: '/fake/bottom_4.jpg');

        // Mark second tile as scrolled off-screen before workers pick it up.
        cancelled2 = true;

        // Release one worker so it drains the queue strictly sequentially.
        blockers['slot_0']!.complete(Uint8List.fromList([0xFF, 0xD8, 0xD9]));

        final results = await Future.wait([
          top1Future,
          cancelled2Future,
          top3Future,
          bottom4Future,
        ]);

        expect(results[0], isNotNull);
        expect(results[1], isNull);
        expect(results[2], isNotNull);
        expect(results[3], isNotNull);
        expect(queuedCallOrder, equals(['top_1', 'top_3', 'bottom_4']));

        for (var i = 1; i < 6; i++) {
          blockers['slot_$i']!
              .complete(Uint8List.fromList([0xFF, 0xD8, 0xD9]));
        }
        await Future.wait(blockerFutures);
      },
    );

    test(
      'GridHiRes queue defers while low-res queue is busy and resumes automatically once drained',
      () async {
        final service = ThumbnailService.instance;
        service.debugSetDiskIndexReady(true);

        final lowResCompleters = <String, Completer<Uint8List?>>{
          'lowres_1': Completer<Uint8List?>(),
          'lowres_2': Completer<Uint8List?>(),
        };
        final hiResStarted = <String>[];
        final lowResStarted = <String>[];

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_thumbnailChannel, (call) async {
          if (call.method == 'getImageThumbnail') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final id = args['assetId'] as String;
            final isLowPriority = args['lowPriority'] == true;
            if (isLowPriority) {
              hiResStarted.add(id);
              return Uint8List.fromList([0xFF, 0xD8, 0xAA, 0xD9]);
            }
            lowResStarted.add(id);
            return lowResCompleters[id]!.future;
          }
          return null;
        });

        final low1Future =
            service.getThumbnail('lowres_1', filePath: '/fake/lowres_1.jpg');
        final low2Future =
            service.getThumbnail('lowres_2', filePath: '/fake/lowres_2.jpg');
        await _waitUntil(() => lowResStarted.length == 2);

        final hiResFuture = service.getGridHiResPhotoThumbnail(
          'hires_1',
          filePath: '/fake/hires_1.jpg',
        );

        // Yield while both low-res workers are active: hi-res must stay deferred.
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(hiResStarted, isEmpty);

        // Complete first low-res worker; second is still active so hi-res remains deferred.
        lowResCompleters['lowres_1']!
            .complete(Uint8List.fromList([0xFF, 0xD8, 0x01, 0xD9]));
        await low1Future;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(hiResStarted, isEmpty);

        // Complete final low-res worker; hi-res must wake up automatically.
        lowResCompleters['lowres_2']!
            .complete(Uint8List.fromList([0xFF, 0xD8, 0x02, 0xD9]));
        await low2Future;

        final hiResBytes = await hiResFuture;
        expect(hiResBytes, isNotNull);
        expect(hiResStarted, equals(['hires_1']));
      },
    );

    test(
      'in-flight GridHiRes worker pauses before next queued hi-res item when low-res work arrives',
      () async {
        final service = ThumbnailService.instance;
        service.debugSetDiskIndexReady(true);

        final hiResCompleters = <String, Completer<Uint8List?>>{
          'hires_a': Completer<Uint8List?>(),
          'hires_b': Completer<Uint8List?>(),
        };
        final lowResCompleter = Completer<Uint8List?>();
        final hiResStarted = <String>[];
        var lowResStarted = false;

        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_thumbnailChannel, (call) async {
          if (call.method == 'getImageThumbnail') {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            final id = args['assetId'] as String;
            if (args['lowPriority'] == true) {
              hiResStarted.add(id);
              final completer = hiResCompleters[id];
              if (completer != null) return completer.future;
              return Uint8List.fromList([0xFF, 0xD8, 0xCC, 0xD9]);
            }
            lowResStarted = true;
            return lowResCompleter.future;
          }
          return null;
        });

        // Fill both hi-res worker slots and queue a 3rd hi-res request.
        final hiAFuture = service.getGridHiResPhotoThumbnail(
          'hires_a',
          filePath: '/fake/hires_a.jpg',
        );
        final hiBFuture = service.getGridHiResPhotoThumbnail(
          'hires_b',
          filePath: '/fake/hires_b.jpg',
        );
        final hiCFuture = service.getGridHiResPhotoThumbnail(
          'hires_c',
          filePath: '/fake/hires_c.jpg',
        );
        await _waitUntil(() => hiResStarted.length == 2);
        expect(hiResStarted, equals(['hires_a', 'hires_b']));

        // Low-res request arrives while hi-res workers are busy.
        final lowFuture = service.getThumbnail(
          'lowres_urgent',
          filePath: '/fake/lowres_urgent.jpg',
        );
        await _waitUntil(() => lowResStarted);

        // Even after hires_a finishes, its worker must yield instead of starting hires_c.
        hiResCompleters['hires_a']!
            .complete(Uint8List.fromList([0xFF, 0xD8, 0xAA, 0xD9]));
        await hiAFuture;
        await Future<void>.delayed(const Duration(milliseconds: 25));
        expect(hiResStarted, equals(['hires_a', 'hires_b']));

        // Once low-res drains, hires_c resumes automatically.
        lowResCompleter.complete(Uint8List.fromList([0xFF, 0xD8, 0x11, 0xD9]));
        await lowFuture;
        hiResCompleters['hires_b']!
            .complete(Uint8List.fromList([0xFF, 0xD8, 0xBB, 0xD9]));
        await hiBFuture;

        final hiCBytes = await hiCFuture;
        expect(hiCBytes, isNotNull);
        expect(hiResStarted, equals(['hires_a', 'hires_b', 'hires_c']));
      },
    );

    test(
      'writeDiskCacheBytes persists atomically without leaving temporary files behind',
      () async {
        final service = ThumbnailService.instance;
        final cacheDir = await service.getCacheDirectory();
        final fileName = service.debugCacheFileName('atomic_test_1');
        final payload = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 42, 43]);

        await service.writeDiskCacheBytes(fileName, payload);

        final file = File(p.join(cacheDir.path, fileName));
        expect(await file.exists(), isTrue);
        expect(await file.readAsBytes(), equals(payload));
        final leftoverTmp = cacheDir
            .listSync()
            .where((e) => e.path.endsWith('.tmp'))
            .toList();
        expect(leftoverTmp, isEmpty);
      },
    );
  });
}
