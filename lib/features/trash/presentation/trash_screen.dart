import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';
import '../../../core/models/trash_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/thumbnail_service.dart';

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
      } else {
        _selected.add(id);
      }
    });
  }

  void _startSelect(String id) =>
      setState(() { _selecting = true; _selected.add(id); });

  void _clearSelection() =>
      setState(() { _selected.clear(); _selecting = false; });

  void _openPreview(BuildContext context, List<TrashItem> items, TrashItem item) {
    if (item.isVideo) {
      final videos = items.where((e) => e.isVideo).toList();
      final idx = videos.indexOf(item);
      Navigator.of(context).openVideo(
        videos.map((e) => e.toMediaItem()).toList(),
        idx >= 0 ? idx : 0,
        isTrash: true,
      );
    } else {
      final photos = items.where((e) => !e.isVideo).toList();
      final idx = photos.indexOf(item);
      Navigator.of(context).openImage(
        photos.map((e) => e.toMediaItem()).toList(),
        idx >= 0 ? idx : 0,
        isTrash: true,
      );
    }
  }

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
        SnackBar(content: Text('$count item${count == 1 ? '' : 's'} restored')),
      );
    }
  }

  Future<void> _deleteSelected(List<TrashItem> all) async {
    final count = _selected.length;
    if (count == 0) return;
    final allSelected = _selected.length == all.length;
    final title = allSelected
        ? 'Permanently delete all items?'
        : (count == 1 ? 'Permanently delete 1 item?' : 'Permanently delete $count items?');

    final ok = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFF03D3D),
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                    elevation: 0,
                  ),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text(
                    'Permanently delete',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: TextButton(
                  style: TextButton.styleFrom(
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      color: cs.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (ok != true || !mounted) return;
    final toDelete = all.where((e) => _selected.contains(e.id)).toList();
    for (final item in toDelete) {
      await ref.read(trashProvider.notifier).permanentDelete(item.id);
    }
    _clearSelection();
  }

  Widget _buildSelectAllCheckbox(BuildContext context, int totalCount) {
    final cs = Theme.of(context).colorScheme;
    final bool allSelected = totalCount > 0 && _selected.length == totalCount;
    final bool partialSelected = _selected.isNotEmpty && !allSelected;

    return IconButton(
      tooltip: allSelected ? 'Deselect all' : 'Select all',
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
        final all = ref.read(trashProvider).value ?? [];
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
    final trashAsync = ref.watch(trashProvider);
    final settings = ref.watch(settingsNotifierProvider);

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _clearSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _selecting
              ? _buildSelectAllCheckbox(context, trashAsync.value?.length ?? 0)
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                  onPressed: () => Navigator.of(context).pop(),
                ),
          centerTitle: _selecting,
          title: Text(
            _selecting
                ? (_selected.isEmpty ? 'Select items' : '${_selected.length} selected')
                : 'Recently deleted',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          actions: [
            if (_selecting)
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                tooltip: 'Cancel',
                onPressed: _clearSelection,
              )
            else if (trashAsync.value?.isNotEmpty ?? false)
              IconButton(
                icon: const Icon(Icons.check_box_outlined, size: 22),
                tooltip: 'Select',
                onPressed: () => setState(() => _selecting = true),
              ),
          ],
        ),
        body: trashAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (items) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    'Deleted content is kept for 30 days before permanent deletion.',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const _TrashEmptyState()
                      : GridView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: settings.gridColumns,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                            childAspectRatio: 0.82,
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
                                  _openPreview(context, items, item);
                                }
                              },
                              onOpenPreview: () => _openPreview(context, items, item),
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
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: _selecting
            ? Container(
                height: 70,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _BottomActionItem(
                      icon: Icons.restore_rounded,
                      label: 'Restore',
                      enabled: _selected.isNotEmpty,
                      onTap: _selected.isNotEmpty
                          ? () => _restoreSelected(trashAsync.value ?? [])
                          : null,
                    ),
                    _BottomActionItem(
                      icon: Icons.delete_outline_rounded,
                      label: 'Delete',
                      enabled: _selected.isNotEmpty,
                      onTap: _selected.isNotEmpty
                          ? () => _deleteSelected(trashAsync.value ?? [])
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
    final color = enabled
        ? cs.onSurface
        : cs.onSurface.withValues(alpha: 0.38);

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

class _TrashEmptyState extends StatelessWidget {
  const _TrashEmptyState();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: cs.outlineVariant.withValues(alpha: 0.35),
                width: 1.5,
              ),
            ),
            child: Icon(
              Icons.image_outlined,
              size: 38,
              color: cs.onSurfaceVariant.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'No recently deleted content',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
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
    required this.onOpenPreview,
    required this.onLongPress,
  });

  final TrashItem item;
  final bool isSelected;
  final bool isSelecting;
  final VoidCallback onTap;
  final VoidCallback onOpenPreview;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final daysRemaining =
        (30 - DateTime.now().difference(item.deletedDate).inDays).clamp(0, 30);

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // Thumbnail image or video placeholder
                  Container(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    child: _TrashThumbnail(item: item),
                  ),

                  // Video duration / play icon badge (bottom-left)
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
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),

                  // Multi-selection tint overlay
                  if (isSelecting && isSelected)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.primary.withValues(alpha: 0.3),
                          border: Border.all(color: cs.primary, width: 2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),

                  // Multi-selection checkmark indicator (top-right)
                  if (isSelecting)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: isSelected ? cs.primary : Colors.black45,
                          border: Border.all(
                            color: isSelected ? cs.primary : Colors.white70,
                            width: 1.8,
                          ),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                    ),

                  // Expand/Fullscreen button (bottom-right)
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: onOpenPreview,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Icon(
                          Icons.open_in_full_rounded,
                          size: 13,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 2),
            child: Text(
              daysRemaining == 1 ? '1 day' : '$daysRemaining days',
              style: TextStyle(
                fontSize: 12,
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w400,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrashThumbnail extends StatelessWidget {
  const _TrashThumbnail({required this.item});
  final TrashItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final file = File(item.trashPath);

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
        if (item.isVideo) {
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
        }
        return Image.file(
          file,
          cacheWidth: 360,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => Container(
            color: cs.surfaceContainerHighest,
            child: Center(
              child: Icon(
                Icons.broken_image_outlined,
                size: 26,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        );
      },
    );
  }
}
