import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../core/enums/thumbnail_crop_style.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/services/psd_service.dart';
import '../../../../core/services/thumbnail_service.dart';
import '../../../../core/utils/media_utils.dart';
import 'grid_hi_res_scope.dart';
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
  GridHiResController? _hiResController;
  bool _hiResActive = false;
  bool _hiResInFlight = false;
  int _hiResWidth = 768;
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
  void didUpdateWidget(covariant MediaGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.path != widget.item.path) {
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

    final targetWidth = controller.computeTargetCacheWidth(context);
    if (_hiResActive &&
        _hiResWidth == targetWidth &&
        (_activeHiResProvider != null || _hiResInFlight)) {
      return;
    }

    final item = widget.item;
    if (item.path.isEmpty) return;

    // Only upgrade after low-res thumbnail is cached so hi-res never competes
    // with cold-start low-res decoding.
    final hasLowRes =
        ThumbnailService.instance.getMemoryThumbnail(item.id) != null ||
            ThumbnailService.instance.hasDiskCache(item.id);
    if (!hasLowRes) {
      return;
    }

    if (!item.isVideo && !PsdService.isPsd(item.path)) {
      final token = ++_hiResToken;
      _hiResWidth = targetWidth;
      _hiResActive = true;
      _hiResInFlight = true;
      ThumbnailService.instance
          .getGridHiResPhotoThumbnail(
        item.id,
        filePath: item.path,
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
        _activeHiResProvider = MemoryImage(bytes);
        setState(() {});
      });
      return;
    }

    if (item.isVideo) {
      final memHi =
          ThumbnailService.instance.getMemoryHighResThumbnail(item.id);
      if (memHi != null && memHi.isNotEmpty) {
        _hiResToken++;
        _hiResInFlight = false;
        _evictHiResProvider();
        _hiResWidth = targetWidth;
        _activeHiResProvider = ResizeImage(
          MemoryImage(memHi),
          width: targetWidth,
          height: targetWidth,
          policy: ResizeImagePolicy.fit,
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
        item.id,
        filePath: item.path,
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
        _activeHiResProvider = MemoryImage(bytes);
        setState(() {});
      });
      return;
    }

    // PSD: decode full cached thumbnail up to targetWidth.
    final mem = ThumbnailService.instance.getMemoryThumbnail(item.id);
    if (mem != null && mem.isNotEmpty) {
      _hiResToken++;
      _hiResInFlight = false;
      _evictHiResProvider();
      _hiResWidth = targetWidth;
      _activeHiResProvider = ResizeImage(
        MemoryImage(mem),
        width: targetWidth,
        height: targetWidth,
        policy: ResizeImagePolicy.fit,
      );
      setState(() => _hiResActive = true);
      return;
    }

    final diskFile = ThumbnailService.instance.getIndexedDiskFile(item.id);
    if (diskFile != null) {
      _hiResToken++;
      _hiResInFlight = false;
      _evictHiResProvider();
      _hiResWidth = targetWidth;
      _activeHiResProvider = ResizeImage(
        FileImage(diskFile),
        width: targetWidth,
        height: targetWidth,
        policy: ResizeImagePolicy.fit,
      );
      setState(() => _hiResActive = true);
    }
  }

  void _startThumbnailFetch() {
    final requestedId = widget.item.id;
    final future = ThumbnailService.instance.getThumbnail(
      requestedId,
      filePath: widget.item.path,
      isVideo: widget.item.isVideo,
      isCancelled: () => !mounted || widget.item.id != requestedId,
    );
    _thumbFuture = future;
    future.then((bytes) {
      if (!mounted || widget.item.id != requestedId) return;
      if (bytes != null &&
          bytes.isNotEmpty &&
          _hiResController?.value.active == true) {
        _onHiResStateChanged();
      }
    });
  }

  void _initThumbnail() {
    // Skip queue if already available in memory or disk cache.
    if (ThumbnailService.instance.getMemoryThumbnail(widget.item.id) != null ||
        ThumbnailService.instance.hasDiskCache(widget.item.id)) {
      _thumbFuture = null;
      return;
    }
    _startThumbnailFetch();
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
    final lowRes = _buildLowResThumbnail(cs, fit);
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
          fit: fit,
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

  Widget _lowResFrameBuilder(
    ColorScheme cs,
    BuildContext context,
    Widget child,
    int? frame,
    bool wasSynchronouslyLoaded,
  ) {
    if (wasSynchronouslyLoaded || frame != null) return child;
    return ColoredBox(color: cs.surfaceContainerHighest);
  }

  Widget _buildLowResThumbnail(ColorScheme cs, BoxFit fit) {
    // 1. Memory cache lookup.
    final mem = ThumbnailService.instance.getMemoryThumbnail(widget.item.id);
    if (mem != null) {
      return Image.memory(
        mem,
        cacheWidth: 288,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        frameBuilder: (ctx, child, frame, sync) =>
            _lowResFrameBuilder(cs, ctx, child, frame, sync),
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
        frameBuilder: (ctx, child, frame, sync) =>
            _lowResFrameBuilder(cs, ctx, child, frame, sync),
        errorBuilder: (_, __, ___) {
          ThumbnailService.instance.evictDiskCacheIndex(widget.item.id);
          return _buildPlaceholder(cs);
        },
      );
    }

    // 3. Fetch asynchronously if not cached.
    if (_thumbFuture == null) {
      _startThumbnailFetch();
    }

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
            frameBuilder: (ctx, child, frame, sync) =>
                _lowResFrameBuilder(cs, ctx, child, frame, sync),
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
              frameBuilder: (ctx, child, frame, sync) =>
                  _lowResFrameBuilder(cs, ctx, child, frame, sync),
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
              frameBuilder: (ctx, child, frame, sync) =>
                  _lowResFrameBuilder(cs, ctx, child, frame, sync),
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
              frameBuilder: (ctx, child, frame, sync) =>
                  _lowResFrameBuilder(cs, ctx, child, frame, sync),
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
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Hero(
                tag: widget.item.id,
                child: _buildThumbnail(cs),
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
