import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/services/thumbnail_service.dart';
import '../../../../core/utils/media_utils.dart';

/// Single cell in the gallery grid. Shows thumbnail + video badge if selected.
class MediaGridItem extends ConsumerStatefulWidget {
  const MediaGridItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isSelecting,
    required this.showBadges,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final bool isSelected;
  final bool isSelecting;
  final bool showBadges;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  ConsumerState<MediaGridItem> createState() => _MediaGridItemState();
}

class _MediaGridItemState extends ConsumerState<MediaGridItem> {
  Future<Uint8List?>? _thumbFuture;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  @override
  void didUpdateWidget(covariant MediaGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.path != widget.item.path) {
      _initThumbnail();
    }
  }

  void _initThumbnail() {
    // If already in memory or on persistent disk cache, skip queuing
    if (ThumbnailService.instance.getMemoryThumbnail(widget.item.id) != null ||
        ThumbnailService.instance.getCachedFile(widget.item.id) != null) {
      _thumbFuture = null;
      return;
    }
    _thumbFuture = ThumbnailService.instance.getThumbnail(
      widget.item.id,
      filePath: widget.item.path,
      isVideo: widget.item.isVideo,
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Icon(
        widget.item.isVideo
            ? Icons.videocam_outlined
            : Icons.image_not_supported_outlined,
        size: 28,
        color: Colors.white38,
      ),
    );
  }

  Widget _buildThumbnail(ColorScheme cs) {
    // 1. Fast in-memory lookup (0ms)
    final mem = ThumbnailService.instance.getMemoryThumbnail(widget.item.id);
    if (mem != null) {
      return Image.memory(
        mem,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    // 2. Persistent disk cache hit (Instant on cold start — skips FutureBuilder delay!)
    final diskFile = ThumbnailService.instance.getCachedFile(widget.item.id);
    if (diskFile != null) {
      return Image.file(
        diskFile,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
      );
    }

    // 3. Fallback: uncached, fetch asynchronously
    _thumbFuture ??= ThumbnailService.instance.getThumbnail(
      widget.item.id,
      filePath: widget.item.path,
      isVideo: widget.item.isVideo,
    );

    return FutureBuilder<Uint8List?>(
      future: _thumbFuture,
      builder: (_, snap) {
        if (snap.data != null && snap.data!.isNotEmpty) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          );
        }
        if (snap.connectionState == ConnectionState.done) {
          final currentMem =
              ThumbnailService.instance.getMemoryThumbnail(widget.item.id);
          if (currentMem != null) {
            return Image.memory(
              currentMem,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            );
          }
          final currentDisk =
              ThumbnailService.instance.getCachedFile(widget.item.id);
          if (currentDisk != null) {
            return Image.file(
              currentDisk,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
            );
          }

          if (!widget.item.isVideo) {
            final file = File(widget.item.path);
            if (file.existsSync()) {
              return Image.file(
                file,
                cacheWidth: 512,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
              );
            }
          }
        }
        return _buildPlaceholder(cs);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Thumbnail ───────────────────────────────────────
          // Hero tag == item id: the viewer's current page (same tag) flies
          // back to this tile on pop, whichever photo it was swiped to.
          Hero(tag: widget.item.id, child: _buildThumbnail(cs)),

          // ── Video badge ─────────────────────────────────────
          if (widget.item.isVideo && widget.showBadges)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.item.duration != null
                      ? MediaUtils.formatDuration(widget.item.duration!)
                      : '▶',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 10, height: 1.2),
                ),
              ),
            ),

          // ── Selection overlay ───────────────────────────────
          if (widget.isSelecting)
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? cs.primary.withValues(alpha: 0.35)
                      : Colors.transparent,
                  border: widget.isSelected
                      ? Border.all(color: cs.primary, width: 3)
                      : null,
                ),
              ),
            ),

          if (widget.isSelecting)
            Positioned(
              top: 4,
              left: 4,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 120),
                child: widget.isSelected
                    ? CircleAvatar(
                        key: const ValueKey('checked'),
                        radius: 11,
                        backgroundColor: cs.primary,
                        child: const Icon(Icons.check,
                            size: 14, color: Colors.white),
                      )
                    : CircleAvatar(
                        key: const ValueKey('unchecked'),
                        radius: 11,
                        backgroundColor: Colors.black38,
                      ),
              ),
            ),
        ],
      ),
    );
  }
}
