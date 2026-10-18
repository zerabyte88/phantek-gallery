import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
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
import '../../gallery/presentation/widgets/delete_confirmation_sheet.dart';
import 'image_viewer_screen.dart' show screenDisplayImage;

Widget _photoThumb(String id, [String? path]) {
  final hr = ThumbnailService.instance.getMemoryHighResThumbnail(id);
  final mem = hr ?? ThumbnailService.instance.getMemoryThumbnail(id);
  final disk = mem == null ? ThumbnailService.instance.getCachedFile(id) : null;
  final ImageProvider? p = mem != null
      ? MemoryImage(mem)
      : (disk != null
          ? FileImage(disk)
          : (path != null ? screenDisplayImage(path) : null));
  if (p == null) return const SizedBox.shrink();
  return Image(
    image: p,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
  );
}

/// Morphing flight shuttle between grid (cover crop) and viewer (contain aspect ratio).
Widget _buildHeroShuttle({
  required Animation<double> animation,
  required HeroFlightDirection flightDirection,
  required MediaItem item,
  Widget? fallbackChild,
}) {
  final hr = ThumbnailService.instance.getMemoryHighResThumbnail(item.id);
  final mem = hr ?? ThumbnailService.instance.getMemoryThumbnail(item.id);
  final disk = mem == null ? ThumbnailService.instance.getCachedFile(item.id) : null;
  final ImageProvider? p = mem != null
      ? MemoryImage(mem)
      : (disk != null
          ? FileImage(disk)
          : (item.path.isNotEmpty && !item.isVideo ? screenDisplayImage(item.path) : null));

  final Widget content = p != null
      ? Image(
          image: p,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        )
      : (fallbackChild ?? const SizedBox.shrink());

  final curved = CurvedAnimation(
    parent: animation,
    curve: const Cubic(0.2, 0.0, 0.0, 1.0),
  );

  return AnimatedBuilder(
    animation: curved,
    builder: (context, child) {
      final t = curved.value;
      // In both push (0->1) and pop (1->0), (1 - t) * 8.0 smoothly matches
      // the grid tile corner radius (8.0 at grid, 0.0 at viewer).
      final radius = (1.0 - t) * 8.0;

      if (radius <= 0.05) return child!;

      return ClipRRect(
        borderRadius: BorderRadius.circular(radius.clamp(0.0, 8.0)),
        clipBehavior: Clip.hardEdge,
        child: child,
      );
    },
    child: content,
  );
}

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
  bool _isScrubbing = false;
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
  int _videoLoadGeneration = 0;
  Timer? _videoLoadDebounce;
  bool _isVideoZoomed = false;
  bool _isPinching = false;
  bool _isMultiTouch = false;
  final Set<int> _activePointers = {};
  AnimationController? _zoomAnimController;
  bool _hasStartedPlaying = false;
  bool _cropToFit = false;
  String? _lastSize;
  bool _highRes = false;
  String? _activePlayerPath;
  bool _routeTransitionComplete = false;
  Animation<double>? _routeAnimation;
  StateController<String?>? _activeMediaNotifier;

  void _toggleCropToFit() {
    HapticFeedback.lightImpact();
    setState(() => _cropToFit = !_cropToFit);
  }

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
    final initialItem = _videos[_current];
    if (initialItem.width != null && initialItem.height != null && initialItem.width! > 0 && initialItem.height! > 0) {
      _highRes = math.max(initialItem.width!, initialItem.height!) > 1920;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _videos.isNotEmpty) {
        _activeMediaNotifier = ref.read(activeViewerMediaIdProvider.notifier);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final modalAnim = ModalRoute.of(context)?.animation;
    if (_routeAnimation != modalAnim) {
      _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
      _routeAnimation = modalAnim;
      _routeAnimation?.addStatusListener(_onRouteAnimationStatus);
      if (_routeAnimation?.isCompleted == true) {
        _routeTransitionComplete = true;
        _startPlaybackAfterTransition();
      }
    }
  }

  void _onRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      _routeTransitionComplete = true;
      _startPlaybackAfterTransition();
    } else if (status == AnimationStatus.reverse) {
      // Pop started: immediately hide video texture surface and pause to avoid freezing / black flash mid-flight
      _videoSurfaceVisible.value = false;
      if (_player.state.playing) {
        _player.pause();
      }
    }
  }

  void _startPlaybackAfterTransition() {
    if (!mounted || !_videos[_current].isVideo) return;
    final settings = ref.read(settingsNotifierProvider);
    if (settings.autoPlayVideo) {
      if (!_player.state.playing) {
        _player.play();
      }
      _controller.waitUntilFirstFrameRendered.then((_) {
        if (mounted && _routeTransitionComplete && !_videoSurfaceVisible.value) {
          _videoSurfaceVisible.value = true;
        }
      });
    }
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
      for (final offset in const [-1, 1]) {
        final target = index + offset;
        if (target >= 0 && target < _videos.length) {
          final item = _videos[target];
          if (item.isVideo) {
            // Pre-fetch high-res preview frame for instant crispness on swipe
            ThumbnailService.instance
                .getHighResVideoThumbnail(
              item.id,
              filePath: item.path,
            )
                .then((hrBytes) {
              if (hrBytes != null && mounted) {
                precacheImage(MemoryImage(hrBytes), context);
              }
            });
            final mem = ThumbnailService.instance.getMemoryThumbnail(item.id);
            if (mem != null && mounted) {
              precacheImage(MemoryImage(mem), context);
            } else {
              final file = ThumbnailService.instance.getCachedFile(item.id);
              if (file != null && mounted) {
                precacheImage(FileImage(file), context);
              } else {
                ThumbnailService.instance
                    .getThumbnail(item.id, filePath: item.path, isVideo: true)
                    .then((bytes) {
                  if (bytes != null && mounted) {
                    precacheImage(MemoryImage(bytes), context);
                  }
                });
              }
            }
          } else {
            final mem = ThumbnailService.instance.getMemoryThumbnail(item.id);
            if (mem != null && mounted) {
              precacheImage(MemoryImage(mem), context);
            }
            if (item.path.isNotEmpty && mounted) {
              precacheImage(screenDisplayImage(item.path), context);
            }
          }
        }
      }
    });
  }

  Future<void> _initPlayer() async {
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
      await native.setProperty('hwdec-codecs', 'h264,hevc,mpeg4,vc1');
      await native.setProperty('demuxer-lavf-buffersize', '8388608'); // 8 MB, within Android limit
      await native.setProperty('demuxer-max-bytes', '33554432'); // 32 MB read-ahead
      await native.setProperty('demuxer-max-back-bytes', '33554432'); // 32 MB backward seek buffer
      await native.setProperty('demuxer-readahead-secs', '10');
      await native.setProperty('demuxer-lavf-probesize', '2097152');
      await native.setProperty('hr-seek-framedrop', 'yes');
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
      if (playing && mounted && _videos[_current].isVideo) {
        if (_routeTransitionComplete && !_videoSurfaceVisible.value) {
          _controller.waitUntilFirstFrameRendered.then((_) {
            if (mounted && _routeTransitionComplete && !_videoSurfaceVisible.value) {
              _videoSurfaceVisible.value = true;
            }
          });
        }
        if (!_hasStartedPlaying) {
          setState(() {
            _hasStartedPlaying = true;
          });
        }
      }
    });

    _player.stream.videoParams.listen((vp) async {
      final w = vp.w ?? 0, h = vp.h ?? 0;
      if (w <= 0 || h <= 0 || _lastSize == '${w}x$h') return;
      _lastSize = '${w}x$h';
      final highRes = math.max(w, h) > 1920;
      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;
        try {
          final hw = await native.getProperty('hwdec-current');
          debugPrint('[VideoPlayer] Active hwdec: $hw');
        } catch (_) {}
      }
      if (mounted && _highRes != highRes) {
        setState(() => _highRes = highRes);
      }
    });

    final currentItem = _videos[_current];
    _videoSurfaceVisible.value = false;
    if (currentItem.isVideo) {
      final currentPath = currentItem.path;
      final isWebM = currentPath.toLowerCase().endsWith('.webm');
      if (_player.platform is NativePlayer) {
        final native = _player.platform as NativePlayer;
        if (isWebM) {
          await native.setProperty('hwdec', 'no');
        } else {
          await native.setProperty(
              'hwdec', settings.hardwareAcceleration ? 'auto-copy' : 'no');
        }
      }

      await _player.open(
        Media(currentPath),
        play: false,
      );
      _activePlayerPath = currentPath;
      if (_routeTransitionComplete && settings.autoPlayVideo) {
        _player.play();
        _controller.waitUntilFirstFrameRendered.then((_) {
          if (mounted && _routeTransitionComplete && !_videoSurfaceVisible.value) {
            _videoSurfaceVisible.value = true;
          }
        });
      }
    }
  }

  void _changeToVideo(int index) {
    if (index == _current) return;
    _videoLoadDebounce?.cancel();
    _activePlayerPath = null;
    final thisGen = ++_videoLoadGeneration;

    if (_isVideoZoomed || !_transformationController.value.isIdentity()) {
      _zoomAnimController?.stop();
      _zoomAnimController?.dispose();
      _zoomAnimController = null;
      _transformationController.value = Matrix4.identity();
      _isVideoZoomed = false;
    }
    _lastSize = null;
    final nextItem = _videos[index];
    if (nextItem.width != null && nextItem.height != null && nextItem.width! > 0 && nextItem.height! > 0) {
      _highRes = math.max(nextItem.width!, nextItem.height!) > 1920;
    }
    setState(() {
      _current = index;
      _hasStartedPlaying = false;
    });

    _videoSurfaceVisible.value = false;
    if (_player.state.playing) {
      _player.pause();
    }

    if (nextItem.isVideo) {
      // Debounce loading native player so fast swipes are 100% fluid and never stall the hardware codec pipeline
      _videoLoadDebounce = Timer(const Duration(milliseconds: 250), () async {
        if (!mounted || _current != index || thisGen != _videoLoadGeneration) return;
        try {
          final settings = ref.read(settingsNotifierProvider);
          final path = _videos[index].path;
          final isWebM = path.toLowerCase().endsWith('.webm');
          if (_player.platform is NativePlayer) {
            final native = _player.platform as NativePlayer;
            if (isWebM) {
              await native.setProperty('hwdec', 'no');
            } else {
              await native.setProperty(
                  'hwdec', settings.hardwareAcceleration ? 'auto-copy' : 'no');
            }
          }
          if (!mounted || _current != index || thisGen != _videoLoadGeneration) return;
          await _player.open(Media(path), play: settings.autoPlayVideo);
          _activePlayerPath = path;
          if (_isLooping) _player.setPlaylistMode(PlaylistMode.loop);
          if (_playbackSpeed != 1.0) _player.setRate(_playbackSpeed);
          if (settings.autoPlayVideo) {
            _controller.waitUntilFirstFrameRendered.then((_) {
              if (mounted && _current == index && thisGen == _videoLoadGeneration) {
                _videoSurfaceVisible.value = true;
              }
            });
          }
        } catch (_) {}
      });
    }

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
  }

  void _onPageChanged(int index) {
    _changeToVideo(index);
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
    final notifier = _activeMediaNotifier;
    if (notifier != null) {
      Future.microtask(() {
        notifier.state = null;
      });
    }
    _routeAnimation?.removeStatusListener(_onRouteAnimationStatus);
    _videoLoadDebounce?.cancel();
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
    if (index == _current && _activePlayerPath == item.path) {
      final vParams = _player.state.videoParams;
      if (vParams.w != null && vParams.h != null && vParams.w! > 0 && vParams.h! > 0) {
        final rotate = vParams.rotate ?? 0;
        final isRotated90or270 = rotate == 90 || rotate == 270;
        final effectiveW = isRotated90or270 ? vParams.h! : vParams.w!;
        final effectiveH = isRotated90or270 ? vParams.w! : vParams.h!;
        return effectiveH > effectiveW;
      }
    }
    // Item width and height from scanner already account for orientation
    if (item.width != null && item.height != null && item.width! > 0 && item.height! > 0) {
      return item.height! > item.width!;
    }
    // Visual thumbnail aspect ratio fallback
    final thumbRatio = ThumbnailService.instance.getThumbnailAspectRatio(item.id);
    if (thumbRatio != null && thumbRatio > 0) {
      return thumbRatio < 1.0;
    }
    return false;
  }

  bool _isCurrentVideoPortrait() {
    return _isVideoPortrait(_videos[_current], _current);
  }

  double? _getVideoAspectRatio(MediaItem item, int index) {
    if (index == _current && _activePlayerPath == item.path) {
      final vParams = _player.state.videoParams;
      if (vParams.w != null && vParams.h != null && vParams.w! > 0 && vParams.h! > 0) {
        final rotate = vParams.rotate ?? 0;
        final isRotated90or270 = rotate == 90 || rotate == 270;
        final effectiveW = isRotated90or270 ? vParams.h! : vParams.w!;
        final effectiveH = isRotated90or270 ? vParams.w! : vParams.h!;
        return effectiveW / effectiveH;
      }
    }
    if (item.width != null && item.height != null && item.width! > 0 && item.height! > 0) {
      return item.width! / item.height!;
    }
    final thumbRatio = ThumbnailService.instance.getThumbnailAspectRatio(item.id);
    if (thumbRatio != null && thumbRatio > 0) {
      return thumbRatio;
    }
    return null;
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

  Widget _buildVideoPage(int index) {
    final item = _videos[index];
    if (!item.isVideo) {
      Widget content = Image(
        image: screenDisplayImage(item.path),
        fit: BoxFit.contain,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return Stack(
            fit: StackFit.passthrough,
            alignment: Alignment.center,
            children: [
              _photoThumb(item.id, item.path),
              child,
            ],
          );
        },
        errorBuilder: (_, __, ___) => const Center(
          child: Icon(Icons.broken_image, size: 80, color: Colors.white38),
        ),
      );
      final ar = (item.width != null && item.height != null && item.width! > 0 && item.height! > 0)
          ? (item.width! / item.height!)
          : ThumbnailService.instance.getThumbnailAspectRatio(item.id);
      if (ar != null && ar > 0) {
        content = AspectRatio(
          aspectRatio: ar,
          child: content,
        );
      }
      return content;
    }

    final isVertical = _isVideoPortrait(item, index);
    final isDeviceLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final shouldCrop = !isVertical && isDeviceLandscape && _cropToFit;

    Widget content = Stack(
      fit: StackFit.expand,
      alignment: Alignment.center,
      children: [
        _VideoThumbnailPage(
          item: item,
          fit: shouldCrop ? BoxFit.cover : BoxFit.contain,
          isSwiping: _isSwipingPage,
        ),
        if (index == _current)
          ValueListenableBuilder<bool>(
            valueListenable: _videoSurfaceVisible,
            builder: (context, visible, _) => AnimatedOpacity(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              opacity: visible ? 1.0 : 0.0,
              child: IgnorePointer(
                ignoring: !visible,
                child: Video(
                  key: const ValueKey('active_video_surface'),
                  controller: _controller,
                  controls: NoVideoControls,
                  fit: shouldCrop ? BoxFit.cover : BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  fill: Colors.transparent,
                ),
              ),
            ),
          ),
      ],
    );

    final ar = _getVideoAspectRatio(item, index);
    if (ar != null && ar > 0 && !shouldCrop) {
      return AspectRatio(
        aspectRatio: ar,
        child: content,
      );
    }

    return content;
  }

  void _handleDoubleTap() {
    if (_doubleTapDetails == null) return;
    final pos = _doubleTapDetails!.localPosition;

    HapticFeedback.lightImpact();
    _zoomToPosition(pos);
  }

  void _showPlaybackSpeedSheet() {
    final speeds = [2.0, 1.5, 1.25, 1.0, 0.75, 0.5, 0.25];
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.25),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogCtx, anim1, anim2) {
        final isLandscape =
            MediaQuery.orientationOf(dialogCtx) == Orientation.landscape;
        return SafeArea(
          child: Align(
            alignment:
                isLandscape ? Alignment.bottomRight : Alignment.bottomCenter,
            child: Padding(
              padding: EdgeInsets.only(
                right: isLandscape ? 40.0 : 0.0,
                bottom: isLandscape ? 56.0 : 80.0,
              ),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 124,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.sizeOf(dialogCtx).height * 0.65,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1E1E1E).withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black54,
                        blurRadius: 16,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: speeds.map((speed) {
                        final isSelected = _playbackSpeed == speed;
                        return InkWell(
                          onTap: () {
                            Navigator.pop(dialogCtx);
                            setState(() {
                              _playbackSpeed = speed;
                            });
                            _player.setRate(speed);
                            HapticFeedback.lightImpact();
                          },
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            color: isSelected
                                ? const Color(0xFF2F80ED)
                                : Colors.transparent,
                            alignment: Alignment.center,
                            child: Text(
                              '${speed}x',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.bold
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (ctx, anim, _, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.9, end: 1.0).animate(
              CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
            ),
            child: child,
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
        if (_videos[_current].isVideo) {
          _player.open(Media(_videos[_current].path), play: false);
        }
      }
    }
  }

  Future<void> _deleteItem() async {
    final item = _videos[_current];

    if (widget.isTrash) {
      final ok = await showDeleteConfirmationSheet(
        context,
        title: context.tr.deletePermanentlyTitle,
        contentText: context.tr.deletePermanentlyConfirm(item.name),
        isTrash: false,
      );
      if (ok != true || !mounted) return;

      _player.pause();
      await ref.read(trashProvider.notifier).permanentDelete(item.id);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr.delete)),
      );
      if (_videos.length <= 1) {
        Navigator.of(context).pop();
      } else {
        setState(() {
          _videos.removeAt(_current);
          _current = _current.clamp(0, _videos.length - 1);
        });
        _pageController.jumpToPage(_current);
        if (_videos[_current].isVideo) {
          _player.open(Media(_videos[_current].path), play: false);
        }
      }
      return;
    }

    final settings = ref.read(settingsNotifierProvider);
    final isTrash = settings.enableTrash;

    final ok = await showDeleteConfirmationSheet(
      context,
      title: isTrash ? context.tr.moveToTrashTitle : context.tr.deletePermanentlyTitle,
      contentText: isTrash
          ? context.tr.moveToTrashConfirm(item.name)
          : context.tr.deletePermanentlyConfirm(item.name),
      isTrash: isTrash,
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
          SnackBar(content: Text(context.tr.failedToDelete(e.toString()))),
        );
      }
      return;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(isTrash ? context.tr.moveToTrash : context.tr.delete),
      ),
    );
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
      if (_videos[_current].isVideo) {
        _player.open(Media(_videos[_current].path), play: false);
      }
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
            // ── Background scrim: opacity follows route animation & drag distance ──
            Positioned.fill(
              child: AnimatedBuilder(
                animation: ModalRoute.of(context)?.animation ?? kAlwaysCompleteAnimation,
                builder: (context, _) {
                  final routeAnim = ModalRoute.of(context)?.animation?.value ?? 1.0;
                  final curved = const Cubic(0.2, 0.0, 0.0, 1.0).transform(routeAnim.clamp(0.0, 1.0));
                  return ValueListenableBuilder<Offset>(
                    valueListenable: _dragNotifier,
                    builder: (_, d, __) {
                      final dragFade = (1.0 - (d.dy / 320.0)).clamp(0.0, 1.0);
                      return ColoredBox(
                        color: Colors.black.withValues(
                          alpha: (curved * dragFade).clamp(0.0, 1.0),
                        ),
                      );
                    },
                  );
                },
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
                  final screenHeight = MediaQuery.sizeOf(context).height;
                  final isCurrentItemVideo = _videos[_current].isVideo;
                  final bottomThreshold = isCurrentItemVideo
                      ? (MediaQuery.orientationOf(context) == Orientation.landscape ? 140.0 : 280.0)
                      : 90.0;
                  final inBottomControlsArea = _showControls && (e.position.dy > screenHeight - bottomThreshold);
                  if (_activePointers.length >= 2 || _isCurrentlyVideoZoomed) {
                    // Instantly lock PageView swiping and abort pull-to-dismiss on multi-touch, pinch, or zoom
                    _isMultiTouch = true;
                    _isPinching = true;
                    _startDragY = null;
                    _startDragX = null;
                    if (_dragNotifier.value != Offset.zero) _setDrag(Offset.zero);
                    return;
                  }
                  if (inBottomControlsArea || _isScrubbing) {
                    _startDragY = null;
                    _startDragX = null;
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
                      !_isScrubbing &&
                      _activePointers.length == 1 &&
                      _startDragX != null &&
                      _startDragY != null) {
                    final adx = (e.position.dx - _startDragX!).abs();
                    final ady = (e.position.dy - _startDragY!).abs();
                    if (adx > 8 && adx > ady * 1.1) {
                      _videoSurfaceVisible.value = false;
                      _isSwipingHorizontal = true;
                      _isSwipingPage.value = true;
                      return;
                    }
                  }

                  if (_isSwipingHorizontal || _isScrubbing) return;

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
                  // Responsive vertical swipe deadzone: natural downward drag
                  if (_dragNotifier.value != Offset.zero || (dy > 16 && dy > dx.abs() * 1.5)) {
                    final dampedDx = dx * 0.45;
                    final dragY = (dy - 16).clamp(0.0, 650.0);
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
                      _videoSurfaceVisible.value = false;
                      _player.pause();
                      _activeMediaNotifier?.state = _videos[_current].id;
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
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(radius),
                              clipBehavior: radius > 0 ? Clip.antiAlias : Clip.none,
                              child: child,
                            ),
                          );
                        },
                        child: RepaintBoundary(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollStartNotification) {
                          if (notification.dragDetails != null) {
                            _isSwiping = true;
                            _isSwipingPage.value = true;
                            if (_player.state.playing) {
                              _player.pause();
                            }
                          }
                        } else if (notification is ScrollEndNotification) {
                          _isSwiping = false;
                          _isSwipingPage.value = false;
                          _precacheAdjacentVideos(_current);
                          _activeMediaNotifier?.state = _videos[_current].id;
                        }
                        return false;
                      },
                      child: ValueListenableBuilder<bool>(
                        valueListenable: _isDraggingDown,
                        builder: (context, isDraggingDown, child) {
                          return IgnorePointer(
                            ignoring: isDraggingDown,
                            child: child,
                          );
                        },
                        child: PageView.builder(
                          controller: _pageController,
                          itemCount: _videos.length,
                          onPageChanged: _onPageChanged,
                          physics: (_isCurrentlyVideoZoomed ||
                                  _isPinching ||
                                  _isMultiTouch ||
                                  _isScrubbing ||
                                  _activePointers.length >= 2)
                              ? const NeverScrollableScrollPhysics()
                              : const BouncingScrollPhysics(),
                          itemBuilder: (context, index) {
                            final isCur = index == _current;
                            return RepaintBoundary(
                              child: Center(
                                child: ClipRect(
                                  child: InteractiveViewer(
                                    key: ValueKey('iv_${_videos[index].id}'),
                                    transformationController: isCur
                                        ? _transformationController
                                        : null,
                                    minScale: 1.0,
                                    maxScale: 8.0,
                                    panEnabled: isCur && _isCurrentlyVideoZoomed,
                                    scaleEnabled: isCur,
                                    clipBehavior: Clip.hardEdge,
                                    onInteractionStart: isCur
                                        ? (details) {
                                            _zoomAnimController?.stop();
                                            if (details.pointerCount >= 2) {
                                              _isPinching = true;
                                            }
                                          }
                                        : null,
                                    onInteractionUpdate: isCur
                                        ? (details) {
                                            final scale = _transformationController
                                                .value
                                                .getMaxScaleOnAxis();
                                            final isZoomed = scale > 1.05;
                                            if (isZoomed != _isVideoZoomed) {
                                              _isVideoZoomed = isZoomed;
                                            }
                                          }
                                        : null,
                                    onInteractionEnd: isCur
                                        ? (details) {
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
                                          }
                                        : null,
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
                                          fallbackChild: flightDirection == HeroFlightDirection.push
                                              ? toHeroContext.widget
                                              : fromHeroContext.widget,
                                        ),
                                        child: _buildVideoPage(index),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
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
                      final baseOpacity = (_showControls && !_isPinching) ? dragFade : 0.0;
                      final anim = ModalRoute.of(context)?.animation;
                      if (anim == null) {
                        return Opacity(
                          opacity: baseOpacity,
                          child: IgnorePointer(
                            ignoring: !_showControls || drag.dy > 4 || _isPinching,
                            child: child,
                          ),
                        );
                      }
                      return AnimatedBuilder(
                        animation: anim,
                        builder: (context, _) {
                          final entrance = const Interval(0.65, 1.0, curve: Curves.easeOut)
                              .transform(anim.value);
                          final opacity = (baseOpacity * entrance).clamp(0.0, 1.0);
                          return Opacity(
                            opacity: opacity,
                            child: IgnorePointer(
                              ignoring: !_showControls || drag.dy > 4 || _isPinching || opacity < 0.5,
                              child: child,
                            ),
                          );
                        },
                      );
                    },
                    child: Stack(
                      children: [
                        // Center play button when paused (exact center of the screen)
                        // In landscape: completely removed.
                        // In portrait: only shown before the video has ever started playing.
                        if (MediaQuery.orientationOf(context) != Orientation.landscape &&
                            !_hasStartedPlaying &&
                            _videos[_current].isVideo)
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
                                initialData: _player.state.playing,
                                stream: _player.stream.playing,
                                builder: (_, snap) {
                                  final playing = snap.data ?? _player.state.playing;
                                  if (playing) return const SizedBox.shrink();
                                  return BouncyTap(
                                    onTap: () {
                                      if (_videoLoadDebounce?.isActive == true) {
                                        _videoLoadDebounce?.cancel();
                                        _player.open(Media(_videos[_current].path), play: true);
                                      } else {
                                        _player.play();
                                      }
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
                                  _videoSurfaceVisible.value = false;
                                  _player.pause();
                                  _activeMediaNotifier?.state = _videos[_current].id;
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
                              cropToFit: _cropToFit,
                              onToggleCropToFit: _toggleCropToFit,
                              onToggleFullscreen: _toggleFullscreen,
                              onToggleLoop: _toggleLoop,
                              onSelectSpeed: _showPlaybackSpeedSheet,
                              onDelete: _deleteItem,
                              onRename: _renameCurrentItem,
                              onToggleOrientation: _toggleOrientation,
                              onScrubbingChanged: (scrubbing) {
                                if (_isScrubbing != scrubbing) {
                                  setState(() => _isScrubbing = scrubbing);
                                  if (!scrubbing && !_videoSurfaceVisible.value) {
                                    _videoSurfaceVisible.value = true;
                                  }
                                }
                              },
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

class _VideoThumbnailPage extends StatefulWidget {
  const _VideoThumbnailPage({
    required this.item,
    this.fit = BoxFit.contain,
    this.isSwiping,
  });
  final MediaItem item;
  final BoxFit fit;
  final ValueListenable<bool>? isSwiping;

  @override
  State<_VideoThumbnailPage> createState() => _VideoThumbnailPageState();
}

class _VideoThumbnailPageState extends State<_VideoThumbnailPage> {
  Uint8List? _highResBytes;

  @override
  void initState() {
    super.initState();
    widget.isSwiping?.addListener(_onSwipeChanged);
    final cached =
        ThumbnailService.instance.getMemoryHighResThumbnail(widget.item.id);
    if (cached != null) {
      _highResBytes = cached;
    } else if (widget.isSwiping?.value != true) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.isSwiping?.value != true && _highResBytes == null) {
          _loadHighRes();
        }
      });
    }
  }

  void _onSwipeChanged() {
    if (widget.isSwiping?.value == false && _highResBytes == null) {
      _loadHighRes();
    }
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isSwiping != widget.isSwiping) {
      oldWidget.isSwiping?.removeListener(_onSwipeChanged);
      widget.isSwiping?.addListener(_onSwipeChanged);
    }
    if (oldWidget.item.id != widget.item.id) {
      _highResBytes = null;
      if (widget.isSwiping?.value != true) {
        _loadHighRes();
      }
    }
  }

  @override
  void dispose() {
    widget.isSwiping?.removeListener(_onSwipeChanged);
    super.dispose();
  }

  void _loadHighRes() {
    final cached =
        ThumbnailService.instance.getMemoryHighResThumbnail(widget.item.id);
    if (cached != null) {
      _highResBytes = cached;
      return;
    }
    ThumbnailService.instance
        .getHighResVideoThumbnail(widget.item.id, filePath: widget.item.path)
        .then((bytes) {
      if (mounted && bytes != null) {
        setState(() {
          _highResBytes = bytes;
        });
      }
    });
  }

  Widget _buildBaseThumbnail() {
    final highResMem =
        ThumbnailService.instance.getMemoryHighResThumbnail(widget.item.id);
    if (highResMem != null) {
      return SizedBox.expand(
        child: Image.memory(
          highResMem,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    final highResDisk =
        ThumbnailService.instance.getCachedHighResFile(widget.item.id);
    if (highResDisk != null) {
      return SizedBox.expand(
        child: Image.file(
          highResDisk,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    final cached = ThumbnailService.instance.getMemoryThumbnail(widget.item.id);
    if (cached != null) {
      return SizedBox.expand(
        child: Image.memory(
          cached,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    final diskFile = ThumbnailService.instance.getCachedFile(widget.item.id);
    if (diskFile != null) {
      return SizedBox.expand(
        child: Image.file(
          diskFile,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: ThumbnailService.instance
          .getThumbnail(widget.item.id, filePath: widget.item.path, isVideo: true),
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          return SizedBox.expand(
            child: Image.memory(
              snapshot.data!,
              fit: widget.fit,
              gaplessPlayback: true,
              filterQuality: FilterQuality.medium,
            ),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final hr = _highResBytes ??
        ThumbnailService.instance.getMemoryHighResThumbnail(widget.item.id);
    if (hr != null) {
      return SizedBox.expand(
        child: Image.memory(
          hr,
          fit: widget.fit,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        ),
      );
    }
    return _buildBaseThumbnail();
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

// ── Seek preview tooltip ─────────────────────────────────────────────────────

class _SeekPreviewTooltip extends StatelessWidget {
  const _SeekPreviewTooltip({
    required this.width,
    required this.height,
    required this.frameBytes,
    required this.displayTime,
  });

  final double width;
  final double height;
  final Uint8List? frameBytes;
  final Duration displayTime;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 1.2,
            ),
            boxShadow: const [
              BoxShadow(
                color: Colors.black87,
                blurRadius: 14,
                spreadRadius: 1,
                offset: Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (frameBytes != null && frameBytes!.isNotEmpty)
                Image.memory(
                  frameBytes!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  filterQuality: FilterQuality.medium,
                )
              else
                const Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    ),
                  ),
                ),
              Positioned(
                bottom: 4,
                left: 4,
                right: 4,
                child: Center(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      MediaUtils.formatDuration(displayTime),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Downward pointing arrow caret toward seekbar thumb
        CustomPaint(
          size: const Size(12, 6),
          painter: _TooltipCaretPainter(
            color: Colors.white.withValues(alpha: 0.35),
            fillColor: const Color(0xFF141414),
          ),
        ),
      ],
    );
  }
}

class _TooltipCaretPainter extends CustomPainter {
  const _TooltipCaretPainter({required this.color, required this.fillColor});
  final Color color;
  final Color fillColor;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();

    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(path, fillPaint);

    final strokePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _TooltipCaretPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.fillColor != fillColor;
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
    this.cropToFit = false,
    this.onToggleCropToFit,
    this.isTrash = false,
    this.onRestore,
    this.onRename,
    this.onScrubbingChanged,
  });

  final Player player;
  final MediaItem item;
  final bool isVertical;
  final bool isFullscreen;
  final bool isLooping;
  final double playbackSpeed;
  final bool cropToFit;
  final VoidCallback? onToggleCropToFit;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleLoop;
  final VoidCallback onSelectSpeed;
  final VoidCallback onDelete;
  final VoidCallback onToggleOrientation;
  final bool isTrash;
  final VoidCallback? onRestore;
  final VoidCallback? onRename;
  final ValueChanged<bool>? onScrubbingChanged;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _isDragging = false;
  double? _dragFraction;
  bool _showPillBadge = false;
  Timer? _pillFadeTimer;
  StreamSubscription<bool>? _playingSub;
  StreamSubscription<bool>? _completedSub;

  final Map<int, Uint8List> _frameCache = {};
  Uint8List? _lastFrameBytes;
  Timer? _debounceTimer;
  Timer? _previewFadeTimer;
  bool _showPreview = false;
  bool _previewMounted = false;
  bool _wasPlayingBeforeDrag = false;
  bool _isFetchingFrame = false;
  Duration? _pendingTargetPos;

  Uint8List? _resolveInitialThumbnail() {
    final mem = ThumbnailService.instance.getMemoryThumbnail(widget.item.id);
    if (mem != null && mem.isNotEmpty) return mem;
    final diskFile = ThumbnailService.instance.getCachedFile(widget.item.id);
    if (diskFile != null && diskFile.existsSync()) {
      try {
        final b = diskFile.readAsBytesSync();
        if (b.isNotEmpty) return b;
      } catch (_) {}
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _lastFrameBytes = _resolveInitialThumbnail();
    if (widget.player.state.playing) {
      _showPillBadge = true;
      _pillFadeTimer = Timer(const Duration(seconds: 2), () {
        if (mounted && !_isDragging) {
          setState(() {
            _showPillBadge = false;
          });
        }
      });
    }
    _subscribePlayer();
  }

  @override
  void didUpdateWidget(covariant _BottomBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id) {
      _debounceTimer?.cancel();
      _previewFadeTimer?.cancel();
      _frameCache.clear();
      _lastFrameBytes = _resolveInitialThumbnail();
      _showPreview = false;
      _previewMounted = false;
      _isFetchingFrame = false;
      _pendingTargetPos = null;
    }
    if (oldWidget.player != widget.player) {
      _unsubscribePlayer();
      _subscribePlayer();
    }
  }

  void _subscribePlayer() {
    _playingSub = widget.player.stream.playing.listen((playing) {
      if (!mounted) return;
      if (playing) {
        _pillFadeTimer?.cancel();
        setState(() {
          _showPillBadge = true;
        });
        _pillFadeTimer = Timer(const Duration(seconds: 2), () {
          if (mounted && !_isDragging) {
            setState(() {
              _showPillBadge = false;
            });
          }
        });
      } else {
        if (!_isDragging && !widget.player.state.completed) {
          _pillFadeTimer?.cancel();
          setState(() {
            _showPillBadge = false;
          });
        }
      }
    });

    _completedSub = widget.player.stream.completed.listen((completed) {
      if (!mounted) return;
      if (completed) {
        _pillFadeTimer?.cancel();
        setState(() {
          _showPillBadge = true;
        });
      }
    });
  }

  void _unsubscribePlayer() {
    _pillFadeTimer?.cancel();
    _playingSub?.cancel();
    _completedSub?.cancel();
  }

  @override
  void dispose() {
    widget.onScrubbingChanged?.call(false);
    _debounceTimer?.cancel();
    _previewFadeTimer?.cancel();
    _frameCache.clear();
    _isFetchingFrame = false;
    _pendingTargetPos = null;
    _unsubscribePlayer();
    super.dispose();
  }

  void _fetchPreviewFrame(Duration targetPos, {bool immediate = false}) {
    if (widget.item.path.isEmpty) return;
    final bucketKey = targetPos.inMilliseconds ~/ 250;
    if (_frameCache.containsKey(bucketKey)) {
      final cached = _frameCache[bucketKey];
      if (_lastFrameBytes != cached) {
        setState(() {
          _lastFrameBytes = cached;
        });
      }
      return;
    }

    _pendingTargetPos = targetPos;
    if (_isFetchingFrame) return;

    if (immediate) {
      _debounceTimer?.cancel();
      _executeNextFetch();
    } else {
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(milliseconds: 35), () {
        _executeNextFetch();
      });
    }
  }

  Future<void> _executeNextFetch() async {
    if (_isFetchingFrame || _pendingTargetPos == null) return;
    if (!mounted || (!_isDragging && !_showPreview)) return;

    final targetPos = _pendingTargetPos!;
    _pendingTargetPos = null;
    final bucketKey = targetPos.inMilliseconds ~/ 250;

    if (_frameCache.containsKey(bucketKey)) {
      final cached = _frameCache[bucketKey];
      if (_lastFrameBytes != cached && mounted) {
        setState(() {
          _lastFrameBytes = cached;
        });
      }
      if (_pendingTargetPos != null) {
        _executeNextFetch();
      }
      return;
    }

    _isFetchingFrame = true;
    try {
      final isVert = widget.isVertical ||
          (widget.item.height != null &&
              widget.item.width != null &&
              widget.item.height! > widget.item.width!);
      final reqW = isVert ? 160 : 280;
      final reqH = isVert ? 280 : 160;

      final bytes = await ThumbnailService.instance.getVideoFrame(
        filePath: widget.item.path,
        time: targetPos,
        width: reqW,
        height: reqH,
      );

      if (mounted && bytes != null && bytes.isNotEmpty) {
        if (_frameCache.length >= 80) {
          _frameCache.remove(_frameCache.keys.first);
        }
        _frameCache[bucketKey] = bytes;
        if (_isDragging || _showPreview) {
          setState(() {
            _lastFrameBytes = bytes;
          });
        }
      }
    } finally {
      _isFetchingFrame = false;
      if (mounted && _pendingTargetPos != null && (_isDragging || _showPreview)) {
        _executeNextFetch();
      }
    }
  }

  void _onScrubStart(double v, Duration dur) {
    widget.onScrubbingChanged?.call(true);
    _pillFadeTimer?.cancel();
    _previewFadeTimer?.cancel();
    _wasPlayingBeforeDrag = widget.player.state.playing;
    if (_wasPlayingBeforeDrag) {
      widget.player.pause();
    }
    final target = Duration(
      milliseconds: (v * dur.inMilliseconds).round(),
    );
    _lastFrameBytes ??= _resolveInitialThumbnail();
    setState(() {
      _isDragging = true;
      _dragFraction = v;
      _showPillBadge = true;
      _showPreview = true;
      _previewMounted = true;
    });
    _fetchPreviewFrame(target, immediate: true);
  }

  void _onScrubUpdate(double v, Duration dur) {
    _pillFadeTimer?.cancel();
    _previewFadeTimer?.cancel();
    setState(() {
      _isDragging = true;
      _dragFraction = v;
      _showPillBadge = true;
      _showPreview = true;
      _previewMounted = true;
    });
    final target = Duration(
      milliseconds: (v * dur.inMilliseconds).round(),
    );
    _fetchPreviewFrame(target, immediate: false);
  }

  void _onScrubEnd(double v, Duration dur) {
    final target = Duration(
      milliseconds: (v * dur.inMilliseconds).round(),
    );
    widget.player.seek(target);
    if (_wasPlayingBeforeDrag) {
      widget.player.play();
    }
    widget.onScrubbingChanged?.call(false);
    _debounceTimer?.cancel();
    _pendingTargetPos = null;
    setState(() {
      _isDragging = false;
      _dragFraction = null;
    });
    _previewFadeTimer?.cancel();
    _previewFadeTimer = Timer(const Duration(milliseconds: 350), () {
      if (mounted && !_isDragging) {
        setState(() {
          _showPreview = false;
        });
        _previewFadeTimer = Timer(const Duration(milliseconds: 200), () {
          if (mounted && !_isDragging) {
            setState(() {
              _previewMounted = false;
            });
          }
        });
      }
    });
    _pillFadeTimer?.cancel();
    _pillFadeTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && !_isDragging) {
        setState(() {
          _showPillBadge = false;
        });
      }
    });
  }

  Widget _buildSeekbarWithPreview(
    BuildContext context, {
    required double frac,
    required Duration displayPos,
    required Duration dur,
    required bool isLandscape,
  }) {
    final isVert = widget.isVertical ||
        (widget.item.height != null &&
            widget.item.width != null &&
            widget.item.height! > widget.item.width!);
    final previewW = isVert ? 74.0 : 144.0;
    final previewH = isVert ? 128.0 : 82.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final scrubberWidget = _VideoScrubberBar(
          value: frac.clamp(0.0, 1.0),
          isLandscape: isLandscape,
          isDragging: _isDragging,
          onScrubStart: (v) => _onScrubStart(v, dur),
          onScrubUpdate: (v) => _onScrubUpdate(v, dur),
          onScrubEnd: (v) => _onScrubEnd(v, dur),
        );

        if (!_previewMounted) {
          return scrubberWidget;
        }

        final trackWidth = constraints.maxWidth - 32.0;
        final thumbX = 16.0 + frac.clamp(0.0, 1.0) * trackWidth;
        final leftOffset =
            (thumbX - previewW / 2).clamp(8.0, constraints.maxWidth - previewW - 8.0);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            scrubberWidget,
            Positioned(
              bottom: isLandscape ? 44.0 : 50.0,
              left: leftOffset,
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  opacity: _showPreview ? 1.0 : 0.0,
                  child: AnimatedScale(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    scale: _showPreview ? 1.0 : 0.88,
                    child: _SeekPreviewTooltip(
                      width: previewW,
                      height: previewH,
                      frameBytes: _lastFrameBytes,
                      displayTime: displayPos,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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
      ),
    );
  }

  void _showHorizontalMoreOptions(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.85,
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
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
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.white),
                    title: Text(context.tr.delete,
                        style: const TextStyle(color: Colors.white, fontSize: 15)),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      widget.onDelete();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showPhotoMoreOptions(BuildContext context) {
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
              if (widget.onRename != null)
                ListTile(
                  leading: const Icon(Icons.edit_outlined, color: Colors.white),
                  title: Text(context.tr.rename,
                      style: const TextStyle(color: Colors.white, fontSize: 15)),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    widget.onRename?.call();
                  },
                ),
              ListTile(
                leading:
                    const Icon(Icons.wallpaper_outlined, color: Colors.white),
                title: Text(context.tr.setAsWallpaper,
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                onTap: () {
                  Navigator.pop(sheetContext);
                  ShareService.setAsWallpaper(widget.item.path);
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
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (!widget.item.isVideo) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
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
                    label: context.tr.restore,
                    onTap: widget.onRestore ?? () {},
                  ),
                  _ViewerActionButton(
                    icon: const Icon(Icons.info_outline,
                        color: Colors.white, size: 22),
                    label: context.tr.details,
                    onTap: () => showMediaInfoSheet(context, widget.item),
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
                  _ViewerActionButton(
                    icon: const Icon(Icons.share_outlined,
                        color: Colors.white, size: 22),
                    label: context.tr.share,
                    onTap: () => ShareService.shareSingle(
                        widget.item.path,
                        isVideo: false),
                  ),
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
                    label: context.tr.delete,
                    onTap: widget.onDelete,
                  ),
                  _ViewerActionButton(
                    icon: const Icon(Icons.more_vert,
                        color: Colors.white, size: 22),
                    label: context.tr.more,
                    onTap: () => _showPhotoMoreOptions(context),
                  ),
                ],
              ),
      );
    }

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
        // 2. Compact seekbar slider with preview
        _buildSeekbarWithPreview(
          context,
          frac: frac,
          displayPos: displayPos,
          dur: dur,
          isLandscape: true,
        ),
        // 3. Actions row: Play/Pause on the left, action icons on the right
        Padding(
          padding: const EdgeInsets.only(left: 8, right: 12, bottom: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Play / Pause button
              StreamBuilder<bool>(
                initialData: widget.player.state.playing,
                stream: widget.player.stream.playing,
                builder: (_, snap) {
                  final playing = snap.data ?? widget.player.state.playing;
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
                    // Crop to fit / Fit to screen toggle (Photo 3)
                    BouncyTap(
                      onTap: widget.onToggleCropToFit,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          widget.cropToFit
                              ? Icons.fit_screen_rounded
                              : Icons.crop_free_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 4),
                  // Rotate (Photo 3 reference)
                  BouncyTap(
                    onTap: widget.onToggleOrientation,
                    child: const Padding(
                      padding: EdgeInsets.all(6),
                      child: DeviceRotateIcon(
                        size: 22,
                        color: Colors.white,
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
        if (widget.isVertical) ...[
          SizedBox(
            height: 28,
            child: Center(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                opacity: (_showPillBadge && !_showPreview) ? 1.0 : 0.0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 0.8,
                    ),
                  ),
                  child: Text(
                    '${MediaUtils.formatDuration(displayPos)}/${MediaUtils.formatDuration(dur)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
        ],
        // Seek bar with preview
        _buildSeekbarWithPreview(
          context,
          frac: frac,
          displayPos: displayPos,
          dur: dur,
          isLandscape: false,
        ),
        if (!widget.isVertical) ...[
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
                    const SizedBox(width: 8),
                    BouncyTap(
                      onTap: widget.onToggleOrientation,
                      child: const Padding(
                        padding: EdgeInsets.all(2),
                        child: DeviceRotateIcon(
                          size: 20,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ] else ...[
          const SizedBox(height: 8),
        ],
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
                    initialData: widget.player.state.playing,
                    stream: widget.player.stream.playing,
                    builder: (_, snap) {
                      final playing = snap.data ?? widget.player.state.playing;
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

// ── Device Rotate Icon (Photo 3 reference) ───────────────────────────────────

class DeviceRotateIcon extends StatelessWidget {
  const DeviceRotateIcon({
    super.key,
    this.size = 22,
    this.color = Colors.white,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _DeviceRotatePainter(color: color),
    );
  }
}

class _DeviceRotatePainter extends CustomPainter {
  const _DeviceRotatePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final center = Offset(size.width / 2, size.height / 2);

    // 1. Draw tilted smartphone outline in center (~ -33 degrees)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.58);

    final phoneWidth = size.width * 0.44;
    final phoneHeight = size.height * 0.68;
    final phoneRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset.zero,
        width: phoneWidth,
        height: phoneHeight,
      ),
      Radius.circular(size.width * 0.10),
    );
    canvas.drawRRect(phoneRect, paint);
    canvas.restore();

    // 2. Draw curved arrows on opposite corners
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    final arrowPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final arcRadius = size.width * 0.44;
    final arcRect = Rect.fromCircle(center: center, radius: arcRadius);

    // Top-right arc (clockwise)
    const sweepAngle = 0.70;
    const startAngle1 = -0.85;
    canvas.drawArc(arcRect, startAngle1, sweepAngle, false, arcPaint);

    // Arrowhead at end of arc 1
    final endAngle1 = startAngle1 + sweepAngle;
    final arrowTip1 = Offset(
      center.dx + arcRadius * math.cos(endAngle1),
      center.dy + arcRadius * math.sin(endAngle1),
    );
    final tan1 = endAngle1 + math.pi / 2;
    const wingLen = 3.5;
    const wingAngle = 0.65;
    final w1a = Offset(
      arrowTip1.dx + wingLen * math.cos(tan1 + math.pi - wingAngle),
      arrowTip1.dy + wingLen * math.sin(tan1 + math.pi - wingAngle),
    );
    final w1b = Offset(
      arrowTip1.dx + wingLen * math.cos(tan1 + math.pi + wingAngle),
      arrowTip1.dy + wingLen * math.sin(tan1 + math.pi + wingAngle),
    );
    final path1 = Path()
      ..moveTo(w1a.dx, w1a.dy)
      ..lineTo(arrowTip1.dx, arrowTip1.dy)
      ..lineTo(w1b.dx, w1b.dy);
    canvas.drawPath(path1, arrowPaint);

    // Bottom-left arc (clockwise)
    const startAngle2 = startAngle1 + math.pi;
    canvas.drawArc(arcRect, startAngle2, sweepAngle, false, arcPaint);

    // Arrowhead at end of arc 2
    final endAngle2 = startAngle2 + sweepAngle;
    final arrowTip2 = Offset(
      center.dx + arcRadius * math.cos(endAngle2),
      center.dy + arcRadius * math.sin(endAngle2),
    );
    final tan2 = endAngle2 + math.pi / 2;
    final w2a = Offset(
      arrowTip2.dx + wingLen * math.cos(tan2 + math.pi - wingAngle),
      arrowTip2.dy + wingLen * math.sin(tan2 + math.pi - wingAngle),
    );
    final w2b = Offset(
      arrowTip2.dx + wingLen * math.cos(tan2 + math.pi + wingAngle),
      arrowTip2.dy + wingLen * math.sin(tan2 + math.pi + wingAngle),
    );
    final path2 = Path()
      ..moveTo(w2a.dx, w2a.dy)
      ..lineTo(arrowTip2.dx, arrowTip2.dy)
      ..lineTo(w2b.dx, w2b.dy);
    canvas.drawPath(path2, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant _DeviceRotatePainter oldDelegate) =>
      oldDelegate.color != color;
}

// ── Video Scrubber Bar ────────────────────────────────────────────────────────

class _VideoScrubberBar extends StatefulWidget {
  const _VideoScrubberBar({
    required this.value,
    required this.isLandscape,
    required this.isDragging,
    required this.onScrubStart,
    required this.onScrubUpdate,
    required this.onScrubEnd,
  });

  final double value;
  final bool isLandscape;
  final bool isDragging;
  final ValueChanged<double> onScrubStart;
  final ValueChanged<double> onScrubUpdate;
  final ValueChanged<double> onScrubEnd;

  @override
  State<_VideoScrubberBar> createState() => _VideoScrubberBarState();
}

class _VideoScrubberBarState extends State<_VideoScrubberBar> {
  double? _lastFrac;

  @override
  Widget build(BuildContext context) {
    final barHeight = widget.isLandscape ? 36.0 : 44.0;
    const trackPadding = 16.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth =
            (constraints.maxWidth - trackPadding * 2).clamp(1.0, double.infinity);

        return Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (e) {
            final x = e.localPosition.dx;
            final frac = ((x - trackPadding) / trackWidth).clamp(0.0, 1.0);
            _lastFrac = frac;
            widget.onScrubStart(frac);
          },
          onPointerMove: (e) {
            final x = e.localPosition.dx;
            final frac = ((x - trackPadding) / trackWidth).clamp(0.0, 1.0);
            _lastFrac = frac;
            widget.onScrubUpdate(frac);
          },
          onPointerUp: (e) {
            final x = e.localPosition.dx;
            final frac = ((x - trackPadding) / trackWidth).clamp(0.0, 1.0);
            _lastFrac = null;
            widget.onScrubEnd(frac);
          },
          onPointerCancel: (e) {
            final endFrac = _lastFrac ?? widget.value;
            _lastFrac = null;
            widget.onScrubEnd(endFrac);
          },
          child: SizedBox(
            height: barHeight,
            width: double.infinity,
            child: CustomPaint(
              size: Size(constraints.maxWidth, barHeight),
              painter: _ScrubberTrackPainter(
                value: widget.value,
                isDragging: widget.isDragging,
                isLandscape: widget.isLandscape,
                trackPadding: trackPadding,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ScrubberTrackPainter extends CustomPainter {
  const _ScrubberTrackPainter({
    required this.value,
    required this.isDragging,
    required this.isLandscape,
    required this.trackPadding,
  });

  final double value;
  final bool isDragging;
  final bool isLandscape;
  final double trackPadding;

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height / 2;
    final trackWidth = size.width - trackPadding * 2;
    final startX = trackPadding;
    final endX = size.width - trackPadding;
    final clampedFrac = value.clamp(0.0, 1.0);
    final thumbX = startX + clampedFrac * trackWidth;

    final trackHeight =
        isDragging ? (isLandscape ? 3.5 : 4.0) : (isLandscape ? 2.2 : 2.8);
    final rradius = Radius.circular(trackHeight / 2);

    // 1. Inactive track (right / background)
    final inactivePaint = Paint()
      ..color = Colors.white30
      ..style = PaintingStyle.fill;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(startX, centerY - trackHeight / 2, endX,
            centerY + trackHeight / 2),
        rradius,
      ),
      inactivePaint,
    );

    // 2. Active track (left / progress)
    if (thumbX > startX) {
      final activePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTRB(startX, centerY - trackHeight / 2, thumbX,
              centerY + trackHeight / 2),
          rradius,
        ),
        activePaint,
      );
    }

    // 3. Thumb circle with subtle shadow & glow halo
    final thumbRadius =
        isDragging ? (isLandscape ? 7.5 : 8.5) : (isLandscape ? 5.5 : 6.5);

    if (isDragging) {
      // Glow ripple halo when dragging
      final haloPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(thumbX, centerY), thumbRadius + 5.0, haloPaint);
    }

    // Shadow under thumb
    final shadowPaint = Paint()
      ..color = Colors.black45
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
    canvas.drawCircle(Offset(thumbX, centerY + 1.0), thumbRadius, shadowPaint);

    // Solid white thumb
    final thumbPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbPaint);
  }

  @override
  bool shouldRepaint(covariant _ScrubberTrackPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.isDragging != isDragging ||
      oldDelegate.isLandscape != isLandscape;
}

