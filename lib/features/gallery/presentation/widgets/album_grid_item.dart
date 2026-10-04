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
  });

  final Album album;
  final VoidCallback onTap;

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
    if (oldWidget.album.coverItem.id != widget.album.coverItem.id) {
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
        if (snap.data != null) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          );
        }
        if (snap.connectionState == ConnectionState.done &&
            !widget.album.coverItem.isVideo) {
          final file = File(widget.album.coverItem.path);
          if (file.existsSync()) {
            return Image.file(
              file,
              cacheWidth: 384,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
            );
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
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Cover Thumbnail ──────────────────────────────
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCover(cs),
                  if (widget.album.name == 'Favorites')
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.favorite,
                          size: 14,
                          color: Colors.redAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),

          // ── Album Name ──────────────────────────────────────────
          Text(
            widget.album.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 1),

          // ── Item Count ──────────────────────────────────────────
          Text(
            '${widget.album.itemCount} items',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
