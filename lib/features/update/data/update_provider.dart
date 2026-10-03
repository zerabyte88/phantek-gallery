import 'dart:io';
import 'package:flutter/material.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/providers/settings_provider.dart';
import 'update_service.dart';

/// Fires once on app launch if autoCheckUpdate is enabled.
final autoCheckUpdateTriggerProvider = Provider<bool>((ref) {
  final settings = ref.watch(settingsNotifierProvider);
  return settings.autoCheckUpdate;
});

/// Update flow state.
sealed class UpdateState {
  const UpdateState();
}
final class UpdateIdle  extends UpdateState { const UpdateIdle(); }
final class UpdateChecking extends UpdateState { const UpdateChecking(); }
final class UpdateFound extends UpdateState {
  const UpdateFound(this.info);
  final UpdateInfo info;
}
final class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.progress);
  final double progress; // 0.0 – 1.0
}
final class UpdateError extends UpdateState {
  const UpdateError(this.message);
  final String message;
}
final class UpdateNotifier extends AsyncNotifier<UpdateState> {
  @override
  Future<UpdateState> build() async => const UpdateIdle();

  /// [silent] = true: only show dialog if update is found.
  /// [silent] = false: show snackbar even when already up-to-date.
  Future<void> checkForUpdate({required bool silent}) async {
    state = const AsyncData(UpdateChecking());
    final result = await UpdateService.instance.checkForUpdate();

    switch (result) {
      case UpdateAvailable(:final info):
        state = AsyncData(UpdateFound(info));

      case AlreadyUpToDate():
        state = const AsyncData(UpdateIdle());
        if (!silent) {
          // Notify via the error field so UI can show a snackbar.
          state = const AsyncError('already_up_to_date', StackTrace.empty);
          // Reset after brief delay.
          await Future<void>.delayed(const Duration(seconds: 2));
          state = const AsyncData(UpdateIdle());
        }

      case UpdateCheckFailed(:final reason):
        state = const AsyncData(UpdateIdle());
        if (!silent) {
          state = AsyncError(reason, StackTrace.empty);
          await Future<void>.delayed(const Duration(seconds: 3));
          state = const AsyncData(UpdateIdle());
        }
    }
  }

  Future<File?> downloadAndInstall(UpdateInfo info, BuildContext context) async {
    state = const AsyncData(UpdateDownloading(0));
    try {
      final apkFile = await UpdateService.instance.downloadApk(
        info,
        onProgress: (p) {
          state = AsyncData(UpdateDownloading(p));
        },
      );
      state = const AsyncData(UpdateIdle());
      return apkFile;
    } catch (e) {
      state = AsyncData(UpdateError(e.toString()));
      return null;
    }
  }

  /// Call on app resume to delete leftover APK files from prior updates.
  Future<void> cleanupOldApks() =>
      UpdateService.instance.cleanupAllApks();
}

final updateNotifierProvider =
    AsyncNotifierProvider<UpdateNotifier, UpdateState>(
        UpdateNotifier.new);
