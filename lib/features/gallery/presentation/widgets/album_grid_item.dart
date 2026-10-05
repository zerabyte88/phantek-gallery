import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/models/album.dart';
import '../../../../core/services/thumbnail_service.dart';

/// Single cell in the albums grid (3 items per row).
/// Shows album cover thumbnail, album folder name, and total item count.
class AlbumGridItem extends StatefulWidget {
  const AlbumGridItem({
    super.key,
    required this.album,
    required this.onTap,
    this.isSelected = false,
    this.isSelecting = false,
    this.onLongPress,
  });

  final Album album;
  final VoidCallback onTap;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback? onLongPress;

  @override
  State<AlbumGridItem> createState() => _AlbumGridItemState();
}

class _AlbumGridItemState extends State<AlbumGridItem> {
  Future<Uint8List?>? _thumbFuture;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  @override
  void didUpdateWidget(covariant AlbumGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.coverItem.id != widget.album.coverItem.id ||
        oldWidget.album.coverItem.path != widget.album.coverItem.path) {
      _initThumbnail();
    }
  }

  void _initThumbnail() {
    if (ThumbnailService.instance
            .getMemoryThumbnail(widget.album.coverItem.id) !=
        null ||
        ThumbnailService.instance
            .getCachedFile(widget.album.coverItem.id) !=
        null) {
      _thumbFuture = null;
      return;
    }
    _thumbFuture = ThumbnailService.instance.getThumbnail(
      widget.album.coverItem.id,
      filePath: widget.album.coverItem.path,
      isVideo: widget.album.coverItem.isVideo,
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return ColoredBox(
      color: cs.surfaceContainerHighest,
      child: const Icon(
        Icons.photo_library_outlined,
        size: 32,
        color: Colors.white38,
      ),
    );
  }

  Widget _buildCover(ColorScheme cs) {
    // 1. Fast in-memory lookup (0ms)
    final mem = ThumbnailService.instance
        .getMemoryThumbnail(widget.album.coverItem.id);
    if (mem != null) {
      return Image.memory(
        mem,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    // 2. Persistent disk cache hit (Instant on cold start — skips FutureBuilder delay!)
    final diskFile = ThumbnailService.instance
        .getCachedFile(widget.album.coverItem.id);
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
      widget.album.coverItem.id,
      filePath: widget.album.coverItem.path,
      isVideo: widget.album.coverItem.isVideo,
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
          final currentMem = ThumbnailService.instance
              .getMemoryThumbnail(widget.album.coverItem.id);
          if (currentMem != null) {
            return Image.memory(
              currentMem,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            );
          }
          final currentDisk = ThumbnailService.instance
              .getCachedFile(widget.album.coverItem.id);
          if (currentDisk != null) {
            return Image.file(
              currentDisk,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
            );
          }
          if (!widget.album.coverItem.isVideo) {
            final file = File(widget.album.coverItem.path);
            if (file.existsSync()) {
              return Image.file(
                file,
                cacheWidth: 256,
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

    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover Thumbnail ──────────────────────────────
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(cs),
                  if (widget.album.name == 'Favorites')
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3.5),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                            width: 0.8,
                          ),
                        ),
                        child: const Icon(
                          Icons.favorite_rounded,
                          size: 13,
                          color: Color(0xFFFF5277),
                        ),
                      ),
                    ),

                  // ── Selection overlay ───────────────────────────
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
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                  if (widget.isSelecting)
                    Positioned(
                      top: 8,
                      left: 8,
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
            ),
          ),
          const SizedBox(height: 7),

          // ── Album Name ──────────────────────────────────────────
          Text(
            widget.album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          const SizedBox(height: 2),

          // ── Item Count ──────────────────────────────────────────
          Text(
            '${widget.album.itemCount} items',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurfaceVariant.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }
}
