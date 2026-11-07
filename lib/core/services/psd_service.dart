// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

/// Representation of an individual Adobe Photoshop (.psd) layer.
class PsdLayerInfo {
  final int index;
  final String name;
  final bool isVisible;
  final int opacity; // 0 - 255
  final bool isFolder;

  const PsdLayerInfo({
    required this.index,
    required this.name,
    required this.isVisible,
    required this.opacity,
    required this.isFolder,
  });

  PsdLayerInfo copyWith({
    int? index,
    String? name,
    bool? isVisible,
    int? opacity,
    bool? isFolder,
  }) {
    return PsdLayerInfo(
      index: index ?? this.index,
      name: name ?? this.name,
      isVisible: isVisible ?? this.isVisible,
      opacity: opacity ?? this.opacity,
      isFolder: isFolder ?? this.isFolder,
    );
  }

  @override
  String toString() =>
      'PsdLayerInfo(index: $index, name: $name, isVisible: $isVisible, opacity: $opacity, isFolder: $isFolder)';
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
class PsdService {
  PsdService._();
  static final PsdService instance = PsdService._();
  final _AsyncGate _isolateGate = _AsyncGate(1);

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

  /// Decodes a fast thumbnail of the PSD file in an isolate.
  Future<Uint8List?> decodeThumbnail(
    String filePath, {
    int maxDimension = 512,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final embedded = await extractEmbeddedThumbnail(filePath);
      if (embedded != null && embedded.isNotEmpty) {
        return embedded;
      }

      return await _isolateGate.run(() => compute(
            _isolateDecodeThumbnail,
            _DecodeThumbnailParams(filePath, maxDimension),
          ));
    } catch (e) {
      debugPrint('[PsdService] decodeThumbnail error for $filePath: $e');
      return null;
    }
  }

  /// Extracts layer metadata from a PSD file in an isolate.
  Future<List<PsdLayerInfo>> getLayers(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return [];

      return await compute(_isolateGetLayers, filePath);
    } catch (e) {
      debugPrint('[PsdService] getLayers error for $filePath: $e');
      return [];
    }
  }

  /// Renders the PSD document with custom layer visibility in an isolate.
  Future<Uint8List?> renderWithLayers(
    String filePath, {
    required Set<int> hiddenLayerIndices,
    int maxDimension = 2048,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final result = await compute(
        _isolateRenderWithLayers,
        _RenderWithLayersParams(
          filePath: filePath,
          hiddenLayerIndices: hiddenLayerIndices,
          maxDimension: maxDimension,
        ),
      );

      if (result == null && hiddenLayerIndices.isEmpty) {
        return await decodeThumbnail(filePath, maxDimension: maxDimension);
      }

      return result;
    } catch (e) {
      debugPrint('[PsdService] renderWithLayers error for $filePath: $e');
      if (hiddenLayerIndices.isEmpty) {
        return await decodeThumbnail(filePath, maxDimension: maxDimension);
      }
      return null;
    }
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

    if (params.hiddenLayerIndices.isEmpty && psd.mergedImage != null) {
      rendered = psd.mergedImage;
    } else {
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
      }

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
            if (!layer.isVisible()) continue;
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
    }

    rendered ??= psd.mergedImage ?? decoder.decode(bytes);
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
