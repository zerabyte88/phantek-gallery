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
  late Future<Uint8List?> _thumbFuture;

  @override
  void initState() {
    super.initState();
    _thumbFuture =
        ThumbnailService.instance.getThumbnail(widget.album.coverItem.id);
  }

  @override
  void didUpdateWidget(covariant AlbumGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.coverItem.id != widget.album.coverItem.id) {
      _thumbFuture =
          ThumbnailService.instance.getThumbnail(widget.album.coverItem.id);
    }
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
                  FutureBuilder<Uint8List?>(
                    future: _thumbFuture,
                    builder: (_, snap) {
                      if (snap.connectionState != ConnectionState.done ||
                          snap.data == null) {
                        return ColoredBox(
                          color: cs.surfaceContainerHighest,
                          child: const Icon(
                            Icons.photo_library_outlined,
                            size: 32,
                            color: Colors.white38,
                          ),
                        );
                      }
                      return Image.memory(
                        snap.data!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      );
                    },
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
