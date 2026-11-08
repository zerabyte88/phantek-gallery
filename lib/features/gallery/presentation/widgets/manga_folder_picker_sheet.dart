import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../app/router.dart';
import '../../../../core/localization/app_localizations.dart';
import '../../../../core/models/media_item.dart';
import '../../../../core/services/psd_service.dart';
import '../../../../core/services/thumbnail_service.dart';
import '../../../../core/utils/natural_sort.dart';
import '../../../../core/widgets/feedback_pill.dart';

/// Metadata for a grouped manga album and its chapters.
class MangaAlbumInfo {
  const MangaAlbumInfo({
    required this.name,
    required this.items,
    required this.subfolders,
    required this.coverItem,
  });

  final String name;
  final List<MediaItem> items;
  final List<String> subfolders;
  final MediaItem coverItem;
}

/// Modal bottom sheet allowing users to browse and select manga albums and chapters.
class MangaFolderPickerSheet extends StatefulWidget {
  const MangaFolderPickerSheet({
    super.key,
    required this.items,
    this.onSelectChapter,
  });

  final List<MediaItem> items;
  final void Function(List<MediaItem> items, int index)? onSelectChapter;

  /// Groups valid media items into sorted manga albums with detected chapter subfolders.
  static List<MangaAlbumInfo> groupMangaAlbums(List<MediaItem> allItems) {
    final validItems = allItems
        .where((e) => !e.isVideo && !PsdService.isPsd(e.path))
        .toList();
    if (validItems.isEmpty) return const [];

    final Map<String, List<MediaItem>> grouped = {};
    for (final item in validItems) {
      grouped.putIfAbsent(item.albumName, () => []).add(item);
    }

    final albumNames = grouped.keys.toList()..sort(naturalCompare);

    final List<MangaAlbumInfo> albums = [];
    for (final albumName in albumNames) {
      final albumItems = grouped[albumName]!;
      final subfolders = albumItems
          .map((e) => e.immediateFolderName)
          .where((s) => s.isNotEmpty && s != albumName)
          .toSet()
          .toList()
        ..sort(naturalCompare);

      albums.add(
        MangaAlbumInfo(
          name: albumName,
          items: albumItems,
          subfolders: subfolders,
          coverItem: albumItems.first,
        ),
      );
    }
    return albums;
  }

  /// Displays the modal bottom sheet for manga folder & chapter selection.
  static Future<void> show(
    BuildContext context, {
    required List<MediaItem> allItems,
    void Function(List<MediaItem> items, int index)? onSelectChapter,
  }) async {
    final validItems = allItems
        .where((e) => !e.isVideo && !PsdService.isPsd(e.path))
        .toList();

    if (validItems.isEmpty) {
      showFeedbackPill(
        context,
        message: context.tr.noPhotosFound,
        icon: Icons.auto_stories_rounded,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MangaFolderPickerSheet(
        items: validItems,
        onSelectChapter: onSelectChapter,
      ),
    );
  }

  @override
  State<MangaFolderPickerSheet> createState() => _MangaFolderPickerSheetState();
}

class _MangaFolderPickerSheetState extends State<MangaFolderPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late List<MangaAlbumInfo> _allAlbums;

  @override
  void initState() {
    super.initState();
    _allAlbums = MangaFolderPickerSheet.groupMangaAlbums(widget.items);
  }

  @override
  void didUpdateWidget(covariant MangaFolderPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _allAlbums = MangaFolderPickerSheet.groupMangaAlbums(widget.items);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<MangaAlbumInfo> get _filteredAlbums {
    if (_searchQuery.trim().isEmpty) return _allAlbums;
    final q = _searchQuery.trim().toLowerCase();
    return _allAlbums.where((album) {
      final nameMatches = album.name.toLowerCase().contains(q);
      final chapterMatches =
          album.subfolders.any((ch) => ch.toLowerCase().contains(q));
      return nameMatches || chapterMatches;
    }).toList();
  }

  List<String> _getDisplayedChapters(MangaAlbumInfo album) {
    if (_searchQuery.trim().isEmpty) return album.subfolders;
    final q = _searchQuery.trim().toLowerCase();
    if (album.name.toLowerCase().contains(q)) {
      return album.subfolders;
    }
    return album.subfolders
        .where((ch) => ch.toLowerCase().contains(q))
        .toList();
  }

  void _openManga(BuildContext context, List<MediaItem> items) {
    final sorted = [...items]..sort(compareMangaCanonical);
    if (widget.onSelectChapter != null) {
      Navigator.of(context).pop();
      widget.onSelectChapter!(sorted, 0);
    } else {
      final nav = Navigator.of(context);
      Navigator.of(context).pop();
      nav.openImage(sorted, 0, initialMangaMode: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final filtered = _filteredAlbums;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: const Color(0xFF1E1E1E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        clipBehavior: Clip.antiAlias,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: screenHeight * 0.75,
          ),
          child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Drag handle pill at the top
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 10, bottom: 8),
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header with title, total manga folders count, and close icon button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 8, 4),
                child: Row(
                  children: [
                    const Icon(
                      Icons.auto_stories_rounded,
                      size: 22,
                      color: Color(0xFF64B5F6),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            context.tr.readAsManga,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_allAlbums.length} manga folder${_allAlbums.length == 1 ? '' : 's'}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white54,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('manga_picker_close_button'),
                      icon: const Icon(Icons.close_rounded, color: Colors.white70),
                      tooltip: context.tr.cancel,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),

              // Search bar TextField allowing filtering by manga title or chapter name
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: TextField(
                  key: const ValueKey('manga_picker_search_field'),
                  controller: _searchController,
                  style: const TextStyle(fontSize: 14, color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Search manga or chapter...',
                    hintStyle: const TextStyle(color: Colors.white38, fontSize: 13.5),
                    prefixIcon: const Icon(Icons.search, size: 20, color: Colors.white54),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            key: const ValueKey('manga_picker_clear_search'),
                            icon: const Icon(Icons.clear, size: 18, color: Colors.white54),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF2A2A2A),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (val) {
                    setState(() => _searchQuery = val);
                  },
                ),
              ),

              const Divider(color: Colors.white10, height: 1),

              // ListView of manga albums
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                        child: Center(
                          child: Text(
                            _searchQuery.isNotEmpty
                                ? 'No manga matching "$_searchQuery"'
                                : 'No manga folders found',
                            style: const TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const Divider(color: Colors.white10, height: 1, indent: 72),
                        itemBuilder: (context, index) {
                          final album = filtered[index];
                          final subfolders = album.subfolders;
                          final displayedChapters = _getDisplayedChapters(album);

                          if (subfolders.isNotEmpty) {
                            return Theme(
                              data: Theme.of(context).copyWith(
                                dividerColor: Colors.transparent,
                              ),
                              child: ExpansionTile(
                                key: PageStorageKey('manga_${album.name}'),
                                initiallyExpanded: _searchQuery.isNotEmpty,
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 4,
                                ),
                                leading: _MangaCoverThumbnail(item: album.coverItem),
                                title: Text(
                                  album.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.white,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${subfolders.length} Chapters • ${album.items.length} pages',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.white60,
                                  ),
                                ),
                                iconColor: Colors.white70,
                                collapsedIconColor: Colors.white54,
                                childrenPadding: const EdgeInsets.only(left: 16),
                                children: [
                                  // Top sub-tile: Read All Chapters
                                  ListTile(
                                    key: ValueKey('read_all_${album.name}'),
                                    dense: true,
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                    leading: const Icon(
                                      Icons.auto_stories,
                                      size: 20,
                                      color: Color(0xFF64B5F6),
                                    ),
                                    title: Text(
                                      '📖 Read All Chapters (${album.items.length} pages)',
                                      style: const TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                    onTap: () => _openManga(context, album.items),
                                  ),
                                  // Chapter sub-tiles
                                  ...displayedChapters.map((chapterName) {
                                    final chapterItems = album.items
                                        .where((e) => e.immediateFolderName == chapterName)
                                        .toList();
                                    return ListTile(
                                      key: ValueKey('chapter_${album.name}_$chapterName'),
                                      dense: true,
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                                      leading: const Icon(
                                        Icons.folder_outlined,
                                        size: 18,
                                        color: Colors.white54,
                                      ),
                                      title: Text(
                                        chapterName,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          color: Colors.white,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Text(
                                        '${chapterItems.length} pages',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          color: Colors.white38,
                                        ),
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_right_rounded,
                                        size: 18,
                                        color: Colors.white30,
                                      ),
                                      onTap: () => _openManga(context, chapterItems),
                                    );
                                  }),
                                ],
                              ),
                            );
                          } else {
                            // Flat album (subfolders.isEmpty)
                            return ListTile(
                              key: ValueKey('flat_manga_${album.name}'),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 4,
                              ),
                              leading: _MangaCoverThumbnail(item: album.coverItem),
                              title: Text(
                                album.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                '${album.items.length} pages',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.white60,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                size: 20,
                                color: Colors.white38,
                              ),
                              onTap: () => _openManga(context, album.items),
                            );
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  }
}

/// Leading thumbnail cover for manga album tile.
class _MangaCoverThumbnail extends StatelessWidget {
  const _MangaCoverThumbnail({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final mem = ThumbnailService.instance.getMemoryThumbnail(item.id);
    if (mem != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.memory(
          mem,
          width: 44,
          height: 56,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      );
    }

    final diskFile = ThumbnailService.instance.getCachedFile(item.id);
    if (diskFile != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.file(
          diskFile,
          width: 44,
          height: 56,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _buildPlaceholder(),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: 44,
        height: 56,
        child: FutureBuilder<Uint8List?>(
          future: ThumbnailService.instance.getThumbnail(
            item.id,
            filePath: item.path,
            isVideo: item.isVideo,
          ),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.done &&
                snapshot.data != null) {
              return Image.memory(
                snapshot.data!,
                width: 44,
                height: 56,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              );
            }
            final file = File(item.path);
            if (file.existsSync()) {
              return Image.file(
                file,
                width: 44,
                height: 56,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(),
              );
            }
            return _buildPlaceholder();
          },
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 44,
      height: 56,
      color: Colors.white12,
      child: const Icon(
        Icons.auto_stories_outlined,
        color: Colors.white38,
        size: 24,
      ),
    );
  }
}
