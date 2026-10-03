import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/trash_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/utils/media_utils.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _startSelect(String id) =>
      setState(() { _selecting = true; _selected.add(id); });

  void _clearSelection() =>
      setState(() { _selected.clear(); _selecting = false; });

  Future<void> _restoreSelected(List<TrashItem> all) async {
    final toRestore = all.where((e) => _selected.contains(e.id)).toList();
    if (toRestore.isEmpty) return;

    for (final item in toRestore) {
      await ref.read(trashProvider.notifier).restore(item.id);
    }
    final count = toRestore.length;
    _clearSelection();
    ref.read(mediaListProvider.notifier).restoreItems(toRestore.map((e) => e.id));
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count item${count == 1 ? '' : 's'} restored \u2705')),
      );
    }
  }

  Future<void> _restoreSingleItem(TrashItem item) async {
    await ref.read(trashProvider.notifier).restore(item.id);
    ref.read(mediaListProvider.notifier).restoreItems([item.id]);
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${item.name}" restored \u2705')),
      );
    }
  }

  Future<void> _restoreAll(List<TrashItem> all) async {
    if (all.isEmpty) return;
    final count = all.length;
    final itemText = count == 1 ? '1 item' : '$count items';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Restore All Files?'),
        content: Text('All $itemText will be restored to their original folders.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.restore),
            onPressed: () => Navigator.pop(context, true),
            label: const Text('Restore All'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    for (final item in all) {
      await ref.read(trashProvider.notifier).restore(item.id);
    }
    ref.read(mediaListProvider.notifier).restoreItems(all.map((e) => e.id));
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('All $itemText restored \u2705')),
      );
    }
  }

  Future<void> _deleteSelected(List<TrashItem> all) async {
    final count = _selected.length;
    if (count == 0) return;
    final itemText = count == 1 ? '1 item' : '$count items';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Permanently?'),
        content: Text(
            '$itemText will be permanently deleted. This action cannot be undone.'),
        actionsOverflowButtonSpacing: 8,
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final toDelete = all.where((e) => _selected.contains(e.id)).toList();
    for (final item in toDelete) {
      await ref.read(trashProvider.notifier).permanentDelete(item.id);
    }
    _clearSelection();
  }

  Future<void> _deleteSingleItem(TrashItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Permanently?'),
        content: Text('"${item.name}" will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(trashProvider.notifier).permanentDelete(item.id);
  }

  Future<void> _emptyTrash() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Empty Trash'),
        content: const Text(
            'All items in trash will be permanently deleted. This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Empty Trash')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(trashProvider.notifier).emptyTrash();
  }

  void _showItemActionSheet(BuildContext context, TrashItem item) {
    final cs = Theme.of(context).colorScheme;
    final file = File(item.trashPath);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                // Preview thumbnail & details
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: SizedBox(
                        width: 72,
                        height: 72,
                        child: item.isVideo
                            ? _VideoTrashThumbnail(item: item)
                            : Image.file(
                                file,
                                cacheWidth: 240,
                                cacheHeight: 240,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: cs.surfaceContainerHighest,
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Deleted ${MediaUtils.formatDate(item.deletedDate)}'
                            '${item.size != null ? ' \u2022 ${MediaUtils.formatSize(item.size!)}' : ''}',
                            style: TextStyle(
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.isVideo ? 'Video' : 'Photo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 16),
                // Action Buttons: Delete and Restore
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.delete_forever),
                        label: const Text('Delete'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _deleteSingleItem(item);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.restore),
                        label: const Text('Restore'),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _restoreSingleItem(item);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final trashAsync = ref.watch(trashProvider);

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _selecting
              ? Text('${_selected.length} selected')
              : const Text('Trash'),
          actions: [
            if (_selecting) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select all',
                onPressed: () {
                  final all = trashAsync.value ?? [];
                  setState(() {
                    if (_selected.length == all.length) {
                      _selected.clear();
                      _selecting = false;
                    } else {
                      _selected.addAll(all.map((e) => e.id));
                    }
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.restore),
                tooltip: 'Restore selected',
                onPressed: () =>
                    _restoreSelected(trashAsync.value ?? []),
              ),
              IconButton(
                icon: const Icon(Icons.delete_forever),
                tooltip: 'Delete permanently',
                onPressed: () =>
                    _deleteSelected(trashAsync.value ?? []),
              ),
              IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _clearSelection),
            ] else if (trashAsync.value?.isNotEmpty ?? false) ...[
              TextButton.icon(
                icon: const Icon(Icons.restore, size: 18),
                label: const Text('Restore All'),
                onPressed: () => _restoreAll(trashAsync.value!),
              ),
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Empty trash',
                onPressed: _emptyTrash,
              ),
            ],
          ],
        ),
        body: trashAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (items) {
            if (items.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.delete_outline,
                        size: 80, color: Colors.white24),
                    SizedBox(height: 16),
                    Text('Trash is empty',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                    SizedBox(height: 4),
                    Text('Deleted photos and videos will appear here',
                        style: TextStyle(fontSize: 13, color: Colors.grey)),
                  ],
                ),
              );
            }
            return GridView.builder(
              padding: const EdgeInsets.all(2),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 2,
                mainAxisSpacing: 2,
                childAspectRatio: 1.0,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final item = items[i];
                final isSelected = _selected.contains(item.id);
                return _TrashGridItem(
                  key: ValueKey(item.id),
                  item: item,
                  isSelected: isSelected,
                  isSelecting: _selecting,
                  onTap: () {
                    if (_selecting) {
                      _toggleSelect(item.id);
                    } else {
                      _showItemActionSheet(context, item);
                    }
                  },
                  onLongPress: () {
                    if (!_selecting) {
                      _startSelect(item.id);
                    } else {
                      _toggleSelect(item.id);
                    }
                  },
                );
              },
            );
          },
        ),
        bottomNavigationBar: _selecting && _selected.isNotEmpty
            ? Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.delete_forever),
                        label: Text('Delete (${_selected.length})'),
                        onPressed: () => _deleteSelected(trashAsync.value ?? []),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        icon: const Icon(Icons.restore),
                        label: Text('Restore (${_selected.length})'),
                        onPressed: () => _restoreSelected(trashAsync.value ?? []),
                      ),
                    ),
                  ],
                ),
              )
            : null,
      ),
    );
  }
}

class _TrashGridItem extends StatelessWidget {
  const _TrashGridItem({
    super.key,
    required this.item,
    required this.isSelected,
    required this.isSelecting,
    required this.onTap,
    required this.onLongPress,
  });

  final TrashItem item;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final file = File(item.trashPath);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Thumbnail image or video placeholder
          Container(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
            child: item.isVideo
                ? _VideoTrashThumbnail(item: item)
                : Image.file(
                    file,
                    cacheWidth: 240,
                    cacheHeight: 240,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => Center(
                      child: Icon(
                        Icons.broken_image,
                        size: 26,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
          ),

          // Video duration / play icon badge
          if (item.isVideo)
            Positioned(
              bottom: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(
                  Icons.play_arrow,
                  size: 13,
                  color: Colors.white,
                ),
              ),
            ),

          // Multi-selection tint overlay
          if (isSelecting)
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary.withValues(alpha: 0.35)
                      : Colors.transparent,
                  border: isSelected
                      ? Border.all(color: cs.primary, width: 2.5)
                      : null,
                ),
              ),
            ),

          // Multi-selection checkmark indicator
          if (isSelecting)
            Positioned(
              top: 4,
              left: 4,
              child: CircleAvatar(
                radius: 10,
                backgroundColor: isSelected ? cs.primary : Colors.black45,
                child: isSelected
                    ? const Icon(Icons.check, size: 13, color: Colors.white)
                    : null,
              ),
            ),
        ],
      ),
    );
  }
}

class _VideoTrashThumbnail extends StatelessWidget {
  const _VideoTrashThumbnail({required this.item});
  final TrashItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<Uint8List?>(
      future: ThumbnailService.instance.getThumbnail(item.id),
      builder: (_, snap) {
        if (snap.data != null) {
          return Image.memory(
            snap.data!,
            fit: BoxFit.cover,
            gaplessPlayback: true,
          );
        }
        return Container(
          color: cs.surfaceContainerHighest,
          child: Center(
            child: Icon(
              Icons.videocam_outlined,
              size: 28,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
        );
      },
    );
  }
}
