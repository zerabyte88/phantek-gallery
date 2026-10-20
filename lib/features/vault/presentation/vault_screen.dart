import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/vault_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/vault_provider.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/widgets/feedback_pill.dart';
import '../../gallery/presentation/widgets/delete_confirmation_sheet.dart';

class VaultScreen extends ConsumerStatefulWidget {
  const VaultScreen({super.key});

  @override
  ConsumerState<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends ConsumerState<VaultScreen>
    with WidgetsBindingObserver {
  final Set<String> _selected = {};
  bool _selecting = false;
  late final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    super.dispose();
  }

  /// Auto-lock: Automatically exits the vault when the app is backgrounded or screen locked.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  void _startSelect(String id) {
    setState(() {
      _selecting = true;
      _selected.add(id);
    });
  }

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  void _openPreview(BuildContext context, List<VaultItem> items, VaultItem item) {
    final mediaList = items.map((e) => e.toMediaItem()).toList();
    if (item.isVideo) {
      final videos = mediaList.where((e) => e.isVideo).toList();
      final idx = videos.indexWhere((e) => e.id == item.id);
      Navigator.of(context).openVideo(
        videos,
        idx >= 0 ? idx : 0,
      );
    } else {
      final photos = mediaList.where((e) => !e.isVideo).toList();
      final idx = photos.indexWhere((e) => e.id == item.id);
      Navigator.of(context).openImage(
        photos,
        idx >= 0 ? idx : 0,
      );
    }
  }

  Future<void> _restoreSelected(List<VaultItem> all) async {
    final toRestore = all.where((e) => _selected.contains(e.id)).toList();
    if (toRestore.isEmpty) return;

    final count = toRestore.length;
    await ref
        .read(vaultProvider.notifier)
        .restoreBatch(toRestore.map((e) => e.id).toList());
    _clearSelection();

    // Refresh main gallery so restored files reappear instantly
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      showFeedbackPill(
        context,
        message: context.tr.itemRestored(context.tr.itemsCount(count)),
        icon: Icons.restore_rounded,
      );
    }
  }

  Future<void> _deleteSelected(List<VaultItem> all) async {
    final count = _selected.length;
    if (count == 0) return;

    final ok = await showDeleteConfirmationSheet(
      context,
      title: context.tr.deleteFromVaultPermanently,
      contentText: context.tr.deleteFromVaultConfirm,
      isTrash: false,
    );

    if (ok != true || !mounted) return;
    final toDelete = all.where((e) => _selected.contains(e.id)).toList();
    await ref
        .read(vaultProvider.notifier)
        .permanentDeleteBatch(toDelete.map((e) => e.id).toList());
    _clearSelection();

    if (mounted) {
      showFeedbackPill(
        context,
        message: context.tr.delete,
        icon: Icons.delete_outline_rounded,
      );
    }
  }

  Widget _buildSelectAllCheckbox(BuildContext context, int totalCount) {
    final cs = Theme.of(context).colorScheme;
    final bool allSelected = totalCount > 0 && _selected.length == totalCount;
    final bool partialSelected = _selected.isNotEmpty && !allSelected;

    return IconButton(
      tooltip: allSelected ? context.tr.deselectAll : context.tr.selectAll,
      icon: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: (allSelected || partialSelected)
              ? cs.primary
              : Colors.transparent,
          border: Border.all(
            color: (allSelected || partialSelected)
                ? cs.primary
                : cs.onSurface.withValues(alpha: 0.6),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(5),
        ),
        child: allSelected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : partialSelected
                ? const Icon(Icons.remove, size: 16, color: Colors.white)
                : null,
      ),
      onPressed: () {
        final all = ref.read(vaultProvider).value ?? [];
        setState(() {
          if (allSelected) {
            _selected.clear();
          } else {
            _selected.addAll(all.map((e) => e.id));
          }
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final vaultAsync = ref.watch(vaultProvider);
    final settings = ref.watch(settingsNotifierProvider);
    final items = vaultAsync.value ?? [];

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selecting
              ? _buildSelectAllCheckbox(context, items.length)
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          centerTitle: false,
          titleSpacing: _selecting ? 8.0 : 16.0,
          title: _selecting
              ? Text(
                  '${_selected.length} ${context.tr.selected}',
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_rounded, size: 20, color: Color(0xFFFFB74D)),
                    const SizedBox(width: 8),
                    Text(
                      context.tr.lockedVault,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
                    ),
                  ],
                ),
          actions: [
            if (_selecting)
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                tooltip: context.tr.cancel,
                onPressed: _clearSelection,
              )
            else if (items.isNotEmpty)
              IconButton(
                icon: const Icon(Icons.check_box_outlined, size: 22),
                tooltip: context.tr.select,
                onPressed: () => setState(() => _selecting = true),
              ),
          ],
        ),
        body: vaultAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (items) {
            if (items.isEmpty) {
              return const _VaultEmptyState();
            }

            return GridView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: settings.gridColumns,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
                childAspectRatio: 1.0,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final isSelected = _selected.contains(item.id);
                return _VaultGridItem(
                  key: ValueKey(item.id),
                  item: item,
                  isSelected: isSelected,
                  isSelecting: _selecting,
                  onTap: () {
                    if (_selecting) {
                      _toggleSelect(item.id);
                    } else {
                      _openPreview(context, items, item);
                    }
                  },
                  onLongPress: () {
                    if (!_selecting) {
                      _startSelect(item.id);
                    }
                  },
                );
              },
            );
          },
        ),
        bottomNavigationBar: _selecting
            ? Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _BottomActionItem(
                      icon: Icons.restore_rounded,
                      label: context.tr.restoreFromVault,
                      enabled: _selected.isNotEmpty,
                      onTap: _selected.isNotEmpty
                          ? () => _restoreSelected(items)
                          : null,
                    ),
                    _BottomActionItem(
                      icon: Icons.delete_forever_rounded,
                      label: context.tr.deleteFromVaultPermanently,
                      enabled: _selected.isNotEmpty,
                      onTap: _selected.isNotEmpty
                          ? () => _deleteSelected(items)
                          : null,
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

class _BottomActionItem extends StatelessWidget {
  const _BottomActionItem({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = enabled ? cs.onSurface : cs.onSurface.withValues(alpha: 0.38);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: enabled ? FontWeight.w500 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultEmptyState extends StatelessWidget {
  const _VaultEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFFFFB74D).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.lock_outline_rounded,
                size: 64,
                color: Color(0xFFFFB74D),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.tr.vaultEmpty,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.tr.vaultEmptyDesc,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VaultGridItem extends StatelessWidget {
  const _VaultGridItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
  });

  final VaultItem item;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Container(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Hero(
                tag: item.id,
                transitionOnUserGestures: true,
                child: _VaultThumbnail(item: item),
              ),
            ),
            if (item.isVideo)
              Positioned(
                bottom: 6,
                left: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            if (isSelecting && isSelected)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.3),
                    border: Border.all(color: cs.primary, width: 2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            if (isSelecting)
              Positioned(
                top: 6,
                right: 6,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: isSelected ? cs.primary : Colors.black45,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _VaultThumbnail extends StatelessWidget {
  const _VaultThumbnail({required this.item});
  final VaultItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final mem = ThumbnailService.instance.getMemoryThumbnail(item.id);
    if (mem != null) {
      return Image.memory(
        mem,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
      );
    }

    final diskFile = ThumbnailService.instance.getCachedFile(item.id);
    if (diskFile != null) {
      return Image.file(
        diskFile,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
      );
    }

    return FutureBuilder<Uint8List?>(
      future: ThumbnailService.instance.getThumbnail(
        item.id,
        filePath: item.vaultPath,
        isVideo: item.isVideo,
      ),
      builder: (_, snap) {
        if (snap.data != null) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          );
        }
        if (!item.isVideo) {
          final file = File(item.vaultPath);
          return Image.file(
            file,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
          );
        }
        return _buildPlaceholder(cs);
      },
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Center(
        child: Icon(
          item.isVideo ? Icons.videocam_outlined : Icons.photo_outlined,
          color: cs.onSurfaceVariant.withValues(alpha: 0.3),
          size: 28,
        ),
      ),
    );
  }
}
