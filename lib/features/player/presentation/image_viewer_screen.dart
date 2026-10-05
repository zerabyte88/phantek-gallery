import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/bouncy_tap.dart';
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

/// Morphing flight shuttle between grid (cover crop) and viewer (contain aspect ratio).
Widget _buildHeroShuttle({
  required Animation<double> animation,
  required HeroFlightDirection flightDirection,
  required String id,
  String? path,
}) {
  final mem = ThumbnailService.instance.getMemoryThumbnail(id);
  final disk = mem == null ? ThumbnailService.instance.getCachedFile(id) : null;
  final ImageProvider? p = mem != null
      ? MemoryImage(mem)
      : (disk != null
          ? FileImage(disk)
          : (path != null ? displayImage(path) : null));

  if (p == null) return const SizedBox.shrink();

  return AnimatedBuilder(
    animation: animation,
    builder: (context, _) {
      final double gridProgress = flightDirection == HeroFlightDirection.pop
          ? animation.value
          : (1.0 - animation.value);

      final double coverOpacity = (gridProgress * 1.5 - 0.2).clamp(0.0, 1.0);
      final double containOpacity = (1.0 - coverOpacity).clamp(0.0, 1.0);

      return ClipRect(
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (coverOpacity > 0.001)
              Opacity(
                opacity: coverOpacity,
                child: Image(
                  image: p,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
            if (containOpacity > 0.001)
              Opacity(
                opacity: containOpacity,
                child: Image(
                  image: p,
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                ),
              ),
          ],
        ),
      );
    },
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
  late final AnimationController _settle; // 1 -> 0 spring, scales _settleFrom
  Offset _settleFrom = Offset.zero;
  VelocityTracker _vt = VelocityTracker.withKind(PointerDeviceKind.touch);
  double? _startDragY;
  double? _startDragX;
  late final TransformationController _transformationController;
  AnimationController? _zoomAnimController;
  TapDownDetails? _doubleTapDetails;
  bool _isPhotoZoomed = false;
  bool _isPinching = false;
  bool _isMultiTouch = false;
  final Set<int> _activePointers = {};

  bool get _isCurrentlyZoomed =>
      _isPhotoZoomed || _transformationController.value.getMaxScaleOnAxis() > 1.05;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _page = PageController(initialPage: _current);
    _transformationController = TransformationController();
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
    _transformationController.dispose();
    _zoomAnimController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _settle.dispose();
    _drag.dispose();
    _page.dispose();
    super.dispose();
  }

  MediaItem get _currentItem => widget.items[_current];

  void _setDrag(Offset o) {
    _drag.value = o;
  }

  /// Spring the dragged image back to center, carrying the release velocity.
  void _springBack(double vy) {
    _settleFrom = _drag.value;
    final v = _settleFrom.dy.abs() > 1 ? vy / _settleFrom.dy : 0.0;
    _settle.value = 1.0;
    _settle.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 1, stiffness: 350, ratio: 0.95),
      1.0,
      0.0,
      v.clamp(-8.0, 8.0),
    ));
  }

  void _toggleBars() {
    if (!_isCurrentlyZoomed && !_isPinching) {
      setState(() => _barsVisible = !_barsVisible);
    }
  }

  void _resetPhotoZoom() {
    if (!_isPhotoZoomed && _transformationController.value.isIdentity()) return;
    _zoomAnimController?.stop();
    _zoomAnimController?.dispose();

    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _zoomAnimController!,
      curve: Curves.easeOutCubic,
    ));

    animation.addListener(() {
      _transformationController.value = animation.value;
    });

    _zoomAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _transformationController.value = Matrix4.identity();
        if (mounted) {
          setState(() {
            _isPhotoZoomed = false;
          });
        }
      }
    });

    _zoomAnimController!.forward();
  }

  void _zoomToPosition(Offset tapPos) {
    _zoomAnimController?.stop();
    _zoomAnimController?.dispose();

    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final bool isZoomed = currentScale > 1.05 || _isPhotoZoomed;

    final Matrix4 endMatrix;
    if (isZoomed) {
      endMatrix = Matrix4.identity();
    } else {
      const double targetScale = 2.5;
      endMatrix = Matrix4.identity()
        ..translateByDouble(tapPos.dx, tapPos.dy, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0)
        ..translateByDouble(-tapPos.dx, -tapPos.dy, 0.0, 1.0);
    }

    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    final animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController!,
      curve: Curves.easeOutCubic,
    ));

    animation.addListener(() {
      _transformationController.value = animation.value;
    });

    _zoomAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        if (isZoomed) {
          _transformationController.value = Matrix4.identity();
        }
        setState(() {
          _isPhotoZoomed = !isZoomed;
        });
      }
    });

    HapticFeedback.lightImpact();
    _zoomAnimController!.forward();
  }

  void _handleDoubleTap() {
    if (_doubleTapDetails == null) return;
    _zoomToPosition(_doubleTapDetails!.localPosition);
  }

  Widget _buildPhotoPage(MediaItem it) {
    return Center(
      child: Stack(
        fit: StackFit.passthrough,
        alignment: Alignment.center,
        children: [
          _thumb(it.id, BoxFit.contain),
          Image(
            image: displayImage(it.path),
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image, size: 80, color: Colors.white38),
            ),
          ),
        ],
      ),
    );
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
          _transformationController.value = Matrix4.identity();
          _isPhotoZoomed = false;
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
            _transformationController.value = Matrix4.identity();
            _isPhotoZoomed = false;
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
        _transformationController.value = Matrix4.identity();
        _isPhotoZoomed = false;
      });
      _page.jumpToPage(_current);
    }
  }

  void _showMoreOptions(MediaItem item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit_outlined, color: Colors.white),
                title: const Text('Rename',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  final updated =
                      await showRenameMediaDialog(context, item, ref);
                  if (updated != null && mounted) {
                    setState(() {
                      widget.items[_current] = updated;
                    });
                  }
                },
              ),
              ListTile(
                leading:
                    const Icon(Icons.wallpaper_outlined, color: Colors.white),
                title: const Text('Set as wallpaper',
                    style: TextStyle(color: Colors.white, fontSize: 15)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ShareService.setAsWallpaper(item.path);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final showBars = _barsVisible && !_isCurrentlyZoomed && !_isPinching;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Listener(
        onPointerDown: (e) {
          _activePointers.add(e.pointer);
          _settle.stop(); // grab a returning image mid-flight
          _zoomAnimController?.stop();
          if (_activePointers.length >= 2 || _isCurrentlyZoomed) {
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
          _vt.addPosition(e.timeStamp, e.position);
        },
        onPointerMove: (e) {
          // While zoomed in, pinching, or multi-touching, NEVER pull-to-dismiss
          if (_startDragY == null ||
              _startDragX == null ||
              _isCurrentlyZoomed ||
              _isPinching ||
              _isMultiTouch ||
              _activePointers.length >= 2) {
            if (_drag.value != Offset.zero) _setDrag(Offset.zero);
            return;
          }
          _vt.addPosition(e.timeStamp, e.position);
          final dy = e.position.dy - _startDragY!;
          final dx = e.position.dx - _startDragX!;
          // Responsive vertical swipe deadzone: natural downward drag (dy > 8 and dy > dx.abs() * 1.1)
          if (_drag.value != Offset.zero || (dy > 8 && dy > dx.abs() * 1.1)) {
            final dampedDx = dx * 0.35;
            final dragY = (dy - 8).clamp(0.0, 600.0);
            _setDrag(Offset(dampedDx, dragY));
          }
        },
        onPointerUp: (e) {
          _vt.addPosition(e.timeStamp, e.position);
          _activePointers.remove(e.pointer);

          if (_activePointers.isEmpty) {
            final wasMultiTouch = _isMultiTouch;
            _isMultiTouch = false;
            _isPinching = false;
            _startDragY = null;
            _startDragX = null;
            final d = _drag.value;
            final vy = _vt.getVelocity().pixelsPerSecond.dy;

            if (!wasMultiTouch &&
                !_isCurrentlyZoomed &&
                d.dy > 0 &&
                (d.dy > 100 || (vy > 600 && d.dy > 25))) {
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
          if (_activePointers.isEmpty) {
            _isMultiTouch = false;
            _isPinching = false;
            _startDragY = null;
            _startDragX = null;
            if (_drag.value != Offset.zero) _springBack(0);
          }
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (_drag.value.dy < 10) {
              _toggleBars();
            }
          },
          onDoubleTapDown: (details) {
            _doubleTapDetails = details;
          },
          onDoubleTap: _handleDoubleTap,
          child: Stack(
            children: [
              // ── Background scrim: opacity follows drag distance ──
              Positioned.fill(
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _drag,
                  builder: (_, d, __) => ColoredBox(
                    color: Colors.black.withValues(
                        alpha: (1.0 - (d.dy / 350)).clamp(0.0, 1.0)),
                  ),
                ),
              ),
              // ── Gallery: translate + proportional scale-down ─────
              ValueListenableBuilder<Offset>(
                valueListenable: _drag,
                builder: (_, d, child) {
                  final s = (1.0 - (d.dy / 800) * 0.25).clamp(0.75, 1.0);
                  return Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.translationValues(d.dx, d.dy, 0)
                      ..scaleByDouble(s, s, 1.0, 1.0),
                    child: child,
                  );
                },
                child: PageView.builder(
                  controller: _page,
                  itemCount: widget.items.length,
                  onPageChanged: (i) {
                    setState(() {
                      _current = i;
                      _isPhotoZoomed = false;
                      _isPinching = false;
                      _transformationController.value = Matrix4.identity();
                    });
                    _precacheAdjacent(i);
                  },
                  physics: (_isCurrentlyZoomed ||
                          _isPinching ||
                          _isMultiTouch ||
                          _activePointers.length >= 2)
                      ? const NeverScrollableScrollPhysics()
                      : const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                  itemBuilder: (context, index) {
                    final it = widget.items[index];
                    if (index == _current) {
                      return Center(
                        child: ClipRect(
                          child: InteractiveViewer(
                            transformationController: _transformationController,
                            minScale: 1.0,
                            maxScale: 6.0,
                            panEnabled: _isCurrentlyZoomed,
                            scaleEnabled: true,
                            clipBehavior: Clip.hardEdge,
                            onInteractionStart: (details) {
                              _zoomAnimController?.stop();
                              if (details.pointerCount >= 2) {
                                _isPinching = true;
                              }
                            },
                            onInteractionUpdate: (details) {
                              final scale = _transformationController
                                  .value
                                  .getMaxScaleOnAxis();
                              final isZoomed = scale > 1.05;
                              if (isZoomed != _isPhotoZoomed) {
                                setState(() {
                                  _isPhotoZoomed = isZoomed;
                                });
                              }
                            },
                            onInteractionEnd: (details) {
                              _isPinching = false;
                              final scale = _transformationController
                                  .value
                                  .getMaxScaleOnAxis();
                              if (scale <= 1.02) {
                                _resetPhotoZoom();
                              } else {
                                if (!_isPhotoZoomed && mounted) {
                                  setState(() {
                                    _isPhotoZoomed = true;
                                  });
                                }
                              }
                            },
                            child: Center(
                              child: Hero(
                                tag: it.id,
                                transitionOnUserGestures: true,
                                flightShuttleBuilder: (
                                  flightContext,
                                  animation,
                                  flightDirection,
                                  fromHeroContext,
                                  toHeroContext,
                                ) =>
                                    _buildHeroShuttle(
                                  animation: animation,
                                  flightDirection: flightDirection,
                                  id: it.id,
                                  path: it.path,
                                ),
                                child: _buildPhotoPage(it),
                              ),
                            ),
                          ),
                        ),
                      );
                    }
                    return _buildPhotoPage(it);
                  },
                ),
              ),

            // ── Top bar ────────────────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _drag,
                  builder: (context, d, child) => AnimatedOpacity(
                    opacity: (showBars && d.dy < 20) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !showBars || d.dy >= 20,
                      child: child,
                    ),
                  ),
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
                                  MediaUtils.formatViewerDate(item.date),
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
                                  MediaUtils.formatViewerTime(item.date),
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
                          if (!widget.isTrash)
                            IconButton(
                              icon: const Icon(Icons.info_outline,
                                  color: Colors.white, size: 22),
                              tooltip: 'Details',
                              onPressed: () =>
                                  showMediaInfoSheet(context, item),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Bottom action bar (Photo 2 reference) ───────────
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<Offset>(
                  valueListenable: _drag,
                  builder: (context, d, child) => AnimatedOpacity(
                    opacity: (showBars && d.dy < 20) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeInOut,
                    child: IgnorePointer(
                      ignoring: !showBars || d.dy >= 20,
                      child: child,
                    ),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: widget.isTrash
                          ? Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _ViewerActionButton(
                                  icon: const Icon(Icons.restore,
                                      color: Colors.white, size: 22),
                                  label: 'Restore',
                                  onTap: _restoreCurrentItem,
                                ),
                                _ViewerActionButton(
                                  icon: const Icon(Icons.info_outline,
                                      color: Colors.white, size: 22),
                                  label: 'Details',
                                  onTap: () =>
                                      showMediaInfoSheet(context, item),
                                ),
                                _ViewerActionButton(
                                  icon: const Icon(Icons.delete_forever,
                                      color: Colors.white, size: 22),
                                  label: 'Delete',
                                  onTap: _deleteCurrentItem,
                                ),
                              ],
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _ViewerActionButton(
                                  icon: const Icon(Icons.share_outlined,
                                      color: Colors.white, size: 22),
                                  label: 'Share',
                                  onTap: () => ShareService.shareSingle(
                                      item.path,
                                      isVideo: false),
                                ),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final isFav = ref.watch(
                                      settingsNotifierProvider.select(
                                        (s) => s.favoriteIds.contains(item.id),
                                      ),
                                    );
                                    return _ViewerActionButton(
                                      icon: Icon(
                                        isFav ? Icons.favorite : Icons.favorite_border,
                                        color: isFav ? Colors.redAccent : Colors.white,
                                        size: 22,
                                      ),
                                      label: 'Favorite',
                                      onTap: () {
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
                                _ViewerActionButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.white, size: 22),
                                  label: 'Delete',
                                  onTap: _deleteCurrentItem,
                                ),
                                _ViewerActionButton(
                                  icon: const Icon(Icons.more_vert,
                                      color: Colors.white, size: 22),
                                  label: 'More',
                                  onTap: () => _showMoreOptions(item),
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
      ),
    );
  }
}

class _ViewerActionButton extends StatelessWidget {
  const _ViewerActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return BouncyTap(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            icon,
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

