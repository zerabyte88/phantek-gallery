import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/utils/media_utils.dart';

/// Shows a bottom sheet with complete details about [item].
void showMediaInfoSheet(
  BuildContext context,
  MediaItem item, {
  Player? player,
  double? fps,
  String? codec,
}) {
  double? effectiveFps = fps;
  String? effectiveCodec = codec;

  if (player != null) {
    try {
      final currentTrack = player.state.track.video;
      effectiveFps ??= (currentTrack.fps != null && currentTrack.fps! > 0)
          ? currentTrack.fps
          : null;
      effectiveCodec ??=
          (currentTrack.codec != null && currentTrack.codec!.isNotEmpty)
              ? currentTrack.codec
              : null;

      if (effectiveFps == null || effectiveCodec == null) {
        for (final t in player.state.tracks.video) {
          if (effectiveFps == null && t.fps != null && t.fps! > 0) {
            effectiveFps = t.fps;
          }
          if (effectiveCodec == null &&
              t.codec != null &&
              t.codec!.isNotEmpty) {
            effectiveCodec = t.codec;
          }
        }
      }
    } catch (_) {}
  }

  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) {
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Details',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 16),
              _InfoRow(icon: Icons.title, label: 'Name', value: item.name),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: 'Date',
                value:
                    '${MediaUtils.formatViewerDate(item.date)}, ${MediaUtils.formatViewerTime(item.date)}',
              ),
              _InfoRow(
                icon: Icons.sd_storage_outlined,
                label: 'Size',
                value: MediaUtils.formatSize(item.size),
              ),
              if (item.resolution.isNotEmpty)
                _InfoRow(
                  icon: Icons.aspect_ratio_outlined,
                  label: 'Resolution',
                  value: item.resolution,
                ),
              if (item.isVideo && effectiveFps != null && effectiveFps > 0)
                _InfoRow(
                  icon: Icons.speed_outlined,
                  label: 'Frame Rate',
                  value: MediaUtils.formatFps(effectiveFps),
                ),
              if (item.isVideo &&
                  effectiveCodec != null &&
                  effectiveCodec.trim().isNotEmpty)
                _InfoRow(
                  icon: Icons.video_settings_outlined,
                  label: 'Codec',
                  value: MediaUtils.formatCodec(effectiveCodec),
                ),
              if (item.isVideo && item.duration != null)
                _InfoRow(
                  icon: Icons.timer_outlined,
                  label: 'Duration',
                  value: MediaUtils.formatDuration(item.duration!),
                ),
              _InfoRow(
                icon: Icons.folder_outlined,
                label: 'Path',
                value: item.path,
                trailing: IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 18),
                  tooltip: 'Copy path',
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.path));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Path copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: item.path));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Path copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  value,
                  style: const TextStyle(fontSize: 14),
                ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: content,
      );
    }
    return content;
  }
}
