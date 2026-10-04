import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
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
  double _dragOffsetY = 0.0;
  bool _isDragging = false;
  double? _startDragY;
  double? _startDragX;
  TapDownDetails? _doubleTapDetails;
  int _seekSeconds = 0;
  bool _seekIsForward = true;
  Timer? _seekOverlayTimer;
  bool _isSwiping = false;
  int? _pendingIndex;
  bool _isVideoZoomed = false;
  bool _isPinching = false;
  bool _isMultiTouch = false;
  final Set<int> _activePointers = {};
  AnimationController? _zoomAnimController;

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
    _initPlayer();
    _precacheAdjacentVideos(_current);
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
        if (mounted) {
          setState(() {
            _isVideoZoomed = false;
          });
        }
      }
    });

    _zoomAnimController!.forward();
  }

  void _precacheAdjacentVideos(int index) {
    for (final offset in const [-2, -1, 1, 2]) {
      final target = index + offset;
      if (target >= 0 && target < _videos.length) {
        ThumbnailService.instance.getThumbnail(
          _videos[target].id,
          filePath: _videos[target].path,
        );
      }
    }
  }

  void _initPlayer() {
    final settings = ref.read(settingsNotifierProvider);
    _player = Player(
      configuration: const PlayerConfiguration(
        // Hardware acceleration controlled via settings.
        // media_kit uses platform HW accel by default on Android.
        // Disable by forcing software renderer when setting is off.
        bufferSize: 64 * 1024 * 1024, // 64 MB buffer
        logLevel: MPVLogLevel.warn,
      ),
    );
    _controller = VideoController(
      _player,
      configuration: VideoControllerConfiguration(
        // enableHardwareAcceleration defaults to true on Android.
        // We propagate the user preference.
        enableHardwareAcceleration: settings.hardwareAcceleration,
        hwdec: settings.hardwareAcceleration ? 'auto-safe' : 'no',
      ),
    );

    // Apply robust codec configuration:
    // H.264 and HEVC (H.265) utilize Android MediaCodec hardware decoding.
    // VP9 and other software-reliable codecs fall back to FFmpeg's robust decoder on Android,
    // eliminating MediaCodec OMX/C2 buffer-copy crashes and black screens on VP9.
    if (_player.platform is NativePlayer && settings.hardwareAcceleration) {
      final native = _player.platform as NativePlayer;
      native.setProperty('hwdec-codecs', 'h264,hevc,mpeg4,mpeg2video,vp8,av1');
    }

    _player.stream.error.listen((err) {
      debugPrint('[VideoPlayer] Playback error: $err');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Playback warning: $err'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    });

    _player.open(
      Media(_videos[_current].path),
      play: false,
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
    });

    final settings = ref.read(settingsNotifierProvider);
    if (_player.platform is NativePlayer && settings.hardwareAcceleration) {
      final native = _player.platform as NativePlayer;
      native.setProperty('hwdec-codecs', 'h264,hevc,mpeg4,mpeg2video,vp8,av1');
    }

    // Never auto-play on swipe — user decides whether to play
    _player.open(Media(_videos[index].path), play: false);
    if (_isLooping) {
      _player.setPlaylistMode(PlaylistMode.loop);
    }
    if (_playbackSpeed != 1.0) {
      _player.setRate(_playbackSpeed);
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _seekOverlayTimer?.cancel();
    _zoomAnimController?.dispose();
    _transformationController.dispose();
    _player.dispose(); // releases native MPV context
    _pageController.dispose();
    _exitFullscreen();
    super.dispose();
  }

  bool _isCurrentVideoPortrait() {
    final item = _videos[_current];
    if (item.width != null && item.height != null) {
      return item.height! > item.width!;
    }
    return false;
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

  void _handleDoubleTap() {
    if (_doubleTapDetails == null) return;
    final width = MediaQuery.of(context).size.width;
    final x = _doubleTapDetails!.localPosition.dx;
    final isForward = x >= width * 0.5;

    HapticFeedback.lightImpact();

    final step = isForward ? 10 : -10;
    if (_seekOverlayTimer?.isActive == true && _seekIsForward == isForward) {
      _seekSeconds += 10;
    } else {
      _seekSeconds = 10;
      _seekIsForward = isForward;
    }

    final pos = _player.state.position;
    final dur = _player.state.duration;
    final target = pos + Duration(seconds: step);
    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds : 86400000;
    final clampedMs = target.inMilliseconds.clamp(0, maxMs);
    _player.seek(Duration(milliseconds: clampedMs));

    _seekOverlayTimer?.cancel();
    setState(() {});

    _seekOverlayTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        setState(() {
          _seekSeconds = 0;
        });
      }
    });
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
                const Text(
                  'Playback Speed',
                  style: TextStyle(
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
                      speed == 1.0 ? '1.0x (Normal)' : '${speed}x',
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
        content: Text(next ? 'Loop enabled' : 'Loop disabled'),
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
        SnackBar(content: Text('"${item.name}" restored')),
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
          SnackBar(content: Text('Failed to delete video: $e')),
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
    final bgOpacity = (1.0 - (_dragOffsetY / 250)).clamp(0.0, 1.0);

    return PopScope(
      canPop: !_isFullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isFullscreen) {
          _exitFullscreen();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: bgOpacity),
        body: SafeArea(
          top: !_isFullscreen,
          bottom: !_isFullscreen,
          child: Listener(
            onPointerDown: (e) {
              _activePointers.add(e.pointer);
              if (_activePointers.length > 1) {
                _isMultiTouch = true;
                _isPinching = true;
                if (_isDragging || _dragOffsetY > 0) {
                  setState(() {
                    _isDragging = false;
                    _dragOffsetY = 0.0;
                    _startDragY = null;
                    _startDragX = null;
                  });
                }
                return;
              }
              _startDragY = e.position.dy;
              _startDragX = e.position.dx;
            },
            onPointerMove: (e) {
              if (_isFullscreen ||
                  _isVideoZoomed ||
                  _isPinching ||
                  _isMultiTouch ||
                  _activePointers.length > 1 ||
                  _startDragY == null ||
                  _startDragX == null) {
                return;
              }
              final dy = e.position.dy - _startDragY!;
              final dx = (e.position.dx - _startDragX!).abs();
              if (dy > 12 && dy > dx * 1.5) {
                setState(() {
                  _isDragging = true;
                  _dragOffsetY = (dy - 12).clamp(0.0, 400.0);
                });
              }
            },
            onPointerUp: (e) {
              _activePointers.remove(e.pointer);
              if (_activePointers.isEmpty) {
                final wasMultiTouch = _isMultiTouch;
                _isMultiTouch = false;
                _isPinching = false;
                _startDragY = null;
                _startDragX = null;
                if (_dragOffsetY > 90 && !wasMultiTouch && !_isVideoZoomed) {
                  _player.pause();
                  Navigator.of(context).pop();
                } else if (_dragOffsetY > 0 || _isDragging) {
                  setState(() {
                    _isDragging = false;
                    _dragOffsetY = 0.0;
                  });
                }
              }
            },
            onPointerCancel: (e) {
              _activePointers.remove(e.pointer);
              if (_activePointers.isEmpty) {
                setState(() {
                  _isMultiTouch = false;
                  _isPinching = false;
                  _isDragging = false;
                  _dragOffsetY = 0.0;
                  _startDragY = null;
                  _startDragX = null;
                });
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_dragOffsetY < 10) {
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
                  // ── Video PageView with drag translation ───────────────
                  AnimatedContainer(
                    duration: _isDragging ? Duration.zero : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    transform: Matrix4.translationValues(0, _dragOffsetY, 0),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: (notification) {
                        if (notification is ScrollStartNotification) {
                          if (notification.dragDetails != null) {
                            _isSwiping = true;
                            // Immediately pause playback on swipe to free hardware decoder
                            // and GPU pipeline for silky-smooth 60/120fps motion.
                            if (_player.state.playing) {
                              _player.pause();
                            }
                          }
                        } else if (notification is ScrollEndNotification) {
                          final settledPage = _pageController.page?.round();
                          final target = _pendingIndex ?? settledPage;
                          _isSwiping = false;
                          _pendingIndex = null;
                          if (target != null &&
                              target != _current &&
                              target >= 0 &&
                              target < _videos.length) {
                            _changeToVideo(target);
                          }
                        }
                        return false;
                      },
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _videos.length,
                        onPageChanged: _onPageChanged,
                        physics: _isVideoZoomed
                            ? const NeverScrollableScrollPhysics()
                            : const BouncingScrollPhysics(),
                        itemBuilder: (context, index) {
                          if (index == _current) {
                            return Center(
                              child: ClipRect(
                                child: InteractiveViewer(
                                  transformationController: _transformationController,
                                  minScale: 1.0,
                                  maxScale: 5.0,
                                  panEnabled: _isVideoZoomed,
                                  scaleEnabled: true,
                                  clipBehavior: Clip.hardEdge,
                                  onInteractionStart: (details) {
                                    if (details.pointerCount > 1) {
                                      setState(() => _isPinching = true);
                                    }
                                  },
                                  onInteractionUpdate: (details) {
                                    final scale = _transformationController.value.getMaxScaleOnAxis();
                                    final isZoomed = scale > 1.05;
                                    if (isZoomed != _isVideoZoomed) {
                                      setState(() {
                                        _isVideoZoomed = isZoomed;
                                      });
                                    }
                                  },
                                  onInteractionEnd: (details) {
                                    final scale = _transformationController.value.getMaxScaleOnAxis();
                                    final isZoomed = scale > 1.05;
                                    setState(() {
                                      _isVideoZoomed = isZoomed;
                                      _isPinching = false;
                                    });
                                  },
                                  child: Center(
                                    child: Stack(
                                      fit: StackFit.passthrough,
                                      alignment: Alignment.center,
                                      children: [
                                        _VideoThumbnailPage(item: _videos[index]),
                                        Video(
                                          key: const ValueKey('active_video_surface'),
                                          controller: _controller,
                                          controls: NoVideoControls,
                                          fit: BoxFit.contain,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                          return _VideoThumbnailPage(item: _videos[index]);
                        },
                      ),
                    ),
                  ),

                  // ── Double-tap seek feedback overlay ────────────────
                  if (_seekSeconds > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Align(
                          alignment: _seekIsForward
                              ? const Alignment(0.65, 0.0)
                              : const Alignment(-0.65, 0.0),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(32),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  width: 1.5),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (!_seekIsForward) ...[
                                  const Icon(Icons.fast_rewind_rounded,
                                      color: Colors.white, size: 28),
                                  const SizedBox(width: 8),
                                ],
                                Text(
                                  '${_seekIsForward ? '+' : '-'}${_seekSeconds}s',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                if (_seekIsForward) ...[
                                  const SizedBox(width: 8),
                                  const Icon(Icons.fast_forward_rounded,
                                      color: Colors.white, size: 28),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ── Video zoom indicator and reset pill ──────────────────
                  if (_isVideoZoomed)
                    Positioned(
                      top: _showControls ? 80 : (MediaQuery.of(context).padding.top + 16),
                      right: 16,
                      child: SafeArea(
                        top: !_showControls,
                        child: BouncyTap(
                          onTap: _resetVideoZoom,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
                  AnimatedOpacity(
                    opacity: (_showControls && _dragOffsetY < 20 && !_isPinching) ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_showControls || _dragOffsetY >= 20 || _isPinching,
                      child: Column(
                        children: [
                          // Top bar
                          _TopBar(
                            item: item,
                            currentIndex: _current,
                            totalVideos: _videos.length,
                            isTrash: widget.isTrash,
                            playbackSpeed: _playbackSpeed,
                            isLooping: _isLooping,
                            onSelectSpeed: _showPlaybackSpeedSheet,
                            onToggleLoop: _toggleLoop,
                            onRestore: _restoreItem,
                            onBack: () {
                              if (_isFullscreen) {
                                _exitFullscreen();
                              } else {
                                Navigator.of(context).pop();
                              }
                            },
                            onInfo: () =>
                                showMediaInfoSheet(context, item),
                            onDelete: _deleteItem,
                            onRename: _renameCurrentItem,
                          ),
                          const Spacer(),
                          // Center play button when paused
                          Center(
                            child: StreamBuilder<bool>(
                              stream: _player.stream.playing,
                              builder: (_, snap) {
                                final playing = snap.data ?? false;
                                if (playing) return const SizedBox.shrink();
                                return BouncyTap(
                                  onTap: _player.play,
                                  child: Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.55),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(alpha: 0.4),
                                        width: 1.5,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 48,
                                      color: Colors.white,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                          const Spacer(),
                          // Bottom controls
                          _BottomBar(
                            player: _player,
                            item: item,
                            isFullscreen: _isFullscreen,
                            isLooping: _isLooping,
                            onToggleFullscreen: _toggleFullscreen,
                            onToggleLoop: _toggleLoop,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Inactive video thumbnail placeholder ───────────────────────────────────

class _VideoThumbnailPage extends StatelessWidget {
  const _VideoThumbnailPage({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final cached = ThumbnailService.instance.getMemoryThumbnail(item.id);
    if (cached != null) {
      return Center(
        child: Image.memory(
          cached,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: ThumbnailService.instance.getThumbnail(item.id, filePath: item.path),
      builder: (context, snapshot) {
        if (snapshot.data != null) {
          return Center(
            child: Image.memory(
              snapshot.data!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          );
        }
        return const Center(
          child: Icon(Icons.videocam_outlined, size: 64, color: Colors.white24),
        );
      },
    );
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.item,
    required this.currentIndex,
    required this.totalVideos,
    required this.onBack,
    required this.onInfo,
    required this.onDelete,
    this.isTrash = false,
    this.playbackSpeed = 1.0,
    this.isLooping = false,
    this.onSelectSpeed,
    this.onToggleLoop,
    this.onRestore,
    this.onRename,
  });
  final MediaItem item;
  final int currentIndex;
  final int totalVideos;
  final VoidCallback onBack;
  final VoidCallback onInfo;
  final VoidCallback onDelete;
  final bool isTrash;
  final double playbackSpeed;
  final bool isLooping;
  final VoidCallback? onSelectSpeed;
  final VoidCallback? onToggleLoop;
  final VoidCallback? onRestore;
  final VoidCallback? onRename;

  @override
  Widget build(BuildContext context) {
    final subtext = totalVideos > 1
        ? '${currentIndex + 1} / $totalVideos • ${MediaUtils.formatViewerDate(item.date)}, ${MediaUtils.formatViewerTime(item.date)}'
        : '${MediaUtils.formatViewerDate(item.date)}, ${MediaUtils.formatViewerTime(item.date)}';

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
                  subtext,
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
          if (isTrash) ...[
            if (onRestore != null)
              IconButton(
                icon: const Icon(Icons.restore,
                    color: Colors.white, size: 22),
                tooltip: 'Restore',
                onPressed: onRestore,
              ),
            IconButton(
              icon: const Icon(Icons.delete_forever,
                  color: Colors.white, size: 22),
              tooltip: 'Delete Permanently',
              onPressed: onDelete,
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
                  tooltip: isFav ? 'Remove from favorites' : 'Add to favorites',
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
                        .update((s) => s.copyWith(favoriteIds: currentFavs.toList()));
                  },
                );
              },
            ),
            IconButton(
              icon: const Icon(Icons.share_outlined,
                  color: Colors.white, size: 22),
              tooltip: 'Share',
              onPressed: () =>
                  ShareService.shareSingle(item.path, isVideo: true),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: Colors.white, size: 22),
              tooltip: 'Delete',
              onPressed: onDelete,
            ),
            IconButton(
              icon: const Icon(Icons.info_outline,
                  color: Colors.white, size: 22),
              tooltip: 'Details',
              onPressed: onInfo,
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert,
                  color: Colors.white, size: 22),
              tooltip: 'More options',
              color: const Color(0xFF222222),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              onSelected: (value) {
                if (value == 'rename') {
                  onRename?.call();
                } else if (value == 'speed') {
                  onSelectSpeed?.call();
                } else if (value == 'loop') {
                  onToggleLoop?.call();
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'speed',
                  child: Row(
                    children: [
                      const Icon(Icons.speed,
                          size: 20, color: Colors.white),
                      const SizedBox(width: 12),
                      Text(
                        'Speed (${playbackSpeed == 1.0 ? 'Normal' : '${playbackSpeed}x'})',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'loop',
                  child: Row(
                    children: [
                      Icon(
                        isLooping ? Icons.repeat_one : Icons.repeat,
                        size: 20,
                        color: isLooping
                            ? Theme.of(context).colorScheme.primary
                            : Colors.white,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        isLooping ? 'Loop: On' : 'Loop: Off',
                        style: TextStyle(
                          color: isLooping
                              ? Theme.of(context).colorScheme.primary
                              : Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isTrash)
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
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────

class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.player,
    required this.item,
    required this.isFullscreen,
    required this.isLooping,
    required this.onToggleFullscreen,
    required this.onToggleLoop,
  });

  final Player player;
  final MediaItem item;
  final bool isFullscreen;
  final bool isLooping;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onToggleLoop;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  bool _isDragging = false;
  double? _dragFraction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Seek bar
          StreamBuilder<Duration>(
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
                  return Column(
                    children: [
                      Slider(
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
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment:
                              MainAxisAlignment.spaceBetween,
                          children: [
                            Text(MediaUtils.formatDuration(displayPos),
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 12)),
                            Text(MediaUtils.formatDuration(dur),
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
          // Play controls
          SizedBox(
            height: 72,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Loop toggle on the left
                Align(
                  alignment: Alignment.centerLeft,
                  child: BouncyTap(
                    onTap: widget.onToggleLoop,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        widget.isLooping
                            ? Icons.repeat_one
                            : Icons.repeat,
                        size: 26,
                        color: widget.isLooping
                            ? cs.primary
                            : Colors.white70,
                      ),
                    ),
                  ),
                ),
                // Centered backward, play/pause, forward (enlarged with bouncy tap)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Seek -10s
                    BouncyTap(
                      onTap: () async {
                        final pos = widget.player.state.position;
                        await widget.player
                            .seek(pos - const Duration(seconds: 10));
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.replay_10,
                            size: 36, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Play/Pause
                    StreamBuilder<bool>(
                      stream: widget.player.stream.playing,
                      builder: (_, snap) {
                        final playing = snap.data ?? false;
                        return BouncyTap(
                          onTap: widget.player.playOrPause,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              playing
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              size: 64,
                              color: Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                    // Seek +10s
                    BouncyTap(
                      onTap: () async {
                        final pos = widget.player.state.position;
                        await widget.player
                            .seek(pos + const Duration(seconds: 10));
                      },
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.forward_10,
                            size: 36, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                // Fullscreen toggle on the right
                Align(
                  alignment: Alignment.centerRight,
                  child: BouncyTap(
                    onTap: widget.onToggleFullscreen,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        widget.isFullscreen
                            ? Icons.fullscreen_exit
                            : Icons.fullscreen,
                        size: 28,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
