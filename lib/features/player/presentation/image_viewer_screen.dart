import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/utils/media_utils.dart';
import 'widgets/media_info_sheet.dart';
import 'widgets/rename_dialog.dart';

/// Display-capped provider shared by viewer + precache (same cache key).
/// A 100MP photo decodes to ~50 MB instead of ~408 MB, so it fits imageCache.
// ponytail: fixed 4096px cap, sharp to ~3x zoom on 1080p. Swap to full-res
// FileImage on deep zoom if pixel-peeping beyond 3x matters.
ImageProvider displayImage(String path) => ResizeImage(
      FileImage(File(path)),
      width: 4096,
      height: 4096,
      policy: ResizeImagePolicy.fit,
    );

/// Cached 512px grid thumbnail, shown instantly while the full image decodes.
Widget _thumb(String id, BoxFit fit) {
  final mem = ThumbnailService.instance.getMemoryThumbnail(id);
  final disk = mem == null ? ThumbnailService.instance.getCachedFile(id) : null;
  final ImageProvider? p =
      mem != null ? MemoryImage(mem) : (disk != null ? FileImage(disk) : null);
  if (p == null) return const SizedBox.shrink();
  return Image(
    image: p,
    fit: fit,
    width: double.infinity,
    height: double.infinity,
    gaplessPlayback: true,
    filterQuality: FilterQuality.high,
  );
}

/// Full-screen swipeable image viewer with delete support.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.isTrash = false,
  });

  final List<MediaItem> items;
  final int initialIndex;
  final bool isTrash;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen>
    with TickerProviderStateMixin {
  late final PageController _page;
  late int _current;
  bool _barsVisible = true;
  // Drag-to-dismiss translation lives in a notifier: pointer-move repaints only
  // the Transform, never the gallery/bars hierarchy.
  final ValueNotifier<Offset> _drag = ValueNotifier(Offset.zero);
  bool _dragHidesBars = false;
  late final AnimationController _settle; // 1 -> 0 spring, scales _settleFrom
  Offset _settleFrom = Offset.zero;
  VelocityTracker _vt = VelocityTracker.withKind(PointerDeviceKind.touch);
  double? _startDragY;
  double? _startDragX;
  bool _isZoomed = false;
  bool _isPinching = false;
  bool _isMultiTouch = false;
  final Set<int> _activePointers = {};
  final Map<int, PhotoViewController> _photoControllers = {};
  AnimationController? _photoZoomAnim;
  int? _lastTapDownTimeMs;
  Offset? _lastTapDownPosition;
  int? _lastTapUpTimeMs;
  Offset? _lastTapUpPosition;

  PhotoViewController _getPhotoController(int index) {
    return _photoControllers.putIfAbsent(index, () => PhotoViewController());
  }

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _page = PageController(initialPage: _current);
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        _setDrag(_settleFrom * _settle.value);
        if (!_settle.isAnimating && _activePointers.isEmpty) {
          _setDrag(Offset.zero);
        }
      });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WidgetsBinding.instance.addPostFrameCallback((_) => _precacheAdjacent(_current));
  }

  void _precacheAdjacent(int index) {
    if (!mounted) return;
    // ±1 only: 3 × ~50 MB stays inside the 256 MB imageCache.
    for (final offset in const [-1, 1]) {
      final target = index + offset;
      if (target >= 0 && target < widget.items.length) {
        precacheImage(displayImage(widget.items[target].path), context);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _photoControllers.values) {
      c.dispose();
    }
    _photoControllers.clear();
    _photoZoomAnim?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _settle.dispose();
    _drag.dispose();
    _page.dispose();
    super.dispose();
  }

  MediaItem get _currentItem => widget.items[_current];

  void _setDrag(Offset o) {
    _drag.value = o;
    final hide = o.dy >= 20;
    if (hide != _dragHidesBars) setState(() => _dragHidesBars = hide);
  }

  /// Spring the dragged image back to center, carrying the release velocity.
  void _springBack(double vy) {
    _settleFrom = _drag.value;
    final v = _settleFrom.dy.abs() > 1 ? vy / _settleFrom.dy : 0.0;
    _settle.value = 1.0;
    _settle.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 1, stiffness: 400, ratio: 0.85),
      1.0,
      0.0,
      v.clamp(-10.0, 10.0),
    ));
  }

  void _toggleBars() {
    if (!_isZoomed && !_isPinching) {
      setState(() => _barsVisible = !_barsVisible);
    }
  }

  void _handlePhotoDoubleTap(Offset tapPos) {
    final controller = _getPhotoController(_current);
    final currentScale = controller.scale ?? 1.0;
    final isZoomed = _isZoomed || currentScale > 1.05;

    _photoZoomAnim?.stop();
    _photoZoomAnim?.dispose();

    final size = MediaQuery.of(context).size;
    final center = Offset(size.width / 2, size.height / 2);
    final delta = tapPos - center;

    const targetScale = 2.5;
    final startScale = currentScale;
    final startPosition = controller.position;

    final endScale = isZoomed ? 1.0 : targetScale;
    final endPosition = isZoomed ? Offset.zero : -delta * (targetScale - 1.0);

    _photoZoomAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    final curve = CurvedAnimation(
      parent: _photoZoomAnim!,
      curve: Curves.easeOutCubic,
    );

    _photoZoomAnim!.addListener(() {
      final t = curve.value;
      final s = startScale + (endScale - startScale) * t;
      final p = Offset(
        startPosition.dx + (endPosition.dx - startPosition.dx) * t,
        startPosition.dy + (endPosition.dy - startPosition.dy) * t,
      );

      controller.value = PhotoViewControllerValue(
        position: p,
        scale: (isZoomed && t >= 0.99) ? null : s,
        rotation: 0,
        rotationFocusPoint: null,
      );
    });

    _photoZoomAnim!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() {
          _isZoomed = !isZoomed;
        });
      }
    });

    HapticFeedback.lightImpact();
    _photoZoomAnim!.forward();
  }

  Future<void> _restoreCurrentItem() async {
    final item = _currentItem;
    await ref.read(trashProvider.notifier).restore(item.id);
    ref.read(mediaListProvider.notifier).restoreItems([item.id]);
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.name}" restored')),
      );
      if (widget.items.length <= 1) {
        Navigator.of(context).pop();
      } else {
        widget.items.removeAt(_current);
        setState(() {
          _current = _current.clamp(0, widget.items.length - 1);
        });
        _page.jumpToPage(_current);
      }
    }
  }

  Future<void> _deleteCurrentItem() async {
    final item = _currentItem;

    if (widget.isTrash) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete Permanently?'),
          content: Text(
            '"${item.name}" will be permanently deleted. This action cannot be undone.',
          ),
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      await ref.read(trashProvider.notifier).permanentDelete(item.id);
      if (mounted) {
        if (widget.items.length <= 1) {
          Navigator.of(context).pop();
        } else {
          widget.items.removeAt(_current);
          setState(() {
            _current = _current.clamp(0, widget.items.length - 1);
          });
          _page.jumpToPage(_current);
        }
      }
      return;
    }

    final settings = ref.read(settingsNotifierProvider);
    final isTrash = settings.enableTrash;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isTrash ? 'Move to Trash?' : 'Delete Permanently?'),
        content: Text(
          isTrash
              ? '"${item.name}" will be moved to trash.'
              : '"${item.name}" will be permanently deleted. This action cannot be undone.',
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: isTrash
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isTrash ? 'Move to Trash' : 'Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final hasPerm = await PermissionService.instance.ensureManageStorage();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Manage All Files permission is required to delete or move items to trash.'),
          ),
        );
      }
      return;
    }

    // 1. Immediately remove from global media list provider
    ref.read(mediaListProvider.notifier).removeItems({item.id});

    try {
      if (settings.enableTrash) {
        await ref.read(trashProvider.notifier).moveToTrash(
              id: item.id,
              path: item.path,
              isVideo: item.isVideo,
            );
      } else {
        final f = File(item.path);
        if (await f.exists()) await f.delete();
        try {
          await PhotoManager.editor.deleteWithIds([item.id]);
        } catch (_) {}
      }
      ref.read(mediaListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete item: $e')),
        );
      }
      return;
    }

    if (!mounted) return;
    if (widget.items.length <= 1) {
      Navigator.of(context).pop();
    } else {
      // Remove from local list and move page.
      widget.items.removeAt(_current);
      setState(() {
        _current = _current.clamp(0, widget.items.length - 1);
      });
      _page.jumpToPage(_current);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final showBars = _barsVisible && !_dragHidesBars && !_isZoomed && !_isPinching;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        onPointerDown: (e) {
          _activePointers.add(e.pointer);
          _lastTapDownTimeMs = DateTime.now().millisecondsSinceEpoch;
          _lastTapDownPosition = e.position;
          _settle.stop(); // grab a returning image mid-flight
          if (_activePointers.length >= 2 || _isZoomed) {
            // Multi-touch, pinch, or zoomed: abort any drag-to-dismiss immediately.
            _isMultiTouch = true;
            _isPinching = true;
            _startDragY = null;
            _startDragX = null;
            if (_drag.value != Offset.zero) _setDrag(Offset.zero);
            return;
          }
          _startDragY = e.position.dy;
          _startDragX = e.position.dx;
          _vt = VelocityTracker.withKind(e.kind);
        },
        onPointerMove: (e) {
          // While zoomed in, pinching, or multi-touching, NEVER pull-to-dismiss
          if (_startDragY == null ||
              _startDragX == null ||
              _isZoomed ||
              _isPinching ||
              _isMultiTouch ||
              _activePointers.length >= 2) {
            if (_drag.value != Offset.zero) _setDrag(Offset.zero);
            return;
          }
          _vt.addPosition(e.timeStamp, e.position);
          final dy = e.position.dy - _startDragY!;
          final dx = e.position.dx - _startDragX!;
          // Strict gesture slop/deadzone: dy > 28 && dy > dx.abs() * 2.2
          if (_drag.value != Offset.zero || (dy > 28 && dy > dx.abs() * 2.2)) {
            _setDrag(Offset(dx, (dy - 28).clamp(0.0, 600.0)));
          }
        },
        onPointerUp: (e) {
          _vt.addPosition(e.timeStamp, e.position);
          _activePointers.remove(e.pointer);

          final now = DateTime.now().millisecondsSinceEpoch;
          bool isDoubleTap = false;
          if (_drag.value == Offset.zero &&
              _lastTapDownTimeMs != null &&
              _lastTapDownPosition != null) {
            final downDuration = now - _lastTapDownTimeMs!;
            final moveDist = (e.position - _lastTapDownPosition!).distance;
            if (downDuration < 300 && moveDist < 25.0) {
              if (_lastTapUpTimeMs != null && _lastTapUpPosition != null) {
                final interval = now - _lastTapUpTimeMs!;
                final doubleTapDist =
                    (e.position - _lastTapUpPosition!).distance;
                if (interval < 350 && doubleTapDist < 45.0) {
                  isDoubleTap = true;
                  _lastTapUpTimeMs = null;
                  _lastTapUpPosition = null;
                  _lastTapDownTimeMs = null;
                  _lastTapDownPosition = null;
                  _handlePhotoDoubleTap(e.position);
                }
              }
              if (!isDoubleTap) {
                _lastTapUpTimeMs = now;
                _lastTapUpPosition = e.position;
              }
            } else {
              _lastTapUpTimeMs = null;
              _lastTapUpPosition = null;
            }
          }

          if (_activePointers.isEmpty) {
            final wasMultiTouch = _isMultiTouch;
            _isMultiTouch = false;
            _isPinching = false;
            _startDragY = null;
            _startDragX = null;
            final d = _drag.value;
            final vy = _vt.getVelocity().pixelsPerSecond.dy;

            if (!wasMultiTouch &&
                !_isZoomed &&
                d.dy > 0 &&
                (d.dy > 90 || (vy > 900 && d.dy > 20))) {
              // Hero flies from the image's current (dragged/scaled) rect to the
              // grid tile whose Hero tag == the current item's id.
              Navigator.of(context).pop();
              return;
            } else if (d != Offset.zero) {
              _springBack(vy);
              return;
            }
          }
        },
        onPointerCancel: (e) {
          _activePointers.remove(e.pointer);
          _lastTapDownTimeMs = null;
          _lastTapDownPosition = null;
          _lastTapUpTimeMs = null;
          _lastTapUpPosition = null;
          if (_activePointers.isEmpty) {
            _isMultiTouch = false;
            _isPinching = false;
            _startDragY = null;
            _startDragX = null;
            if (_drag.value != Offset.zero) _springBack(0);
          }
        },
        child: Stack(
          children: [
            // ── Background scrim: opacity follows drag distance ──
            Positioned.fill(
              child: ValueListenableBuilder<Offset>(
                valueListenable: _drag,
                builder: (_, d, __) => ColoredBox(
                  color: Colors.black.withValues(
                      alpha: (1.0 - d.dy / 300).clamp(0.0, 1.0)),
                ),
              ),
            ),
            // ── Gallery: translate + proportional scale-down ─────
            ValueListenableBuilder<Offset>(
              valueListenable: _drag,
              builder: (_, d, child) {
                final s = (1.0 - d.dy / 900).clamp(0.6, 1.0);
                return Transform(
                  alignment: Alignment.center,
                  transform: Matrix4.translationValues(d.dx, d.dy, 0)
                    ..scaleByDouble(s, s, 1.0, 1.0),
                  child: child,
                );
              },
              child: PhotoViewGallery.builder(
                pageController: _page,
                itemCount: widget.items.length,
                onPageChanged: (i) {
                  setState(() {
                    _current = i;
                    _isZoomed = false;
                    _isPinching = false;
                  });
                  _lastTapUpTimeMs = null;
                  _lastTapUpPosition = null;
                  _precacheAdjacent(i);
                },
                scaleStateChangedCallback: (state) {
                  final zoomed = state != PhotoViewScaleState.initial;
                  if (_isZoomed != zoomed) {
                    setState(() {
                      _isZoomed = zoomed;
                      if (zoomed) {
                        _drag.value = Offset.zero;
                        _dragHidesBars = false;
                        _startDragY = null;
                        _startDragX = null;
                      }
                    });
                  }
                },
                scrollPhysics: (_isZoomed ||
                        _isPinching ||
                        _isMultiTouch ||
                        _activePointers.length >= 2)
                    ? const NeverScrollableScrollPhysics()
                    : const BouncingScrollPhysics(
                        parent: AlwaysScrollableScrollPhysics(),
                      ),
                backgroundDecoration:
                    const BoxDecoration(color: Colors.transparent),
                // Gallery-level builder has no index: resolve the page's item
                // from the enclosing PhotoView's provider.
                loadingBuilder: (ctx, _) {
                  final p = ctx
                      .findAncestorWidgetOfExactType<PhotoView>()
                      ?.imageProvider;
                  final inner = p is ResizeImage ? p.imageProvider : p;
                  if (inner is! FileImage) return const SizedBox.shrink();
                  final i = widget.items
                      .indexWhere((m) => m.path == inner.file.path);
                  return i < 0
                      ? const SizedBox.shrink()
                      : _thumb(widget.items[i].id, BoxFit.contain);
                },
                builder: (_, i) {
                  final it = widget.items[i];
                  return PhotoViewGalleryPageOptions(
                    controller: _getPhotoController(i),
                    scaleStateCycle: (actual) => actual,
                    imageProvider: displayImage(it.path),
                    // Only the current page carries the tag, so the fly-back always
                    // targets the grid tile of the photo currently shown.
                    heroAttributes: i == _current
                        ? PhotoViewHeroAttributes(
                            tag: it.id,
                            transitionOnUserGestures: true,
                            flightShuttleBuilder: (_, __, ___, ____, _____) =>
                                _thumb(it.id, BoxFit.cover),
                          )
                        : null,
                    minScale: PhotoViewComputedScale.contained,
                    maxScale: PhotoViewComputedScale.covered * 6.0,
                    initialScale: PhotoViewComputedScale.contained,
                    filterQuality: FilterQuality.high,
                    basePosition: Alignment.center,
                    onTapUp: (_, __, ___) => _toggleBars(),
                    errorBuilder: (_, __, ___) => const Center(
                      child: Icon(Icons.broken_image,
                          size: 80, color: Colors.white38),
                    ),
                  );
                },
              ),
            ),

            // ── Top bar ────────────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !showBars,
                  child: AnimatedOpacity(
                    opacity: showBars ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                  child: SafeArea(
                    bottom: false,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: const Icon(Icons.arrow_back_ios_new,
                                color: Colors.white, size: 20),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${MediaUtils.formatViewerDate(item.date)}, ${MediaUtils.formatViewerTime(item.date)}',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          if (widget.isTrash) ...[
                            IconButton(
                              icon: const Icon(Icons.restore,
                                  color: Colors.white, size: 22),
                              tooltip: 'Restore',
                              onPressed: _restoreCurrentItem,
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_forever,
                                  color: Colors.white, size: 22),
                              tooltip: 'Delete Permanently',
                              onPressed: _deleteCurrentItem,
                            ),
                          ] else ...[
                            Consumer(
                              builder: (context, ref, _) {
                                final isFav = ref.watch(
                                  settingsNotifierProvider.select(
                                    (s) => s.favoriteIds.contains(item.id),
                                  ),
                                );
                                return IconButton(
                                  icon: Icon(
                                    isFav ? Icons.favorite : Icons.favorite_border,
                                    color: isFav ? Colors.redAccent : Colors.white,
                                    size: 22,
                                  ),
                                  tooltip: isFav
                                      ? 'Remove from favorites'
                                      : 'Add to favorites',
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    final currentFavs = Set<String>.from(
                                      ref.read(settingsNotifierProvider).favoriteIds,
                                    );
                                    if (currentFavs.contains(item.id)) {
                                      currentFavs.remove(item.id);
                                    } else {
                                      currentFavs.add(item.id);
                                    }
                                    ref
                                        .read(settingsNotifierProvider.notifier)
                                        .update(
                                          (s) => s.copyWith(favoriteIds: currentFavs.toList()),
                                        );
                                  },
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.share_outlined,
                                  color: Colors.white, size: 22),
                              tooltip: 'Share',
                              onPressed: () =>
                                  ShareService.shareSingle(item.path, isVideo: false),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  color: Colors.white, size: 22),
                              tooltip: 'Delete',
                              onPressed: _deleteCurrentItem,
                            ),
                            IconButton(
                              icon: const Icon(Icons.info_outline,
                                  color: Colors.white, size: 22),
                              tooltip: 'Details',
                              onPressed: () => showMediaInfoSheet(context, item),
                            ),
                            PopupMenuButton<String>(
                              icon: const Icon(Icons.more_vert,
                                  color: Colors.white, size: 22),
                              tooltip: 'More options',
                              color: const Color(0xFF222222),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              onSelected: (value) async {
                                if (value == 'wallpaper') {
                                  ShareService.setAsWallpaper(item.path);
                                } else if (value == 'rename') {
                                  final updated =
                                      await showRenameMediaDialog(context, item, ref);
                                  if (updated != null && mounted) {
                                    setState(() {
                                      widget.items[_current] = updated;
                                    });
                                  }
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'wallpaper',
                                  child: Row(
                                    children: [
                                      Icon(Icons.wallpaper_outlined,
                                          size: 20, color: Colors.white),
                                      SizedBox(width: 12),
                                      Text('Set as wallpaper',
                                          style: TextStyle(
                                              color: Colors.white, fontSize: 14)),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'rename',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit_outlined,
                                          size: 20, color: Colors.white),
                                      SizedBox(width: 12),
                                      Text('Rename',
                                          style: TextStyle(
                                              color: Colors.white, fontSize: 14)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

              // ── Bottom info bar ─────────────────────────────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: !showBars,
                  child: AnimatedOpacity(
                    opacity: showBars ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeInOut,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            '${_current + 1} / ${widget.items.length}',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            MediaUtils.formatDateTime(item.date),
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 12),
                          ),
                          const Spacer(),
                          if (item.resolution.isNotEmpty)
                            Text(
                              item.resolution,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
}
