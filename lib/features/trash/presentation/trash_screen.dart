import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../app/router.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/trash_item.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../gallery/presentation/widgets/delete_confirmation_sheet.dart';
import '../../../core/widgets/feedback_pill.dart';

class TrashScreen extends ConsumerStatefulWidget {
  const TrashScreen({super.key});

  @override
  ConsumerState<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends ConsumerState<TrashScreen> {
  final Set<String> _selected = {};
  bool _selecting = false;
  late final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToActiveMedia(
    String mediaId,
    List<TrashItem> items,
    SettingsModel settings,
  ) {
    if (!mounted || !_scrollController.hasClients) return;
    final index = items.indexWhere((e) => e.id == mediaId);
    if (index < 0) return;

    final cols = settings.gridColumns;
    final row = index ~/ cols;
    final screenWidth = MediaQuery.sizeOf(context).width;
    const paddingHorizontal = 16.0;
    const spacing = 8.0;
    final availableWidth =
        screenWidth - paddingHorizontal - ((cols - 1) * spacing);
    final tileWidth = availableWidth / cols;
    final tileHeight = tileWidth / 0.82;
    final rowHeight = tileHeight + spacing;
    final rowTop = 2.0 + (row * rowHeight);

    final viewportHeight = _scrollController.position.viewportDimension;
    final currentScroll = _scrollController.offset;
    final viewportTop = currentScroll;
    final viewportBottom = currentScroll + viewportHeight;

    final effectiveTopThreshold = viewportTop <= 0.0 ? 0.0 : viewportTop + 10.0;
    if (rowTop >= effectiveTopThreshold &&
        (rowTop + tileHeight) <= viewportBottom - 10.0) {
      return;
    }

    final ideal = (rowTop - (viewportHeight - tileHeight) / 2.0)
        .clamp(0.0, _scrollController.position.maxScrollExtent);

    if ((ideal - _scrollController.offset).abs() > 1.0) {
      _scrollController.jumpTo(ideal);
    }
  }

  void _toggleSelect(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _startSelect(String id) => setState(() {
        _selecting = true;
        _selected.add(id);
      });

  void _clearSelection() => setState(() {
        _selected.clear();
        _selecting = false;
      });

  void _openPreview(
      BuildContext context, List<TrashItem> items, TrashItem item) {
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
    ref
        .read(mediaListProvider.notifier)
        .restoreItems(toRestore.map((e) => e.id));
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      showFeedbackPill(
        context,
        message: context.tr.itemRestored(context.tr.itemsCount(count)),
        icon: Icons.restore_rounded,
      );
    }
  }

  Future<void> _deleteSelected(List<TrashItem> all) async {
    final count = _selected.length;
    if (count == 0) return;
    final allSelected = _selected.length == all.length;
    final title = allSelected
        ? context.tr.permanentlyDeleteAllTitle
        : context.tr.permanentlyDeleteCountTitle(count);

    final ok = await showDeleteConfirmationSheet(
      context,
      title: title,
      contentText: '',
      isTrash: false,
    );

    if (ok != true || !mounted) return;
    final toDelete = all.where((e) => _selected.contains(e.id)).toList();
    for (final item in toDelete) {
      await ref.read(trashProvider.notifier).permanentDelete(item.id);
    }
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
    final items = trashAsync.value ?? [];

    ref.listen<String?>(activeViewerMediaIdProvider, (_, nextId) {
      if (nextId != null) {
        _scrollToActiveMedia(nextId, items, settings);
      }
    });

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
                ? (_selected.isEmpty
                    ? context.tr.selectItems
                    : '${_selected.length} ${context.tr.selected}')
                : context.tr.recentlyDeleted,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
          ),
          actions: [
            if (_selecting)
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                tooltip: context.tr.cancel,
                onPressed: _clearSelection,
              )
            else if (trashAsync.value?.isNotEmpty ?? false)
              IconButton(
                icon: const Icon(Icons.check_box_outlined, size: 22),
                tooltip: context.tr.select,
                onPressed: () => setState(() => _selecting = true),
              ),
          ],
        ),
        body: trashAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (items) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(
                    context.tr.trashRetentionNote,
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.8),
                    ),
                  ),
                ),
                Expanded(
                  child: items.isEmpty
                      ? const _TrashEmptyState()
                      : GridView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          gridDelegate:
                              SliverGridDelegateWithFixedCrossAxisCount(
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
                                  if (item.isVideo) {
                                    ThumbnailService.instance
                                        .getHighResVideoThumbnail(
                                      item.id,
                                      filePath: item.trashPath,
                                    );
                                  }
                                  _openPreview(context, items, item);
                                }
                              },
                              onOpenPreview: () =>
                                  _openPreview(context, items, item),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  border: Border(
                    top: BorderSide(
                      color:
                          Theme.of(context).dividerColor.withValues(alpha: 0.2),
                      width: 0.5,
                    ),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _BottomActionItem(
                      icon: Icons.restore_rounded,
                      label: context.tr.restore,
                      enabled: _selected.isNotEmpty,
                      onTap: _selected.isNotEmpty
                          ? () => _restoreSelected(trashAsync.value ?? [])
                          : null,
                    ),
                    _BottomActionItem(
                      icon: Icons.delete_outline_rounded,
                      label: context.tr.delete,
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
            context.tr.noRecentlyDeleted,
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
                  Container(
                    color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    child: Hero(
                      tag: item.id,
                      transitionOnUserGestures: true,
                      child: _TrashThumbnail(item: item),
                    ),
                  ),
                  if (item.isVideo)
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
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
                            ? const Icon(Icons.check,
                                size: 14, color: Colors.white)
                            : null,
                      ),
                    ),
                  Positioned(
                    bottom: 6,
                    right: 6,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (item.isVideo) {
                          ThumbnailService.instance.getHighResVideoThumbnail(
                            item.id,
                            filePath: item.trashPath,
                          );
                        }
                        onOpenPreview();
                      },
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
              context.tr.daysLeft(daysRemaining),
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

    final file = File(item.trashPath);

    return FutureBuilder<Uint8List?>(
      future: ThumbnailService.instance.getThumbnail(
        item.id,
        filePath: item.trashPath,
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
        if (item.isVideo) {
          return _buildPlaceholder(cs);
        }
        return Image.file(
          file,
          cacheWidth: 256,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, __, ___) => _buildPlaceholder(cs),
        );
      },
    );
  }

  Widget _buildPlaceholder(ColorScheme cs) {
    return Container(
      color: cs.surfaceContainerHighest,
      child: Center(
        child: Icon(
          item.isVideo ? Icons.videocam_outlined : Icons.broken_image_outlined,
          size: 28,
          color: cs.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}
