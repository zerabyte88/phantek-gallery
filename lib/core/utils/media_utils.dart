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

  /// Formats date for media viewer top bar: "September 15" or "September 15, 2024".
  static String formatViewerDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year) {
      return DateFormat('MMMM d').format(dt);
    }
    return DateFormat('MMMM d, y').format(dt);
  }

  /// Formats time for media viewer top bar: "3:40 PM".
  static String formatViewerTime(DateTime dt) => DateFormat('h:mm a').format(dt);

  /// Formats frame rate into clean string, e.g. "60 fps", "29.97 fps", "24 fps".
  static String formatFps(double fps) {
    if (fps <= 0) return '';
    if (fps == fps.roundToDouble()) {
      return '${fps.toInt()} fps';
    }
    final str = fps.toStringAsFixed(2);
    final trimmed = str.endsWith('0') ? str.substring(0, str.length - 1) : str;
    return '$trimmed fps';
  }

  /// Formats raw video codec string into human-friendly name.
  static String formatCodec(String codec) {
    final c = codec.trim().toLowerCase();
    if (c.isEmpty) return '';
    if (c.contains('264') || c.contains('avc')) return 'H.264 (AVC)';
    if (c.contains('265') || c.contains('hevc') || c.contains('hvc1')) {
      return 'H.265 (HEVC)';
    }
    if (c.contains('av01') || c == 'av1') return 'AV1';
    if (c == 'vp9') return 'VP9';
    if (c == 'vp8') return 'VP8';
    if (c.contains('mpeg4') || c.contains('mp4v')) return 'MPEG-4';
    if (c.contains('mjpeg')) return 'Motion JPEG';
    return codec.trim().toUpperCase();
  }
}
