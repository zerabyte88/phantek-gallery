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
import '../../../core/services/thumbnail_service.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/bouncy_tap.dart';
import 'widgets/media_info_sheet.dart';

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
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  late final List<MediaItem> _videos;
  late final PageController _pageController;
  late int _current;
  bool _showControls = true;
  bool _isFullscreen = false;

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
    _initPlayer();
    _precacheAdjacentVideos(_current);
  }

  void _precacheAdjacentVideos(int index) {
    if (index + 1 < _videos.length) {
      ThumbnailService.instance.getThumbnail(_videos[index + 1].id);
    }
    if (index - 1 >= 0) {
      ThumbnailService.instance.getThumbnail(_videos[index - 1].id);
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
      ),
    );

    _player.open(
      Media(_videos[_current].path),
      play: false,
    );
  }

  void _onPageChanged(int index) {
    if (index == _current) return;
    setState(() {
      _current = index;
    });
    // Never auto-play on swipe — user decides whether to play
    _player.open(Media(_videos[index].path), play: false);
    _precacheAdjacentVideos(index);
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
    _player.dispose(); // releases native MPV context
    _pageController.dispose();
    _exitLandscape();
    super.dispose();
  }

  void _enterLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    setState(() => _isFullscreen = true);
  }

  void _exitLandscape() {
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    setState(() => _isFullscreen = false);
  }

  void _toggleFullscreen() {
    if (_isFullscreen) {
      _exitLandscape();
    } else {
      _enterLandscape();
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
      });
      _pageController.jumpToPage(_current);
      _player.open(Media(_videos[_current].path), play: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = _videos[_current];

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showControls = !_showControls),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video PageView ──────────────────────────────────
              PageView.builder(
                controller: _pageController,
                itemCount: _videos.length,
                onPageChanged: _onPageChanged,
                physics: const BouncingScrollPhysics(),
                itemBuilder: (context, index) {
                  if (index == _current) {
                    return Center(
                      child: Video(
                        key: ValueKey(_videos[index].id),
                        controller: _controller,
                        controls: NoVideoControls,
                        fit: BoxFit.contain,
                      ),
                    );
                  }
                  return _VideoThumbnailPage(item: _videos[index]);
                },
              ),

              // ── Controls overlay ───────────────────────────────
              AnimatedOpacity(
                opacity: _showControls ? 1 : 0,
                duration: const Duration(milliseconds: 200),
                child: IgnorePointer(
                  ignoring: !_showControls,
                  child: Column(
                    children: [
                      // Top bar
                      _TopBar(
                        item: item,
                        currentIndex: _current,
                        totalVideos: _videos.length,
                        isTrash: widget.isTrash,
                        onRestore: _restoreItem,
                        onBack: () {
                          if (_isFullscreen) {
                            _exitLandscape();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                        onInfo: () =>
                            showMediaInfoSheet(context, item),
                        onDelete: _deleteItem,
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
                        onToggleFullscreen: _toggleFullscreen,
                      ),
                    ],
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

// ── Inactive video thumbnail placeholder ───────────────────────────────────

class _VideoThumbnailPage extends StatelessWidget {
  const _VideoThumbnailPage({required this.item});
  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: ThumbnailService.instance.getThumbnail(item.id),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
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
          ],
        ],
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.player,
    required this.item,
    required this.isFullscreen,
    required this.onToggleFullscreen,
  });
  final Player player;
  final MediaItem item;
  final bool isFullscreen;
  final VoidCallback onToggleFullscreen;

  @override
  Widget build(BuildContext context) {
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
            stream: player.stream.position,
            builder: (_, posSnap) {
              return StreamBuilder<Duration>(
                stream: player.stream.duration,
                builder: (_, durSnap) {
                  final pos = posSnap.data ?? Duration.zero;
                  final dur =
                      durSnap.data ?? item.duration ?? Duration.zero;
                  final frac =
                      dur.inMilliseconds > 0
                          ? pos.inMilliseconds / dur.inMilliseconds
                          : 0.0;
                  return Column(
                    children: [
                      Slider(
                        value: frac.clamp(0.0, 1.0),
                        onChanged: (v) {
                          final target = Duration(
                              milliseconds:
                                  (v * dur.inMilliseconds).round());
                          player.seek(target);
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
                            Text(MediaUtils.formatDuration(pos),
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
                // Centered backward, play/pause, forward (enlarged with bouncy tap)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Seek -10s
                    BouncyTap(
                      onTap: () async {
                        final pos = player.state.position;
                        await player.seek(pos - const Duration(seconds: 10));
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
                      stream: player.stream.playing,
                      builder: (_, snap) {
                        final playing = snap.data ?? false;
                        return BouncyTap(
                          onTap: player.playOrPause,
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
                        final pos = player.state.position;
                        await player.seek(pos + const Duration(seconds: 10));
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
                    onTap: onToggleFullscreen,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Icon(
                        isFullscreen
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
