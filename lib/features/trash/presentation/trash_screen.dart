import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/trash_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/trash_provider.dart';
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
    for (final item in toRestore) {
      await ref.read(trashProvider.notifier).restore(item.id);
    }
    _clearSelection();
    ref.read(mediaListProvider.notifier).restoreItems(toRestore.map((e) => e.id));
    ref.read(mediaListProvider.notifier).refresh();
  }

  Future<void> _deleteSelected(List<TrashItem> all) async {
    final count = _selected.length;
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
                icon: const Icon(Icons.restore),
                tooltip: 'Restore',
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
            ] else
              IconButton(
                icon: const Icon(Icons.delete_sweep),
                tooltip: 'Empty trash',
                onPressed:
                    trashAsync.value?.isEmpty ?? true ? null : _emptyTrash,
              ),
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
                    Text('Trash is empty'),
                  ],
                ),
              );
            }
            return ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final item = items[i];
                final isSelected = _selected.contains(item.id);
                return ListTile(
                  leading: _TrashItemIcon(item: item),
                  title: Text(item.name,
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    'Deleted ${MediaUtils.formatDate(item.deletedDate)}'
                    '${item.size != null ? '  ${MediaUtils.formatSize(item.size!)}' : ''}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: isSelected,
                  selectedTileColor: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.4),
                  trailing: _selecting
                      ? Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelect(item.id),
                        )
                      : null,
                  onTap: () {
                    if (_selecting) {
                      _toggleSelect(item.id);
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
      ),
    );
  }
}

class _TrashItemIcon extends StatelessWidget {
  const _TrashItemIcon({required this.item});
  final TrashItem item;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      backgroundColor:
          Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Icon(
        item.isVideo
            ? Icons.videocam_outlined
            : Icons.image_outlined,
        size: 22,
      ),
    );
  }
}
