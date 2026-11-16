// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'settings_service.dart';
import 'thumbnail_service.dart';

/// Representation of an individual Adobe Photoshop (.psd) layer.
class PsdLayerInfo {
  final int index;
  final String name;
  final bool isVisible;
  final int opacity; // 0 - 255
  final bool isFolder;
  final bool isClipped;
  final int depth;
  final int? parentIndex;

  const PsdLayerInfo({
    required this.index,
    required this.name,
    required this.isVisible,
    required this.opacity,
    required this.isFolder,
    this.isClipped = false,
    this.depth = 0,
    this.parentIndex,
  });

  PsdLayerInfo copyWith({
    int? index,
    String? name,
    bool? isVisible,
    int? opacity,
    bool? isFolder,
    bool? isClipped,
    int? depth,
    int? parentIndex,
  }) {
    return PsdLayerInfo(
      index: index ?? this.index,
      name: name ?? this.name,
      isVisible: isVisible ?? this.isVisible,
      opacity: opacity ?? this.opacity,
      isFolder: isFolder ?? this.isFolder,
      isClipped: isClipped ?? this.isClipped,
      depth: depth ?? this.depth,
      parentIndex: parentIndex ?? this.parentIndex,
    );
  }

  @override
  String toString() =>
      'PsdLayerInfo(index: $index, name: $name, isVisible: $isVisible, opacity: $opacity, isFolder: $isFolder, isClipped: $isClipped, depth: $depth, parentIndex: $parentIndex)';
}

class _AsyncGate {
  final int maxConcurrent;
  int _active = 0;
  final Queue<Completer<void>> _waiters = Queue();

  _AsyncGate([this.maxConcurrent = 1]);

  Future<T> run<T>(Future<T> Function() action) async {
    while (_active >= maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
}

/// Service for decoding, inspecting layers, and rendering Adobe Photoshop (.psd) files.
class _RawLayerRecord {
  final int index;
  final String name;
  final bool isVisible;
  final int opacity;
  final bool isFolder;
  final bool isClosingDelimiter;
  final bool isClipped;

  const _RawLayerRecord({
    required this.index,
    required this.name,
    required this.isVisible,
    required this.opacity,
    required this.isFolder,
    required this.isClosingDelimiter,
    required this.isClipped,
  });
}

class PsdService {
  PsdService._();
  static final PsdService instance = PsdService._();
  static const int _maxMemoryRenderedPreviews = 20;
  final _AsyncGate _renderGate = _AsyncGate(1);
  final _AsyncGate _thumbGate = _AsyncGate(1);
  final Map<String, Uint8List> _renderedPreviewCache = {};
  final Map<String, ({int size, int mtimeMs, List<PsdLayerInfo> layers})>
      _layersMemoryCache = {};
  final Map<String, Future<Uint8List?>> _renderInFlight = {};

  /// Returns true if [pathOrExt] has a .psd extension (case-insensitive).
  static bool isPsd(String pathOrExt) {
    if (pathOrExt.trim().isEmpty) return false;
    final ext = p.extension(pathOrExt).isNotEmpty
        ? p.extension(pathOrExt).toLowerCase()
        : (pathOrExt.startsWith('.')
            ? pathOrExt.toLowerCase()
            : '.$pathOrExt'.toLowerCase());
    return ext == '.psd';
  }

  /// Extracts the embedded JPEG thumbnail (resource 0x040C or 0x0409) if present.
  Future<Uint8List?> extractEmbeddedThumbnail(String filePath) async {
    RandomAccessFile? raf;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      raf = await file.open(mode: FileMode.read);
      final fileLen = await raf.length();
      if (fileLen < 34) return null;

      // 1. Read 26-byte header, verify signature 0x38425053 ('8BPS')
      final header = await raf.read(26);
      if (header.length < 26) return null;
      if (header[0] != 0x38 ||
          header[1] != 0x42 ||
          header[2] != 0x50 ||
          header[3] != 0x53) {
        return null;
      }

      // 2. Read 4-byte Color Mode Data length, seek past it
      final colorDataLenBytes = await raf.read(4);
      if (colorDataLenBytes.length < 4) return null;
      final colorDataLen = ByteData.sublistView(colorDataLenBytes).getUint32(0);

      final resourcesSectionStart = 26 + 4 + colorDataLen;
      if (resourcesSectionStart + 4 > fileLen) return null;
      await raf.setPosition(resourcesSectionStart);

      // 3. Read 4-byte Image Resources length
      final resLenBytes = await raf.read(4);
      if (resLenBytes.length < 4) return null;
      final resLen = ByteData.sublistView(resLenBytes).getUint32(0);

      final resourcesSectionEnd =
          (resourcesSectionStart + 4 + resLen).clamp(0, fileLen);

      // 4. Iterate resource blocks while within resource length
      while ((await raf.position()) + 10 <= resourcesSectionEnd) {
        final blockHead = await raf.read(6);
        if (blockHead.length < 6) break;

        // 4 bytes signature: 0x3842494d ('8BIM')
        final sig = ByteData.sublistView(blockHead).getUint32(0);
        if (sig != 0x3842494d) break;

        // 2 bytes resource ID
        final resourceId = ByteData.sublistView(blockHead).getUint16(4);

        // Pascal string: 1 byte length + ASCII chars, padded to even length
        final nameLenByte = await raf.read(1);
        if (nameLenByte.isEmpty) break;
        final nameLen = nameLenByte[0];
        final nameSkip = nameLen + ((nameLen % 2 == 0) ? 1 : 0);
        await raf.setPosition(await raf.position() + nameSkip);

        // 4 bytes data size
        final sizeBytes = await raf.read(4);
        if (sizeBytes.length < 4) break;
        final dataSize = ByteData.sublistView(sizeBytes).getUint32(0);
        if (dataSize <= 0 || (await raf.position()) + dataSize > fileLen) break;

        // If ID is 0x040C (Photoshop 5.0) or 0x0409 (Photoshop 4.0)
        if (resourceId == 0x040C || resourceId == 0x0409) {
          if (dataSize >= 28) {
            final thumbHead = await raf.read(28);
            if (thumbHead.length == 28) {
              final format = ByteData.sublistView(thumbHead).getUint32(0);
              if (format == 1) {
                final jpegSize = dataSize - 28;
                if (jpegSize > 0) {
                  final jpegBytes = await raf.read(jpegSize);
                  if (jpegBytes.length == jpegSize &&
                      jpegBytes.length >= 4 &&
                      jpegBytes[0] == 0xFF &&
                      jpegBytes[1] == 0xD8) {
                    return jpegBytes;
                  }
                }
              }
            }
          }
          break;
        } else {
          final paddedSize = dataSize + (dataSize % 2);
          await raf.setPosition(await raf.position() + paddedSize);
        }
      }
      return null;
    } catch (_) {
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// Streams Section 5 (Image Data Section) containing the pre-rendered, flattened composite
  /// image directly from disk using [RandomAccessFile], completely bypassing Section 4's
  /// multi-layer memory allocation.
  ///
  /// Safely avoids OutOfMemoryError on large PSD files (300-400MB) by only reading
  /// Section 5 into memory (typically 5MB - 25MB instead of ~400MB+ in RAM).
  Future<Uint8List?> extractMergedComposite(
    String filePath, {
    int maxDimension = 2048,
  }) async {
    RandomAccessFile? raf;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      raf = await file.open(mode: FileMode.read);
      final fileLen = await raf.length();
      if (fileLen < 34) return null;

      // 1. Read 26-byte header: verify signature 0x38425053 ('8BPS')
      final header = await raf.read(26);
      if (header.length < 26) return null;
      if (header[0] != 0x38 ||
          header[1] != 0x42 ||
          header[2] != 0x50 ||
          header[3] != 0x53) {
        return null;
      }

      final headerView = ByteData.sublistView(header);
      final version = headerView.getUint16(4);
      if (version != 1 && version != 2) return null;

      final channels = headerView.getUint16(12);
      final height = headerView.getUint32(14);
      final width = headerView.getUint32(18);
      if (channels < 1 || height < 1 || width < 1) return null;

      // 2. Read 4-byte Color Mode Data length (L1), seek past it
      final colorDataLenBytes = await raf.read(4);
      if (colorDataLenBytes.length < 4) return null;
      final colorDataLen = ByteData.sublistView(colorDataLenBytes).getUint32(0);

      Uint8List colorData = Uint8List(0);
      if (colorDataLen > 0) {
        if (colorDataLen <= 65536 &&
            (await raf.position()) + colorDataLen <= fileLen) {
          colorData = await raf.read(colorDataLen);
        } else {
          final targetPos = await raf.position() + colorDataLen;
          if (targetPos > fileLen) return null;
          await raf.setPosition(targetPos);
        }
      }

      // 3. Read 4-byte Image Resources length (L2), seek past it
      if ((await raf.position()) + 4 > fileLen) return null;
      final resLenBytes = await raf.read(4);
      if (resLenBytes.length < 4) return null;
      final resLen = ByteData.sublistView(resLenBytes).getUint32(0);
      final resEndPos = await raf.position() + resLen;
      if (resEndPos > fileLen) return null;
      await raf.setPosition(resEndPos);

      // 4. Read Layer and Mask Information length (L3): seek past it!
      // This skips the 380MB of layer pixel data in ~0ms without loading it into RAM!
      final int layerSectionLen;
      if (version == 2) {
        if ((await raf.position()) + 8 > fileLen) return null;
        final layerLenBytes = await raf.read(8);
        if (layerLenBytes.length < 8) return null;
        layerSectionLen = ByteData.sublistView(layerLenBytes).getUint64(0);
      } else {
        if ((await raf.position()) + 4 > fileLen) return null;
        final layerLenBytes = await raf.read(4);
        if (layerLenBytes.length < 4) return null;
        layerSectionLen = ByteData.sublistView(layerLenBytes).getUint32(0);
      }

      final section5Pos = await raf.position() + layerSectionLen;
      if (section5Pos > fileLen) return null;
      await raf.setPosition(section5Pos);

      // 5. Check if remaining bytes > 2 (Section 5: Image Data Section)
      final remainingBytes = fileLen - await raf.position();
      if (remainingBytes <= 2) return null;

      // 6. Read ONLY Section 5 bytes
      final section5Bytes = await raf.read(remainingBytes);
      if (section5Bytes.length < 2) return null;

      // 7. Construct synthesized lightweight PSD payload:
      // - 26-byte original Header
      // - Color Mode Data length & bytes (or 4 zero bytes)
      // - 4 zero bytes (Image resources len = 0)
      // - Layer & mask data block: 4 bytes len (8), 4 bytes layer len (0), 4 bytes mask len (0)
      // - Section 5 bytes
      final builder = BytesBuilder(copy: false);
      builder.add(header);

      if (colorData.isNotEmpty) {
        final cdLenBytes = Uint8List(4);
        ByteData.sublistView(cdLenBytes).setUint32(0, colorData.length);
        builder.add(cdLenBytes);
        builder.add(colorData);
      } else {
        builder.add(Uint8List(4));
      }

      builder.add(Uint8List(4)); // Resources len = 0

      if (version == 2) {
        final sec4 = Uint8List(24);
        final bd = ByteData.sublistView(sec4);
        bd.setUint64(0, 16); // section len = 16
        bd.setUint64(8, 0); // layer info len = 0
        bd.setUint64(16, 0); // mask info len = 0
        builder.add(sec4);
      } else {
        final sec4 = Uint8List(12);
        final bd = ByteData.sublistView(sec4);
        bd.setUint32(0, 8); // section len = 8
        bd.setUint32(4, 0); // layer info len = 0
        bd.setUint32(8, 0); // mask info len = 0
        builder.add(sec4);
      }

      builder.add(section5Bytes);
      final synthBytes = builder.takeBytes();

      // 8 & 9. Decode synthesized payload in worker isolate
      return await compute(
        _isolateDecodeSynthPsd,
        _DecodeSynthParams(synthBytes, maxDimension),
      );
    } catch (e) {
      debugPrint('[PsdService] extractMergedComposite error for $filePath: $e');
      return null;
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  /// Decodes a fast thumbnail of the PSD file.
  ///
  /// Uses a tiered strategy:
  /// 1st: try [extractEmbeddedThumbnail].
  /// 2nd: try [extractMergedComposite].
  /// 3rd: for smaller files (< 50MB), fallback to [_isolateDecodeThumbnail].
  ///      Files >= 50MB strictly avoid full isolate decode to prevent OutOfMemoryError.
  Future<Uint8List?> decodeThumbnail(
    String filePath, {
    int maxDimension = 512,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      // 1st: try embedded thumbnail
      final embedded = await extractEmbeddedThumbnail(filePath);
      if (embedded != null && embedded.isNotEmpty) {
        return embedded;
      }

      // 2nd: try streaming Section 5 merged composite
      final composite = await extractMergedComposite(
        filePath,
        maxDimension: maxDimension,
      );
      if (composite != null && composite.isNotEmpty) {
        return composite;
      }

      // 3rd: for smaller files (< 50MB), fallback to isolate layer decode.
      // For files >= 50MB, do NOT run _isolateDecodeThumbnail to prevent OOM.
      final fileSize = await file.length();
      if (fileSize < 50 * 1024 * 1024) {
        return await _renderGate.run(() => compute(
              _isolateDecodeThumbnail,
              _DecodeThumbnailParams(filePath, maxDimension),
            ).timeout(const Duration(seconds: 12), onTimeout: () => null));
      }

      return null;
    } catch (e) {
      debugPrint('[PsdService] decodeThumbnail error for $filePath: $e');
      return null;
    }
  }

  /// Streams layer metadata directly from Section 4 using [RandomAccessFile],
  /// reading only layer headers and extra data without loading layer pixel channels.
  ///
  /// Safe for files of any size (300MB - 1GB+) with zero OOM risk and completing in < 5ms.
  Future<List<PsdLayerInfo>> _streamLayerRecords(String filePath) async {
    RandomAccessFile? raf;
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];
      raf = await file.open(mode: FileMode.read);
      final fileLen = await raf.length();
      if (fileLen < 34) return [];

      // 1. Read 26-byte header: verify signature '8BPS'
      final header = await raf.read(26);
      if (header.length < 26) return [];
      if (header[0] != 0x38 ||
          header[1] != 0x42 ||
          header[2] != 0x50 ||
          header[3] != 0x53) {
        return [];
      }

      final headerView = ByteData.sublistView(header);
      final version = headerView.getUint16(4);
      if (version != 1 && version != 2) return [];

      // 2. Read 4-byte Color Mode Data length, seek past it
      final colorDataLenBytes = await raf.read(4);
      if (colorDataLenBytes.length < 4) return [];
      final colorDataLen = ByteData.sublistView(colorDataLenBytes).getUint32(0);
      final sec3Pos = 26 + 4 + colorDataLen;
      if (sec3Pos + 4 > fileLen) return [];
      await raf.setPosition(sec3Pos);

      // 3. Read 4-byte Image Resources length, seek past it
      final resLenBytes = await raf.read(4);
      if (resLenBytes.length < 4) return [];
      final resLen = ByteData.sublistView(resLenBytes).getUint32(0);
      final sec4Pos = sec3Pos + 4 + resLen;
      final sec4LenHeaderSize = (version == 2) ? 8 : 4;
      if (sec4Pos + sec4LenHeaderSize > fileLen) return [];
      await raf.setPosition(sec4Pos);

      // 4. Section 4: Layer and Mask Information Section
      final int section4Len;
      if (version == 2) {
        final sec4LenBytes = await raf.read(8);
        if (sec4LenBytes.length < 8) return [];
        section4Len = ByteData.sublistView(sec4LenBytes).getUint64(0);
      } else {
        final sec4LenBytes = await raf.read(4);
        if (sec4LenBytes.length < 4) return [];
        section4Len = ByteData.sublistView(sec4LenBytes).getUint32(0);
      }
      if (section4Len <= 0) return [];

      final sec4End = (await raf.position()) + section4Len;
      if (sec4End > fileLen) return [];

      // Layer Info length
      final int layerInfoLen;
      if (version == 2) {
        if ((await raf.position()) + 8 > sec4End) return [];
        final layerLenBytes = await raf.read(8);
        if (layerLenBytes.length < 8) return [];
        layerInfoLen = ByteData.sublistView(layerLenBytes).getUint64(0);
      } else {
        if ((await raf.position()) + 4 > sec4End) return [];
        final layerLenBytes = await raf.read(4);
        if (layerLenBytes.length < 4) return [];
        layerInfoLen = ByteData.sublistView(layerLenBytes).getUint32(0);
      }
      if (layerInfoLen <= 0) return [];

      // Layer count (int16)
      if ((await raf.position()) + 2 > sec4End) return [];
      final countBytes = await raf.read(2);
      if (countBytes.length < 2) return [];
      final count = ByteData.sublistView(countBytes).getInt16(0);
      final layerCount = count.abs();
      if (layerCount == 0) return [];

      final rawLayers = <_RawLayerRecord>[];

      for (var i = 0; i < layerCount; i++) {
        // Rect (16 bytes: top, left, bottom, right)
        if ((await raf.position()) + 16 > fileLen) break;
        await raf.setPosition((await raf.position()) + 16);

        // Channel count (2 bytes)
        if ((await raf.position()) + 2 > fileLen) break;
        final chanCountBytes = await raf.read(2);
        if (chanCountBytes.length < 2) break;
        final numChannels = ByteData.sublistView(chanCountBytes).getUint16(0);

        // Skip channel info: numChannels * (version == 2 ? 10 : 6)
        final chanInfoLen = numChannels * (version == 2 ? 10 : 6);
        if ((await raf.position()) + chanInfoLen > fileLen) break;
        await raf.setPosition((await raf.position()) + chanInfoLen);

        // Blend signature (4 bytes), blend key (4 bytes), opacity (1 byte),
        // clipping (1 byte), flags (1 byte: (flags & 2) == 0 is visible), filler (1 byte)
        if ((await raf.position()) + 12 > fileLen) break;
        final blendBytes = await raf.read(12);
        if (blendBytes.length < 12) break;
        final opacity = blendBytes[8];
        final clipping = blendBytes[9];
        final isClipped = clipping == 1;
        final flags = blendBytes[10];
        final isVisible = (flags & 2) == 0;

        // Extra data length (4 bytes)
        if ((await raf.position()) + 4 > fileLen) break;
        final extraLenBytes = await raf.read(4);
        if (extraLenBytes.length < 4) break;
        final extraLen = ByteData.sublistView(extraLenBytes).getUint32(0);
        final extraEnd = (await raf.position()) + extraLen;
        if (extraEnd > fileLen) break;

        String pascalName = '';
        bool isFolder = false;
        bool isClosingDelimiter = false;
        String? unicodeName;

        if (extraLen > 0) {
          // Layer mask data
          if ((await raf.position()) + 4 <= extraEnd) {
            final maskLen =
                ByteData.sublistView(await raf.read(4)).getUint32(0);
            final nextPos = (await raf.position()) + maskLen;
            if (nextPos <= extraEnd) {
              await raf.setPosition(nextPos);
            } else {
              await raf.setPosition(extraEnd);
            }
          }

          // Layer blending ranges
          if ((await raf.position()) + 4 <= extraEnd) {
            final blendLen =
                ByteData.sublistView(await raf.read(4)).getUint32(0);
            final nextPos = (await raf.position()) + blendLen;
            if (nextPos <= extraEnd) {
              await raf.setPosition(nextPos);
            } else {
              await raf.setPosition(extraEnd);
            }
          }

          // Layer name (Pascal string: 1 byte len, bytes, padded to multiple of 4: (4 - (len % 4)) - 1)
          if ((await raf.position()) + 1 <= extraEnd) {
            final nameLenByte = await raf.read(1);
            final nameLen = nameLenByte[0];
            if ((await raf.position()) + nameLen <= extraEnd) {
              final nameBytes = await raf.read(nameLen);
              pascalName = ascii.decode(nameBytes, allowInvalid: true);
              final padding = (4 - (nameLen % 4)) - 1;
              final nextPos = (await raf.position()) + padding;
              if (nextPos <= extraEnd) {
                await raf.setPosition(nextPos);
              } else {
                await raf.setPosition(extraEnd);
              }
            }
          }

          // Tagged blocks ('8BIM' / '8B64')
          while ((await raf.position()) + 12 <= extraEnd) {
            final tagHead = await raf.read(12);
            if (tagHead.length < 12) break;
            final headView = ByteData.sublistView(tagHead);
            final sig = headView.getUint32(0);
            if (sig != 0x3842494D && sig != 0x38423634) {
              break;
            }
            final tagKey =
                ascii.decode(tagHead.sublist(4, 8), allowInvalid: true);
            final tagLen = headView.getUint32(8);
            final tagDataStart = await raf.position();
            final nextTagPos = tagDataStart + tagLen + (tagLen % 2);
            if (nextTagPos > extraEnd) break;

            if (tagKey == 'lsct' || tagKey == 'lsdk') {
              if (tagLen >= 4) {
                final typeBytes = await raf.read(4);
                if (typeBytes.length == 4) {
                  final type = ByteData.sublistView(typeBytes).getUint32(0);
                  if (type == 1 || type == 2) {
                    isFolder = true;
                  } else if (type == 3) {
                    isClosingDelimiter = true;
                  }
                }
              }
            } else if (tagKey == 'luni') {
              if (tagLen >= 4) {
                final countBytes = await raf.read(4);
                if (countBytes.length == 4) {
                  final charCount =
                      ByteData.sublistView(countBytes).getUint32(0);
                  final byteCount = charCount * 2;
                  if (byteCount > 0 && byteCount <= tagLen - 4) {
                    final uniBytes = await raf.read(byteCount);
                    final codeUnits = <int>[];
                    for (var c = 0;
                        c < charCount && (c * 2 + 1) < uniBytes.length;
                        c++) {
                      final ch = (uniBytes[c * 2] << 8) | uniBytes[c * 2 + 1];
                      if (ch != 0) codeUnits.add(ch);
                    }
                    if (codeUnits.isNotEmpty) {
                      unicodeName = String.fromCharCodes(codeUnits);
                    }
                  }
                }
              }
            }

            await raf.setPosition(nextTagPos);
          }

          await raf.setPosition(extraEnd);
        }

        final effectiveName =
            (unicodeName != null && unicodeName.trim().isNotEmpty)
                ? unicodeName.trim()
                : (pascalName.trim().isNotEmpty
                    ? pascalName.trim()
                    : 'Layer ${i + 1}');

        final isClosing = isClosingDelimiter ||
            effectiveName == '</Layer group>' ||
            effectiveName == '</Layer set>';

        rawLayers.add(_RawLayerRecord(
          index: i,
          name: effectiveName,
          isVisible: isVisible,
          opacity: opacity,
          isFolder: isFolder,
          isClosingDelimiter: isClosing,
          isClipped: isClipped,
        ));
      }

      // Determine if folder headers are at higher indices than delimiters (standard Photoshop)
      int lastFolderIdx = -1;
      int lastDelimiterIdx = -1;
      for (final r in rawLayers) {
        if (r.isFolder) lastFolderIdx = r.index;
        if (r.isClosingDelimiter) lastDelimiterIdx = r.index;
      }
      final bool isStandardPsOrder = lastDelimiterIdx == -1 ||
          lastFolderIdx == -1 ||
          lastFolderIdx > lastDelimiterIdx;

      final processed = <PsdLayerInfo>[];
      final folderStack = <int>[];

      if (isStandardPsOrder) {
        // Standard Photoshop: iterate top-down (index rawLayers.length - 1 down to 0)
        for (var i = rawLayers.length - 1; i >= 0; i--) {
          final rec = rawLayers[i];
          if (rec.isClosingDelimiter ||
              rec.name == '</Layer group>' ||
              rec.name == '</Layer set>') {
            if (folderStack.isNotEmpty) {
              folderStack.removeLast();
            }
            continue;
          }

          final parentIndex = folderStack.isNotEmpty ? folderStack.last : null;
          final depth = folderStack.length;

          processed.add(PsdLayerInfo(
            index: rec.index,
            name: rec.name,
            isVisible: rec.isVisible,
            opacity: rec.opacity,
            isFolder: rec.isFolder,
            isClipped: rec.isClipped,
            depth: depth,
            parentIndex: parentIndex,
          ));

          if (rec.isFolder) {
            folderStack.add(rec.index);
          }
        }
        return processed.reversed.toList();
      } else {
        // Forward order: iterate bottom-up (0 up to rawLayers.length - 1)
        for (var i = 0; i < rawLayers.length; i++) {
          final rec = rawLayers[i];
          if (rec.isClosingDelimiter ||
              rec.name == '</Layer group>' ||
              rec.name == '</Layer set>') {
            if (folderStack.isNotEmpty) {
              folderStack.removeLast();
            }
            continue;
          }

          final parentIndex = folderStack.isNotEmpty ? folderStack.last : null;
          final depth = folderStack.length;

          processed.add(PsdLayerInfo(
            index: rec.index,
            name: rec.name,
            isVisible: rec.isVisible,
            opacity: rec.opacity,
            isFolder: rec.isFolder,
            isClipped: rec.isClipped,
            depth: depth,
            parentIndex: parentIndex,
          ));

          if (rec.isFolder) {
            folderStack.add(rec.index);
          }
        }
        return processed;
      }
    } catch (e) {
      debugPrint('[PsdService] _streamLayerRecords error for $filePath: $e');
      return [];
    } finally {
      try {
        await raf?.close();
      } catch (_) {}
    }
  }

  @visibleForTesting
  Future<List<PsdLayerInfo>> streamLayerRecords(String filePath) =>
      _streamLayerRecords(filePath);

  /// Extracts layer metadata from a PSD file.
  ///
  /// Uses streaming layer record parser directly from disk (< 5ms, 0 MB memory overhead).
  /// For smaller files (< 80MB), falls back to isolate layer decoding if streaming
  /// yields no layers.
  Future<List<PsdLayerInfo>> getLayers(String filePath) async {
    final cached = getCachedLayersSync(filePath);
    if (cached != null) return cached;

    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      void cacheLayers(List<PsdLayerInfo> layers) {
        if (layers.isEmpty) return;
        try {
          final stat = file.statSync();
          _layersMemoryCache[filePath] = (
            size: stat.size,
            mtimeMs: stat.modified.millisecondsSinceEpoch,
            layers: layers,
          );
        } catch (_) {}
      }

      // 1. Fast streaming layer records directly from disk (< 5ms, 0 MB memory overhead)
      final streamedLayers = await _streamLayerRecords(filePath);
      if (streamedLayers.isNotEmpty) {
        cacheLayers(streamedLayers);
        return streamedLayers;
      }

      // 2. Fallback to isolate decoder only for files < 80MB if streaming didn't find layers
      final fileSize = await file.length();
      if (fileSize < 80 * 1024 * 1024) {
        final isolateLayers = await _renderGate.run(() => compute(
              _isolateGetLayers,
              filePath,
            ).timeout(const Duration(seconds: 12),
                onTimeout: () => <PsdLayerInfo>[]));
        cacheLayers(isolateLayers);
        return isolateLayers;
      }

      return [];
    } catch (e) {
      debugPrint('[PsdService] getLayers error for $filePath: $e');
      return [];
    }
  }

  final Map<String, Map<int, Uint8List>> _layerThumbnailsCache = {};

  /// Returns cached layer thumbnails if already extracted, or null.
  Map<int, Uint8List>? getCachedLayerThumbnails(String filePath) =>
      _layerThumbnailsCache[filePath];

  /// Extracts downsampled PNG thumbnails for all raster layers in [filePath].
  Future<Map<int, Uint8List>> getLayerThumbnails(
    String filePath, {
    int maxThumbDim = 56,
  }) async {
    if (_layerThumbnailsCache.containsKey(filePath)) {
      return _layerThumbnailsCache[filePath]!;
    }
    try {
      final file = File(filePath);
      if (!await file.exists()) return {};

      final results = await _thumbGate.run(() => compute(
            _isolateExtractLayerThumbnails,
            _ExtractThumbParams(filePath, maxThumbDim),
          ).timeout(const Duration(seconds: 12), onTimeout: () => null));
      if (results != null && results.isNotEmpty) {
        _layerThumbnailsCache[filePath] = results;
        return results;
      }
      return results ?? {};
    } catch (e) {
      debugPrint('[PsdService] getLayerThumbnails error for $filePath: $e');
      return {};
    }
  }

  @visibleForTesting
  Future<Map<int, Uint8List>> extractLayerThumbnails(
    String filePath, {
    int maxThumbDim = 56,
  }) =>
      getLayerThumbnails(filePath, maxThumbDim: maxThumbDim);

  String? _psdCacheFileName(
    String filePath, {
    Set<int>? hiddenLayerIndices,
    int maxDimension = 2048,
  }) {
    if (filePath.isEmpty) return null;
    try {
      final file = File(filePath);
      if (!file.existsSync()) return null;
      final stat = file.statSync();
      final effectiveHidden =
          hiddenLayerIndices ?? getSavedLayerVisibility(filePath);
      final hiddenSig = effectiveHidden == null
          ? 'default'
          : (effectiveHidden.toList()..sort()).join(',');
      final sig =
          '${filePath}_${stat.size}_${stat.modified.millisecondsSinceEpoch}_${maxDimension}_$hiddenSig';
      final safe = p
          .basenameWithoutExtension(filePath)
          .replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), '_');
      return 'psd_prev_${sig.hashCode.abs()}_$safe.bin';
    } catch (_) {
      return null;
    }
  }

  /// Synchronously returns cached layers if file metadata matches on disk.
  List<PsdLayerInfo>? getCachedLayersSync(String filePath) {
    final cached = _layersMemoryCache[filePath];
    if (cached == null) return null;
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        _layersMemoryCache.remove(filePath);
        return null;
      }
      final stat = file.statSync();
      if (cached.size == stat.size &&
          cached.mtimeMs == stat.modified.millisecondsSinceEpoch) {
        return cached.layers;
      }
      _layersMemoryCache.remove(filePath);
    } catch (_) {}
    return null;
  }

  void _putRenderedPreviewInMemory(String fileName, Uint8List bytes) {
    _renderedPreviewCache.remove(fileName);
    while (_renderedPreviewCache.length >= _maxMemoryRenderedPreviews) {
      _renderedPreviewCache.remove(_renderedPreviewCache.keys.first);
    }
    _renderedPreviewCache[fileName] = bytes;
  }

  /// Synchronously returns cached rendered PSD preview bytes from memory or disk.
  Uint8List? getCachedRenderedPreviewSync(
    String filePath, {
    Set<int>? hiddenLayerIndices,
    int? maxDimension,
  }) {
    final dims = maxDimension != null ? [maxDimension] : const [1600, 2048];
    for (final dim in dims) {
      final fileName = _psdCacheFileName(
        filePath,
        hiddenLayerIndices: hiddenLayerIndices,
        maxDimension: dim,
      );
      if (fileName == null) return null;

      final mem = _renderedPreviewCache.remove(fileName);
      if (mem != null) {
        _renderedPreviewCache[fileName] = mem;
        return mem;
      }

      final dirPath = ThumbnailService.instance.cacheDirPathSync;
      if (dirPath != null) {
        try {
          final file = File(p.join(dirPath, fileName));
          if (file.existsSync()) {
            final bytes = file.readAsBytesSync();
            if (bytes.isNotEmpty) {
              _putRenderedPreviewInMemory(fileName, bytes);
              ThumbnailService.instance.registerDiskCacheFileName(fileName);
              return bytes;
            }
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<void> _storeRenderedPreview(
    String filePath,
    Uint8List bytes, {
    Set<int>? hiddenLayerIndices,
    required int maxDimension,
  }) async {
    if (bytes.isEmpty) return;
    final fileName = _psdCacheFileName(
      filePath,
      hiddenLayerIndices: hiddenLayerIndices,
      maxDimension: maxDimension,
    );
    if (fileName == null) return;
    _putRenderedPreviewInMemory(fileName, bytes);
    try {
      await ThumbnailService.instance.writeDiskCacheBytes(fileName, bytes);
    } catch (_) {}
  }

  /// Renders the PSD document with custom layer visibility in an isolate.
  ///
  /// When [hiddenLayerIndices] is empty, attempts streaming Section 5 merged
  /// composite first for zero layer overhead. Only decodes all layers if layers are toggled.
  Future<Uint8List?> renderWithLayers(
    String filePath, {
    required Set<int> hiddenLayerIndices,
    int maxDimension = 2048,
  }) async {
    final cached = getCachedRenderedPreviewSync(
      filePath,
      hiddenLayerIndices: hiddenLayerIndices,
      maxDimension: maxDimension,
    );
    if (cached != null && cached.isNotEmpty) {
      return cached;
    }

    final cacheFileName = _psdCacheFileName(
      filePath,
      hiddenLayerIndices: hiddenLayerIndices,
      maxDimension: maxDimension,
    );
    final inFlightKey =
        cacheFileName != null ? 'render:$cacheFileName' : null;
    if (inFlightKey != null) {
      final existing = _renderInFlight[inFlightKey];
      if (existing != null) return existing;
    }

    final future = _computeAndStoreRenderWithLayers(
      filePath,
      hiddenLayerIndices: hiddenLayerIndices,
      maxDimension: maxDimension,
    );
    if (inFlightKey != null) {
      _renderInFlight[inFlightKey] = future;
    }
    try {
      return await future;
    } finally {
      if (inFlightKey != null &&
          identical(_renderInFlight[inFlightKey], future)) {
        _renderInFlight.remove(inFlightKey);
      }
    }
  }

  Future<Uint8List?> _computeAndStoreRenderWithLayers(
    String filePath, {
    required Set<int> hiddenLayerIndices,
    int maxDimension = 2048,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      try {
        await ThumbnailService.instance.getCacheDirectory();
      } catch (_) {}

      final diskCached = getCachedRenderedPreviewSync(
        filePath,
        hiddenLayerIndices: hiddenLayerIndices,
        maxDimension: maxDimension,
      );
      if (diskCached != null && diskCached.isNotEmpty) {
        return diskCached;
      }

      Future<Uint8List?> cacheAndReturn(Uint8List? bytes) async {
        if (bytes != null && bytes.isNotEmpty) {
          await _storeRenderedPreview(
            filePath,
            bytes,
            hiddenLayerIndices: hiddenLayerIndices,
            maxDimension: maxDimension,
          );
          return bytes;
        }
        return null;
      }

      // 1. Primary execution path: streaming renderer for custom layer visibility
      try {
        final streamed = await _renderGate.run(() => compute(
              _isolateStreamRenderWithLayers,
              _StreamRenderParams(
                filePath: filePath,
                hiddenLayerIndices: hiddenLayerIndices,
                maxDimension: maxDimension,
              ),
            ).timeout(const Duration(seconds: 30), onTimeout: () => null));
        if (streamed != null && streamed.isNotEmpty) {
          return await cacheAndReturn(streamed);
        }
      } catch (e) {
        debugPrint('[PsdService] _isolateStreamRenderWithLayers error: $e');
      }

      // 2. Secondary fallback: isolate full layer decode and composite
      final result = await _renderGate.run(() => compute(
            _isolateRenderWithLayers,
            _RenderWithLayersParams(
              filePath: filePath,
              hiddenLayerIndices: hiddenLayerIndices,
              maxDimension: maxDimension,
            ),
          ).timeout(const Duration(seconds: 30), onTimeout: () => null));

      if (result != null && result.isNotEmpty) {
        return await cacheAndReturn(result);
      }

      // 3. Last-resort fallback when both renderers return null and all layers are visible
      if (hiddenLayerIndices.isEmpty) {
        final layers = await getLayers(filePath);
        final allVisibleInPs =
            layers.isNotEmpty && layers.every((l) => l.isVisible);
        if (allVisibleInPs) {
          final composite = await extractMergedComposite(
            filePath,
            maxDimension: maxDimension,
          );
          if (composite != null && composite.isNotEmpty) {
            return await cacheAndReturn(composite);
          }
          final thumb =
              await decodeThumbnail(filePath, maxDimension: maxDimension);
          return await cacheAndReturn(thumb);
        }
      }

      return null;
    } catch (e) {
      debugPrint('[PsdService] renderWithLayers error for $filePath: $e');
      if (hiddenLayerIndices.isEmpty) {
        final layers = await getLayers(filePath);
        final allVisibleInPs =
            layers.isNotEmpty && layers.every((l) => l.isVisible);
        if (allVisibleInPs) {
          final composite = await extractMergedComposite(
            filePath,
            maxDimension: maxDimension,
          );
          if (composite != null && composite.isNotEmpty) {
            await _storeRenderedPreview(
              filePath,
              composite,
              hiddenLayerIndices: hiddenLayerIndices,
              maxDimension: maxDimension,
            );
            return composite;
          }
          final thumb =
              await decodeThumbnail(filePath, maxDimension: maxDimension);
          if (thumb != null && thumb.isNotEmpty) {
            await _storeRenderedPreview(
              filePath,
              thumb,
              hiddenLayerIndices: hiddenLayerIndices,
              maxDimension: maxDimension,
            );
          }
          return thumb;
        }
      }
      return null;
    }
  }

  /// Photoshop-style PSD Document Loader with multi-tier recovery engine:
  /// - Tier 1: Merged composite from Section 5 ([extractMergedComposite])
  /// - Tier 2: Embedded JPEG thumbnail ([extractEmbeddedThumbnail])
  /// - Tier 3: Render composite with all layers visible ([renderWithLayers])
  /// - Tier 4: Fallback to null
  Future<Uint8List?> loadPsdDocument(
    String filePath, {
    int maxDimension = 2048,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      // Pre-cache layer thumbnails in background so they are ready for layer sheet
      unawaited(
          getLayerThumbnails(filePath).catchError((_) => <int, Uint8List>{}));

      // Check if user has saved custom layer visibility
      final savedHidden = getSavedLayerVisibility(filePath);
      if (savedHidden != null) {
        final cachedSaved = getCachedRenderedPreviewSync(
              filePath,
              hiddenLayerIndices: savedHidden,
              maxDimension: maxDimension,
            ) ??
            (maxDimension >= 1600 && maxDimension != 1600
                ? getCachedRenderedPreviewSync(
                    filePath,
                    hiddenLayerIndices: savedHidden,
                    maxDimension: 1600,
                  )
                : null);
        if (cachedSaved != null && cachedSaved.isNotEmpty) {
          return cachedSaved;
        }
        final rendered = await renderWithLayers(
          filePath,
          hiddenLayerIndices: savedHidden,
          maxDimension: maxDimension,
        );
        if (rendered != null && rendered.isNotEmpty) {
          return rendered;
        }
      }

      final cachedDefault = getCachedRenderedPreviewSync(
        filePath,
        hiddenLayerIndices: savedHidden,
        maxDimension: maxDimension,
      );
      if (cachedDefault != null && cachedDefault.isNotEmpty) {
        return cachedDefault;
      }

      final cacheFileName = _psdCacheFileName(
        filePath,
        hiddenLayerIndices: savedHidden,
        maxDimension: maxDimension,
      );
      final inFlightKey =
          cacheFileName != null ? 'load:$cacheFileName' : null;
      if (inFlightKey != null) {
        final existing = _renderInFlight[inFlightKey];
        if (existing != null) return await existing;
      }

      final future = _computeAndStoreLoadPsdDocument(
        filePath,
        savedHidden: savedHidden,
        maxDimension: maxDimension,
      );
      if (inFlightKey != null) {
        _renderInFlight[inFlightKey] = future;
      }
      try {
        return await future;
      } finally {
        if (inFlightKey != null &&
            identical(_renderInFlight[inFlightKey], future)) {
          _renderInFlight.remove(inFlightKey);
        }
      }
    } catch (e) {
      debugPrint('[PsdService] loadPsdDocument error for $filePath: $e');
      return null;
    }
  }

  Future<Uint8List?> _computeAndStoreLoadPsdDocument(
    String filePath, {
    required Set<int>? savedHidden,
    required int maxDimension,
  }) async {
    try {
      await ThumbnailService.instance.getCacheDirectory();
    } catch (_) {}

    final diskCached = getCachedRenderedPreviewSync(
      filePath,
      hiddenLayerIndices: savedHidden,
      maxDimension: maxDimension,
    );
    if (diskCached != null && diskCached.isNotEmpty) {
      return diskCached;
    }

    Future<Uint8List?> cacheAndReturn(Uint8List? bytes) async {
      if (bytes != null && bytes.isNotEmpty) {
        await _storeRenderedPreview(
          filePath,
          bytes,
          hiddenLayerIndices: savedHidden,
          maxDimension: maxDimension,
        );
        return bytes;
      }
      return null;
    }

    // Tier 1: Merged composite from Section 5
    try {
      final composite = await extractMergedComposite(
        filePath,
        maxDimension: maxDimension,
      );
      if (composite != null && composite.isNotEmpty) {
        return await cacheAndReturn(composite);
      }
    } catch (e) {
      debugPrint('[PsdService] Tier 1 extractMergedComposite failed: $e');
    }

    // Tier 2: Embedded high-resolution thumbnail (for files saved without Maximize Compatibility)
    try {
      final thumbnail = await extractEmbeddedThumbnail(filePath);
      if (thumbnail != null && thumbnail.isNotEmpty) {
        return await cacheAndReturn(thumbnail);
      }
    } catch (e) {
      debugPrint('[PsdService] Tier 2 extractEmbeddedThumbnail failed: $e');
    }

    // Tier 3: Render composite with all layers
    try {
      final rendered = await renderWithLayers(
        filePath,
        hiddenLayerIndices: const {},
        maxDimension: maxDimension,
      );
      if (rendered != null && rendered.isNotEmpty) {
        return await cacheAndReturn(rendered);
      }
    } catch (e) {
      debugPrint('[PsdService] Tier 3 renderWithLayers failed: $e');
    }

    return null;
  }

  /// Pre-parses layer metadata and renders a cached PSD preview in the background.
  Future<Uint8List?> prewarmPsdDocument(String filePath) async {
    if (filePath.isEmpty || !isPsd(filePath)) return null;
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;
      await getLayers(filePath);
      final maxDim = getSavedLayerVisibility(filePath) != null ? 1600 : 2048;
      return await loadPsdDocument(filePath, maxDimension: maxDim);
    } catch (_) {
      return null;
    }
  }

  /// Clears in-memory PSD rendered preview and layer metadata caches.
  void clearMemoryCache() {
    _renderedPreviewCache.clear();
    _layersMemoryCache.clear();
  }

  /// Clears both in-memory PSD caches and persisted PSD preview files on disk.
  Future<void> clearCache() async {
    clearMemoryCache();
    ThumbnailService.instance
        .unregisterDiskCacheFileNamesByPrefix('psd_prev_');
    try {
      final dir = await ThumbnailService.instance.getCacheDirectory();
      if (await dir.exists()) {
        await for (final entity
            in dir.list(recursive: false, followLinks: false)) {
          if (entity is File) {
            final name = p.basename(entity.path);
            if (name.startsWith('psd_prev_') && name.endsWith('.bin')) {
              try {
                await entity.delete();
              } catch (_) {}
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[PsdService] Error clearing cache: $e');
    }
  }

  // ── Saved Layer Visibility ──────────────────────────────────────────────────

  Set<int>? getSavedLayerVisibility(String filePath) {
    try {
      return SettingsService.instance.getSavedPsdHiddenLayers(filePath);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveLayerVisibility(
      String filePath, Set<int> hiddenIndices) async {
    try {
      await SettingsService.instance
          .savePsdHiddenLayers(filePath, hiddenIndices);
    } catch (_) {}
  }

  Future<void> clearSavedLayerVisibility(String filePath) async {
    try {
      await SettingsService.instance.clearSavedPsdHiddenLayers(filePath);
    } catch (_) {}
  }
}

class _DecodeSynthParams {
  final Uint8List synthBytes;
  final int maxDimension;
  const _DecodeSynthParams(this.synthBytes, this.maxDimension);
}

Uint8List? _isolateDecodeSynthPsd(_DecodeSynthParams params) {
  try {
    final decoder = img.PsdDecoder(maxPixels: 0);
    final psd = decoder.decodePsd(params.synthBytes);
    img.Image? image = psd?.mergedImage;
    if (image == null && psd != null) {
      try {
        image = psd.renderImage();
      } catch (_) {
        image = null;
      }
    }
    image ??= decoder.decode(params.synthBytes);
    if (image == null) return null;

    if (params.maxDimension > 0 &&
        (image.width > params.maxDimension ||
            image.height > params.maxDimension)) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? params.maxDimension : null,
        height: image.height > image.width ? params.maxDimension : null,
        maintainAspect: true,
      );
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  } catch (e) {
    return null;
  }
}

class _DecodeThumbnailParams {
  final String filePath;
  final int maxDimension;
  const _DecodeThumbnailParams(this.filePath, this.maxDimension);
}

Uint8List? _isolateDecodeThumbnail(_DecodeThumbnailParams params) {
  try {
    final bytes = File(params.filePath).readAsBytesSync();
    if (bytes.isEmpty) return null;

    final decoder = img.PsdDecoder(maxPixels: 0);
    if (!decoder.isValidFile(bytes)) return null;

    img.Image? image;
    final psd = decoder.decodePsd(bytes);
    if (psd != null) {
      if (psd.mergedImage != null) {
        image = psd.mergedImage;
      } else {
        try {
          image = psd.renderImage();
        } catch (_) {
          image = null;
        }
      }
    }
    image ??= decoder.decode(bytes);

    if (image == null) return null;

    if (image.width > params.maxDimension ||
        image.height > params.maxDimension) {
      image = img.copyResize(
        image,
        width: image.width >= image.height ? params.maxDimension : null,
        height: image.height > image.width ? params.maxDimension : null,
        maintainAspect: true,
      );
    }

    return Uint8List.fromList(img.encodeJpg(image, quality: 90));
  } catch (e) {
    return null;
  }
}

List<PsdLayerInfo> _isolateGetLayers(String filePath) {
  try {
    final bytes = File(filePath).readAsBytesSync();
    if (bytes.isEmpty) return [];

    final decoder = img.PsdDecoder(maxPixels: 0);
    final psd = decoder.decodePsd(bytes);
    if (psd == null || psd.layers.isEmpty) return [];

    final result = <PsdLayerInfo>[];
    for (var i = 0; i < psd.layers.length; i++) {
      final layer = psd.layers[i];
      final layerType = layer.type();

      // Section divider type 3 indicates closing </Layer group> tags in PSD specification
      if (layerType == 3 ||
          layer.name == '</Layer group>' ||
          layer.name == '</Layer set>') {
        continue;
      }

      final rawName = layer.name?.trim() ?? '';
      final cleanName = rawName.isNotEmpty ? rawName : 'Layer ${i + 1}';
      final isFolder = layerType == 1 || layerType == 2;
      final isVisible = layer.isVisible();

      result.add(PsdLayerInfo(
        index: i,
        name: cleanName,
        isVisible: isVisible,
        opacity: layer.opacity,
        isFolder: isFolder,
      ));
    }
    return result;
  } catch (e) {
    return [];
  }
}

class _RenderWithLayersParams {
  final String filePath;
  final Set<int> hiddenLayerIndices;
  final int maxDimension;
  const _RenderWithLayersParams({
    required this.filePath,
    required this.hiddenLayerIndices,
    required this.maxDimension,
  });
}

Uint8List? _isolateRenderWithLayers(_RenderWithLayersParams params) {
  try {
    final bytes = File(params.filePath).readAsBytesSync();
    if (bytes.isEmpty) return null;

    final decoder = img.PsdDecoder(maxPixels: 0);
    final psd = decoder.decodePsd(bytes);
    if (psd == null) {
      if (params.hiddenLayerIndices.isNotEmpty) return null;
      final fallback = decoder.decode(bytes);
      if (fallback == null) return null;
      var rendered = fallback;
      if (params.maxDimension > 0 &&
          (rendered.width > params.maxDimension ||
              rendered.height > params.maxDimension)) {
        rendered = img.copyResize(
          rendered,
          width: rendered.width >= rendered.height ? params.maxDimension : null,
          height: rendered.height > rendered.width ? params.maxDimension : null,
          maintainAspect: true,
        );
      }
      return Uint8List.fromList(img.encodeJpg(rendered, quality: 90));
    }

    img.Image? rendered;
    final allVisibleInPs = psd.layers.isNotEmpty &&
        psd.layers.every((l) => (l.flags & img.PsdFlag.hidden) == 0);

    if (psd.layers.isNotEmpty) {
      for (var i = 0; i < psd.layers.length; i++) {
        final layer = psd.layers[i];
        if (params.hiddenLayerIndices.contains(i)) {
          layer.flags |= img.PsdFlag.hidden;
        } else {
          layer.flags &= ~img.PsdFlag.hidden;
        }
      }
      psd.mergedImage = null;

      try {
        rendered = psd.renderImage();
      } catch (_) {
        rendered = null;
      }

      if (rendered == null && psd.width > 0 && psd.height > 0) {
        try {
          final canvas = img.Image(
            width: psd.width,
            height: psd.height,
            numChannels: 4,
          );
          for (var i = 0; i < psd.layers.length; i++) {
            if (params.hiddenLayerIndices.contains(i)) continue;
            final layer = psd.layers[i];
            final src = layer.layerImage;
            if (src == null || src.width <= 0 || src.height <= 0) continue;
            img.compositeImage(
              canvas,
              src,
              dstX: layer.left,
              dstY: layer.top,
              blend: img.BlendMode.alpha,
            );
          }
          rendered = canvas;
        } catch (_) {}
      }
    } else if (params.hiddenLayerIndices.isEmpty &&
        allVisibleInPs &&
        psd.mergedImage != null) {
      rendered = psd.mergedImage;
    }

    if (rendered == null) {
      if (params.hiddenLayerIndices.isEmpty && allVisibleInPs) {
        rendered = psd.mergedImage ?? decoder.decode(bytes);
      }
    }
    if (rendered == null) return null;

    if (params.maxDimension > 0 &&
        (rendered.width > params.maxDimension ||
            rendered.height > params.maxDimension)) {
      rendered = img.copyResize(
        rendered,
        width: rendered.width >= rendered.height ? params.maxDimension : null,
        height: rendered.height > rendered.width ? params.maxDimension : null,
        maintainAspect: true,
      );
    }

    return Uint8List.fromList(img.encodeJpg(rendered, quality: 90));
  } catch (e) {
    return null;
  }
}

class _LayerChannelRecord {
  final int id;
  final int length;
  int fileOffset = 0;
  _LayerChannelRecord({
    required this.id,
    required this.length,
  });
}

class _StreamLayerInfo {
  final int index;
  final String name;
  final int top;
  final int left;
  final int bottom;
  final int right;
  final int opacity;
  final bool isVisible;
  final bool isFolder;
  final bool isClosingDelimiter;
  final bool isClipped;
  int? parentIndex;
  final List<_LayerChannelRecord> channels;

  int get width => right - left;
  int get height => bottom - top;

  _StreamLayerInfo({
    required this.index,
    this.name = '',
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
    required this.opacity,
    required this.isVisible,
    this.isFolder = false,
    this.isClosingDelimiter = false,
    this.isClipped = false,
    required this.channels,
  });
}

class _StreamRenderParams {
  final String filePath;
  final Set<int> hiddenLayerIndices;
  final int maxDimension;
  const _StreamRenderParams({
    required this.filePath,
    required this.hiddenLayerIndices,
    required this.maxDimension,
  });
}

Uint8List _decodePackBits(
  Uint8List src,
  int srcOffset,
  int srcLength,
  int expectedLength,
) {
  if (expectedLength <= 0) return Uint8List(0);
  final dst = Uint8List(expectedLength);
  var inIdx = srcOffset;
  final inEnd = (srcOffset + srcLength).clamp(0, src.length);
  var outIdx = 0;

  while (inIdx < inEnd && outIdx < expectedLength) {
    var n = src[inIdx++];
    if (n > 127) n -= 256; // convert to signed byte -128..127

    if (n >= 0) {
      final count = n + 1;
      for (var i = 0;
          i < count && inIdx < inEnd && outIdx < expectedLength;
          i++) {
        dst[outIdx++] = src[inIdx++];
      }
    } else if (n > -128) {
      final count = -n + 1;
      if (inIdx < inEnd) {
        final val = src[inIdx++];
        for (var i = 0; i < count && outIdx < expectedLength; i++) {
          dst[outIdx++] = val;
        }
      }
    }
    // n == -128 is NOP
  }
  return dst;
}

Uint8List? _decompressChannelData(
  Uint8List rawChannelData,
  int width,
  int height, {
  bool isPsb = false,
  int depth = 8,
}) {
  if (width <= 0 || height <= 0 || rawChannelData.length < 2) return null;

  try {
    final compression = ByteData.sublistView(rawChannelData).getUint16(0);
    final bytesPerPixel = (depth == 16) ? 2 : 1;
    final rowBytes = width * bytesPerPixel;
    final expectedBytes = width * height * bytesPerPixel;

    switch (compression) {
      case 0: // Raw uncompressed
        final out = Uint8List(expectedBytes);
        final available = min(expectedBytes, rawChannelData.length - 2);
        if (available > 0) {
          out.setRange(0, available, rawChannelData, 2);
        }
        return out;

      case 1: // PackBits RLE
        final entrySize = isPsb ? 4 : 2;
        final tableLength = height * entrySize;
        if (rawChannelData.length < 2 + tableLength) return null;

        final out = Uint8List(expectedBytes);
        var dataOffset = 2 + tableLength;
        final bd = ByteData.sublistView(rawChannelData);

        for (var row = 0; row < height; row++) {
          final scanlineLen =
              isPsb ? bd.getUint32(2 + row * 4) : bd.getUint16(2 + row * 2);
          if (dataOffset + scanlineLen > rawChannelData.length) {
            final remaining = rawChannelData.length - dataOffset;
            if (remaining > 0) {
              final scanline = _decodePackBits(
                rawChannelData,
                dataOffset,
                remaining,
                rowBytes,
              );
              final copyLen = min(scanline.length, rowBytes);
              out.setRange(row * rowBytes, row * rowBytes + copyLen, scanline);
            }
            break;
          }
          final scanline = _decodePackBits(
            rawChannelData,
            dataOffset,
            scanlineLen,
            rowBytes,
          );
          final copyLen = min(scanline.length, rowBytes);
          out.setRange(row * rowBytes, row * rowBytes + copyLen, scanline);
          dataOffset += scanlineLen;
        }
        return out;

      case 2: // ZIP without prediction
        final compressed = rawChannelData.sublist(2);
        List<int> decomp;
        try {
          decomp = zlib.decode(compressed);
        } catch (_) {
          decomp = ZLibDecoder(raw: true).convert(compressed);
        }
        final decompressed = Uint8List.fromList(decomp);
        if (decompressed.length >= expectedBytes) {
          return decompressed.length == expectedBytes
              ? decompressed
              : Uint8List.sublistView(decompressed, 0, expectedBytes);
        } else {
          final out = Uint8List(expectedBytes);
          out.setRange(0, decompressed.length, decompressed);
          return out;
        }

      case 3: // ZIP with delta differencing
        final compressed = rawChannelData.sublist(2);
        List<int> decomp;
        try {
          decomp = zlib.decode(compressed);
        } catch (_) {
          decomp = ZLibDecoder(raw: true).convert(compressed);
        }
        final decompressed = Uint8List.fromList(decomp);
        for (var y = 0; y < height; y++) {
          final rowStart = y * rowBytes;
          for (var x = 1; x < rowBytes; x++) {
            final idx = rowStart + x;
            if (idx < decompressed.length) {
              decompressed[idx] =
                  (decompressed[idx] + decompressed[idx - 1]) & 0xFF;
            }
          }
        }
        if (decompressed.length >= expectedBytes) {
          return decompressed.length == expectedBytes
              ? decompressed
              : Uint8List.sublistView(decompressed, 0, expectedBytes);
        } else {
          final out = Uint8List(expectedBytes);
          out.setRange(0, decompressed.length, decompressed);
          return out;
        }

      default:
        return null;
    }
  } catch (e) {
    debugPrint('[PsdService] decompressChannelData error: $e');
    return null;
  }
}

void _compositeLayer(
  img.Image dst,
  img.Image src,
  int dstX,
  int dstY,
  int opacity,
) {
  if (opacity <= 0) return;
  if (src.width <= 0 || src.height <= 0 || dst.width <= 0 || dst.height <= 0) {
    return;
  }
  final effOpacity = opacity.clamp(0, 255);

  final startX = dstX < 0 ? -dstX : 0;
  final startY = dstY < 0 ? -dstY : 0;
  final dstStartX = dstX < 0 ? 0 : dstX;
  final dstStartY = dstY < 0 ? 0 : dstY;
  final dstEndX = (dstX + src.width).clamp(0, dst.width);
  final dstEndY = (dstY + src.height).clamp(0, dst.height);

  if (dstStartX >= dstEndX || dstStartY >= dstEndY) return;

  for (var dy = dstStartY; dy < dstEndY; dy++) {
    final sy = startY + (dy - dstStartY);
    for (var dx = dstStartX; dx < dstEndX; dx++) {
      final sx = startX + (dx - dstStartX);
      final sp = src.getPixel(sx, sy);
      final sa = (sp.a.toInt() * effOpacity) ~/ 255;
      if (sa == 0) continue;

      if (sa >= 255) {
        dst.setPixelRgba(dx, dy, sp.r.toInt(), sp.g.toInt(), sp.b.toInt(), 255);
        continue;
      }

      final dp = dst.getPixel(dx, dy);
      final da = dp.a.toInt();
      final invSa = 255 - sa;
      final outA = sa + (da * invSa ~/ 255);
      if (outA <= 0) continue;

      final sr = sp.r.toInt();
      final sg = sp.g.toInt();
      final sb = sp.b.toInt();
      final dr = dp.r.toInt();
      final dg = dp.g.toInt();
      final db = dp.b.toInt();

      final outR = ((sr * sa) + (dr * da * invSa ~/ 255)) ~/ outA;
      final outG = ((sg * sa) + (dg * da * invSa ~/ 255)) ~/ outA;
      final outB = ((sb * sa) + (db * da * invSa ~/ 255)) ~/ outA;

      dst.setPixelRgba(
        dx,
        dy,
        outR.clamp(0, 255),
        outG.clamp(0, 255),
        outB.clamp(0, 255),
        outA.clamp(0, 255),
      );
    }
  }
}

class _ChannelScanlineReader {
  final Uint8List raw;
  final int width;
  final int height;
  final int bytesPerPixel;
  final int depth;
  final int compression;
  final Uint32List? scanlineOffsets;
  final Uint32List? scanlineLengths;
  final Uint8List? fullDecompressed;

  int get rowBytes => width * bytesPerPixel;

  int _cachedRow = -1;
  Uint8List? _cachedScanline;

  _ChannelScanlineReader._({
    required this.raw,
    required this.width,
    required this.height,
    required this.bytesPerPixel,
    required this.depth,
    required this.compression,
    this.scanlineOffsets,
    this.scanlineLengths,
    this.fullDecompressed,
  });

  static _ChannelScanlineReader? create(
    Uint8List rawChannelData,
    int width,
    int height, {
    bool isPsb = false,
    int depth = 8,
  }) {
    if (width <= 0 || height <= 0 || rawChannelData.length < 2) return null;
    final compression = ByteData.sublistView(rawChannelData).getUint16(0);
    final bytesPerPixel = (depth == 16) ? 2 : 1;

    if (compression == 0) {
      return _ChannelScanlineReader._(
        raw: rawChannelData,
        width: width,
        height: height,
        bytesPerPixel: bytesPerPixel,
        depth: depth,
        compression: 0,
      );
    } else if (compression == 1) {
      final entrySize = isPsb ? 4 : 2;
      final tableLength = height * entrySize;
      if (rawChannelData.length < 2 + tableLength) return null;

      final scanlineOffsets = Uint32List(height);
      final scanlineLengths = Uint32List(height);
      var currOffset = 2 + tableLength;
      final bd = ByteData.sublistView(rawChannelData);

      for (var r = 0; r < height; r++) {
        final slen = isPsb ? bd.getUint32(2 + r * 4) : bd.getUint16(2 + r * 2);
        scanlineOffsets[r] = currOffset;
        scanlineLengths[r] = slen;
        currOffset += slen;
      }

      return _ChannelScanlineReader._(
        raw: rawChannelData,
        width: width,
        height: height,
        bytesPerPixel: bytesPerPixel,
        depth: depth,
        compression: 1,
        scanlineOffsets: scanlineOffsets,
        scanlineLengths: scanlineLengths,
      );
    } else if (compression == 2 || compression == 3) {
      final decompressed = _decompressChannelData(
        rawChannelData,
        width,
        height,
        isPsb: isPsb,
        depth: depth,
      );
      if (decompressed == null) return null;
      return _ChannelScanlineReader._(
        raw: rawChannelData,
        width: width,
        height: height,
        bytesPerPixel: bytesPerPixel,
        depth: depth,
        compression: compression,
        fullDecompressed: decompressed,
      );
    }
    return null;
  }

  Uint8List? getScanline(int sy) {
    if (sy < 0 || sy >= height) return null;
    if (fullDecompressed != null) {
      final start = sy * rowBytes;
      if (start + rowBytes <= fullDecompressed!.length) {
        return Uint8List.sublistView(
            fullDecompressed!, start, start + rowBytes);
      }
      return null;
    }
    if (compression == 0) {
      final start = 2 + sy * rowBytes;
      if (start + rowBytes <= raw.length) {
        return Uint8List.sublistView(raw, start, start + rowBytes);
      }
      return null;
    }
    if (compression == 1) {
      if (scanlineOffsets == null || scanlineLengths == null) return null;
      if (_cachedRow != sy) {
        final off = scanlineOffsets![sy];
        final len = scanlineLengths![sy];
        if (off + len <= raw.length) {
          _cachedScanline = _decodePackBits(raw, off, len, rowBytes);
        } else {
          final rem = raw.length - off;
          _cachedScanline = rem > 0
              ? _decodePackBits(raw, off, rem, rowBytes)
              : Uint8List(rowBytes);
        }
        _cachedRow = sy;
      }
      return _cachedScanline;
    }
    return null;
  }

  int getSample(int sx, int sy) {
    final sl = getScanline(sy);
    if (sl == null) return 0;
    final bIdx = (depth == 16) ? sx * 2 : sx;
    return (bIdx < sl.length) ? sl[bIdx] : 0;
  }
}

Uint8List? _isolateStreamRenderWithLayers(_StreamRenderParams params) {
  RandomAccessFile? raf;
  try {
    final file = File(params.filePath);
    if (!file.existsSync()) return null;
    raf = file.openSync(mode: FileMode.read);
    final fileLen = raf.lengthSync();
    if (fileLen < 34) return null;

    // 1. Read 26-byte header
    final header = raf.readSync(26);
    if (header.length < 26) return null;
    if (header[0] != 0x38 ||
        header[1] != 0x42 ||
        header[2] != 0x50 ||
        header[3] != 0x53) {
      return null;
    }
    final headerView = ByteData.sublistView(header);
    final version = headerView.getUint16(4);
    if (version != 1 && version != 2) return null;
    final isPsb = version == 2;
    final depth = headerView.getUint16(22);
    final colorMode = headerView.getUint16(24);
    final docHeight = headerView.getUint32(14);
    final docWidth = headerView.getUint32(18);
    if (docWidth <= 0 || docHeight <= 0) return null;

    // 2. Color Mode Data
    final colorDataLenBytes = raf.readSync(4);
    if (colorDataLenBytes.length < 4) return null;
    final colorDataLen = ByteData.sublistView(colorDataLenBytes).getUint32(0);
    final sec3Pos = 26 + 4 + colorDataLen;
    if (sec3Pos + 4 > fileLen) return null;
    raf.setPositionSync(sec3Pos);

    // 3. Image Resources
    final resLenBytes = raf.readSync(4);
    if (resLenBytes.length < 4) return null;
    final resLen = ByteData.sublistView(resLenBytes).getUint32(0);
    final sec4Pos = sec3Pos + 4 + resLen;
    final sec4LenHeaderSize = isPsb ? 8 : 4;
    if (sec4Pos + sec4LenHeaderSize > fileLen) return null;
    raf.setPositionSync(sec4Pos);

    // 4. Section 4: Layer and Mask Information Section
    final int section4Len;
    if (isPsb) {
      final sec4LenBytes = raf.readSync(8);
      if (sec4LenBytes.length < 8) return null;
      section4Len = ByteData.sublistView(sec4LenBytes).getUint64(0);
    } else {
      final sec4LenBytes = raf.readSync(4);
      if (sec4LenBytes.length < 4) return null;
      section4Len = ByteData.sublistView(sec4LenBytes).getUint32(0);
    }
    if (section4Len <= 0) return null;

    final sec4End = raf.positionSync() + section4Len;
    if (sec4End > fileLen) return null;

    // Layer Info length
    final int layerInfoLen;
    if (isPsb) {
      if (raf.positionSync() + 8 > sec4End) return null;
      final layerLenBytes = raf.readSync(8);
      if (layerLenBytes.length < 8) return null;
      layerInfoLen = ByteData.sublistView(layerLenBytes).getUint64(0);
    } else {
      if (raf.positionSync() + 4 > sec4End) return null;
      final layerLenBytes = raf.readSync(4);
      if (layerLenBytes.length < 4) return null;
      layerInfoLen = ByteData.sublistView(layerLenBytes).getUint32(0);
    }
    if (layerInfoLen <= 0) return null;

    // Layer count (int16)
    if (raf.positionSync() + 2 > sec4End) return null;
    final countBytes = raf.readSync(2);
    if (countBytes.length < 2) return null;
    final count = ByteData.sublistView(countBytes).getInt16(0);
    final layerCount = count.abs();
    if (layerCount == 0) return null;

    final layers = <_StreamLayerInfo>[];

    for (var i = 0; i < layerCount; i++) {
      if (raf.positionSync() + 16 > fileLen) break;
      final rectBytes = raf.readSync(16);
      if (rectBytes.length < 16) break;
      final rectView = ByteData.sublistView(rectBytes);
      final top = rectView.getInt32(0);
      final left = rectView.getInt32(4);
      final bottom = rectView.getInt32(8);
      final right = rectView.getInt32(12);

      if (raf.positionSync() + 2 > fileLen) break;
      final chanCountBytes = raf.readSync(2);
      if (chanCountBytes.length < 2) break;
      final numChannels = ByteData.sublistView(chanCountBytes).getUint16(0);

      final channelEntrySize = isPsb ? 10 : 6;
      final totalChanInfoLen = numChannels * channelEntrySize;
      if (raf.positionSync() + totalChanInfoLen > fileLen) break;
      final chanInfoBytes = raf.readSync(totalChanInfoLen);
      if (chanInfoBytes.length < totalChanInfoLen) break;
      final chanInfoView = ByteData.sublistView(chanInfoBytes);

      final channels = <_LayerChannelRecord>[];
      for (var c = 0; c < numChannels; c++) {
        final chId = chanInfoView.getInt16(c * channelEntrySize);
        final chLen = isPsb
            ? chanInfoView.getUint64(c * channelEntrySize + 2)
            : chanInfoView.getUint32(c * channelEntrySize + 2);
        channels.add(_LayerChannelRecord(id: chId, length: chLen));
      }

      if (raf.positionSync() + 12 > fileLen) break;
      final blendBytes = raf.readSync(12);
      if (blendBytes.length < 12) break;
      final opacity = blendBytes[8];
      final clipping = blendBytes[9];
      final isClipped = clipping == 1;
      final flags = blendBytes[10];
      final isVisible = (flags & 2) == 0;

      if (raf.positionSync() + 4 > fileLen) break;
      final extraLenBytes = raf.readSync(4);
      if (extraLenBytes.length < 4) break;
      final extraLen = ByteData.sublistView(extraLenBytes).getUint32(0);
      final extraEnd = raf.positionSync() + extraLen;
      if (extraEnd > fileLen) break;

      bool isFolder = false;
      bool isClosingDelimiter = false;
      String? pascalName;
      String? unicodeName;
      if (extraLen > 0) {
        if (raf.positionSync() + 4 <= extraEnd) {
          final maskLen = ByteData.sublistView(raf.readSync(4)).getUint32(0);
          final nextPos = raf.positionSync() + maskLen;
          raf.setPositionSync(nextPos <= extraEnd ? nextPos : extraEnd);
        }
        if (raf.positionSync() + 4 <= extraEnd) {
          final blendLen = ByteData.sublistView(raf.readSync(4)).getUint32(0);
          final nextPos = raf.positionSync() + blendLen;
          raf.setPositionSync(nextPos <= extraEnd ? nextPos : extraEnd);
        }
        if (raf.positionSync() + 1 <= extraEnd) {
          final nameLen = raf.readSync(1)[0];
          if (raf.positionSync() + nameLen <= extraEnd) {
            final nameBytes = raf.readSync(nameLen);
            pascalName = ascii.decode(nameBytes, allowInvalid: true);
            final padding = (4 - ((nameLen + 1) % 4)) % 4;
            final nextPos = raf.positionSync() + padding;
            raf.setPositionSync(nextPos <= extraEnd ? nextPos : extraEnd);
          }
        }
        while (raf.positionSync() + 12 <= extraEnd) {
          final tagHead = raf.readSync(12);
          if (tagHead.length < 12) break;
          final headView = ByteData.sublistView(tagHead);
          final sig = headView.getUint32(0);
          if (sig != 0x3842494D && sig != 0x38423634) break;
          final tagKey =
              ascii.decode(tagHead.sublist(4, 8), allowInvalid: true);
          final tagLen = headView.getUint32(8);
          final tagDataStart = raf.positionSync();
          final nextTagPos = tagDataStart + tagLen + (tagLen % 2);
          if (nextTagPos > extraEnd) break;

          if (tagKey == 'lsct' || tagKey == 'lsdk') {
            if (tagLen >= 4) {
              final typeBytes = raf.readSync(4);
              if (typeBytes.length == 4) {
                final type = ByteData.sublistView(typeBytes).getUint32(0);
                if (type == 1 || type == 2) {
                  isFolder = true;
                } else if (type == 3) {
                  isClosingDelimiter = true;
                }
              }
            }
          } else if (tagKey == 'luni') {
            if (tagLen >= 4) {
              final countBytes = raf.readSync(4);
              if (countBytes.length == 4) {
                final charCount = ByteData.sublistView(countBytes).getUint32(0);
                final byteCount = charCount * 2;
                if (byteCount > 0 && byteCount <= tagLen - 4) {
                  final uniBytes = raf.readSync(byteCount);
                  final codeUnits = <int>[];
                  for (var c = 0;
                      c < charCount && (c * 2 + 1) < uniBytes.length;
                      c++) {
                    final ch = (uniBytes[c * 2] << 8) | uniBytes[c * 2 + 1];
                    if (ch != 0) codeUnits.add(ch);
                  }
                  if (codeUnits.isNotEmpty) {
                    unicodeName = String.fromCharCodes(codeUnits);
                  }
                }
              }
            }
          }
          raf.setPositionSync(nextTagPos);
        }
        raf.setPositionSync(extraEnd);
      }

      final effectiveName =
          (unicodeName != null && unicodeName.trim().isNotEmpty)
              ? unicodeName.trim()
              : (pascalName != null && pascalName.trim().isNotEmpty
                  ? pascalName.trim()
                  : 'Layer ${i + 1}');

      if (effectiveName == '</Layer group>' ||
          effectiveName == '</Layer set>') {
        isClosingDelimiter = true;
      }

      layers.add(_StreamLayerInfo(
        index: i,
        name: effectiveName,
        top: top,
        left: left,
        bottom: bottom,
        right: right,
        opacity: opacity,
        isVisible: isVisible,
        isFolder: isFolder,
        isClosingDelimiter: isClosingDelimiter,
        isClipped: isClipped,
        channels: channels,
      ));
    }

    if (layers.isEmpty) return null;

    int lastFolderIdx = -1;
    int lastDelimiterIdx = -1;
    for (final l in layers) {
      if (l.isFolder) lastFolderIdx = l.index;
      if (l.isClosingDelimiter) lastDelimiterIdx = l.index;
    }
    final bool isStandardPsOrder = lastDelimiterIdx == -1 ||
        lastFolderIdx == -1 ||
        lastFolderIdx > lastDelimiterIdx;

    final folderStack = <int>[];
    final parentMap = <int, int>{};

    if (isStandardPsOrder) {
      for (var idx = layers.length - 1; idx >= 0; idx--) {
        final l = layers[idx];
        if (l.isClosingDelimiter ||
            l.name == '</Layer group>' ||
            l.name == '</Layer set>') {
          if (folderStack.isNotEmpty) folderStack.removeLast();
          continue;
        }
        final pIndex = folderStack.isNotEmpty ? folderStack.last : null;
        l.parentIndex = pIndex;
        if (pIndex != null) {
          parentMap[l.index] = pIndex;
        }
        if (l.isFolder) {
          folderStack.add(l.index);
        }
      }
    } else {
      for (var idx = 0; idx < layers.length; idx++) {
        final l = layers[idx];
        if (l.isClosingDelimiter ||
            l.name == '</Layer group>' ||
            l.name == '</Layer set>') {
          if (folderStack.isNotEmpty) folderStack.removeLast();
          continue;
        }
        final pIndex = folderStack.isNotEmpty ? folderStack.last : null;
        l.parentIndex = pIndex;
        if (pIndex != null) {
          parentMap[l.index] = pIndex;
        }
        if (l.isFolder) {
          folderStack.add(l.index);
        }
      }
    }

    final clippingBaseMap = <int, int>{};
    int? currentBaseIndex;
    for (final layer in layers) {
      if (layer.isFolder || layer.isClosingDelimiter) {
        currentBaseIndex = null;
        continue;
      }
      if (layer.isClipped && currentBaseIndex != null) {
        clippingBaseMap[layer.index] = currentBaseIndex;
      } else {
        currentBaseIndex = layer.index;
      }
    }

    bool isAncestorHidden(int? pIndex) {
      var curr = pIndex;
      while (curr != null) {
        if (params.hiddenLayerIndices.contains(curr)) return true;
        curr = parentMap[curr];
      }
      return false;
    }

    // Calculate absolute file offsets for every channel data block
    int currentOffset = raf.positionSync();
    for (var lIdx = 0; lIdx < layers.length; lIdx++) {
      final layer = layers[lIdx];
      for (var cIdx = 0; cIdx < layer.channels.length; cIdx++) {
        final ch = layer.channels[cIdx];
        ch.fileOffset = currentOffset;
        currentOffset += ch.length;
        final isLast =
            (lIdx == layers.length - 1) && (cIdx == layer.channels.length - 1);
        if (!isLast && currentOffset + 2 <= fileLen) {
          final nextLayer =
              (cIdx < layer.channels.length - 1) ? layer : layers[lIdx + 1];
          final nextCh = (cIdx < layer.channels.length - 1)
              ? layer.channels[cIdx + 1]
              : layers[lIdx + 1].channels.first;
          final sampleBytes = (depth == 16) ? 2 : 1;
          final expectedRawLen =
              2 + nextLayer.width * nextLayer.height * sampleBytes;

          raf.setPositionSync(currentOffset);
          final probe = raf.readSync(2);
          if (probe.length == 2) {
            final comp = (probe[0] << 8) | probe[1];
            if ((comp == 0 && nextCh.length != expectedRawLen) ||
                probe[0] != 0 ||
                probe[1] > 3) {
              if (currentOffset + 3 <= fileLen) {
                raf.setPositionSync(currentOffset + 1);
                final probePad = raf.readSync(2);
                if (probePad.length == 2 &&
                    probePad[0] == 0 &&
                    probePad[1] <= 3) {
                  currentOffset += 1;
                }
              }
            }
          }
        }
      }
    }

    // Initialize document canvas
    final maxDim = params.maxDimension;
    final double scale = maxDim > 0 && max(docWidth, docHeight) > maxDim
        ? maxDim / max(docWidth, docHeight)
        : 1.0;
    final canvasW = max(1, (docWidth * scale).round());
    final canvasH = max(1, (docHeight * scale).round());
    final canvas = img.Image(width: canvasW, height: canvasH, numChannels: 4);
    img.fill(canvas, color: img.ColorRgba8(255, 255, 255, 255));

    int renderedLayerCount = 0;
    int visibleRasterLayers = 0;

    // Render layers from bottom to top (0 .. layerCount - 1)
    for (final layer in layers) {
      if (params.hiddenLayerIndices.contains(layer.index)) continue;
      if (layer.parentIndex != null &&
          (params.hiddenLayerIndices.contains(layer.parentIndex) ||
              isAncestorHidden(layer.parentIndex))) {
        continue;
      }
      if (layer.isClipped) {
        final baseIndex = clippingBaseMap[layer.index];
        if (baseIndex != null &&
            (params.hiddenLayerIndices.contains(baseIndex) ||
                (layers[baseIndex].parentIndex != null &&
                    (params.hiddenLayerIndices
                            .contains(layers[baseIndex].parentIndex) ||
                        isAncestorHidden(layers[baseIndex].parentIndex))))) {
          continue;
        }
      }
      if (layer.isFolder || layer.isClosingDelimiter) continue;
      if (layer.width <= 0 || layer.height <= 0) continue;
      if (layer.opacity <= 0) continue;

      visibleRasterLayers++;

      try {
        final readers = <int, _ChannelScanlineReader>{};
        for (final ch in layer.channels) {
          if (ch.length <= 0) continue;
          if (ch.fileOffset + ch.length > fileLen) continue;

          raf.setPositionSync(ch.fileOffset);
          final rawData = raf.readSync(ch.length);
          if (rawData.length < ch.length) continue;

          final reader = _ChannelScanlineReader.create(
            rawData,
            layer.width,
            layer.height,
            isPsb: isPsb,
            depth: depth,
          );
          if (reader != null) {
            readers[ch.id] = reader;
          }
        }

        final r0 = readers[0];
        final r1 = readers[1];
        final r2 = readers[2];
        final r3 = readers[3];
        final rAlpha = readers[-1] ?? readers[-2];

        // Skip mask-only or adjustment layers in color modes
        if (colorMode != 1 &&
            r0 == null &&
            r1 == null &&
            r2 == null &&
            r3 == null) {
          continue;
        }
        if (r0 == null &&
            r1 == null &&
            r2 == null &&
            r3 == null &&
            rAlpha == null) {
          continue;
        }

        final startDstX = (layer.left * scale).round();
        final startDstY = (layer.top * scale).round();
        final endDstX = ((layer.left + layer.width) * scale).round();
        final endDstY = ((layer.top + layer.height) * scale).round();
        final targetW = max(1, endDstX - startDstX);
        final targetH = max(1, endDstY - startDstY);

        final minCy = max(0, startDstY);
        final maxCy = min(canvasH, endDstY);
        final minCx = max(0, startDstX);
        final maxCx = min(canvasW, endDstX);
        if (minCx >= maxCx || minCy >= maxCy) continue;

        final layerW = layer.width;
        final layerH = layer.height;
        final layerOpacity = layer.opacity.clamp(0, 255);

        for (var cy = minCy; cy < maxCy; cy++) {
          final ty = cy - startDstY;
          final sy = (ty * layerH ~/ targetH).clamp(0, layerH - 1);

          final rScan = r0?.getScanline(sy);
          final gScan = r1?.getScanline(sy) ?? rScan;
          final bScan = r2?.getScanline(sy) ?? rScan;
          final kScan = r3?.getScanline(sy);
          final aScan = rAlpha?.getScanline(sy);

          for (var cx = minCx; cx < maxCx; cx++) {
            final tx = cx - startDstX;
            final sx = (tx * layerW ~/ targetW).clamp(0, layerW - 1);
            final sIdx = (depth == 16) ? sx * 2 : sx;

            int r = 0, g = 0, b = 0, a = 255;
            if (colorMode == 4) {
              // CMYK
              final c =
                  (rScan != null && sIdx < rScan.length) ? rScan[sIdx] : 0;
              final m =
                  (gScan != null && sIdx < gScan.length) ? gScan[sIdx] : 0;
              final y =
                  (bScan != null && sIdx < bScan.length) ? bScan[sIdx] : 0;
              final k =
                  (kScan != null && sIdx < kScan.length) ? kScan[sIdx] : 0;
              r = ((255 - c) * (255 - k)) ~/ 255;
              g = ((255 - m) * (255 - k)) ~/ 255;
              b = ((255 - y) * (255 - k)) ~/ 255;
            } else if (colorMode == 1) {
              // Grayscale
              final gray =
                  (rScan != null && sIdx < rScan.length) ? rScan[sIdx] : 0;
              r = gray;
              g = gray;
              b = gray;
            } else {
              // RGB
              r = (rScan != null && sIdx < rScan.length) ? rScan[sIdx] : 0;
              g = (gScan != null && sIdx < gScan.length) ? gScan[sIdx] : r;
              b = (bScan != null && sIdx < bScan.length) ? bScan[sIdx] : r;
            }

            if (aScan != null && sIdx < aScan.length) {
              a = aScan[sIdx];
            }

            final effA = (a * layerOpacity) ~/ 255;
            if (effA <= 0) continue;

            if (effA >= 255) {
              canvas.setPixelRgba(cx, cy, r, g, b, 255);
            } else {
              final cp = canvas.getPixel(cx, cy);
              final da = cp.a.toInt();
              final invSa = 255 - effA;
              final outA = effA + (da * invSa ~/ 255);
              if (outA > 0) {
                final outR =
                    ((r * effA) + (cp.r.toInt() * da * invSa ~/ 255)) ~/ outA;
                final outG =
                    ((g * effA) + (cp.g.toInt() * da * invSa ~/ 255)) ~/ outA;
                final outB =
                    ((b * effA) + (cp.b.toInt() * da * invSa ~/ 255)) ~/ outA;
                canvas.setPixelRgba(
                  cx,
                  cy,
                  outR.clamp(0, 255),
                  outG.clamp(0, 255),
                  outB.clamp(0, 255),
                  outA.clamp(0, 255),
                );
              }
            }
          }
        }
        renderedLayerCount++;
      } catch (layerErr) {
        debugPrint(
            '[PsdService] stream render error on layer ${layer.index}: $layerErr');
      }
    }

    if (renderedLayerCount == 0 && visibleRasterLayers > 0) {
      return null;
    }

    return Uint8List.fromList(img.encodeJpg(canvas, quality: 90));
  } catch (e) {
    debugPrint('[PsdService] _isolateStreamRenderWithLayers error: $e');
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}

@visibleForTesting
Uint8List decodePackBits(
  Uint8List src,
  int srcOffset,
  int srcLength,
  int expectedLength,
) =>
    _decodePackBits(src, srcOffset, srcLength, expectedLength);

@visibleForTesting
Uint8List? decompressChannelData(
  Uint8List rawChannelData,
  int width,
  int height, {
  bool isPsb = false,
  int depth = 8,
}) =>
    _decompressChannelData(rawChannelData, width, height,
        isPsb: isPsb, depth: depth);

@visibleForTesting
void compositeLayer(
  img.Image dst,
  img.Image src,
  int dstX,
  int dstY,
  int opacity,
) =>
    _compositeLayer(dst, src, dstX, dstY, opacity);

class _ExtractThumbParams {
  final String filePath;
  final int maxThumbDim;
  const _ExtractThumbParams(this.filePath, this.maxThumbDim);
}

Map<int, Uint8List>? _isolateExtractLayerThumbnails(
    _ExtractThumbParams params) {
  RandomAccessFile? raf;
  try {
    final file = File(params.filePath);
    if (!file.existsSync()) return null;
    raf = file.openSync(mode: FileMode.read);
    final fileLen = raf.lengthSync();
    if (fileLen < 34) return null;

    final header = raf.readSync(26);
    if (header.length < 26) return null;
    if (header[0] != 0x38 ||
        header[1] != 0x42 ||
        header[2] != 0x50 ||
        header[3] != 0x53) {
      return null;
    }
    final headerView = ByteData.sublistView(header);
    final version = headerView.getUint16(4);
    if (version != 1 && version != 2) return null;
    final isPsb = version == 2;
    final depth = headerView.getUint16(22);
    final colorMode = headerView.getUint16(24);

    final colorDataLenBytes = raf.readSync(4);
    if (colorDataLenBytes.length < 4) return null;
    final colorDataLen = ByteData.sublistView(colorDataLenBytes).getUint32(0);
    final sec3Pos = 26 + 4 + colorDataLen;
    if (sec3Pos + 4 > fileLen) return null;
    raf.setPositionSync(sec3Pos);

    final resLenBytes = raf.readSync(4);
    if (resLenBytes.length < 4) return null;
    final resLen = ByteData.sublistView(resLenBytes).getUint32(0);
    final sec4Pos = sec3Pos + 4 + resLen;
    final sec4LenHeaderSize = isPsb ? 8 : 4;
    if (sec4Pos + sec4LenHeaderSize > fileLen) return null;
    raf.setPositionSync(sec4Pos);

    final int section4Len;
    if (isPsb) {
      final sec4LenBytes = raf.readSync(8);
      if (sec4LenBytes.length < 8) return null;
      section4Len = ByteData.sublistView(sec4LenBytes).getUint64(0);
    } else {
      final sec4LenBytes = raf.readSync(4);
      if (sec4LenBytes.length < 4) return null;
      section4Len = ByteData.sublistView(sec4LenBytes).getUint32(0);
    }
    if (section4Len <= 0) return null;

    final sec4End = raf.positionSync() + section4Len;
    if (sec4End > fileLen) return null;

    final int layerInfoLen;
    if (isPsb) {
      if (raf.positionSync() + 8 > sec4End) return null;
      final layerLenBytes = raf.readSync(8);
      if (layerLenBytes.length < 8) return null;
      layerInfoLen = ByteData.sublistView(layerLenBytes).getUint64(0);
    } else {
      if (raf.positionSync() + 4 > sec4End) return null;
      final layerLenBytes = raf.readSync(4);
      if (layerLenBytes.length < 4) return null;
      layerInfoLen = ByteData.sublistView(layerLenBytes).getUint32(0);
    }
    if (layerInfoLen <= 0) return null;

    if (raf.positionSync() + 2 > sec4End) return null;
    final countBytes = raf.readSync(2);
    if (countBytes.length < 2) return null;
    final count = ByteData.sublistView(countBytes).getInt16(0);
    final layerCount = count.abs();
    if (layerCount == 0) return null;

    final layers = <_StreamLayerInfo>[];

    for (var i = 0; i < layerCount; i++) {
      if (raf.positionSync() + 16 > fileLen) break;
      final rectBytes = raf.readSync(16);
      if (rectBytes.length < 16) break;
      final rectView = ByteData.sublistView(rectBytes);
      final top = rectView.getInt32(0);
      final left = rectView.getInt32(4);
      final bottom = rectView.getInt32(8);
      final right = rectView.getInt32(12);

      if (raf.positionSync() + 2 > fileLen) break;
      final chanCountBytes = raf.readSync(2);
      if (chanCountBytes.length < 2) break;
      final numChannels = ByteData.sublistView(chanCountBytes).getUint16(0);

      final channelEntrySize = isPsb ? 10 : 6;
      final totalChanInfoLen = numChannels * channelEntrySize;
      if (raf.positionSync() + totalChanInfoLen > fileLen) break;
      final chanInfoBytes = raf.readSync(totalChanInfoLen);
      if (chanInfoBytes.length < totalChanInfoLen) break;
      final chanInfoView = ByteData.sublistView(chanInfoBytes);

      final channels = <_LayerChannelRecord>[];
      for (var c = 0; c < numChannels; c++) {
        final chId = chanInfoView.getInt16(c * channelEntrySize);
        final chLen = isPsb
            ? chanInfoView.getUint64(c * channelEntrySize + 2)
            : chanInfoView.getUint32(c * channelEntrySize + 2);
        channels.add(_LayerChannelRecord(id: chId, length: chLen));
      }

      if (raf.positionSync() + 12 > fileLen) break;
      final blendBytes = raf.readSync(12);
      if (blendBytes.length < 12) break;
      final opacity = blendBytes[8];
      final flags = blendBytes[10];
      final isVisible = (flags & 2) == 0;

      if (raf.positionSync() + 4 > fileLen) break;
      final extraLenBytes = raf.readSync(4);
      if (extraLenBytes.length < 4) break;
      final extraLen = ByteData.sublistView(extraLenBytes).getUint32(0);
      final extraEnd = raf.positionSync() + extraLen;
      if (extraEnd > fileLen) break;
      raf.setPositionSync(extraEnd);

      layers.add(_StreamLayerInfo(
        index: i,
        top: top,
        left: left,
        bottom: bottom,
        right: right,
        opacity: opacity,
        isVisible: isVisible,
        channels: channels,
      ));
    }

    if (layers.isEmpty) return {};

    int currentOffset = raf.positionSync();
    for (var lIdx = 0; lIdx < layers.length; lIdx++) {
      final layer = layers[lIdx];
      for (var cIdx = 0; cIdx < layer.channels.length; cIdx++) {
        final ch = layer.channels[cIdx];
        ch.fileOffset = currentOffset;
        currentOffset += ch.length;
        final isLast =
            (lIdx == layers.length - 1) && (cIdx == layer.channels.length - 1);
        if (!isLast && currentOffset + 2 <= fileLen) {
          final nextLayer =
              (cIdx < layer.channels.length - 1) ? layer : layers[lIdx + 1];
          final nextCh = (cIdx < layer.channels.length - 1)
              ? layer.channels[cIdx + 1]
              : layers[lIdx + 1].channels.first;
          final sampleBytes = (depth == 16) ? 2 : 1;
          final expectedRawLen =
              2 + nextLayer.width * nextLayer.height * sampleBytes;

          raf.setPositionSync(currentOffset);
          final probe = raf.readSync(2);
          if (probe.length == 2) {
            final comp = (probe[0] << 8) | probe[1];
            if ((comp == 0 && nextCh.length != expectedRawLen) ||
                probe[0] != 0 ||
                probe[1] > 3) {
              if (currentOffset + 3 <= fileLen) {
                raf.setPositionSync(currentOffset + 1);
                final probePad = raf.readSync(2);
                if (probePad.length == 2 &&
                    probePad[0] == 0 &&
                    probePad[1] <= 3) {
                  currentOffset += 1;
                }
              }
            }
          }
        }
      }
    }

    final results = <int, Uint8List>{};

    for (final layer in layers) {
      if (layer.width <= 0 || layer.height <= 0 || layer.channels.isEmpty) {
        continue;
      }

      final readers = <int, _ChannelScanlineReader>{};
      for (final ch in layer.channels) {
        if (ch.id < -2 || ch.id > 3) continue;
        if (ch.length <= 0) continue;
        if (ch.fileOffset + ch.length > fileLen) continue;

        raf.setPositionSync(ch.fileOffset);
        final rawData = raf.readSync(ch.length);
        if (rawData.length < ch.length) continue;

        final reader = _ChannelScanlineReader.create(
          rawData,
          layer.width,
          layer.height,
          isPsb: isPsb,
          depth: depth,
        );
        if (reader != null) {
          readers[ch.id] = reader;
        }
      }

      final r0 = readers[0];
      final r1 = readers[1];
      final r2 = readers[2];
      final r3 = readers[3];
      final rAlpha = readers[-1] ?? readers[-2];

      if (r0 == null &&
          r1 == null &&
          r2 == null &&
          r3 == null &&
          rAlpha == null) {
        continue;
      }

      final maxDim = params.maxThumbDim;
      int thumbW, thumbH;
      if (layer.width >= layer.height) {
        thumbW = min(maxDim, layer.width);
        thumbH = max(1, (thumbW * layer.height / layer.width).round());
      } else {
        thumbH = min(maxDim, layer.height);
        thumbW = max(1, (thumbH * layer.width / layer.height).round());
      }

      final stepX = layer.width / thumbW;
      final stepY = layer.height / thumbH;
      final thumbImg = img.Image(width: thumbW, height: thumbH, numChannels: 4);

      final opacity = layer.opacity;

      for (var ty = 0; ty < thumbH; ty++) {
        final sy = (ty * stepY).toInt().clamp(0, layer.height - 1);
        for (var tx = 0; tx < thumbW; tx++) {
          final sx = (tx * stepX).toInt().clamp(0, layer.width - 1);

          int r, g, b, a;
          if (colorMode == 4) {
            // CMYK
            final c = r0?.getSample(sx, sy) ?? 0;
            final m = r1?.getSample(sx, sy) ?? 0;
            final y = r2?.getSample(sx, sy) ?? 0;
            final k = r3?.getSample(sx, sy) ?? 0;
            r = ((255 - c) * (255 - k)) ~/ 255;
            g = ((255 - m) * (255 - k)) ~/ 255;
            b = ((255 - y) * (255 - k)) ~/ 255;
          } else if (colorMode == 1) {
            // Grayscale
            final gray = r0?.getSample(sx, sy) ?? 0;
            r = gray;
            g = gray;
            b = gray;
          } else if (r0 == null && r1 == null && r2 == null) {
            // Mask-only / alpha-only layer
            final mask = rAlpha?.getSample(sx, sy) ?? 0;
            r = mask;
            g = mask;
            b = mask;
          } else {
            // RGB
            r = r0?.getSample(sx, sy) ?? 0;
            g = r1 != null
                ? r1.getSample(sx, sy)
                : (r0?.getSample(sx, sy) ?? 0);
            b = r2 != null
                ? r2.getSample(sx, sy)
                : (r0?.getSample(sx, sy) ?? 0);
          }

          if (r0 == null &&
              r1 == null &&
              r2 == null &&
              r3 == null &&
              rAlpha != null) {
            a = (255 * opacity) ~/ 255;
          } else {
            final rawA = (rAlpha != null) ? rAlpha.getSample(sx, sy) : 255;
            a = (rawA * opacity) ~/ 255;
          }

          thumbImg.setPixelRgba(tx, ty, r, g, b, a);
        }
      }

      final pngBytes = Uint8List.fromList(img.encodePng(thumbImg));
      results[layer.index] = pngBytes;
    }

    return results;
  } catch (e) {
    debugPrint('[PsdService] _isolateExtractLayerThumbnails error: $e');
    return null;
  } finally {
    try {
      raf?.closeSync();
    } catch (_) {}
  }
}
