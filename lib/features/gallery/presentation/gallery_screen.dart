import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../app/router.dart';
import 'widgets/filter_sort_bar.dart';
import 'widgets/media_grid_item.dart';

class GalleryScreen extends ConsumerStatefulWidget {
  const GalleryScreen({super.key});

  @override
  ConsumerState<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends ConsumerState<GalleryScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  // ── Permission + initial scan ──────────────────────────────────────────

  Future<void> _bootstrap() async {
    final granted =
        await PermissionService.instance.requestMediaPermissions();
    if (!mounted) return;
    if (granted) {
      ref.read(mediaListProvider.notifier).refresh();
    }
  }

  // ── Selection helpers ──────────────────────────────────────────────────

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

  // ── Delete selected ────────────────────────────────────────────────────

  Future<void> _deleteSelected(List<MediaItem> allItems) async {
    final settings = ref.read(settingsNotifierProvider);
    final toDelete =
        allItems.where((e) => _selected.contains(e.id)).toList();

    final confirm = await _confirmDelete(toDelete.length);
    if (!confirm || !mounted) return;

    for (final item in toDelete) {
      if (settings.enableTrash) {
        await ref
            .read(trashProvider.notifier)
            .moveToTrash(id: item.id, path: item.path, isVideo: item.isVideo);
      } else {
        // Direct permanent delete.
        try {
          final f = File(item.path);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    _clearSelection();
    if (mounted) {
      ref.read(mediaListProvider.notifier).refresh();
    }
  }

  Future<bool> _confirmDelete(int count) async {
    final settings = ref.read(settingsNotifierProvider);
    final label = settings.enableTrash ? 'Move to Trash' : 'Delete Permanently';
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('$label ($count item${count == 1 ? '' : 's'})'),
        content: settings.enableTrash
            ? const Text('Selected items will be moved to trash.')
            : const Text(
                'This action cannot be undone. Delete permanently?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(label)),
        ],
      ),
    );
    return result ?? false;
  }

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mediaAsync = ref.watch(filteredMediaProvider);
    final settings   = ref.watch(settingsNotifierProvider);

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: _selecting
              ? Text('${_selected.length} selected')
              : const Text('Phantek Gallery'),
          actions: [
            if (_selecting) ...[
              IconButton(
                icon: const Icon(Icons.select_all),
                tooltip: 'Select all',
                onPressed: () {
                  final all = mediaAsync.value ?? [];
                  setState(() {
                    _selected.addAll(all.map((e) => e.id));
                  });
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete selected',
                onPressed: () =>
                    _deleteSelected(mediaAsync.value ?? []),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              ),
            ] else ...[
              IconButton(
                icon: const Icon(Icons.delete_sweep_outlined),
                tooltip: 'Trash',
                onPressed: () =>
                    Navigator.of(context).openTrash(),
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () =>
                    Navigator.of(context).openSettings(),
              ),
            ],
          ],
        ),
        body: Column(
          children: [
            const FilterSortBar(),
            const Divider(height: 1),
            Expanded(
              child: mediaAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => _ErrorState(error: e, onRetry: _bootstrap),
                data: (items) {
                  if (items.isEmpty) {
                    return _EmptyState(onRefresh: _bootstrap);
                  }
                  return RefreshIndicator(
                    onRefresh: () =>
                        ref.read(mediaListProvider.notifier).refresh(),
                    child: GridView.builder(
                      padding: const EdgeInsets.all(2),
                      gridDelegate:
                          SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: settings.gridColumns,
                        crossAxisSpacing: 2,
                        mainAxisSpacing: 2,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        return MediaGridItem(
                          key: ValueKey(item.id),
                          item: item,
                          isSelected: _selected.contains(item.id),
                          isSelecting: _selecting,
                          showBadges: settings.showBadges,
                          onTap: () {
                            if (_selecting) {
                              _toggleSelect(item.id);
                              return;
                            }
                            if (item.isVideo) {
                              Navigator.of(context).openVideo(item);
                            } else {
                              // Pass only photo items for swipe navigation.
                              final photos = items
                                  .where((e) => !e.isVideo)
                                  .toList();
                              final idx = photos.indexOf(item);
                              Navigator.of(context)
                                  .openImage(photos, idx);
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
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.photo_library_outlined, size: 80,
              color: Colors.white38),
          const SizedBox(height: 16),
          const Text('No media found',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          const Text('Grant storage permission or add photos/videos.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 60, color: Colors.redAccent),
          const SizedBox(height: 12),
          const Text('Could not load media'),
          const SizedBox(height: 8),
          Text('$error',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
