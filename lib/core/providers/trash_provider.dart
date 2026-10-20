import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../enums/trash_cleanup_interval.dart';
import '../models/trash_item.dart';
import '../services/trash_service.dart';

import 'settings_provider.dart';

final trashServiceProvider = Provider<TrashService>(
  (_) => TrashService(),
);

class TrashNotifier extends AsyncNotifier<List<TrashItem>> {
  @override
  Future<List<TrashItem>> build() {
    final maxDays = ref.watch(settingsNotifierProvider).autoTrashCleanup.inDays;
    return ref.read(trashServiceProvider).getItems(maxDays: maxDays);
  }

  Future<void> moveToTrash({
    required String id,
    required String path,
    required bool isVideo,
  }) async {
    await ref.read(trashServiceProvider).moveToTrash(
          id: id,
          sourcePath: path,
          isVideo: isVideo,
        );
    await _reload();
  }

  Future<void> restore(String trashItemId) async {
    await ref.read(trashServiceProvider).restore(trashItemId);
    await _reload();
  }

  Future<void> permanentDelete(String trashItemId) async {
    await ref.read(trashServiceProvider).permanentDelete(trashItemId);
    await _reload();
  }

  Future<void> emptyTrash() async {
    await ref.read(trashServiceProvider).emptyTrash();
    state = const AsyncData([]);
  }

  Future<void> _reload() async {
    final maxDays = ref.read(settingsNotifierProvider).autoTrashCleanup.inDays;
    state = AsyncData(
        await ref.read(trashServiceProvider).getItems(maxDays: maxDays));
  }
}

final trashProvider =
    AsyncNotifierProvider<TrashNotifier, List<TrashItem>>(TrashNotifier.new);
