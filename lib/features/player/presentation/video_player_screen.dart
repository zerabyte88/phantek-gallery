import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/screen_keeper_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/bouncy_tap.dart';
import 'widgets/media_info_sheet.dart';
import 'widgets/rename_dialog.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({
    super.key,
    this.item,
    this.items,
    this.initialIndex = 0,
    this.isTrash = false,
  }) : assert(item != null || (items != null && items.length > 0));

  final MediaItem? item;
  final List<MediaItem>? items;
  final int initialIndex;
  final bool isTrash;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  late final Player _player;
  late final VideoController _controller;
  late final List<MediaItem> _videos;
  late final PageController _pageController;
  late final TransformationController _transformationController;
  late int _current;
  bool _showControls = true;
  bool _isFullscreen = false;
  bool _isLooping = false;
  double _playbackSpeed = 1.0;
  // Drag-to-dismiss offset lives in a notifier so pointer-move never rebuilds
  // the PageView / InteractiveViewer hierarchy.
  final ValueNotifier<Offset> _dragNotifier = ValueNotifier(Offset.zero);
  final ValueNotifier<bool> _isDraggingDown = ValueNotifier(false);
  bool _isSwipingHorizontal = false;
  late final AnimationController _settle;
  Offset _settleFrom = Offset.zero;
  VelocityTracker _vt = VelocityTracker.withKind(PointerDeviceKind.touch);
  double? _startDragY;
  double? _startDragX;
  TapDownDetails? _doubleTapDetails;
  bool _isSwiping = false;
  // Controls the visibility of the active Video() texture surface.
  final ValueNotifier<bool> _videoSurfaceVisible = ValueNotifier(false);
  // Controls the opacity of the center play button during horizontal page swipe.
  final ValueNotifier<bool> _isSwipingPage = ValueNotifier(false);
  int? _pendingIndex;
  bool _isVideoZoomed = false;
  bool _isPinching = false;
  bool _isMultiTouch = false;
  final Set<int> _activePointers = {};
  AnimationController? _zoomAnimController;
  bool _hasStartedPlaying = false;

  bool get _isCurrentlyVideoZoomed {
    return _transformationController.value.getMaxScaleOnAxis() > 1.05;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.items != null && widget.items!.isNotEmpty) {
      _videos = List<MediaItem>.from(widget.items!);
      _current = widget.initialIndex.clamp(0, _videos.length - 1);
    } else {
      _videos = [widget.item!];
      _current = 0;
    }
    _pageController = PageController(initialPage: _current);
    _transformationController = TransformationController();
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        final current = _settleFrom * _settle.value;
        _setDrag(current);
        if (!_settle.isAnimating && _activePointers.isEmpty) {
          _setDrag(Offset.zero);
          _isDraggingDown.value = false;
        }
      });
    _initPlayer();
    if (ref.read(settingsNotifierProvider).keepScreenOn) {
      ScreenKeeperService.setKeepScreenOn(true);
    }
    _precacheAdjacentVideos(_current);
  }

  void _setDrag(Offset o) {
    _dragNotifier.value = o;
    final isDown = o != Offset.zero;
    if (_isDraggingDown.value != isDown) {
      _isDraggingDown.value = isDown;
    }
  }

  /// Spring the dragged video back to center, carrying release velocity.
  void _springBack(double vy) {
    _settleFrom = _dragNotifier.value;
    if (_settleFrom == Offset.zero) {
      _isDraggingDown.value = false;
      return;
    }
    final v = _settleFrom.dy.abs() > 1 ? vy / _settleFrom.dy : 0.0;
    _settle.value = 1.0;
    _settle.animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 1.0, stiffness: 320, ratio: 0.82),
      1.0,
      0.0,
      v.clamp(-8.0, 8.0),
    ));
  }

  void _resetVideoZoom() {
    if (!_isVideoZoomed && _transformationController.value.isIdentity()) return;
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
            _isVideoZoomed = false;
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
    final bool isZoomed = currentScale > 1.05 || _isVideoZoomed;

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
          _isVideoZoomed = !isZoomed;
        });
      }
    });

    _zoomAnimController!.forward();
  }

  void _precacheAdjacentVideos(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final offset in const [-2, -1, 0, 1, 2]) {
        final target = index + offset;
        if (target >= 0 && target < _videos.length) {
          final video = _videos[target];
          final mem = ThumbnailService.instance.getMemoryThumbnail(video.id);
          if (mem != null && mounted) {
            precacheImage(MemoryImage(mem), context);
          } else {
            final file = ThumbnailService.instance.getCachedFile(video.id);
            if (file != null && mounted) {
              precacheImage(FileImage(file), context);
            } else {
              ThumbnailService.instance
                  .getThumbnail(video.id, filePath: video.path, isVideo: true)
                  .then((bytes) {
                if (bytes != null && mounted) {
                  precacheImage(MemoryImage(bytes), context);
                }
              });
            }
          }
        }
      }
    });
  }

  void _initPlayer() {
    final settings = ref.read(settingsNotifierProvider);
    _player = Player(
      configuration: const PlayerConfiguration(
        bufferSize: 32 * 1024 * 1024, // 32 MB buffer
        logLevel: MPVLogLevel.warn,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        enableHardwareAcceleration: settings.hardwareAcceleration,
        hwdec: settings.hardwareAcceleration ? 'auto-copy' : 'no',
      ),
    );

    // MPV properties:
    // 1. Restrict hardware decoding to stable decoders on Snapdragon 685; exclude VP9, VP8, AV1
    //    Snapdragon 685 MediaCodec hangs when negotiating VP9 profiles without falling back to SW.
    // 2. Allow Opus/Vorbis audio demuxing and decoding within WebM containers.
    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      native.setProperty('hwdec-codecs', 'h264,hevc,mpeg4,vc1');
      native.setProperty('demuxer-lavf-buffersize', '8388608'); // 8 MB, within Android limit
      native.setProperty('demuxer-max-bytes', '33554432'); // 32 MB read-ahead
      native.setProperty('demuxer-max-back-bytes', '33554432'); // 32 MB backward seek buffer
      native.setProperty('demuxer-readahead-secs', '10');
      native.setProperty('demuxer-lavf-probesize', '2097152');
      native.setProperty('hr-seek-framedrop', 'yes');
    }

    _player.stream.error.listen((err) {
      debugPrint('[VideoPlayer] Playback error: $err');
      // Filter non-fatal MPV warnings that occur during normal HW→SW codec fallback,
      // keyframe seeking, or stream buffer flushes.
      final errLower = err.toString().toLowerCase();
      final isNonFatal = errLower.contains('could not open codec') ||
          errLower.contains('decoder init failed') ||
          errLower.contains('hwdec') ||
          errLower.contains('using software decoding') ||
          errLower.contains('error decoding') ||
          errLower.contains('cannot decode') ||
          errLower.contains('invalid data') ||
          errLower.contains('corrupt') ||
          errLower.contains('missing picture') ||
          errLower.contains('packet');
      if (mounted && !isNonFatal) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback warning: $err'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    _player.stream.playing.listen((playing) {
      if (playing && mounted) {
        if (!_videoSurfaceVisible.value) {
          _videoSurfaceVisible.value = true;
        }
        if (!_hasStartedPlaying) {
          setState(() {
            _hasStartedPlaying = true;
          });
        }
      }
    });

    _player.stream.videoParams.listen((params) {
      if (mounted && params.w != null && params.h != null && params.w! > 0 && params.h! > 0) {
        setState(() {});
      }
    });

    final currentPath = _videos[_current].path;
    final isWebM = currentPath.toLowerCase().endsWith('.webm');
    if (_player.platform is NativePlayer) {
      final native = _player.platform as NativePlayer;
      if (isWebM) {
        native.setProperty('hwdec', 'no');
      } else {
        native.setProperty(
            'hwdec', settings.hardwareAcceleration ? 'auto-copy' : 'no');
      }
    }

    _videoSurfaceVisible.value = false;
    _player.open(
      Media(currentPath),
      play: settings.autoPlayVideo,
    );
  }

  void _changeToVideo(int index) {
    if (index == _current) return;
    if (_isVideoZoomed || !_transformationController.value.isIdentity()) {
      _zoomAnimController?.stop();
      _zoomAnimController?.dispose();
      _zoomAnimController = null;
      _transformationController.value = Matrix4.identity();
      _isVideoZoomed = false;
    }
    setState(() {
      _current = index;
      _hasStartedPlaying = false;
    });

    _videoSurfaceVisible.value = false;

    // Open after the frame is built so the native call never lands mid-gesture.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || _current != index) return;
      try {
        final settings = ref.read(settingsNotifierProvider);
        final path = _videos[index].path;
        final isWebM = path.toLowerCase().endsWith('.webm');
        if (_player.platform is NativePlayer) {
          final native = _player.platform as NativePlayer;
          if (isWebM) {
            native.setProperty('hwdec', 'no');
          } else {
            native.setProperty(
                'hwdec', settings.hardwareAcceleration ? 'auto-copy' : 'no');
          }
        }
        await _player.open(Media(path), play: settings.autoPlayVideo);
        if (_isLooping) _player.setPlaylistMode(PlaylistMode.loop);
        if (_playbackSpeed != 1.0) _player.setRate(_playbackSpeed);
      } catch (_) {}
    });
    if (_isFullscreen) {
      if (_isCurrentVideoPortrait()) {
        SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
      } else {
        SystemChrome.setPreferredOrientations([
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ]);
      }
    }
    _precacheAdjacentVideos(index);
  }

  void _onPageChanged(int index) {
    if (_isSwiping) {
      // User is actively sliding/swiping between pages.
      // We keep the transition at 60/120fps by deferring the heavy native player
      // switch until the scroll animation has settled.
      _pendingIndex = index;
      _precacheAdjacentVideos(index);
    } else {
      _changeToVideo(index);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-pause on background to prevent memory / battery drain.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _player.pause();
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _transformationController.value = Matrix4.identity();
    if (_isVideoZoomed && mounted) {
      setState(() => _isVideoZoomed = false);
    }
  }

  @override
  void dispose() {
    ScreenKeeperService.setKeepScreenOn(false);
    WidgetsBinding.instance.removeObserver(this);
    _zoomAnimController?.dispose();
    _settle.dispose();
    _isDraggingDown.dispose();
    _videoSurfaceVisible.dispose();
    _isSwipingPage.dispose();
    _dragNotifier.dispose();
    _transformationController.dispose();
    _player.dispose(); // releases native MPV context
    _pageController.dispose();
    _exitFullscreen();
    super.dispose();
  }

  bool _isVideoPortrait(MediaItem item, int index) {
    if (index == _current) {
      final vParams = _player.state.videoParams;
      if (vParams.w != null && vParams.h != null && vParams.w! > 0 && vParams.h! > 0) {
        final rotate = vParams.rotate ?? 0;
        final isRotated90or270 = rotate == 90 || rotate == 270;
        final effectiveW = isRotated90or270 ? vParams.h! : vParams.w!;
        final effectiveH = isRotated90or270 ? vParams.w! : vParams.h!;
        return effectiveH > effectiveW;
      }
    }
    final thumbRatio = ThumbnailService.instance.getThumbnailAspectRatio(item.id);
    if (thumbRatio != null && thumbRatio > 0) {
      return thumbRatio < 1.0;
    }
    if (item.width != null && item.height != null && item.width! > 0 && item.height! > 0) {
      return item.height! > item.width!;
    }
    return false;
  }

  bool _isCurrentVideoPortrait() {
    return _isVideoPortrait(_videos[_current], _current);
  }

  void _enterFullscreen() {
    if (_isVideoZoomed || !_transformationController.value.isIdentity()) {
      _zoomAnimController?.stop();
      _transformationController.value = Matrix4.identity();
      _isVideoZoomed = false;
    }
    if (_isCurrentVideoPortrait()) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _isFullscreen = true);
  }

  void _exitFullscreen() {
    if (_isVideoZoomed || !_transformationController.value.isIdentity()) {
      _zoomAnimController?.stop();
      _transformationController.value = Matrix4.identity();
      _isVideoZoomed = false;
    }
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _isFullscreen = false);
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      _exitFullscreen();
    } else {
      _enterFullscreen();
    }
  }

  void _toggleOrientation() {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    HapticFeedback.lightImpact();
    if (isLandscape) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  double _resolveAspectRatio(MediaItem item, int index) {
    // 1. Prioritize visual thumbnail aspect ratio on frame 0
    // This perfectly matches the thumbnail already rendered in memory/disk with zero stretch or snap
    final thumbRatio = ThumbnailService.instance.getThumbnailAspectRatio(item.id);
    if (thumbRatio != null && thumbRatio > 0) {
      return thumbRatio;
    }

    // 2. Active player videoParams (includes native rotation matrix)
    if (index == _current) {
      final vParams = _player.state.videoParams;
      if (vParams.w != null && vParams.h != null && vParams.w! > 0 && vParams.h! > 0) {
        final rotate = vParams.rotate ?? 0;
        final isRot90or270 = rotate == 90 || rotate == 270;
        final w = isRot90or270 ? vParams.h! : vParams.w!;
        final h = isRot90or270 ? vParams.w! : vParams.h!;
        return w / h;
      }
    }

    // 3. Fallback to MediaItem metadata
    if (item.width != null && item.height != null && item.width! > 0 && item.height! > 0) {
      return item.width! / item.height!;
    }

    return 16.0 / 9.0;
  }

  Widget _buildVideoPage(int index) {
    final item = _videos[index];
    final isVertical = _isVideoPortrait(item, index);
    final content = Stack(
      alignment: Alignment.center,
      children: [
        _VideoThumbnailPage(
          item: item,
          fit: isVertical ? BoxFit.cover : BoxFit.contain,
        ),
        if (index == _current)
          ValueListenableBuilder<bool>(
            valueListenable: _videoSurfaceVisible,
            builder: (context, visible, _) => AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              opacity: visible ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !visible,
                child: Video(
                  key: const ValueKey('active_video_surface'),
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: isVertical ? BoxFit.cover : BoxFit.contain,
                  fill: Colors.transparent,
                ),
              ),
            ),
          ),
      ],
    );

    if (isVertical) {
      return SizedBox.expand(child: content);
    }

    final ratio = _resolveAspectRatio(item, index);
    return AspectRatio(
      aspectRatio: ratio,
      child: content,
    );
  }

  void _handleDoubleTap() {
    if (_doubleTapDetails == null) return;
    final pos = _doubleTapDetails!.localPosition;

    HapticFeedback.lightImpact();
    _zoomToPosition(pos);
  }

  void _showPlaybackSpeedSheet() {
    final speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final cs = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  context.tr.playbackSpeedTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                ...speeds.map((speed) {
                  final isSelected = _playbackSpeed == speed;
                  return ListTile(
                    dense: true,
                    title: Text(
                      speed == 1.0 ? '1.0x (${context.tr.normal})' : '${speed}x',
                      style: TextStyle(
                        color: isSelected ? cs.primary : Colors.white,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: cs.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _playbackSpeed = speed;
                      });
                      _player.setRate(speed);
                      HapticFeedback.lightImpact();
                    },
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  void _toggleLoop() {
    final next = !_isLooping;
    setState(() {
      _isLooping = next;
    });
    _player.setPlaylistMode(next ? PlaylistMode.loop : PlaylistMode.none);
    HapticFeedback.lightImpact();
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        content: Text(next ? context.tr.loopEnabled : context.tr.loopDisabled),
      ),
    );
  }

  Future<void> _renameCurrentItem() async {
    final item = _videos[_current];
    final updated = await showRenameMediaDialog(context, item, ref);
    if (updated != null && mounted) {
      setState(() {
        _videos[_current] = updated;
      });
    }
  }

  Future<void> _restoreItem() async {
    final item = _videos[_current];
    _player.pause();
    await ref.read(trashProvider.notifier).restore(item.id);
    ref.read(mediaListProvider.notifier).restoreItems([item.id]);
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr.itemRestored(item.name))),
      );
      if (_videos.length <= 1) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _videos.removeAt(_current);
          _current = _current.clamp(0, _videos.length - 1);
        });
        _pageController.jumpToPage(_current);
        _player.open(Media(_videos[_current].path), play: false);
      }
    }
  }

  Future<void> _deleteItem() async {
    final item = _videos[_current];

    if (widget.isTrash) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(context.tr.deletePermanentlyTitle),
          content: Text(
            context.tr.deletePermanentlyConfirm(item.name),
          ),
          actionsOverflowButtonSpacing: 8,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(context.tr.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: Text(context.tr.delete),
            ),
          ],
        ),
      );
      if (ok != true || !mounted) return;

      _player.pause();
      await ref.read(trashProvider.notifier).permanentDelete(item.id);

      if (!mounted) return;
      if (_videos.length <= 1) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _videos.removeAt(_current);
          _current = _current.clamp(0, _videos.length - 1);
        });
        _pageController.jumpToPage(_current);
        _player.open(Media(_videos[_current].path), play: false);
      }
      return;
    }

    final settings = ref.read(settingsNotifierProvider);
    final isTrash = settings.enableTrash;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(isTrash ? context.tr.moveToTrashTitle : context.tr.deletePermanentlyTitle),
        content: Text(
          isTrash
              ? context.tr.moveToTrashConfirm(item.name)
              : context.tr.deletePermanentlyConfirm(item.name),
        ),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr.cancel),
          ),
          FilledButton(
            style: isTrash
                ? null
                : FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isTrash ? context.tr.moveToTrash : context.tr.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final hasPerm = await PermissionService.instance.ensureManageStorage();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr.manageFilesPermissionRequired),
          ),
        );
      }
      return;
    }

    _player.pause();

    // 1. Immediately remove from global media list provider
    ref.read(mediaListProvider.notifier).removeItems({item.id});

    try {
      if (settings.enableTrash) {
        await ref.read(trashProvider.notifier).moveToTrash(
              id: item.id,
              path: item.path,
              isVideo: true,
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
          SnackBar(content: Text(context.tr.failedToDelete(e.toString()))),
        );
      }
      return;
    }

    if (!mounted) return;
    if (_videos.length <= 1) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _videos.removeAt(_current);
        _current = _current.clamp(0, _videos.length - 1);
        _transformationController.value = Matrix4.identity();
        _isVideoZoomed = false;
      });
      _pageController.jumpToPage(_current);
      _player.open(Media(_videos[_current].path), play: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _videos[_current];


    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) {
          _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // ── Background scrim: opacity follows drag distance ──
            Positioned.fill(
              child: ValueListenableBuilder<Offset>(
                valueListenable: _dragNotifier,
                builder: (_, d, __) => ColoredBox(
                  color: Colors.black.withValues(
                      alpha: (1.0 - (d.dy / 320.0)).clamp(0.0, 1.0)),
                ),
              ),
            ),
            // ── Main Content inside SafeArea and Listener ──────────
            SafeArea(
              top: !_isFullscreen,
              bottom: !_isFullscreen,
              left: !_isFullscreen,
              right: !_isFullscreen,
              child: Listener(
                onPointerDown: (e) {
                  _activePointers.add(e.pointer);
                  _settle.stop(); // grab a returning video mid-flight
                  _zoomAnimController?.stop();
                  _isSwipingHorizontal = false;
                  if (_activePointers.length == 1) {
                    _isMultiTouch = false;
                    _isPinching = false;
                    if (_transformationController.value.getMaxScaleOnAxis() <= 1.05) {
                      _isVideoZoomed = false;
                    }
                  }
                  if (_activePointers.length >= 2 || _isCurrentlyVideoZoomed) {
                    // Instantly lock PageView swiping and abort pull-to-dismiss on multi-touch, pinch, or zoom
                    _isMultiTouch = true;
                    _isPinching = true;
                    _startDragY = null;
                    _startDragX = null;
                    if (_dragNotifier.value != Offset.zero) _setDrag(Offset.zero);
                    return;
                  }
                  _startDragY = e.position.dy;
                  _startDragX = e.position.dx;
                  _vt = VelocityTracker.withKind(e.kind);
                  _vt.addPosition(e.timeStamp, e.position);
                },
                onPointerMove: (e) {
                  // Detach the MPV texture on the first horizontal movement, before
                  // the PageView's own drag slop triggers ScrollStartNotification.
                  if (_videoSurfaceVisible.value &&
                      !_isCurrentlyVideoZoomed &&
                      !_isMultiTouch &&
                      !_isPinching &&
                      _activePointers.length == 1 &&
                      _startDragX != null &&
                      _startDragY != null) {
                    final adx = (e.position.dx - _startDragX!).abs();
                    final ady = (e.position.dy - _startDragY!).abs();
                    if (adx > 10 && adx > ady * 1.3) {
                      _videoSurfaceVisible.value = false;
                      _isSwipingHorizontal = true;
                      _isSwipingPage.value = true;
                      return;
                    }
                  }

                  if (_isSwipingHorizontal) return;

                  // Keep pull-to-dismiss and page swiping completely locked whenever
                  // the video is zoomed above 1.0x, pinching, or multi-touching.
                  if (_isFullscreen ||
                      _isCurrentlyVideoZoomed ||
                      _isPinching ||
                      _isMultiTouch ||
                      _activePointers.length >= 2 ||
                      _startDragY == null ||
                      _startDragX == null) {
                    if (_dragNotifier.value != Offset.zero) _setDrag(Offset.zero);
                    return;
                  }

                  _vt.addPosition(e.timeStamp, e.position);
                  final dy = e.position.dy - _startDragY!;
                  final dx = e.position.dx - _startDragX!;
                  // Responsive vertical swipe deadzone: natural downward drag (dy > 6 and dy > dx.abs() * 0.75)
                  if (_dragNotifier.value != Offset.zero || (dy > 6 && dy > dx.abs() * 0.75)) {
                    final dampedDx = dx * 0.45;
                    final dragY = (dy - 6).clamp(0.0, 650.0);
                    _setDrag(Offset(dampedDx, dragY));
                    if (_player.state.playing && dy > 12) {
                      _player.pause();
                    }
                  }
                },
                onPointerUp: (e) {
                  _vt.addPosition(e.timeStamp, e.position);
                  _activePointers.remove(e.pointer);
                  if (_activePointers.isEmpty) {
                    final wasMultiTouch = _isMultiTouch;
                    _isMultiTouch = false;
                    _isPinching = false;
                    _isSwipingHorizontal = false;
                    _startDragY = null;
                    _startDragX = null;
                    if (!_isSwiping) {
                      _isSwipingPage.value = false;
                    }
                    // Restore video surface if not swiping and player is playing
                    if (!_isSwiping && _player.state.playing) {
                      _videoSurfaceVisible.value = true;
                    }

                    final d = _dragNotifier.value;
                    final vy = _vt.getVelocity().pixelsPerSecond.dy;

                    if (!wasMultiTouch &&
                        !_isCurrentlyVideoZoomed &&
                        d.dy > 0 &&
                        (d.dy > 85 || (vy > 550 && d.dy > 20))) {
                      _player.pause();
                      Navigator.of(context).pop();
                    } else if (d != Offset.zero) {
                      _springBack(vy);
                    }
                  }
                },
                onPointerCancel: (e) {
                  _activePointers.remove(e.pointer);
                  if (_activePointers.isEmpty) {
                    _isMultiTouch = false;
                    _isPinching = false;
                    _isSwipingHorizontal = false;
                    _startDragY = null;
                    _startDragX = null;
                    if (!_isSwiping) {
                      _isSwipingPage.value = false;
                    }
                    if (_dragNotifier.value != Offset.zero) _springBack(0);
                  }
                },
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_dragNotifier.value.dy < 10) {
                      setState(() => _showControls = !_showControls);
                    }
                  },
                  onDoubleTapDown: (details) {
                    _doubleTapDetails = details;
                  },
                  onDoubleTap: _handleDoubleTap,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // ── Video PageView with translation + proportional scale-down + smooth corner radius ──
                      ValueListenableBuilder<Offset>(
                        valueListenable: _dragNotifier,
                        builder: (context, d, child) {
                          final s = (1.0 - (d.dy / 1000.0) * 0.28).clamp(0.72, 1.0);
                          final radius = (d.dy > 0 ? (d.dy / 12.0).clamp(0.0, 20.0) : 0.0);
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.translationValues(d.dx, d.dy, 0)
                              ..scaleByDouble(s, s, 1.0, 1.0),
                            child: radius > 0
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(radius),
                                    child: child,
                                  )
                                : child,
                          );
                        },
                        child: RepaintBoundary(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollStartNotification) {
                          if (notification.dragDetails != null) {
                            _isSwiping = true;
                            _isSwipingPage.value = true;
                            _videoSurfaceVisible.value = false;
                            // Immediately pause playback on swipe to free hardware decoder
                            // and GPU pipeline for silky-smooth 60/120fps motion.
                            if (_player.state.playing) {
                              _player.pause();
                            }
                          }
                        } else if (notification is ScrollUpdateNotification) {
                          if (notification.dragDetails != null && !_isSwiping) {
                            _isSwiping = true;
                            _isSwipingPage.value = true;
                            _videoSurfaceVisible.value = false;
                            if (_player.state.playing) {
                              _player.pause();
                            }
                          }
                        } else if (notification is ScrollEndNotification) {
                          final settledPage = _pageController.page?.round();
                          final target = _pendingIndex ?? settledPage;
                          final changing = target != null &&
                              target != _current &&
                              target >= 0 &&
                              target < _videos.length;
                          _isSwiping = false;
                          _isSwipingPage.value = false;
                          _pendingIndex = null;
                          if (changing) {
                            // _changeToVideo re-mounts the texture once loaded.
                            _changeToVideo(target);
                          }
                        }
                        return false;
                      },
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isDraggingDown,
                        builder: (context, isDraggingDown, _) {
                          return PageView.builder(
                            controller: _pageController,
                            itemCount: _videos.length,
                            onPageChanged: _onPageChanged,
                            physics: (_isCurrentlyVideoZoomed ||
                                    _isPinching ||
                                    _isMultiTouch ||
                                    _activePointers.length >= 2 ||
                                    isDraggingDown)
                                ? const NeverScrollableScrollPhysics()
                                : const BouncingScrollPhysics(),
                            itemBuilder: (context, index) {
                          if (index == _current) {
                            return Center(
                              child: ClipRect(
                                child: InteractiveViewer(
                                  key: ValueKey('iv_${_videos[index].id}_${_isFullscreen}_${MediaQuery.orientationOf(context)}'),
                                  transformationController:
                                      _transformationController,
                                  minScale: 1.0,
                                  maxScale: 6.0,
                                  panEnabled: _isCurrentlyVideoZoomed,
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
                                    if (isZoomed != _isVideoZoomed) {
                                      _isVideoZoomed = isZoomed;
                                    }
                                  },
                                  onInteractionEnd: (details) {
                                    _isPinching = false;
                                    final scale = _transformationController
                                        .value
                                        .getMaxScaleOnAxis();
                                    if (scale <= 1.02) {
                                      _resetVideoZoom();
                                    } else {
                                      if (!_isVideoZoomed && mounted) {
                                        setState(() {
                                          _isVideoZoomed = true;
                                        });
                                      }
                                    }
                                  },
                                  child: Center(
                                    child: Hero(
                                      tag: _videos[index].id,
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
                                        item: _videos[index],
                                      ),
                                      child: _buildVideoPage(index),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return Center(child: _buildVideoPage(index));
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
                  



                  // ── Video zoom indicator and reset pill ──────────────────
                  if (_isVideoZoomed)
                    Positioned(
                      top: _showControls
                          ? 80
                          : (MediaQuery.of(context).padding.top + 16),
                      right: 16,
                      child: SafeArea(
                        top: !_showControls,
                        child: BouncyTap(
                          onTap: _resetVideoZoom,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black45,
                                  blurRadius: 8,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.zoom_out_map_rounded,
                                  color: Colors.white,
                                  size: 16,
                                ),
                                const SizedBox(width: 6),
                                ValueListenableBuilder<Matrix4>(
                                  valueListenable: _transformationController,
                                  builder: (context, matrix, _) {
                                    final scale = matrix.getMaxScaleOnAxis();
                                    return Text(
                                      '${scale.toStringAsFixed(1)}x • Reset',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.3,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Controls overlay ───────────────────────────────
                  ValueListenableBuilder<Offset>(
                    valueListenable: _dragNotifier,
                    builder: (context, drag, child) {
                      final dragFade = (1.0 - (drag.dy / 35.0)).clamp(0.0, 1.0);
                      final effectiveOpacity = (_showControls && !_isPinching) ? dragFade : 0.0;
                      return Opacity(
                        opacity: effectiveOpacity,
                        child: IgnorePointer(
                          ignoring: !_showControls || drag.dy > 4 || _isPinching,
                          child: child,
                        ),
                      );
                    },
                    child: Stack(
                      children: [
                        // Center play button when paused (exact center of the screen)
                        // In landscape: completely removed.
                        // In portrait: only shown before the video has ever started playing.
                        if (MediaQuery.orientationOf(context) != Orientation.landscape &&
                            !_hasStartedPlaying)
                          Center(
                            child: ValueListenableBuilder<bool>(
                              valueListenable: _isSwipingPage,
                              builder: (context, isSwiping, child) {
                                return AnimatedOpacity(
                                  duration: Duration(milliseconds: isSwiping ? 150 : 250),
                                  curve: Curves.easeInOut,
                                  opacity: isSwiping ? 0.0 : 1.0,
                                  child: IgnorePointer(
                                    ignoring: isSwiping,
                                    child: child,
                                  ),
                                );
                              },
                              child: StreamBuilder<bool>(
                                stream: _player.stream.playing,
                                builder: (_, snap) {
                                  final playing = snap.data ?? false;
                                  if (playing) return const SizedBox.shrink();
                                  return BouncyTap(
                                    onTap: () {
                                      _player.play();
                                      if (!_hasStartedPlaying) {
                                        setState(() => _hasStartedPlaying = true);
                                      }
                                    },
                                    child: Container(
                                      width: 72,
                                      height: 72,
                                      decoration: BoxDecoration(
                                        color: Colors.black
                                            .withValues(alpha: 0.55),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.4),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: const Center(
                                        child: Padding(
                                          padding: EdgeInsets.only(left: 3),
                                          child: Icon(
                                            Icons.play_arrow_rounded,
                                            size: 48,
                                            color: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        // Top bar
                        Positioned(
                          top: 0,
                          left: 0,
                          right: 0,
                          child: SafeArea(
                            bottom: false,
                            child: _TopBar(
                              item: item,
                              currentIndex: _current,
                              totalVideos: _videos.length,
                              isTrash: widget.isTrash,
                              onRestore: _restoreItem,
                              onBack: () {
                                if (_isFullscreen) {
                                  _exitFullscreen();
                                } else {
                                  Navigator.of(context).pop();
                                }
                              },
                              onInfo: () => showMediaInfoSheet(context, item, player: _player),
                              onDelete: _deleteItem,
                            ),
                          ),
                        ),
                        // Bottom controls
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: SafeArea(
                            top: false,
                            child: _BottomBar(
                              player: _player,
                              item: item,
                              isVertical: _isCurrentVideoPortrait(),
                              isTrash: widget.isTrash,
                              onRestore: _restoreItem,
                              isFullscreen: _isFullscreen,
                              isLooping: _isLooping,
                              playbackSpeed: _playbackSpeed,
                              onToggleFullscreen: _toggleFullscreen,
                              onToggleLoop: _toggleLoop,
                              onSelectSpeed: _showPlaybackSpeedSheet,
                              onDelete: _deleteItem,
                              onRename: _renameCurrentItem,
                              onToggleOrientation: _toggleOrientation,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
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

// ── Video thumbnail placeholder ───────────────────────────────────────────

/// Morphing flight shuttle between grid (cover crop) and viewer (contain aspect ratio).
Widget _buildHeroShuttle({
  required Animation<double> animation,
  required HeroFlightDirection flightDirection,
  required MediaItem item,
}) {
  final mem = ThumbnailService.instance.getMemoryThumbnail(item.id);
  final disk =
      mem == null ? ThumbnailService.instance.getCachedFile(item.id) : null;
  final ImageProvider? p =
      mem != null ? MemoryImage(mem) : (disk != null ? FileImage(disk) : null);

  if (p == null) {
    return _VideoThumbnailPage(item: item);
  }

  return ClipRect(
    clipBehavior: Clip.hardEdge,
    child: Image(
      image: p,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
    ),
  );
}

class _VideoThumbnailPage extends StatelessWidget {
  const _VideoThumbnailPage({
    required this.item,
    this.fit = BoxFit.contain,
  });
  final MediaItem item;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final cached = ThumbnailService.instance.getMemoryThumbnail(item.id);
    if (cached != null) {
      return Image.memory(
        cached,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    }

    final diskFile = ThumbnailService.instance.getCachedFile(item.id);
    if (diskFile != null) {
      return Image.file(
        diskFile,
        fit: fit,
        gaplessPlayback: true,
        filterQuality: FilterQuality.high,
      );
    }

    return FutureBuilder<Uint8List?>(
      future: ThumbnailService.instance
          .getThumbnail(item.id, filePath: item.path, isVideo: true),
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          return Image.memory(
            snapshot.data!,
            fit: fit,
            gaplessPlayback: true,
            filterQuality: FilterQuality.high,
          );
        }
        return const Center(
          child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
        );
      },
    );
  }
}

// ── Top bar (Photo 2 reference) ───────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.item,
    required this.currentIndex,
    required this.totalVideos,
    required this.onBack,
    required this.onInfo,
    required this.onDelete,
    this.isTrash = false,
    this.onRestore,
  });
  final MediaItem item;
  final int currentIndex;
  final int totalVideos;
  final VoidCallback onBack;
  final VoidCallback onInfo;
  final VoidCallback onDelete;
  final bool isTrash;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
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
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_ios_new,
                color: Colors.white, size: 20),
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
          if (!isTrash)
            IconButton(
              icon:
                  const Icon(Icons.info_outline, color: Colors.white, size: 22),
              tooltip: context.tr.details,
              onPressed: onInfo,
            ),
        ],
      ),
    );
  }
}

// ── Bottom bar (Photo 2 reference) ────────────────────────────────────────

class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.player,
    required this.item,
    required this.isVertical,
    required this.isFullscreen,
    required this.isLooping,
    required this.playbackSpeed,
    required this.onToggleFullscreen,
    required this.onToggleLoop,
    required this.onSelectSpeed,
    required this.onDelete,
    required this.onToggleOrientation,
    this.isTrash = false,
    this.onRestore,
    this.onRename,
  });

  final Player player;
  final MediaItem item;
  final bool isVertical;
  final bool isFullscreen;
  final bool isLooping;
  final double playbackSpeed;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleLoop;
  final VoidCallback onSelectSpeed;
  final VoidCallback onDelete;
  final VoidCallback onToggleOrientation;
  final bool isTrash;
  final VoidCallback? onRestore;
  final VoidCallback? onRename;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _isDragging = false;
  double? _dragFraction;

  void _showMoreOptions(BuildContext context) {
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
                leading: const Icon(Icons.speed, color: Colors.white),
                title: Text(
                  '${context.tr.speed} (${widget.playbackSpeed == 1.0 ? context.tr.normal : '${widget.playbackSpeed}x'})',
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onSelectSpeed();
                },
              ),
              ListTile(
                leading: Icon(
                  widget.isLooping ? Icons.repeat_one : Icons.repeat,
                  color: widget.isLooping
                      ? Theme.of(context).colorScheme.primary
                      : Colors.white,
                ),
                title: Text(
                  widget.isLooping ? context.tr.loopOn : context.tr.loopOff,
                  style: TextStyle(
                    color: widget.isLooping
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                    fontSize: 15,
                  ),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  widget.onToggleLoop();
                },
              ),
              if (!widget.isVertical)
                ListTile(
                  leading: Icon(
                    widget.isFullscreen
                        ? Icons.fullscreen_exit
                        : Icons.fullscreen,
                    color: Colors.white,
                  ),
                  title: Text(
                    widget.isFullscreen ? context.tr.exitFullscreen : context.tr.fullscreen,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onToggleFullscreen();
                  },
                ),
              if (widget.onRename != null)
                ListTile(
                  leading:
                      const Icon(Icons.edit_outlined, color: Colors.white),
                  title: Text(context.tr.rename,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onRename?.call();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showHorizontalMoreOptions(BuildContext context) {
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
              if (widget.isTrash) ...[
                ListTile(
                  leading: const Icon(Icons.restore, color: Colors.white),
                  title: Text(context.tr.restore,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onRestore?.call();
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: Text(context.tr.delete,
                      style: const TextStyle(color: Colors.redAccent, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onDelete();
                  },
                ),
              ] else ...[
                Consumer(
                  builder: (context, ref, _) {
                    final isFav = ref.watch(
                      settingsNotifierProvider.select(
                        (s) => s.favoriteIds.contains(widget.item.id),
                      ),
                    );
                    return ListTile(
                      leading: Icon(
                        isFav ? Icons.favorite : Icons.favorite_border,
                        color: isFav ? Colors.redAccent : Colors.white,
                      ),
                      title: Text(
                        context.tr.favorite,
                        style: TextStyle(
                          color: isFav ? Colors.redAccent : Colors.white,
                          fontSize: 15,
                        ),
                      ),
                      onTap: () {
                        HapticFeedback.lightImpact();
                        final currentFavs = Set<String>.from(
                          ref.read(settingsNotifierProvider).favoriteIds,
                        );
                        if (currentFavs.contains(widget.item.id)) {
                          currentFavs.remove(widget.item.id);
                        } else {
                          currentFavs.add(widget.item.id);
                        }
                        ref.read(settingsNotifierProvider.notifier).update(
                              (s) => s.copyWith(favoriteIds: currentFavs.toList()),
                            );
                        Navigator.pop(sheetContext);
                      },
                    );
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.share_outlined, color: Colors.white),
                  title: Text(context.tr.share,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    ShareService.shareSingle(widget.item.path, isVideo: true);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_outline, color: Colors.white),
                  title: Text(context.tr.delete,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onDelete();
                  },
                ),
                if (widget.onRename != null)
                  ListTile(
                    leading: const Icon(Icons.edit_outlined, color: Colors.white),
                    title: Text(context.tr.rename,
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      widget.onRename!();
                    },
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Container(
      padding: EdgeInsets.fromLTRB(8, 0, 8, isLandscape ? 2 : 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: StreamBuilder<Duration>(
        stream: widget.player.stream.position,
        builder: (_, posSnap) {
          return StreamBuilder<Duration>(
            stream: widget.player.stream.duration,
            builder: (_, durSnap) {
              final pos = posSnap.data ?? Duration.zero;
              final dur =
                  durSnap.data ?? widget.item.duration ?? Duration.zero;
              final displayPos = (_isDragging &&
                      _dragFraction != null &&
                      dur.inMilliseconds > 0)
                  ? Duration(
                      milliseconds:
                          (_dragFraction! * dur.inMilliseconds).round())
                  : pos;
              final frac = dur.inMilliseconds > 0
                  ? (_dragFraction ??
                      (pos.inMilliseconds / dur.inMilliseconds))
                  : 0.0;

              if (isLandscape) {
                return _buildLandscapeLayout(
                  context,
                  displayPos: displayPos,
                  dur: dur,
                  frac: frac,
                );
              }
              return _buildPortraitLayout(
                context,
                displayPos: displayPos,
                dur: dur,
                frac: frac,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildLandscapeLayout(
    BuildContext context, {
    required Duration displayPos,
    required Duration dur,
    required double frac,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Timestamp on the left (e.g. 00:04 / 00:14)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            '${MediaUtils.formatDuration(displayPos)} / ${MediaUtils.formatDuration(dur)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        // 2. Compact seekbar slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.5),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
          ),
          child: Slider(
            value: frac.clamp(0.0, 1.0),
            onChangeStart: (_) {
              setState(() {
                _isDragging = true;
              });
            },
            onChanged: (v) {
              setState(() {
                _dragFraction = v;
              });
            },
            onChangeEnd: (v) {
              final target = Duration(
                milliseconds: (v * dur.inMilliseconds).round(),
              );
              widget.player.seek(target);
              setState(() {
                _isDragging = false;
                _dragFraction = null;
              });
            },
            activeColor: Colors.white,
            inactiveColor: Colors.white30,
            thumbColor: Colors.white,
          ),
        ),
        // 3. Actions row: Play/Pause on the left, action icons on the right
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 12, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Play / Pause button
              StreamBuilder<bool>(
                stream: widget.player.stream.playing,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return BouncyTap(
                    onTap: widget.player.playOrPause,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  );
                },
              ),
              // Action buttons on the right: Speed, Loop, Fullscreen, Rotate, More
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Speed
                  BouncyTap(
                    onTap: widget.onSelectSpeed,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.speed_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 3),
                          Text(
                            widget.playbackSpeed == 1.0
                                ? '1.0'
                                : '${widget.playbackSpeed}x',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // Loop
                  BouncyTap(
                    onTap: widget.onToggleLoop,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(
                        widget.isLooping
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        color: widget.isLooping
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  if (!widget.isVertical) ...[
                    const SizedBox(width: 4),
                    // Fullscreen / Exit Fullscreen
                    BouncyTap(
                      onTap: widget.onToggleFullscreen,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          widget.isFullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  // Rotate
                  BouncyTap(
                    onTap: widget.onToggleOrientation,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.screen_rotation_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  // More (⋮)
                  BouncyTap(
                    onTap: () => _showHorizontalMoreOptions(context),
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: Icon(
                        Icons.more_vert_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPortraitLayout(
    BuildContext context, {
    required Duration displayPos,
    required Duration dur,
    required double frac,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Seek bar
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2.5,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          ),
          child: Slider(
            value: frac.clamp(0.0, 1.0),
            onChangeStart: (_) {
              setState(() {
                _isDragging = true;
              });
            },
            onChanged: (v) {
              setState(() {
                _dragFraction = v;
              });
            },
            onChangeEnd: (v) {
              final target = Duration(
                milliseconds: (v * dur.inMilliseconds).round(),
              );
              widget.player.seek(target);
              setState(() {
                _isDragging = false;
                _dragFraction = null;
              });
            },
            activeColor: Colors.white,
            inactiveColor: Colors.white30,
            thumbColor: Colors.white,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(MediaUtils.formatDuration(displayPos),
                  style: const TextStyle(color: Colors.white, fontSize: 12)),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(MediaUtils.formatDuration(dur),
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                  if (!widget.isVertical) ...[
                    const SizedBox(width: 8),
                    BouncyTap(
                      onTap: widget.onToggleFullscreen,
                      child: Padding(
                        padding: const EdgeInsets.all(2),
                        child: Icon(
                          widget.isFullscreen
                              ? Icons.fullscreen_exit_rounded
                              : Icons.fullscreen_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        widget.isTrash
            ? Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ViewerActionButton(
                    icon: const Icon(Icons.restore,
                        color: Colors.white, size: 22),
                    label: context.tr.restore,
                    onTap: widget.onRestore ?? () {},
                  ),
                  _ViewerActionButton(
                    icon: const Icon(Icons.info_outline,
                        color: Colors.white, size: 22),
                    label: context.tr.details,
                    onTap: () => showMediaInfoSheet(context, widget.item,
                        player: widget.player),
                  ),
                  _ViewerActionButton(
                    icon: const Icon(Icons.delete_forever,
                        color: Colors.white, size: 22),
                    label: context.tr.delete,
                    onTap: widget.onDelete,
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  // 1. Share
                  _ViewerActionButton(
                    icon: const Icon(Icons.share_outlined,
                        color: Colors.white, size: 22),
                    label: context.tr.share,
                    onTap: () => ShareService.shareSingle(widget.item.path,
                        isVideo: true),
                  ),
                  // 2. Favorite
                  Consumer(
                    builder: (context, ref, _) {
                      final isFav = ref.watch(
                        settingsNotifierProvider.select(
                          (s) => s.favoriteIds.contains(widget.item.id),
                        ),
                      );
                      return _ViewerActionButton(
                        icon: Icon(
                          isFav ? Icons.favorite : Icons.favorite_border,
                          color: isFav ? Colors.redAccent : Colors.white,
                          size: 22,
                        ),
                        label: context.tr.favorite,
                        onTap: () {
                          HapticFeedback.lightImpact();
                          final currentFavs = Set<String>.from(
                            ref.read(settingsNotifierProvider).favoriteIds,
                          );
                          if (currentFavs.contains(widget.item.id)) {
                            currentFavs.remove(widget.item.id);
                          } else {
                            currentFavs.add(widget.item.id);
                          }
                          ref.read(settingsNotifierProvider.notifier).update(
                                (s) => s.copyWith(
                                    favoriteIds: currentFavs.toList()),
                              );
                        },
                      );
                    },
                  ),
                  // 3. Play / Pause
                  StreamBuilder<bool>(
                    stream: widget.player.stream.playing,
                    builder: (_, snap) {
                      final playing = snap.data ?? false;
                      return _ViewerActionButton(
                        icon: Icon(
                          playing
                              ? Icons.pause_circle_outline
                              : Icons.play_circle_outline,
                          color: Colors.white,
                          size: 24,
                        ),
                        label: playing ? context.tr.pause : context.tr.play,
                        onTap: widget.player.playOrPause,
                      );
                    },
                  ),
                  // 4. Delete
                  _ViewerActionButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.white, size: 22),
                    label: context.tr.delete,
                    onTap: widget.onDelete,
                  ),
                  // 5. More (Bottom sheet)
                  _ViewerActionButton(
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white, size: 22),
                    label: context.tr.more,
                    onTap: () => _showMoreOptions(context),
                  ),
                ],
              ),
      ],
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
