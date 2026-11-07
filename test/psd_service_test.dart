import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:phantek_gallery/core/services/license_service.dart';
import 'package:phantek_gallery/core/services/psd_service.dart';

class _SyntheticLayer {
  final String pascalName;
  final String? unicodeName;
  final bool isVisible;
  final int opacity;
  final bool isFolder;
  final bool isClosingDelimiter;
  final bool isClipped;

  const _SyntheticLayer({
    required this.pascalName,
    this.unicodeName,
    this.isVisible = true,
    this.opacity = 255,
    this.isFolder = false,
    this.isClosingDelimiter = false,
    this.isClipped = false,
  });
}

Uint8List _createSyntheticPsd({
  int version = 1,
  required List<_SyntheticLayer> layers,
}) {
  final bb = BytesBuilder();

  // 1. Header (26 bytes)
  bb.add([0x38, 0x42, 0x50, 0x53]); // '8BPS'
  final headerMeta = ByteData(22);
  headerMeta.setUint16(0, version); // version (1 = PSD, 2 = PSB)
  // 6 bytes reserved = 0
  headerMeta.setUint16(8, 3); // channels = 3
  headerMeta.setUint32(10, 100); // height = 100
  headerMeta.setUint32(14, 100); // width = 100
  headerMeta.setUint16(18, 8); // depth = 8
  headerMeta.setUint16(20, 3); // colorMode = RGB
  bb.add(headerMeta.buffer.asUint8List());

  // 2. Color Mode Data (4 bytes length: 0)
  bb.add([0, 0, 0, 0]);

  // 3. Image Resources (4 bytes length: 0)
  bb.add([0, 0, 0, 0]);

  // Build Layer Records block
  final recordsBuilder = BytesBuilder();
  // Layer count (int16)
  final countData = ByteData(2);
  countData.setInt16(0, layers.length);
  recordsBuilder.add(countData.buffer.asUint8List());

  for (final l in layers) {
    // Rect (16 bytes: top, left, bottom, right)
    final rect = ByteData(16);
    rect.setInt32(0, 0);
    rect.setInt32(4, 0);
    rect.setInt32(8, 100);
    rect.setInt32(12, 100);
    recordsBuilder.add(rect.buffer.asUint8List());

    // Channel count (2 bytes)
    final chanCount = ByteData(2);
    chanCount.setUint16(0, 3);
    recordsBuilder.add(chanCount.buffer.asUint8List());

    // Channel info (3 channels * (version == 2 ? 10 : 6))
    final chanInfo = ByteData(3 * (version == 2 ? 10 : 6));
    recordsBuilder.add(chanInfo.buffer.asUint8List());

    // Blend mode sig (4), key (4), opacity (1), clipping (1), flags (1), filler (1)
    recordsBuilder.add([0x38, 0x42, 0x49, 0x4D]); // '8BIM'
    recordsBuilder.add([0x6E, 0x6F, 0x72, 0x6D]); // 'norm'
    recordsBuilder.add([l.opacity]);
    recordsBuilder.add([l.isClipped ? 1 : 0]); // clipping
    recordsBuilder.add([l.isVisible ? 0 : 2]); // flags (bit 1 is invisible)
    recordsBuilder.add([0]); // filler

    // Build extra data
    final extraBuilder = BytesBuilder();
    // Mask data len (4 bytes = 0)
    extraBuilder.add([0, 0, 0, 0]);
    // Blending ranges len (4 bytes = 0)
    extraBuilder.add([0, 0, 0, 0]);

    // Pascal string name
    final nameBytes = l.pascalName.codeUnits;
    extraBuilder.add([nameBytes.length]);
    extraBuilder.add(nameBytes);
    final padding = (4 - (nameBytes.length % 4)) - 1;
    if (padding > 0) {
      extraBuilder.add(List.filled(padding, 0));
    }

    // Tagged blocks
    if (l.isFolder || l.isClosingDelimiter) {
      extraBuilder.add([0x38, 0x42, 0x49, 0x4D]); // '8BIM'
      extraBuilder.add([0x6C, 0x73, 0x63, 0x74]); // 'lsct'
      final tagLen = ByteData(4);
      tagLen.setUint32(0, 4);
      extraBuilder.add(tagLen.buffer.asUint8List());
      final typeData = ByteData(4);
      typeData.setUint32(0, l.isFolder ? 1 : 3);
      extraBuilder.add(typeData.buffer.asUint8List());
    }

    if (l.unicodeName != null) {
      extraBuilder.add([0x38, 0x42, 0x49, 0x4D]); // '8BIM'
      extraBuilder.add([0x6C, 0x75, 0x6E, 0x69]); // 'luni'
      final uniChars = l.unicodeName!.codeUnits;
      final luniLen = 4 + uniChars.length * 2;
      final tagLen = ByteData(4);
      tagLen.setUint32(0, luniLen);
      extraBuilder.add(tagLen.buffer.asUint8List());

      final charCountData = ByteData(4);
      charCountData.setUint32(0, uniChars.length);
      extraBuilder.add(charCountData.buffer.asUint8List());

      final charBytes = ByteData(uniChars.length * 2);
      for (var c = 0; c < uniChars.length; c++) {
        charBytes.setUint16(c * 2, uniChars[c]);
      }
      extraBuilder.add(charBytes.buffer.asUint8List());
      if (luniLen % 2 != 0) {
        extraBuilder.add([0]); // pad to even
      }
    }

    final extraBytes = extraBuilder.toBytes();
    final extraLenData = ByteData(4);
    extraLenData.setUint32(0, extraBytes.length);
    recordsBuilder.add(extraLenData.buffer.asUint8List());
    recordsBuilder.add(extraBytes);
  }

  final recordsBytes = recordsBuilder.toBytes();

  // 4. Section 4:
  final layerInfoLen = recordsBytes.length;
  if (version == 2) {
    final sec4Meta = ByteData(16);
    sec4Meta.setUint64(0, 8 + layerInfoLen); // Section 4 length
    sec4Meta.setUint64(8, layerInfoLen); // Layer Info length
    bb.add(sec4Meta.buffer.asUint8List());
  } else {
    final sec4Meta = ByteData(8);
    sec4Meta.setUint32(0, 4 + layerInfoLen); // Section 4 length
    sec4Meta.setUint32(4, layerInfoLen); // Layer Info length
    bb.add(sec4Meta.buffer.asUint8List());
  }
  bb.add(recordsBytes);

  return bb.toBytes();
}

void main() {
  group('PsdService Tests', () {
    test(
        'PsdService.isPsd detects .psd extension accurately and case-insensitively',
        () {
      expect(PsdService.isPsd('photo.psd'), isTrue);
      expect(PsdService.isPsd('/storage/emulated/0/DCIM/artwork.PSD'), isTrue);
      expect(PsdService.isPsd('C:\\Users\\art\\banner.Psd'), isTrue);
      expect(PsdService.isPsd('.psd'), isTrue);
      expect(PsdService.isPsd('psd'), isTrue);
      expect(PsdService.isPsd('.PSD'), isTrue);

      expect(PsdService.isPsd('photo.jpg'), isFalse);
      expect(PsdService.isPsd('photo.png'), isFalse);
      expect(PsdService.isPsd('video.mp4'), isFalse);
      expect(PsdService.isPsd(''), isFalse);
    });

    test('LicenseService registers image Apache 2.0 license', () async {
      LicenseService.registerLicenses();
      final licenses = await LicenseRegistry.licenses.toList();
      final allPackages = licenses.expand((e) => e.packages).toSet();
      expect(allPackages.contains('image'), isTrue);
      expect(allPackages.contains('phantek_gallery'), isTrue);
      expect(allPackages.contains('androidx.media3 (ExoPlayer)'), isTrue);
    });

    test('PsdService gracefully handles non-existent or invalid files',
        () async {
      final embedded = await PsdService.instance
          .extractEmbeddedThumbnail('non_existent_file.psd');
      expect(embedded, isNull);

      final thumb =
          await PsdService.instance.decodeThumbnail('non_existent_file.psd');
      expect(thumb, isNull);

      final layers =
          await PsdService.instance.getLayers('non_existent_file.psd');
      expect(layers, isEmpty);

      final rendered = await PsdService.instance.renderWithLayers(
        'non_existent_file.psd',
        hiddenLayerIndices: {},
      );
      expect(rendered, isNull);
    });

    test('PsdLayerInfo copyWith and properties', () {
      const info = PsdLayerInfo(
        index: 0,
        name: 'Background',
        isVisible: true,
        opacity: 255,
        isFolder: false,
      );

      expect(info.index, 0);
      expect(info.name, 'Background');
      expect(info.isVisible, isTrue);
      expect(info.opacity, 255);
      expect(info.isFolder, isFalse);

      final updated = info.copyWith(isVisible: false, opacity: 128);
      expect(updated.isVisible, isFalse);
      expect(updated.opacity, 128);
      expect(updated.name, 'Background');
    });

    test('PsdService streaming and getLayers accurately detects layers, folders, and unicode names', () async {
      final tempDir = await Directory.systemTemp.createTemp('psd_test_');
      final psdFile = File('${tempDir.path}/test_multi.psd');

      final syntheticLayers = [
        const _SyntheticLayer(
          pascalName: 'Background',
          isVisible: true,
          opacity: 255,
        ),
        const _SyntheticLayer(
          pascalName: 'Group 1',
          isFolder: true,
          isVisible: true,
          opacity: 255,
        ),
        const _SyntheticLayer(
          pascalName: 'Layer 2',
          unicodeName: 'Design 🎨 ✨',
          isVisible: false,
          opacity: 180,
        ),
        const _SyntheticLayer(
          pascalName: '</Layer group>',
          isClosingDelimiter: true,
        ),
      ];

      await psdFile.writeAsBytes(_createSyntheticPsd(layers: syntheticLayers));

      // Test streamLayerRecords
      final streamed = await PsdService.instance.streamLayerRecords(psdFile.path);
      expect(streamed.length, 3); // closing delimiter excluded!

      expect(streamed[0].index, 0);
      expect(streamed[0].name, 'Background');
      expect(streamed[0].isVisible, isTrue);
      expect(streamed[0].opacity, 255);
      expect(streamed[0].isFolder, isFalse);

      expect(streamed[1].index, 1);
      expect(streamed[1].name, 'Group 1');
      expect(streamed[1].isVisible, isTrue);
      expect(streamed[1].isFolder, isTrue);

      expect(streamed[2].index, 2);
      expect(streamed[2].name, 'Design 🎨 ✨');
      expect(streamed[2].isVisible, isFalse);
      expect(streamed[2].opacity, 180);
      expect(streamed[2].isFolder, isFalse);

      // Test getLayers returns the streamed layers
      final layers = await PsdService.instance.getLayers(psdFile.path);
      expect(layers.length, 3);
      expect(layers[2].name, 'Design 🎨 ✨');

      await tempDir.delete(recursive: true);
    });

    test('PsdService streaming correctly parses PSB (version 2) format', () async {
      final tempDir = await Directory.systemTemp.createTemp('psb_test_');
      final psbFile = File('${tempDir.path}/test_large.psb');

      final syntheticLayers = [
        const _SyntheticLayer(
          pascalName: 'PSB Base Layer',
          isVisible: true,
          opacity: 255,
        ),
        const _SyntheticLayer(
          pascalName: 'Artwork',
          unicodeName: 'PSB Unicode Layer',
          isVisible: true,
          opacity: 200,
        ),
      ];

      await psbFile.writeAsBytes(_createSyntheticPsd(version: 2, layers: syntheticLayers));

      final layers = await PsdService.instance.getLayers(psbFile.path);
      expect(layers.length, 2);
      expect(layers[0].name, 'PSB Base Layer');
      expect(layers[1].name, 'PSB Unicode Layer');
      expect(layers[1].opacity, 200);

      await tempDir.delete(recursive: true);
    });

    test('PsdService streaming accurately calculates depth, parentIndex, and clipping mask', () async {
      final tempDir = await Directory.systemTemp.createTemp('psd_hier_test_');
      final psdFile = File('${tempDir.path}/hierarchy.psd');

      final syntheticLayers = [
        const _SyntheticLayer(pascalName: 'Base', isVisible: true),
        const _SyntheticLayer(pascalName: 'Group A', isFolder: true),
        const _SyntheticLayer(pascalName: 'Child 1', isVisible: true),
        const _SyntheticLayer(pascalName: 'Child 2 Clipped', isClipped: true),
        const _SyntheticLayer(pascalName: '</Layer group>', isClosingDelimiter: true),
      ];

      await psdFile.writeAsBytes(_createSyntheticPsd(layers: syntheticLayers));

      final layers = await PsdService.instance.streamLayerRecords(psdFile.path);
      expect(layers.length, 4);

      // Forward ordering (header at index 1, delimiter at index 4):
      expect(layers[0].name, 'Base');
      expect(layers[0].depth, 0);
      expect(layers[0].parentIndex, isNull);
      expect(layers[0].isClipped, isFalse);

      expect(layers[1].name, 'Group A');
      expect(layers[1].depth, 0);
      expect(layers[1].parentIndex, isNull);
      expect(layers[1].isFolder, isTrue);

      expect(layers[2].name, 'Child 1');
      expect(layers[2].depth, 1);
      expect(layers[2].parentIndex, 1);
      expect(layers[2].isClipped, isFalse);

      expect(layers[3].name, 'Child 2 Clipped');
      expect(layers[3].depth, 1);
      expect(layers[3].parentIndex, 1);
      expect(layers[3].isClipped, isTrue);

      await tempDir.delete(recursive: true);
    });

    test('getLayerThumbnails extracts per-layer PNG thumbnails with correct dimensions', () async {
      final tempDir = await Directory.systemTemp.createTemp('psd_thumb_test_');
      final psdFile = File('${tempDir.path}/renderable.psd');

      final psdBytes = _createRenderableSyntheticPsd(
        width: 10,
        height: 10,
        layerColors: [
          img.ColorRgba8(255, 0, 0, 255),
          img.ColorRgba8(0, 255, 0, 255),
        ],
      );
      await psdFile.writeAsBytes(psdBytes);

      final thumbs = await PsdService.instance.getLayerThumbnails(psdFile.path, maxThumbDim: 48);
      expect(thumbs.length, 2);
      expect(thumbs.containsKey(0), isTrue);
      expect(thumbs.containsKey(1), isTrue);

      final png0 = img.decodePng(thumbs[0]!);
      expect(png0, isNotNull);
      expect(png0!.width, lessThanOrEqualTo(48));
      expect(png0.height, lessThanOrEqualTo(48));

      await tempDir.delete(recursive: true);
    });

    test('PackBits decompression decodes literal runs and repeat runs accurately', () {
      final src = Uint8List.fromList([2, 1, 2, 3, 0xFE, 9, 0x80]);
      final decoded = decodePackBits(src, 0, src.length, 6);
      expect(decoded, equals(Uint8List.fromList([1, 2, 3, 9, 9, 9])));
    });

    test('Channel decompression handles raw, PackBits, ZIP, and ZIP delta differencing', () {
      // 1. Raw
      final rawData = Uint8List.fromList([0, 0, 10, 20, 30, 40]);
      final decRaw = decompressChannelData(rawData, 2, 2);
      expect(decRaw, equals(Uint8List.fromList([10, 20, 30, 40])));

      // 2. PackBits
      final rleData = Uint8List.fromList([
        0, 1, // comp 1
        0, 2, // scanline 0 len = 2
        0, 2, // scanline 1 len = 2
        0xFF, 5, // scanline 0 repeat 2x of 5
        0xFF, 7, // scanline 1 repeat 2x of 7
      ]);
      final decRle = decompressChannelData(rleData, 2, 2);
      expect(decRle, equals(Uint8List.fromList([5, 5, 7, 7])));

      // 3. ZIP
      final uncompressed = Uint8List.fromList([1, 2, 3, 4]);
      final zipped = zlib.encode(uncompressed);
      final zipData = Uint8List.fromList([0, 2, ...zipped]);
      final decZip = decompressChannelData(zipData, 2, 2);
      expect(decZip, equals(uncompressed));

      // 4. ZIP Delta differencing: rows [10, 25], [100, 120] -> deltas [10, 15], [100, 20]
      final deltaData = Uint8List.fromList([10, 15, 100, 20]);
      final zipDelta = zlib.encode(deltaData);
      final zipDeltaData = Uint8List.fromList([0, 3, ...zipDelta]);
      final decDelta = decompressChannelData(zipDeltaData, 2, 2);
      expect(decDelta, equals(Uint8List.fromList([10, 25, 100, 120])));
    });

    test('compositeLayer blends with opacity and handles clipping bounds', () {
      final dst = img.Image(width: 4, height: 4, numChannels: 4);
      img.fill(dst, color: img.ColorRgba8(255, 255, 255, 255));

      final src = img.Image(width: 2, height: 2, numChannels: 4);
      img.fill(src, color: img.ColorRgba8(0, 0, 0, 255));

      compositeLayer(dst, src, 1, 1, 255);
      final p11 = dst.getPixel(1, 1);
      expect(p11.r.toInt(), 0);
      expect(p11.g.toInt(), 0);
      expect(p11.b.toInt(), 0);

      final p00 = dst.getPixel(0, 0);
      expect(p00.r.toInt(), 255);
    });

    test('renderWithLayers excludes hidden layers and reflects layer toggling in output image', () async {
      final tempDir = await Directory.systemTemp.createTemp('psd_render_test_');
      final psdFile = File('${tempDir.path}/two_layers.psd');

      // Layer 0: Solid Red (255, 0, 0)
      // Layer 1: Solid Blue (0, 0, 255)
      final psdBytes = _createRenderableSyntheticPsd(
        width: 10,
        height: 10,
        layerColors: [
          img.ColorRgba8(255, 0, 0, 255),
          img.ColorRgba8(0, 0, 255, 255),
        ],
      );
      await psdFile.writeAsBytes(psdBytes);

      // Render 1: Hidden layer 1 -> Only Layer 0 (Red) is visible!
      final renderedHidden1 = await PsdService.instance.renderWithLayers(
        psdFile.path,
        hiddenLayerIndices: {1},
      );
      expect(renderedHidden1, isNotNull);
      final imgHidden1 = img.decodeJpg(renderedHidden1!)!;
      final pRed = imgHidden1.getPixel(5, 5);
      expect(pRed.r.toInt(), greaterThan(200));
      expect(pRed.b.toInt(), lessThan(50));

      // Render 2: All layers visible -> Layer 1 (Blue) covers Layer 0 (Red)!
      final renderedAll = await PsdService.instance.renderWithLayers(
        psdFile.path,
        hiddenLayerIndices: {999},
      );
      expect(renderedAll, isNotNull);
      final imgAll = img.decodeJpg(renderedAll!)!;
      final pBlue = imgAll.getPixel(5, 5);
      expect(pBlue.b.toInt(), greaterThan(200));
      expect(pBlue.r.toInt(), lessThan(50));

      // Output bytes must be different
      expect(renderedHidden1, isNot(equals(renderedAll)));

      await tempDir.delete(recursive: true);
    });
  });
}

Uint8List _createRenderableSyntheticPsd({
  int width = 10,
  int height = 10,
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

  final channelLen = 2 + width * height; // 2 bytes comp + uncompressed raw pixels

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

    // 3 channels (id 0 = R, 1 = G, 2 = B)
    final chanInfo = ByteData(3 * 6);
    for (var c = 0; c < 3; c++) {
      chanInfo.setInt16(c * 6, c);
      chanInfo.setUint32(c * 6 + 2, channelLen);
    }
    recordsBuilder.add(chanInfo.buffer.asUint8List());

    // Blend norm, opacity 255, visible (flags = 0)
    recordsBuilder.add([0x38, 0x42, 0x49, 0x4D]); // '8BIM'
    recordsBuilder.add([0x6E, 0x6F, 0x72, 0x6D]); // 'norm'
    recordsBuilder.add([255, 0, 0, 0]);

    // Extra data length = 0
    recordsBuilder.add([0, 0, 0, 0]);
  }

  // Channel image data
  final channelDataBuilder = BytesBuilder();
  for (final color in layerColors) {
    // Channel 0: R
    channelDataBuilder.add([0, 0]); // comp 0
    channelDataBuilder.add(List.filled(width * height, color.r.toInt()));

    // Channel 1: G
    channelDataBuilder.add([0, 0]); // comp 0
    channelDataBuilder.add(List.filled(width * height, color.g.toInt()));

    // Channel 2: B
    channelDataBuilder.add([0, 0]); // comp 0
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
