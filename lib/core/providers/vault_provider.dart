import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/media_item.dart';
import '../models/vault_item.dart';
import '../services/vault_service.dart';

final vaultServiceProvider = Provider<VaultService>(
  (_) => VaultService.instance,
);

class VaultNotifier extends AsyncNotifier<List<VaultItem>> {
  @override
  Future<List<VaultItem>> build() {
    return ref.read(vaultServiceProvider).getItems();
  }

  Future<void> moveToVault(MediaItem item) async {
    await ref.read(vaultServiceProvider).moveToVault(item);
    await _reload();
  }

  Future<void> moveToVaultBatch(List<MediaItem> items) async {
    await ref.read(vaultServiceProvider).moveToVaultBatch(items);
    await _reload();
  }

  Future<void> restore(String vaultItemId) async {
    await ref.read(vaultServiceProvider).restore(vaultItemId);
    await _reload();
  }

  Future<void> restoreBatch(List<String> vaultItemIds) async {
    await ref.read(vaultServiceProvider).restoreBatch(vaultItemIds);
    await _reload();
  }

  Future<void> permanentDelete(String vaultItemId) async {
    await ref.read(vaultServiceProvider).permanentDelete(vaultItemId);
    await _reload();
  }

  Future<void> permanentDeleteBatch(List<String> vaultItemIds) async {
    await ref.read(vaultServiceProvider).permanentDeleteBatch(vaultItemIds);
    await _reload();
  }

  Future<void> _reload() async {
    state = AsyncData(await ref.read(vaultServiceProvider).getItems());
  }
}

final vaultProvider =
    AsyncNotifierProvider<VaultNotifier, List<VaultItem>>(VaultNotifier.new);
