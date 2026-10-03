import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/utils/media_utils.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  const VideoPlayerScreen({super.key, required this.item});
  final MediaItem item;

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen>
    with WidgetsBindingObserver {
  late final Player _player;
  late final VideoController _controller;
  bool _showControls = true;
  bool _isFullscreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initPlayer();
  }

  void _initPlayer() {
    final settings = ref.read(settingsNotifierProvider);
    _player = Player(
      configuration: PlayerConfiguration(
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

    _player.open(Media(widget.item.path));
    if (settings.autoPlayVideo) _player.play();
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

  Future<void> _deleteItem() async {
    final settings = ref.read(settingsNotifierProvider);
    final label = settings.enableTrash ? 'Move to Trash' : 'Delete';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(label),
        content: Text('"${widget.item.name}" will be '
            '${settings.enableTrash ? 'moved to trash' : 'permanently deleted'}.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    _player.pause();
    if (settings.enableTrash) {
      await ref.read(trashProvider.notifier).moveToTrash(
            id: widget.item.id,
            path: widget.item.path,
            isVideo: true,
          );
    } else {
      final f = File(widget.item.path);
      if (await f.exists()) await f.delete();
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullscreen,
        bottom: !_isFullscreen,
        child: GestureDetector(
          onTap: () => setState(() => _showControls = !_showControls),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ── Video surface ──────────────────────────────────
              Center(
                child: Video(
                  controller: _controller,
                  fit: BoxFit.contain,
                ),
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
                        item: widget.item,
                        onDelete: _deleteItem,
                        onBack: () {
                          if (_isFullscreen) {
                            _exitLandscape();
                          } else {
                            Navigator.of(context).pop();
                          }
                        },
                      ),
                      const Spacer(),
                      // Bottom controls
                      _BottomBar(
                        player: _player,
                        item: widget.item,
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

// ── Top bar ───────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar(
      {required this.item,
      required this.onDelete,
      required this.onBack});
  final MediaItem item;
  final VoidCallback onDelete;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4),
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
            icon: const Icon(Icons.arrow_back, color: Colors.white),
          ),
          Expanded(
            child: Text(
              item.name,
              style:
                  const TextStyle(color: Colors.white, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon:
                const Icon(Icons.delete_outline, color: Colors.white),
            onPressed: onDelete,
          ),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Seek -10s
              IconButton(
                icon: const Icon(Icons.replay_10, color: Colors.white),
                onPressed: () async {
                  final pos = player.state.position;
                  await player.seek(
                      pos - const Duration(seconds: 10));
                },
              ),
              // Play/Pause
              StreamBuilder<bool>(
                stream: player.stream.playing,
                builder: (_, snap) {
                  final playing = snap.data ?? false;
                  return IconButton(
                    iconSize: 52,
                    icon: Icon(
                      playing ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                    ),
                    onPressed: player.playOrPause,
                  );
                },
              ),
              // Seek +10s
              IconButton(
                icon: const Icon(Icons.forward_10, color: Colors.white),
                onPressed: () async {
                  final pos = player.state.position;
                  await player
                      .seek(pos + const Duration(seconds: 10));
                },
              ),
              const Spacer(),
              // Fullscreen toggle
              IconButton(
                icon: Icon(
                  isFullscreen
                      ? Icons.fullscreen_exit
                      : Icons.fullscreen,
                  color: Colors.white,
                ),
                onPressed: onToggleFullscreen,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
