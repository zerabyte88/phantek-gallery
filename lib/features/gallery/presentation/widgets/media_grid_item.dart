import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/enums/thumbnail_crop_style.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/services/psd_service.dart';
import '../../../../core/services/thumbnail_service.dart';
import '../../../../core/utils/media_utils.dart';
import 'shimmer_loading_tile.dart';

/// Gallery grid thumbnail item.
class MediaGridItem extends StatefulWidget {
  const MediaGridItem({
    super.key,
    required this.item,
    this.cropStyle = ThumbnailCropStyle.square,
    required this.isSelected,
    required this.isSelecting,
    required this.showBadges,
    required this.onTap,
    required this.onLongPress,
  });

  final MediaItem item;
  final ThumbnailCropStyle cropStyle;
  final bool isSelected;
  final bool isSelecting;
  final bool showBadges;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  State<MediaGridItem> createState() => _MediaGridItemState();
}

class _MediaGridItemState extends State<MediaGridItem> {
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
    // Skip queue if already available in memory or disk cache.
    if (ThumbnailService.instance.getMemoryThumbnail(widget.item.id) != null ||
        ThumbnailService.instance.hasDiskCache(widget.item.id)) {
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
    final fit = widget.cropStyle == ThumbnailCropStyle.adaptive
        ? BoxFit.contain
        : BoxFit.cover;

    // 1. Memory cache lookup.
    final mem = ThumbnailService.instance.getMemoryThumbnail(widget.item.id);
    if (mem != null) {
      return Image.memory(
        mem,
        cacheWidth: 288,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }

    // 2. Disk cache lookup (zero synchronous existsSync on UI thread).
    final diskFile =
        ThumbnailService.instance.getIndexedDiskFile(widget.item.id);
    if (diskFile != null) {
      return Image.file(
        diskFile,
        cacheWidth: 288,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) {
          ThumbnailService.instance.evictDiskCacheIndex(widget.item.id);
          return _buildPlaceholder(cs);
        },
      );
    }

    // 3. Fetch asynchronously if not cached.
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
            cacheWidth: 288,
            fit: fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          );
        }
        if (snap.connectionState == ConnectionState.done) {
          final currentMem =
              ThumbnailService.instance.getMemoryThumbnail(widget.item.id);
          if (currentMem != null) {
            return Image.memory(
              currentMem,
              cacheWidth: 288,
              fit: fit,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            );
          }
          final currentDisk =
              ThumbnailService.instance.getIndexedDiskFile(widget.item.id);
          if (currentDisk != null) {
            return Image.file(
              currentDisk,
              cacheWidth: 288,
              fit: fit,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) {
                ThumbnailService.instance.evictDiskCacheIndex(widget.item.id);
                return _buildPlaceholder(cs);
              },
            );
          }

          if (!widget.item.isVideo &&
              !PsdService.isPsd(widget.item.path) &&
              widget.item.path.isNotEmpty) {
            return Image.file(
              File(widget.item.path),
              cacheWidth: 288,
              fit: fit,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
            );
          }
        }
        return ShimmerLoadingTile(isVideo: widget.item.isVideo);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Hero(
                  tag: widget.item.id,
                  child: _buildThumbnail(cs),
                ),
              ),
            ),
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
          if (!widget.item.isVideo &&
              PsdService.isPsd(widget.item.path) &&
              widget.showBadges)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PSD',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
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
      ),
    );
  }
}
