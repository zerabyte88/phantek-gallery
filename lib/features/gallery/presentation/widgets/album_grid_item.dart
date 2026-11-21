import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/models/album.dart';
import '../../../../core/services/psd_service.dart';
import '../../../../core/services/thumbnail_service.dart';
import 'grid_hi_res_scope.dart';
import 'shimmer_loading_tile.dart';

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
  GridHiResController? _hiResController;
  bool _hiResActive = false;
  bool _hiResInFlight = false;
  int _hiResWidth = 640;
  int _hiResToken = 0;
  ImageProvider? _activeHiResProvider;

  @override
  void initState() {
    super.initState();
    _initThumbnail();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = GridHiResScope.maybeOf(context);
    if (next != _hiResController) {
      _hiResController?.removeListener(_onHiResStateChanged);
      _hiResController = next;
      _hiResController?.addListener(_onHiResStateChanged);
      if (next?.value.active == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onHiResStateChanged();
        });
      } else {
        _downgradeToLowRes(triggerRebuild: false);
      }
    }
  }

  @override
  void didUpdateWidget(covariant AlbumGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.album.coverItem.id != widget.album.coverItem.id ||
        oldWidget.album.coverItem.path != widget.album.coverItem.path) {
      _downgradeToLowRes(triggerRebuild: false);
      _initThumbnail();
      if (_hiResController?.value.active == true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _onHiResStateChanged();
        });
      }
    }
  }

  @override
  void dispose() {
    _hiResController?.removeListener(_onHiResStateChanged);
    _downgradeToLowRes(triggerRebuild: false);
    super.dispose();
  }

  void _evictHiResProvider() {
    _activeHiResProvider?.evict();
    _activeHiResProvider = null;
  }

  void _downgradeToLowRes({required bool triggerRebuild}) {
    _hiResToken++;
    _hiResInFlight = false;
    final wasActive = _hiResActive || _activeHiResProvider != null;
    _evictHiResProvider();
    _hiResActive = false;
    if (triggerRebuild && mounted && wasActive) {
      setState(() {});
    }
  }

  void _onHiResStateChanged() {
    if (!mounted) return;
    final controller = _hiResController;
    if (controller == null ||
        !controller.value.active ||
        !controller.isTileVisibleInViewport(context)) {
      _downgradeToLowRes(triggerRebuild: true);
      return;
    }

    final targetWidth = controller.computeTargetCacheWidth(
      context,
      minWidth: 640,
      maxWidth: 960,
    );
    if (_hiResActive &&
        _hiResWidth == targetWidth &&
        (_activeHiResProvider != null || _hiResInFlight)) {
      return;
    }

    final cover = widget.album.coverItem;
    if (cover.path.isEmpty) return;

    if (!cover.isVideo && !PsdService.isPsd(cover.path)) {
      _hiResToken++;
      _hiResInFlight = false;
      _evictHiResProvider();
      _hiResWidth = targetWidth;
      _activeHiResProvider = ResizeImage(
        FileImage(File(cover.path)),
        width: targetWidth,
      );
      setState(() => _hiResActive = true);
      return;
    }

    if (cover.isVideo) {
      final memHi =
          ThumbnailService.instance.getMemoryHighResThumbnail(cover.id);
      if (memHi != null && memHi.isNotEmpty) {
        _hiResToken++;
        _hiResInFlight = false;
        _evictHiResProvider();
        _hiResWidth = targetWidth;
        _activeHiResProvider = ResizeImage(
          MemoryImage(memHi),
          width: targetWidth,
        );
        setState(() => _hiResActive = true);
        return;
      }

      final token = ++_hiResToken;
      _hiResWidth = targetWidth;
      _hiResActive = true;
      _hiResInFlight = true;
      ThumbnailService.instance
          .getGridHiResVideoThumbnail(
        cover.id,
        filePath: cover.path,
        size: targetWidth,
        isCancelled: () =>
            !mounted ||
            _hiResToken != token ||
            !(_hiResController?.value.active ?? false),
      )
          .then((bytes) {
        if (!mounted ||
            _hiResToken != token ||
            !(_hiResController?.value.active ?? false)) {
          return;
        }
        _hiResInFlight = false;
        if (bytes == null || bytes.isEmpty) return;
        _evictHiResProvider();
        _activeHiResProvider = ResizeImage(
          MemoryImage(bytes),
          width: targetWidth,
        );
        setState(() {});
      });
      return;
    }

    // PSD: decode full cached thumbnail up to targetWidth.
    final mem = ThumbnailService.instance.getMemoryThumbnail(cover.id);
    if (mem != null && mem.isNotEmpty) {
      _hiResToken++;
      _hiResInFlight = false;
      _evictHiResProvider();
      _hiResWidth = targetWidth;
      _activeHiResProvider = ResizeImage(
        MemoryImage(mem),
        width: targetWidth,
      );
      setState(() => _hiResActive = true);
      return;
    }

    final diskFile = ThumbnailService.instance.getIndexedDiskFile(cover.id);
    if (diskFile != null) {
      _hiResToken++;
      _hiResInFlight = false;
      _evictHiResProvider();
      _hiResWidth = targetWidth;
      _activeHiResProvider = ResizeImage(
        FileImage(diskFile),
        width: targetWidth,
      );
      setState(() => _hiResActive = true);
    }
  }

  void _initThumbnail() {
    if (ThumbnailService.instance
                .getMemoryThumbnail(widget.album.coverItem.id) !=
            null ||
        ThumbnailService.instance.hasDiskCache(widget.album.coverItem.id)) {
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
    final lowRes = _buildLowResCover(cs);
    final hiResProvider = _activeHiResProvider;
    if (!_hiResActive || hiResProvider == null) {
      return lowRes;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        lowRes,
        Image(
          image: hiResProvider,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded || frame != null) {
              return child;
            }
            return const SizedBox.shrink();
          },
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildLowResCover(ColorScheme cs) {
    final mem =
        ThumbnailService.instance.getMemoryThumbnail(widget.album.coverItem.id);
    if (mem != null) {
      return Image.memory(
        mem,
        cacheWidth: 320,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
      );
    }

    final diskFile =
        ThumbnailService.instance.getIndexedDiskFile(widget.album.coverItem.id);
    if (diskFile != null) {
      return Image.file(
        diskFile,
        cacheWidth: 320,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) {
          ThumbnailService.instance
              .evictDiskCacheIndex(widget.album.coverItem.id);
          return _buildPlaceholder(cs);
        },
      );
    }

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
            cacheWidth: 320,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
          );
        }
        if (snap.connectionState == ConnectionState.done) {
          final currentMem = ThumbnailService.instance
              .getMemoryThumbnail(widget.album.coverItem.id);
          if (currentMem != null) {
            return Image.memory(
              currentMem,
              cacheWidth: 320,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
            );
          }
          final currentDisk = ThumbnailService.instance
              .getIndexedDiskFile(widget.album.coverItem.id);
          if (currentDisk != null) {
            return Image.file(
              currentDisk,
              cacheWidth: 320,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) {
                ThumbnailService.instance
                    .evictDiskCacheIndex(widget.album.coverItem.id);
                return _buildPlaceholder(cs);
              },
            );
          }
          if (!widget.album.coverItem.isVideo &&
              !PsdService.isPsd(widget.album.coverItem.path) &&
              widget.album.coverItem.path.isNotEmpty) {
            return Image.file(
              File(widget.album.coverItem.path),
              cacheWidth: 320,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.low,
              errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
            );
          }
        }
        return const ShimmerLoadingTile(icon: Icons.photo_library_rounded);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        borderRadius: BorderRadius.circular(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: RepaintBoundary(
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
          ),
          const SizedBox(height: 7),
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
      ),
    );
  }
}
