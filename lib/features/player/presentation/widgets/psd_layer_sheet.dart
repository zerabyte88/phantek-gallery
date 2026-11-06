// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import '../../../../core/services/psd_service.dart';

/// Modal bottom sheet for viewing and toggling Photoshop PSD layers.
class PsdLayerSheet extends StatefulWidget {
  const PsdLayerSheet({
    super.key,
    required this.layers,
    required this.hiddenIndices,
    required this.onVisibilityChanged,
  });

  final List<PsdLayerInfo> layers;
  final Set<int> hiddenIndices;
  final ValueChanged<Set<int>> onVisibilityChanged;

  static Future<void> show({
    required BuildContext context,
    required List<PsdLayerInfo> layers,
    required Set<int> hiddenIndices,
    required ValueChanged<Set<int>> onVisibilityChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PsdLayerSheet(
        layers: layers,
        hiddenIndices: hiddenIndices,
        onVisibilityChanged: onVisibilityChanged,
      ),
    );
  }

  @override
  State<PsdLayerSheet> createState() => _PsdLayerSheetState();
}

class _PsdLayerSheetState extends State<PsdLayerSheet> {
  late Set<int> _hidden;

  @override
  void initState() {
    super.initState();
    _hidden = Set<int>.from(widget.hiddenIndices);
  }

  void _toggleLayer(int index) {
    setState(() {
      if (_hidden.contains(index)) {
        _hidden.remove(index);
      } else {
        _hidden.add(index);
      }
    });
    widget.onVisibilityChanged(_hidden);
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

    // Photoshop stacks layers bottom-to-top internally, but displays them top-to-bottom in UI
    final displayLayers = widget.layers.reversed.toList();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
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
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle pill
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
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
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
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
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: displayLayers.length,
                  separatorBuilder: (_, __) => Divider(
                    height: 1,
                    thickness: 0.5,
                    indent: 56,
                    color: colorScheme.onSurface.withValues(alpha: 0.04),
                  ),
                  itemBuilder: (context, idx) {
                    final layer = displayLayers[idx];
                    final isHidden = _hidden.contains(layer.index);
                    final isVisible = !isHidden;

                    return SizedBox(
                      height: 52,
                      child: ListTile(
                        dense: true,
                        contentPadding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        leading: Icon(
                          layer.isFolder
                              ? Icons.folder_outlined
                              : Icons.image_outlined,
                          size: 20,
                          color: isVisible
                              ? colorScheme.onSurface
                              : colorScheme.onSurface.withValues(alpha: 0.38),
                        ),
                        title: Text(
                          layer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight:
                                isVisible ? FontWeight.w500 : FontWeight.w400,
                            color: isVisible
                                ? colorScheme.onSurface
                                : colorScheme.onSurface.withValues(alpha: 0.38),
                          ),
                        ),
                        subtitle: layer.opacity < 255
                            ? Text(
                                'Opacity ${(layer.opacity * 100 / 255).round()}%',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              )
                            : null,
                        trailing: IconButton(
                          iconSize: 22,
                          splashRadius: 24,
                          constraints: const BoxConstraints(
                            minWidth: 48,
                            minHeight: 48,
                          ),
                          icon: Icon(
                            isVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                            color: isVisible
                                ? colorScheme.primary
                                : colorScheme.onSurface.withValues(alpha: 0.38),
                          ),
                          onPressed: () => _toggleLayer(layer.index),
                          tooltip: isVisible ? 'Hide layer' : 'Show layer',
                        ),
                        onTap: () => _toggleLayer(layer.index),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

