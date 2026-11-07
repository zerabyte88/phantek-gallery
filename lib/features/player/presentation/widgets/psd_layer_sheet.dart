// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/services/psd_service.dart';

/// Modal bottom sheet for viewing and toggling Photoshop PSD layers.
class PsdLayerSheet extends StatefulWidget {
  const PsdLayerSheet({
    super.key,
    required this.layers,
    required this.hiddenIndices,
    required this.onVisibilityChanged,
    this.filePath,
    this.initialThumbnails,
  });

  final List<PsdLayerInfo> layers;
  final Set<int> hiddenIndices;
  final ValueChanged<Set<int>> onVisibilityChanged;
  final String? filePath;
  final Map<int, Uint8List>? initialThumbnails;

  static Future<void> show({
    required BuildContext context,
    required List<PsdLayerInfo> layers,
    required Set<int> hiddenIndices,
    required ValueChanged<Set<int>> onVisibilityChanged,
    String? filePath,
    Map<int, Uint8List>? initialThumbnails,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.black26,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PsdLayerSheet(
        layers: layers,
        hiddenIndices: hiddenIndices,
        onVisibilityChanged: onVisibilityChanged,
        filePath: filePath,
        initialThumbnails: initialThumbnails,
      ),
    );
  }

  @override
  State<PsdLayerSheet> createState() => _PsdLayerSheetState();
}

class _PsdLayerSheetState extends State<PsdLayerSheet> {
  late Set<int> _hidden;
  late Map<int, Uint8List> _thumbnails;
  final Set<int> _collapsedFolders = <int>{};

  @override
  void initState() {
    super.initState();
    _hidden = Set<int>.from(widget.hiddenIndices);
    _thumbnails = widget.initialThumbnails != null
        ? Map<int, Uint8List>.from(widget.initialThumbnails!)
        : {};

    if (widget.filePath != null && _thumbnails.isEmpty) {
      PsdService.instance.getLayerThumbnails(widget.filePath!).then((thumbs) {
        if (mounted) {
          setState(() {
            _thumbnails = thumbs;
          });
        }
      });
    }
  }

  Set<int> _getDescendantIndices(int folderIndex) {
    final descendants = <int>{};
    void collect(int pIndex) {
      for (final l in widget.layers) {
        if (l.parentIndex == pIndex) {
          descendants.add(l.index);
          collect(l.index);
        }
      }
    }
    collect(folderIndex);
    return descendants;
  }

  void _toggleLayer(PsdLayerInfo layer) {
    setState(() {
      if (layer.isFolder) {
        final descendants = _getDescendantIndices(layer.index);
        final isCurrentlyHidden = _hidden.contains(layer.index);
        if (isCurrentlyHidden) {
          _hidden.remove(layer.index);
          _hidden.removeAll(descendants);
        } else {
          _hidden.add(layer.index);
          _hidden.addAll(descendants);
        }
      } else {
        if (_hidden.contains(layer.index)) {
          _hidden.remove(layer.index);
        } else {
          _hidden.add(layer.index);
        }
      }
    });
    widget.onVisibilityChanged(_hidden);
  }

  void _toggleFolderCollapsed(int folderIndex) {
    setState(() {
      if (_collapsedFolders.contains(folderIndex)) {
        _collapsedFolders.remove(folderIndex);
      } else {
        _collapsedFolders.add(folderIndex);
      }
    });
  }

  void _showAll() {
    setState(() {
      _hidden.clear();
    });
    widget.onVisibilityChanged(_hidden);
  }

  void _hideAll() {
    setState(() {
      _hidden = widget.layers.map((l) => l.index).toSet();
    });
    widget.onVisibilityChanged(_hidden);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final mediaQuery = MediaQuery.of(context);
    final isLandscape = mediaQuery.orientation == Orientation.landscape;
    final sheetHeight = isLandscape
        ? (mediaQuery.size.height * 0.45).clamp(200.0, 320.0)
        : (mediaQuery.size.height * 0.35).clamp(240.0, 380.0);

    // Photoshop stacks layers bottom-to-top internally, but displays them top-to-bottom in UI
    final displayLayers = widget.layers.reversed.toList();
    final layerMap = {for (final l in widget.layers) l.index: l};

    bool isDescendantOfCollapsed(PsdLayerInfo layer) {
      var curr = layer.parentIndex;
      while (curr != null) {
        if (_collapsedFolders.contains(curr)) return true;
        final parent = layerMap[curr];
        curr = parent?.parentIndex;
      }
      return false;
    }

    final visibleLayers =
        displayLayers.where((l) => !isDescendantOfCollapsed(l)).toList();

    return Container(
      height: sheetHeight,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF16181B) : colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(
            color: colorScheme.onSurface.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle pill
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 6),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header: Title & Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Icon(
                    Icons.layers_outlined,
                    size: 20,
                    color: colorScheme.onSurface,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Photoshop layers (${widget.layers.length})',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  if (widget.layers.length > 1) ...[
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: colorScheme.primary,
                      ),
                      onPressed: _showAll,
                      child: const Text('Show all'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        foregroundColor: colorScheme.onSurfaceVariant,
                      ),
                      onPressed: _hideAll,
                      child: const Text('Hide all'),
                    ),
                  ],
                ],
              ),
            ),

            Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.onSurface.withValues(alpha: 0.06),
            ),

            // Content
            if (widget.layers.isEmpty)
              Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
                child: Center(
                  child: Text(
                    'This file has only a single base layer',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: visibleLayers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 48,
                    color: colorScheme.onSurface.withValues(alpha: 0.04),
                  ),
                  itemBuilder: (context, idx) {
                    final layer = visibleLayers[idx];
                    return _buildLayerRow(
                      context,
                      layer,
                      colorScheme,
                      theme,
                      isDark,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerRow(
    BuildContext context,
    PsdLayerInfo layer,
    ColorScheme colorScheme,
    ThemeData theme,
    bool isDark,
  ) {
    final isHidden = _hidden.contains(layer.index);
    final isVisible = !isHidden;

    return InkWell(
      onTap: () {
        if (layer.isFolder) {
          _toggleFolderCollapsed(layer.index);
        } else {
          _toggleLayer(layer);
        }
      },
      child: SizedBox(
        height: 50,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: [
              // 1. Eye toggle icon on left
              IconButton(
                iconSize: 22,
                splashRadius: 20,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                icon: Icon(
                  isVisible
                      ? Icons.visibility_rounded
                      : Icons.visibility_off_outlined,
                  color: isVisible
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.38),
                ),
                onPressed: () => _toggleLayer(layer),
                tooltip: isVisible ? 'Hide layer' : 'Show layer',
              ),
              const SizedBox(width: 2),

              // Content row dimmed if hidden
              Expanded(
                child: Opacity(
                  opacity: isVisible ? 1.0 : 0.38,
                  child: Row(
                    children: [
                      // 2. Folder depth indent
                      if (layer.depth > 0)
                        SizedBox(width: layer.depth * 20.0),

                      // 3. If folder: Chevron
                      if (layer.isFolder) ...[
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _toggleFolderCollapsed(layer.index),
                          child: Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(
                              _collapsedFolders.contains(layer.index)
                                  ? Icons.chevron_right_rounded
                                  : Icons.expand_more_rounded,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],

                      // 4. If clipped: Elbow arrow pointing down/right
                      if (layer.isClipped) ...[
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Icon(
                            Icons.subdirectory_arrow_right_rounded,
                            size: 16,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],

                      // 5. Thumbnail box (38x38)
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.15),
                            width: 0.8,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            CustomPaint(
                              painter: _CheckerboardPainter(
                                lightColor: isDark
                                    ? const Color(0xFF2C2C2C)
                                    : const Color(0xFFEEEEEE),
                                darkColor: isDark
                                    ? const Color(0xFF1E1E1E)
                                    : const Color(0xFFDCDCDC),
                                squareSize: 4.0,
                              ),
                            ),
                            if (layer.isFolder)
                              Center(
                                child: Icon(
                                  Icons.folder_rounded,
                                  color: Colors.amber[700],
                                  size: 20,
                                ),
                              )
                            else if (_thumbnails[layer.index] != null)
                              Image.memory(
                                _thumbnails[layer.index]!,
                                fit: BoxFit.contain,
                                filterQuality: FilterQuality.medium,
                              )
                            else
                              Center(
                                child: Icon(
                                  Icons.image_outlined,
                                  size: 18,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            if (layer.isClipped)
                              Positioned(
                                bottom: 1,
                                left: 1,
                                child: Container(
                                  padding: const EdgeInsets.all(1),
                                  decoration: BoxDecoration(
                                    color:
                                        Colors.black.withValues(alpha: 0.65),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                  child: const Icon(
                                    Icons.subdirectory_arrow_right_rounded,
                                    size: 9,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // 6. Title & Subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Row(
                              children: [
                                if (layer.isFolder) ...[
                                  Icon(
                                    Icons.folder_rounded,
                                    color: Colors.amber[700],
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                ],
                                Expanded(
                                  child: Text(
                                    layer.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: layer.isFolder
                                          ? FontWeight.w700
                                          : (isVisible
                                              ? FontWeight.w500
                                              : FontWeight.w400),
                                      color: isVisible
                                          ? colorScheme.onSurface
                                          : colorScheme.onSurface
                                              .withValues(alpha: 0.5),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (layer.opacity < 255) ...[
                              const SizedBox(height: 1),
                              Text(
                                'Opacity ${(layer.opacity * 100 / 255).round()}%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Checkerboard pattern painter for transparent thumbnails.
class _CheckerboardPainter extends CustomPainter {
  final Color lightColor;
  final Color darkColor;
  final double squareSize;

  const _CheckerboardPainter({
    this.lightColor = const Color(0xFFEEEEEE),
    this.darkColor = const Color(0xFFDCDCDC),
    this.squareSize = 4.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final lightPaint = Paint()..color = lightColor;
    final darkPaint = Paint()..color = darkColor;

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), lightPaint);

    final numX = (size.width / squareSize).ceil();
    final numY = (size.height / squareSize).ceil();

    for (var y = 0; y < numY; y++) {
      for (var x = 0; x < numX; x++) {
        if ((x + y) % 2 == 1) {
          canvas.drawRect(
            Rect.fromLTWH(
              x * squareSize,
              y * squareSize,
              squareSize,
              squareSize,
            ),
            darkPaint,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerboardPainter oldDelegate) =>
      oldDelegate.lightColor != lightColor ||
      oldDelegate.darkColor != darkColor ||
      oldDelegate.squareSize != squareSize;
}
