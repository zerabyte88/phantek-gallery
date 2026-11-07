import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phantek_gallery/core/services/license_service.dart';
import 'package:phantek_gallery/core/services/psd_service.dart';

class _SyntheticLayer {
  final String pascalName;
  final String? unicodeName;
  final bool isVisible;
  final int opacity;
  final bool isFolder;
  final bool isClosingDelimiter;

  const _SyntheticLayer({
    required this.pascalName,
    this.unicodeName,
    this.isVisible = true,
    this.opacity = 255,
    this.isFolder = false,
    this.isClosingDelimiter = false,
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
    recordsBuilder.add([0]); // clipping
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
  });
}
