import 'package:flutter/material.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/utils/media_utils.dart';

/// Shows a bottom sheet with complete details about [item].
void showMediaInfoSheet(BuildContext context, MediaItem item) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
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
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
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
        ],
      ),
    );
  }
}
