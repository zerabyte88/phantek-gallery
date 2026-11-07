import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:phantek_gallery/core/services/psd_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PSD Real-world Structure Tests', () {
    test('RLE compressed layers with folders and extra data', () async {
      final tempDir = await Directory.systemTemp.createTemp('psd_real_');
      final psdFile = File('${tempDir.path}/test_real.psd');

      // Create a PSD that closely mimics Adobe Photoshop CS6/CC output:
      // Doc size: 30x30
      // Layer 0: Background (white, 30x30, RLE compressed)
      // Layer 1: Red Rect (10x10 at 5,5, RLE compressed)
      // Layer 2: Folder 'Group 1' (0x0, empty channels)
      // Layer 3: Blue Rect inside folder (10x10 at 15,15, RLE compressed)
      // Layer 4: Folder closing delimiter '</Layer group>' (0x0, empty channels)
      final bytes = _createPhotoshopLikePsd();
      await psdFile.writeAsBytes(bytes);

      final layers = await PsdService.instance.getLayers(psdFile.path);
      expect(layers.length, 4); // background, red, group 1, blue (delimiter filtered)

      final thumbs = await PsdService.instance.getLayerThumbnails(psdFile.path);
      expect(thumbs.containsKey(0), isTrue);
      expect(thumbs.containsKey(1), isTrue);
      expect(thumbs.containsKey(3), isTrue);

      final rendered = await PsdService.instance.renderWithLayers(
        psdFile.path,
        hiddenLayerIndices: {1},
      );
      expect(rendered, isNotNull);

      await tempDir.delete(recursive: true);
    });

    test('CMYK PSD renders and extracts layer thumbnails', () async {
      final tempDir = await Directory.systemTemp.createTemp('psd_cmyk_');
      final psdFile = File('${tempDir.path}/test_cmyk.psd');

      final bytes = _createCmykPsd();
      await psdFile.writeAsBytes(bytes);

      final thumbs = await PsdService.instance.getLayerThumbnails(psdFile.path);
      expect(thumbs.containsKey(0), isTrue);

      final rendered = await PsdService.instance.renderWithLayers(
        psdFile.path,
        hiddenLayerIndices: {},
      );
      expect(rendered, isNotNull);

      await tempDir.delete(recursive: true);
    });

    test('16-bit depth PackBits decompression decodes accurately', () {
      final rawData = Uint8List.fromList([
        0, 1, // comp = 1 (RLE)
        0, 3, // row 0 byte count = 3
        0x01, 0x12, 0x34, // literal 2 bytes: 0x12, 0x34
      ]);
      final decoded = decompressChannelData(rawData, 1, 1, depth: 16);
      expect(decoded, isNotNull);
      expect(decoded!.length, 2);
      expect(decoded[0], 0x12);
      expect(decoded[1], 0x34);
    });
  });
}

Uint8List _createCmykPsd() {
  final bb = BytesBuilder();
  bb.add([0x38, 0x42, 0x50, 0x53]); // '8BPS'
  final head = ByteData(22);
  head.setUint16(0, 1);
  head.setUint16(8, 4); // 4 channels (CMYK)
  head.setUint32(10, 10);
  head.setUint32(14, 10);
  head.setUint16(18, 8); // 8-bit
  head.setUint16(20, 4); // CMYK color mode
  bb.add(head.buffer.asUint8List());

  bb.add([0, 0, 0, 0]); // color mode
  bb.add([0, 0, 0, 0]); // image res

  // Layer 0: Solid Cyan (C=255, M=0, Y=0, K=0)
  final recordsBuilder = BytesBuilder();
  final countData = ByteData(2);
  countData.setInt16(0, 1);
  recordsBuilder.add(countData.buffer.asUint8List());

  final rect = ByteData(16);
  rect.setInt32(0, 0);
  rect.setInt32(4, 0);
  rect.setInt32(8, 10);
  rect.setInt32(12, 10);
  recordsBuilder.add(rect.buffer.asUint8List());

  final chanCount = ByteData(2);
  chanCount.setUint16(0, 4); // C, M, Y, K
  recordsBuilder.add(chanCount.buffer.asUint8List());

  final chanInfo = ByteData(4 * 6);
  for (var c = 0; c < 4; c++) {
    chanInfo.setInt16(c * 6, c);
    chanInfo.setUint32(c * 6 + 2, 2 + 100); // 2 bytes comp + 100 raw bytes
  }
  recordsBuilder.add(chanInfo.buffer.asUint8List());

  recordsBuilder.add([0x38, 0x42, 0x49, 0x4D, 0x6E, 0x6F, 0x72, 0x6D, 255, 0, 0, 0]);
  recordsBuilder.add([0, 0, 0, 0]); // extra len = 0

  final channelDataBuilder = BytesBuilder();
  // Cyan: 255
  channelDataBuilder.add([0, 0]);
  channelDataBuilder.add(List.filled(100, 255));
  // Magenta: 0
  channelDataBuilder.add([0, 0]);
  channelDataBuilder.add(List.filled(100, 0));
  // Yellow: 0
  channelDataBuilder.add([0, 0]);
  channelDataBuilder.add(List.filled(100, 0));
  // Black: 0
  channelDataBuilder.add([0, 0]);
  channelDataBuilder.add(List.filled(100, 0));

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

Uint8List _encodePackBitsScanline(List<int> bytes) {
  // PackBits RLE encoding for a single scanline
  final out = BytesBuilder();
  var i = 0;
  while (i < bytes.length) {
    var runLen = 1;
    while (i + runLen < bytes.length && bytes[i + runLen] == bytes[i] && runLen < 128) {
      runLen++;
    }
    if (runLen > 1) {
      out.addByte(1 - runLen + 256); // -(runLen - 1) as byte
      out.addByte(bytes[i]);
      i += runLen;
    } else {
      var litLen = 1;
      while (i + litLen < bytes.length &&
          litLen < 128 &&
          (i + litLen + 1 >= bytes.length || bytes[i + litLen] != bytes[i + litLen + 1])) {
        litLen++;
      }
      out.addByte(litLen - 1);
      for (var j = 0; j < litLen; j++) {
        out.addByte(bytes[i + j]);
      }
      i += litLen;
    }
  }
  return out.toBytes();
}

Uint8List _createPhotoshopLikePsd() {
  final bb = BytesBuilder();

  final docW = 30;
  final docH = 30;

  // 1. Header (26 bytes)
  bb.add([0x38, 0x42, 0x50, 0x53]); // '8BPS'
  final head = ByteData(22);
  head.setUint16(0, 1); // version 1
  head.setUint16(8, 3); // channels = 3
  head.setUint32(10, docH);
  head.setUint32(14, docW);
  head.setUint16(18, 8); // 8-bit
  head.setUint16(20, 3); // RGB
  bb.add(head.buffer.asUint8List());

  // 2. Color mode data
  bb.add([0, 0, 0, 0]);

  // 3. Image resources
  bb.add([0, 0, 0, 0]);

  // 4. Section 4:
  // Layers:
  // Layer 0: Background (0, 0, 30, 30) White
  // Layer 1: RedBox (5, 5, 15, 15)
  // Layer 2: Closing delimiter (0,0,0,0)
  // Layer 3: BlueBox (15, 15, 25, 25)
  // Layer 4: Group 1 (0,0,0,0)
  // Note: in standard Photoshop, Group 1 header is at a HIGHER index than closing delimiter!
  final layerSpecs = [
    _LayerSpec(0, 0, 0, 30, 30, 'Background', img.ColorRgba8(255, 255, 255, 255), isFolder: false),
    _LayerSpec(1, 5, 5, 15, 15, 'Red Box', img.ColorRgba8(255, 0, 0, 255), isFolder: false),
    _LayerSpec(2, 0, 0, 0, 0, '</Layer group>', img.ColorRgba8(0, 0, 0, 0), isClosing: true),
    _LayerSpec(3, 15, 15, 25, 25, 'Blue Box', img.ColorRgba8(0, 0, 255, 255), isFolder: false),
    _LayerSpec(4, 0, 0, 0, 0, 'Group 1', img.ColorRgba8(0, 0, 0, 0), isFolder: true),
  ];

  final recordsBuilder = BytesBuilder();
  final countData = ByteData(2);
  countData.setInt16(0, layerSpecs.length);
  recordsBuilder.add(countData.buffer.asUint8List());

  final channelDataList = <Uint8List>[];

  for (final spec in layerSpecs) {
    final w = spec.right - spec.left;
    final h = spec.bottom - spec.top;

    // Build channel data first so we know lengths
    final chanLens = <int>[];
    if (w <= 0 || h <= 0) {
      // Empty / folder layer: 4 channels each 2 bytes (compression 0)
      for (var c = 0; c < 4; c++) {
        chanLens.add(2);
        channelDataList.add(Uint8List.fromList([0, 0]));
      }
    } else {
      // 4 channels: R, G, B, A (IDs: 0, 1, 2, -1)
      final chanColors = [spec.color.r.toInt(), spec.color.g.toInt(), spec.color.b.toInt(), spec.color.a.toInt()];
      for (final val in chanColors) {
        final scanlines = <Uint8List>[];
        for (var row = 0; row < h; row++) {
          final rowBytes = List.filled(w, val);
          scanlines.add(_encodePackBitsScanline(rowBytes));
        }
        final scanlineTable = ByteData(h * 2);
        for (var row = 0; row < h; row++) {
          scanlineTable.setUint16(row * 2, scanlines[row].length);
        }
        final chBuilder = BytesBuilder();
        chBuilder.add([0, 1]); // compression = 1 (RLE)
        chBuilder.add(scanlineTable.buffer.asUint8List());
        for (final sl in scanlines) {
          chBuilder.add(sl);
        }
        final chBytes = chBuilder.toBytes();
        chanLens.add(chBytes.length);
        channelDataList.add(chBytes);
      }
    }

    // Write layer record
    final rect = ByteData(16);
    rect.setInt32(0, spec.top);
    rect.setInt32(4, spec.left);
    rect.setInt32(8, spec.bottom);
    rect.setInt32(12, spec.right);
    recordsBuilder.add(rect.buffer.asUint8List());

    final chanCount = ByteData(2);
    chanCount.setUint16(0, 4);
    recordsBuilder.add(chanCount.buffer.asUint8List());

    final chanInfo = ByteData(4 * 6);
    final chanIds = [0, 1, 2, -1];
    for (var c = 0; c < 4; c++) {
      chanInfo.setInt16(c * 6, chanIds[c]);
      chanInfo.setUint32(c * 6 + 2, chanLens[c]);
    }
    recordsBuilder.add(chanInfo.buffer.asUint8List());

    // '8BIM', 'norm', opacity 255, clipping 0, flags 0, filler 0
    recordsBuilder.add([0x38, 0x42, 0x49, 0x4D]);
    recordsBuilder.add([0x6E, 0x6F, 0x72, 0x6D]);
    recordsBuilder.add([255, 0, 0, 0]);

    // Extra data: mask len, blend len, name, tagged blocks
    final extraBuilder = BytesBuilder();
    extraBuilder.add([0, 0, 0, 0]); // mask len = 0
    extraBuilder.add([0, 0, 0, 0]); // blend len = 0

    final nameBytes = spec.name.codeUnits;
    final nameLen = nameBytes.length;
    extraBuilder.addByte(nameLen);
    extraBuilder.add(nameBytes);
    final pad = (4 - (nameLen % 4)) - 1;
    if (pad > 0) extraBuilder.add(List.filled(pad, 0));

    // Tagged block: lsct for folder / closing delimiter
    if (spec.isFolder || spec.isClosing) {
      extraBuilder.add([0x38, 0x42, 0x49, 0x4D]); // '8BIM'
      extraBuilder.add([0x6C, 0x73, 0x63, 0x74]); // 'lsct'
      final tagLen = ByteData(4);
      tagLen.setUint32(0, 4);
      extraBuilder.add(tagLen.buffer.asUint8List());
      final typeData = ByteData(4);
      typeData.setUint32(0, spec.isFolder ? 1 : 3);
      extraBuilder.add(typeData.buffer.asUint8List());
    }

    final extraBytes = extraBuilder.toBytes();
    final extraLenData = ByteData(4);
    extraLenData.setUint32(0, extraBytes.length);
    recordsBuilder.add(extraLenData.buffer.asUint8List());
    recordsBuilder.add(extraBytes);
  }

  final channelDataBuilder = BytesBuilder();
  for (final ch in channelDataList) {
    channelDataBuilder.add(ch);
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

class _LayerSpec {
  final int index;
  final int top;
  final int left;
  final int bottom;
  final int right;
  final String name;
  final img.ColorRgba8 color;
  final bool isFolder;
  final bool isClosing;

  _LayerSpec(this.index, this.top, this.left, this.bottom, this.right, this.name, this.color,
      {this.isFolder = false, this.isClosing = false});
}
