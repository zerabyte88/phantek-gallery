// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

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

/// Service for decoding, inspecting layers, and rendering Adobe Photoshop (.psd) files.
class PsdService {
  PsdService._();
  static final PsdService instance = PsdService._();

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

  /// Decodes a fast thumbnail of the PSD file in an isolate.
  Future<Uint8List?> decodeThumbnail(
    String filePath, {
    int maxDimension = 512,
  }) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      return await compute(
        _isolateDecodeThumbnail,
        _DecodeThumbnailParams(filePath, maxDimension),
      );
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

      return await compute(
        _isolateRenderWithLayers,
        _RenderWithLayersParams(
          filePath: filePath,
          hiddenLayerIndices: hiddenLayerIndices,
          maxDimension: maxDimension,
        ),
      );
    } catch (e) {
      debugPrint('[PsdService] renderWithLayers error for $filePath: $e');
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

    final decoder = img.PsdDecoder();
    if (!decoder.isValidFile(bytes)) return null;

    img.Image? image;
    final psd = decoder.decodePsd(bytes);
    if (psd != null) {
      if (psd.mergedImage != null) {
        image = psd.mergedImage;
      } else {
        image = psd.renderImage();
      }
    } else {
      image = decoder.decode(bytes);
    }

    if (image == null) return null;

    if (image.width > params.maxDimension || image.height > params.maxDimension) {
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

    final decoder = img.PsdDecoder();
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

    final decoder = img.PsdDecoder();
    final psd = decoder.decodePsd(bytes);
    if (psd == null) return null;

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

    img.Image? rendered = psd.renderImage();

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

