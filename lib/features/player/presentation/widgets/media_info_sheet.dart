import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/utils/media_utils.dart';

/// Shows a bottom sheet with complete details about [item].
void showMediaInfoSheet(
  BuildContext context,
  MediaItem item, {
  VideoPlayerController? player,
  double? fps,
  String? codec,
}) {
  double? effectiveFps = fps;
  String? effectiveCodec = codec;

  String resolution = item.resolution;
  Duration? duration = item.duration;

  if (player != null && player.value.isInitialized) {
    final size = player.value.size;
    if (size.width > 0 && size.height > 0) {
      resolution = '${size.width.toInt()} × ${size.height.toInt()}';
    }
    if (player.value.duration > Duration.zero) {
      duration = player.value.duration;
    }
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
                context.tr.details,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 16),
              _InfoRow(
                  icon: Icons.title, label: context.tr.name, value: item.name),
              _InfoRow(
                icon: Icons.calendar_today_outlined,
                label: context.tr.date,
                value:
                    '${MediaUtils.formatViewerDate(item.date)}, ${MediaUtils.formatViewerTime(item.date)}',
              ),
              _InfoRow(
                icon: Icons.sd_storage_outlined,
                label: context.tr.size,
                value: MediaUtils.formatSize(item.size),
              ),
              if (resolution.isNotEmpty)
                _InfoRow(
                  icon: Icons.aspect_ratio_outlined,
                  label: context.tr.resolution,
                  value: resolution,
                ),
              if (item.isVideo && effectiveFps != null && effectiveFps > 0)
                _InfoRow(
                  icon: Icons.speed_outlined,
                  label: context.tr.frameRate,
                  value: MediaUtils.formatFps(effectiveFps),
                ),
              if (item.isVideo &&
                  effectiveCodec != null &&
                  effectiveCodec.trim().isNotEmpty)
                _InfoRow(
                  icon: Icons.video_settings_outlined,
                  label: context.tr.codec,
                  value: MediaUtils.formatCodec(effectiveCodec),
                ),
              if (item.isVideo && duration != null)
                _InfoRow(
                  icon: Icons.timer_outlined,
                  label: context.tr.duration,
                  value: MediaUtils.formatDuration(duration),
                ),
              _InfoRow(
                icon: Icons.folder_outlined,
                label: context.tr.path,
                value: item.path,
                trailing: IconButton(
                  icon: const Icon(Icons.copy_outlined, size: 20),
                  tooltip: context.tr.copyPath,
                  constraints:
                      const BoxConstraints(minWidth: 48, minHeight: 48),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: item.path));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(context.tr.pathCopied),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: item.path));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(context.tr.pathCopied),
                      duration: const Duration(seconds: 2),
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
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon,
              size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
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
