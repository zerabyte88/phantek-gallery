import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:phantek_gallery/core/localization/app_localizations.dart';
import 'package:phantek_gallery/core/models/media_item.dart';
import 'package:phantek_gallery/core/services/psd_service.dart';
import 'package:phantek_gallery/core/services/settings_service.dart';
import 'package:phantek_gallery/core/services/thumbnail_service.dart';
import 'package:phantek_gallery/features/player/presentation/image_viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _createRenderableSyntheticPsd({
  int width = 20,
  int height = 16,
  required List<img.ColorRgba8> layerColors,
}) {
  final bb = BytesBuilder();

  // 1. Header (26 bytes)
  bb.add([0x38, 0x42, 0x50, 0x53]); // '8BPS'
  final headerMeta = ByteData(22);
  headerMeta.setUint16(0, 1); // version 1
  headerMeta.setUint16(8, 3); // channels = 3
  headerMeta.setUint32(10, height);
  headerMeta.setUint32(14, width);
  headerMeta.setUint16(18, 8); // depth = 8
  headerMeta.setUint16(20, 3); // colorMode = RGB
  bb.add(headerMeta.buffer.asUint8List());

  // 2. Color Mode Data
  bb.add([0, 0, 0, 0]);

  // 3. Image Resources
  bb.add([0, 0, 0, 0]);

  final channelLen = 2 + width * height;

  // 4. Section 4: Layer records
  final recordsBuilder = BytesBuilder();
  final countData = ByteData(2);
  countData.setInt16(0, layerColors.length);
  recordsBuilder.add(countData.buffer.asUint8List());

  for (var i = 0; i < layerColors.length; i++) {
    final rect = ByteData(16);
    rect.setInt32(0, 0);
    rect.setInt32(4, 0);
    rect.setInt32(8, height);
    rect.setInt32(12, width);
    recordsBuilder.add(rect.buffer.asUint8List());

    final chanCount = ByteData(2);
    chanCount.setUint16(0, 3);
    recordsBuilder.add(chanCount.buffer.asUint8List());

    final chanInfo = ByteData(3 * 6);
    for (var c = 0; c < 3; c++) {
      chanInfo.setInt16(c * 6, c);
      chanInfo.setUint32(c * 6 + 2, channelLen);
    }
    recordsBuilder.add(chanInfo.buffer.asUint8List());

    recordsBuilder.add([0x38, 0x42, 0x49, 0x4D]); // '8BIM'
    recordsBuilder.add([0x6E, 0x6F, 0x72, 0x6D]); // 'norm'
    recordsBuilder.add([255, 0, 0, 0]);
    recordsBuilder.add([0, 0, 0, 0]); // extra data length = 0
  }

  final channelDataBuilder = BytesBuilder();
  for (final color in layerColors) {
    channelDataBuilder.add([0, 0]);
    channelDataBuilder.add(List.filled(width * height, color.r.toInt()));
    channelDataBuilder.add([0, 0]);
    channelDataBuilder.add(List.filled(width * height, color.g.toInt()));
    channelDataBuilder.add([0, 0]);
    channelDataBuilder.add(List.filled(width * height, color.b.toInt()));
  }

  final recordsBytes = recordsBuilder.toBytes();
  final channelDataBytes = channelDataBuilder.toBytes();
  final layerInfoLen = recordsBytes.length + channelDataBytes.length;

  final sec4Meta = ByteData(8);
  sec4Meta.setUint32(0, 4 + layerInfoLen);
  sec4Meta.setUint32(4, layerInfoLen);
  bb.add(sec4Meta.buffer.asUint8List());
  bb.add(recordsBytes);
  bb.add(channelDataBytes);

  return bb.toBytes();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Photo & PSD Preview Caching Tests', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await SettingsService.init();
    });

    test(
        'ThumbnailService.prewarmPhotoPreview generates persistent disk and memory preview for high-res photo and screenDisplayImage serves cached providers synchronously',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('photo_preview_cache_');
      addTearDown(() async {
        await ThumbnailService.instance.clearAll();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      await ThumbnailService.init();
      await ThumbnailService.instance.clearAll();

      // Generate a real 2400x1800 JPEG image in temp directory
      final sourceImage = img.Image(width: 2400, height: 1800);
      img.fill(sourceImage, color: img.ColorRgb8(40, 120, 220));
      final jpgBytes = img.encodeJpg(sourceImage, quality: 85);
      final photoFile = File('${tempDir.path}/highres_test.jpg');
      await photoFile.writeAsBytes(jpgBytes, flush: true);

      // Synthetic non-existent paths never throw
      expect(screenDisplayImage('/a/1.jpg'), isA<ResizeImage>());
      expect(
        PsdService.instance.getCachedRenderedPreviewSync('/a/1.psd'),
        isNull,
      );

      final prewarmed = await ThumbnailService.instance.prewarmPhotoPreview(
        photoFile.path,
        assetId: 'photo_1',
      );
      expect(prewarmed, isNotNull);
      expect(prewarmed, isNotEmpty);

      final memBytes =
          ThumbnailService.instance.getMemoryPreview(photoFile.path);
      expect(memBytes, isNotNull);
      expect(memBytes, equals(prewarmed));

      final diskFile =
          ThumbnailService.instance.getCachedPreviewFile(photoFile.path);
      expect(diskFile, isNotNull);
      expect(diskFile!.existsSync(), isTrue);

      final decodedPreview = img.decodeJpg(memBytes!);
      expect(decodedPreview, isNotNull);
      expect(
        math.max(decodedPreview!.width, decodedPreview.height),
        lessThanOrEqualTo(ThumbnailService.defaultPreviewMaxDim),
      );
      expect(decodedPreview.width, 1440);
      expect(decodedPreview.height, 1080);

      // Memory cache hit serves MemoryImage synchronously
      final memProvider = screenDisplayImage(photoFile.path);
      expect(memProvider, isA<MemoryImage>());
      expect((memProvider as MemoryImage).bytes, equals(memBytes));

      // After trimming memory, disk cache hit serves FileImage pointing to cached preview file
      ThumbnailService.instance.trimMemory();
      expect(ThumbnailService.instance.getMemoryPreview(photoFile.path), isNull);

      final diskProvider = screenDisplayImage(photoFile.path);
      expect(diskProvider, isA<FileImage>());
      expect((diskProvider as FileImage).file.path, equals(diskFile.path));
    });

    testWidgets(
        'PsdService caches rendered preview on disk and memory, and ImageViewerScreen opens cached PSD immediately without loading card',
        (tester) async {
      late Directory tempDir;
      late File psdFile;
      late Uint8List prewarmedBytes;

      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('psd_preview_cache_');
        psdFile = File('${tempDir.path}/artwork_cached.psd');
        final psdBytes = _createRenderableSyntheticPsd(
          width: 20,
          height: 16,
          layerColors: [
            img.ColorRgba8(255, 0, 0, 255),
            img.ColorRgba8(0, 180, 255, 255),
          ],
        );
        await psdFile.writeAsBytes(psdBytes, flush: true);

        await ThumbnailService.init();
        await ThumbnailService.instance.clearAll();

        final result =
            await PsdService.instance.prewarmPsdDocument(psdFile.path);
        expect(result, isNotNull);
        expect(result, isNotEmpty);
        prewarmedBytes = result!;

        expect(
          PsdService.instance.getCachedLayersSync(psdFile.path),
          isNotNull,
        );
        expect(
          PsdService.instance.getCachedRenderedPreviewSync(psdFile.path),
          equals(prewarmedBytes),
        );

        // Verify disk cache survives memory clearing
        PsdService.instance.clearMemoryCache();
        expect(
          PsdService.instance.getCachedLayersSync(psdFile.path),
          isNull,
        );
        final diskRestored =
            PsdService.instance.getCachedRenderedPreviewSync(psdFile.path);
        expect(diskRestored, isNotNull);
        expect(diskRestored, equals(prewarmedBytes));

        // Clear memory again so ImageViewerScreen proves disk-backed sync load on frame 1
        PsdService.instance.clearMemoryCache();
      });

      addTearDown(() async {
        await tester.runAsync(() async {
          await ThumbnailService.instance.clearAll();
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final psdItem = MediaItem(
        id: 'psd_cached_1',
        path: psdFile.path,
        name: 'artwork_cached.psd',
        date: DateTime(2026, 1, 1),
        size: psdFile.lengthSync(),
        isVideo: false,
        width: 20,
        height: 16,
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
              items: [psdItem],
              initialIndex: 0,
            ),
          ),
        ),
      );

      // On the very first frame, cached PSD preview must render without loading card
      expect(find.text('Reading Photoshop document...'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
