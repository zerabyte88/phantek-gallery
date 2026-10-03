import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// GitHub repository coordinates.
const _kGitHubOwner = 'zerabyte88';
const _kGitHubRepo  = 'phantek-gallery';
const _kApiUrl =
    'https://api.github.com/repos/$_kGitHubOwner/$_kGitHubRepo/releases/latest';

/// Describes an available update fetched from GitHub Releases.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.versionCode,
    required this.apkUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });

  final String version;       // e.g. "1.2.0"
  final int versionCode;      // e.g. 5
  final String apkUrl;        // direct APK download URL
  final String releaseNotes;  // body of the release
  final DateTime publishedAt;
}

/// Result of a version check.
sealed class UpdateResult {
  const UpdateResult();
}

final class UpdateAvailable extends UpdateResult {
  const UpdateAvailable(this.info);
  final UpdateInfo info;
}

final class AlreadyUpToDate extends UpdateResult {
  const AlreadyUpToDate();
}

final class UpdateCheckFailed extends UpdateResult {
  const UpdateCheckFailed(this.reason);
  final String reason;
}

/// Handles checking GitHub Releases and downloading the APK.
///
/// Internet access is used ONLY for GitHub Releases – no telemetry.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  // ── Check ─────────────────────────────────────────────────────────────

  Future<UpdateResult> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentCode = int.tryParse(info.buildNumber) ?? 0;
      final currentVersion = info.version;

      final resp = await http
          .get(Uri.parse(_kApiUrl), headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        return UpdateCheckFailed('HTTP ${resp.statusCode}');
      }

      final json = jsonDecode(resp.body) as Map<String, dynamic>;
      final rawTag    = json['tag_name'] as String? ?? '';
      final cleanTag  = rawTag.startsWith('v') ? rawTag.substring(1) : rawTag;
      final body      = json['body'] as String? ?? '';
      final published = DateTime.tryParse(
              json['published_at'] as String? ?? '') ??
          DateTime.now();

      // Look for .apk assets in release assets and pick the matching ABI variant
      final assets =
          (json['assets'] as List? ?? []).cast<Map<String, dynamic>>();
      final apkAssets = assets
          .where((a) => (a['name'] as String? ?? '').endsWith('.apk'))
          .toList();

      final apkAsset = selectBestApkAsset(apkAssets);
      final apkUrl = apkAsset['browser_download_url'] as String? ?? '';
      if (apkUrl.isEmpty) {
        return const UpdateCheckFailed('No compatible APK asset found in release');
      }

      // Supports both "v1.2.0+5" and "v1.2.0" tag formats
      final plusIdx = cleanTag.indexOf('+');
      final remoteVersion = plusIdx != -1 ? cleanTag.substring(0, plusIdx) : cleanTag;
      final remoteCode = plusIdx != -1
          ? int.tryParse(cleanTag.substring(plusIdx + 1)) ?? 0
          : 0;

      final isNewer = _isNewer(
        remoteVer: remoteVersion,
        remoteCode: remoteCode,
        localVer: currentVersion,
        localCode: currentCode,
      );

      if (!isNewer) return const AlreadyUpToDate();

      return UpdateAvailable(UpdateInfo(
        version: remoteVersion,
        versionCode: remoteCode,
        apkUrl: apkUrl,
        releaseNotes: body,
        publishedAt: published,
      ));
    } on SocketException {
      return const UpdateCheckFailed('No internet connection');
    } catch (e) {
      return UpdateCheckFailed(e.toString());
    }
  }

  static bool _isNewer({
    required String remoteVer,
    required int remoteCode,
    required String localVer,
    required int localCode,
  }) {
    // If build numbers are present, compare them first
    if (remoteCode > 0 && localCode > 0) {
      return remoteCode > localCode;
    }
    // Fallback: SemVer comparison (e.g., 1.0.1 > 1.0.0)
    final rParts = remoteVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final lParts = localVer.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final maxLen = rParts.length > lParts.length ? rParts.length : lParts.length;
    for (var i = 0; i < maxLen; i++) {
      final r = i < rParts.length ? rParts[i] : 0;
      final l = i < lParts.length ? lParts[i] : 0;
      if (r > l) return true;
      if (r < l) return false;
    }
    return false;
  }

  /// Selects the best APK asset matching the device's CPU architecture (e.g. arm64-v8a vs armeabi-v7a).
  static Map<String, dynamic> selectBestApkAsset(
    List<Map<String, dynamic>> rawApkAssets, [
    Abi? overrideAbi,
  ]) {
    final apkAssets =
        rawApkAssets.map((e) => Map<String, dynamic>.from(e)).toList();
    if (apkAssets.isEmpty) return <String, dynamic>{};
    if (apkAssets.length == 1) return apkAssets.first;

    final currentAbi = overrideAbi ?? Abi.current();
    final is64Bit = currentAbi == Abi.androidArm64 ||
        currentAbi == Abi.androidX64 ||
        currentAbi == Abi.androidRiscv64;
    final is32Bit =
        currentAbi == Abi.androidArm || currentAbi == Abi.androidIA32;

    if (is64Bit) {
      // 1. Prefer 64-bit APK (arm64-v8a / arm64 / v8a)
      final arm64 = apkAssets.firstWhere(
        (a) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          return name.contains('arm64') || name.contains('v8a');
        },
        orElse: () => <String, dynamic>{},
      );
      if (arm64.isNotEmpty) return arm64;
    } else if (is32Bit) {
      // 1. Prefer 32-bit APK (armeabi-v7a / v7a / arm32)
      final arm32 = apkAssets.firstWhere(
        (a) {
          final name = (a['name'] as String? ?? '').toLowerCase();
          return name.contains('armeabi') ||
              name.contains('v7a') ||
              (name.contains('arm') && !name.contains('arm64'));
        },
        orElse: () => <String, dynamic>{},
      );
      if (arm32.isNotEmpty) return arm32;
    }

    // 2. Fallback to universal APK (not tagged with specific ABI)
    final universal = apkAssets.firstWhere(
      (a) {
        final name = (a['name'] as String? ?? '').toLowerCase();
        return !name.contains('arm') && !name.contains('x86');
      },
      orElse: () => <String, dynamic>{},
    );
    if (universal.isNotEmpty) return universal;

    // 3. Fallback to first available APK
    return apkAssets.first;
  }

  // ── Download ──────────────────────────────────────────────────────────

  /// Downloads the APK to the public Downloads folder.
  /// Reports progress [0.0 – 1.0] via [onProgress].
  ///
  /// SAFETY: only creates/deletes ONE specific file path – never touches
  /// any other file in Downloads.
  Future<File> downloadApk(
    UpdateInfo info, {
    required void Function(double) onProgress,
  }) async {
    final apkFile = await _apkFile(info.version);

    // Clean up a stale partial download.
    if (await apkFile.exists()) await apkFile.delete();

    final client = http.Client();
    try {
      final request  = http.Request('GET', Uri.parse(info.apkUrl));
      final response = await client.send(request);
      final total    = response.contentLength ?? 0;
      var received   = 0;

      final sink = apkFile.openWrite();
      await response.stream.listen(
        (chunk) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress(received / total);
        },
        onDone: () async => sink.close(),
        cancelOnError: true,
      ).asFuture<void>();
      await sink.close();
    } catch (e) {
      // Clean up incomplete file on error.
      if (await apkFile.exists()) await apkFile.delete();
      client.close();
      rethrow;
    }
    client.close();
    return apkFile;
  }

  // ── Cleanup ───────────────────────────────────────────────────────────

  /// Deletes any previously downloaded APK for the given version.
  ///
  /// PROTEKSI: ONLY deletes the exact path returned by [_apkFile].
  /// Never deletes directories or other user files.
  Future<void> cleanupApk(String version) async {
    final apkFile = await _apkFile(version);
    if (await apkFile.exists()) await apkFile.delete();
  }

  /// Scans the Downloads folder and removes any leftover Phantek Gallery APKs.
  /// Matches only files starting with "Phantek_Gallery_v" and ending with ".apk".
  Future<void> cleanupAllApks() async {
    final dir = await _downloadsDir();
    if (!await dir.exists()) return;
    final apks = dir
        .listSync()
        .whereType<File>()
        .where((f) {
          final name = f.uri.pathSegments.last;
          return name.startsWith('Phantek_Gallery_v') && name.endsWith('.apk');
        });
    for (final apk in apks) {
      // Extra guard: only delete if the path starts with our expected dir.
      if (apk.path.startsWith(dir.path)) {
        await apk.delete();
      }
    }
  }

  // ── Path helpers ──────────────────────────────────────────────────────

  Future<File> _apkFile(String version) async {
    final dir = await _downloadsDir();
    await dir.create(recursive: true);
    return File('${dir.path}/Phantek_Gallery_v$version.apk');
  }

  Future<Directory> _downloadsDir() async {
    // Android public Downloads directory.
    const downloadsPath = '/storage/emulated/0/Download';
    final d = Directory(downloadsPath);
    if (await d.exists()) return d;
    // Fallback to app-specific external dir (no extra permissions needed).
    final ext = await getExternalStorageDirectory();
    return Directory(
        '${ext?.path ?? (await _appDocDir()).path}/downloads');
  }

  Future<Directory> _appDocDir() async {
    // ignore: implementation_imports
    final d = await getApplicationDocumentsDirectory();
    return d;
  }
}
