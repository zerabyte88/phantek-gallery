import 'package:intl/intl.dart';

/// Lightweight helpers for formatting media metadata.
/// No external network calls \u2013 100% local.
class MediaUtils {
  MediaUtils._();

  static final _dateFormatter = DateFormat('dd MMM yyyy');
  static final _dateTimeFormatter = DateFormat('dd MMM yyyy  HH:mm');

  /// Human-readable file size: "3.2 MB", "840 KB", etc.
  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Formats a [Duration] as "mm:ss" or "h:mm:ss" for video playback display.
  static String formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  static String formatDate(DateTime dt) => _dateFormatter.format(dt);
  static String formatDateTime(DateTime dt) => _dateTimeFormatter.format(dt);
}
