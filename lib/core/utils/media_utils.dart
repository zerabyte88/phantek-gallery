import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

/// Lightweight helpers for formatting media metadata.
/// No external network calls \u2013 100% local.
class MediaUtils {
  MediaUtils._();

  static final _dateFormatter = DateFormat('dd MMM yyyy');
  static final _dateTimeFormatter = DateFormat('dd MMM yyyy  HH:mm');
  static final RegExp _pathSepRegex = RegExp(r'[/\\]');

  /// Returns true if any path segment starts with '.' (other than '.').
  static bool isHiddenPath(String path) {
    if (!path.contains('/.') &&
        !path.contains('\\.') &&
        !path.startsWith('.')) {
      return false;
    }
    final segments = path.split(_pathSepRegex);
    return segments.any((s) => s.isNotEmpty && s.startsWith('.') && s != '.');
  }

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
  static String formatViewerTime(DateTime dt) =>
      DateFormat('h:mm a').format(dt);

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
    if (c.contains('vp9')) return 'VP9';
    if (c.contains('vp8')) return 'VP8';
    if (c.contains('mpeg4') || c.contains('mp4v')) return 'MPEG-4';
    if (c.contains('mjpeg')) return 'Motion JPEG';
    if (c.startsWith('video/')) return c.substring(6).toUpperCase();
    return codec.trim().toUpperCase();
  }

  /// Formats raw audio codec / MIME string into human-friendly name.
  static String formatAudioCodec(String codec) {
    final c = codec.trim().toLowerCase();
    if (c.isEmpty) return '';
    if (c.contains('mp4a') || c.contains('aac')) return 'AAC';
    if (c.contains('opus')) return 'Opus';
    if (c.contains('vorbis')) return 'Vorbis';
    if (c.contains('flac')) return 'FLAC';
    if (c.contains('eac3')) return 'E-AC-3';
    if (c.contains('ac3')) return 'AC-3';
    if (c.contains('mpeg') || c.contains('mp3')) return 'MP3';
    if (c.contains('amr')) return 'AMR';
    if (c.contains('raw') || c.contains('pcm')) return 'PCM';
    if (c.startsWith('audio/')) return c.substring(6).toUpperCase();
    return codec.trim().toUpperCase();
  }

  /// Formats bitrate in bits per second (e.g. "12.4 Mbps", "320 kbps").
  static String formatBitrate(int bps) {
    if (bps <= 0) return '';
    if (bps >= 1000000) {
      final mbps = bps / 1000000.0;
      return '${mbps.toStringAsFixed(mbps >= 10 ? 1 : 2)} Mbps';
    }
    if (bps >= 1000) {
      return '${(bps / 1000.0).round()} kbps';
    }
    return '$bps bps';
  }

  /// Formats audio channel count (e.g. 1 -> "Mono", 2 -> "Stereo", 6 -> "5.1").
  static String formatAudioChannels(int channels) {
    return switch (channels) {
      <= 0 => '',
      1 => 'Mono',
      2 => 'Stereo',
      6 => '5.1',
      8 => '7.1',
      _ => '$channels ch',
    };
  }

  /// Formats aperture f-number (e.g. 1.8 -> "f/1.8", 8.0 -> "f/8").
  static String formatAperture(double fNumber) {
    if (fNumber <= 0) return '';
    if (fNumber == fNumber.roundToDouble()) {
      return 'f/${fNumber.toInt()}';
    }
    final formatted = fNumber.toStringAsFixed(1);
    return formatted.endsWith('.0')
        ? 'f/${fNumber.round()}'
        : 'f/$formatted';
  }

  /// Formats shutter speed in seconds (e.g. 0.008 -> "1/125 s", 2.0 -> "2 s").
  static String formatShutterSpeed(double seconds) {
    if (seconds <= 0) return '';
    if (seconds >= 1.0) {
      final str = seconds == seconds.roundToDouble()
          ? '${seconds.toInt()}'
          : seconds.toStringAsFixed(1);
      return '$str s';
    }
    final denom = (1.0 / seconds).round();
    if (denom <= 1) return '${seconds.toStringAsFixed(2)} s';
    return '1/$denom s';
  }

  /// Formats focal length in mm (e.g. "26 mm" or "5.4 mm (26 mm eq.)").
  static String formatFocalLength(double mm, {int? focalLength35mm}) {
    if (mm <= 0) return '';
    final base = mm == mm.roundToDouble()
        ? '${mm.toInt()} mm'
        : '${mm.toStringAsFixed(1)} mm';
    if (focalLength35mm != null &&
        focalLength35mm > 0 &&
        (focalLength35mm - mm).abs() >= 1.0) {
      return '$base ($focalLength35mm mm eq.)';
    }
    return base;
  }

  /// Normalizes Android ColorSpace names into concise labels.
  static String formatColorSpace(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return '';
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('srgb')) return 'sRGB';
    if (lower.contains('display p3') || lower.contains('dci-p3')) {
      return 'Display P3';
    }
    if (lower.contains('adobe rgb')) return 'Adobe RGB';
    if (lower.contains('bt.2020') || lower.contains('bt2020')) return 'BT.2020';
    if (lower.contains('prophoto')) return 'ProPhoto RGB';
    return trimmed;
  }

  /// Derives a clean file format label from MIME type or path extension.
  static String formatFileFormat(String path, {String? mimeType}) {
    final m = mimeType?.trim().toLowerCase() ?? '';
    if (m.isNotEmpty) {
      if (m.contains('photoshop') || m.contains('psd')) return 'PSD';
      if (m == 'image/jpeg' || m == 'image/jpg') return 'JPEG';
      if (m == 'image/png') return 'PNG';
      if (m == 'image/webp') return 'WebP';
      if (m == 'image/gif') return 'GIF';
      if (m == 'image/heif' || m == 'image/heic') return 'HEIC';
      if (m == 'image/avif') return 'AVIF';
      if (m == 'image/bmp') return 'BMP';
      if (m == 'image/tiff') return 'TIFF';
      if (m.contains('dng')) return 'DNG (RAW)';
    }
    final dot = path.lastIndexOf('.');
    if (dot != -1 && dot < path.length - 1) {
      final ext = path.substring(dot + 1).toLowerCase();
      return switch (ext) {
        'jpg' || 'jpeg' => 'JPEG',
        'png' => 'PNG',
        'webp' => 'WebP',
        'gif' => 'GIF',
        'heic' || 'heif' => 'HEIC',
        'avif' => 'AVIF',
        'psd' => 'PSD',
        'dng' => 'DNG (RAW)',
        'mp4' || 'm4v' => 'MP4',
        'mkv' => 'MKV',
        'webm' => 'WebM',
        'mov' => 'MOV',
        'avi' => 'AVI',
        '3gp' => '3GP',
        _ => ext.toUpperCase(),
      };
    }
    return '';
  }

  /// Computes the scroll offset required to ensure an item at [index] in a fixed-column
  /// grid is visible in the viewport. If already fully visible, returns [currentScrollOffset].
  static double calculateGridScrollOffset({
    required int index,
    required int crossAxisCount,
    required double screenWidth,
    required double viewportHeight,
    required double currentScrollOffset,
    required double maxScrollExtent,
    double paddingHorizontal = 6.0,
    double paddingTop = 2.0,
    double spacing = 3.0,
  }) {
    if (crossAxisCount <= 0) return currentScrollOffset;
    final row = index ~/ crossAxisCount;
    final availableWidth =
        screenWidth - paddingHorizontal - ((crossAxisCount - 1) * spacing);
    final tileSize = availableWidth / crossAxisCount;
    final rowHeight = tileSize + spacing;
    final rowTop = paddingTop + (row * rowHeight);
    final rowBottom = rowTop + tileSize;

    final viewportTop = currentScrollOffset;
    final viewportBottom = currentScrollOffset + viewportHeight;

    // Already comfortably visible in viewport? Keep existing offset.
    final effectiveTopThreshold = viewportTop <= 0.0 ? 0.0 : viewportTop + 10.0;
    if (rowTop >= effectiveTopThreshold && rowBottom <= viewportBottom - 10.0) {
      return currentScrollOffset;
    }

    final ideal = rowTop - (viewportHeight - tileSize) / 2.0;
    return ideal.clamp(0.0, maxScrollExtent);
  }
}

/// Computes a clamped focal zoom [Matrix4] from [currentMatrix] to [targetScale],
/// keeping [localFocal] anchored within [viewportSize].
Matrix4 computeClampedFocalZoomMatrix({
  required Matrix4 currentMatrix,
  required Offset localFocal,
  required Size viewportSize,
  required double targetScale,
}) {
  if (targetScale <= 1.05 ||
      viewportSize.width <= 0 ||
      viewportSize.height <= 0) {
    return Matrix4.identity();
  }
  final clampedX = localFocal.dx.clamp(0.0, viewportSize.width);
  final clampedY = localFocal.dy.clamp(0.0, viewportSize.height);
  final rawScale = currentMatrix.getMaxScaleOnAxis();
  final currentScale = rawScale > 0 ? rawScale : 1.0;
  final sceneX = (clampedX - currentMatrix.storage[12]) / currentScale;
  final sceneY = (clampedY - currentMatrix.storage[13]) / currentScale;
  final minTx = -viewportSize.width * (targetScale - 1.0);
  final minTy = -viewportSize.height * (targetScale - 1.0);
  final tx = (clampedX - sceneX * targetScale).clamp(minTx, 0.0);
  final ty = (clampedY - sceneY * targetScale).clamp(minTy, 0.0);
  return Matrix4.translationValues(tx, ty, 0.0)
    ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
}

/// Resolves the focal point in [viewerKey]-local coordinates and its viewport size,
/// falling back to [fallbackLocalPos] and [fallbackSize] if unavailable.
(Offset localFocal, Size viewportSize) resolveViewerFocalAndSize({
  required GlobalKey? viewerKey,
  required Offset fallbackLocalPos,
  required Size fallbackSize,
  Offset? globalPos,
}) {
  final renderObj = viewerKey?.currentContext?.findRenderObject();
  if (renderObj is RenderBox &&
      renderObj.hasSize &&
      renderObj.size.width > 0 &&
      renderObj.size.height > 0) {
    final localFocal = globalPos != null
        ? renderObj.globalToLocal(globalPos)
        : fallbackLocalPos;
    return (localFocal, renderObj.size);
  }
  return (fallbackLocalPos, fallbackSize);
}
