import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/media_item.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/providers/trash_provider.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/screen_keeper_service.dart';
import '../../../core/services/share_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/services/psd_service.dart';
import '../../../core/utils/media_utils.dart';
import '../../../core/widgets/bouncy_tap.dart';
import 'widgets/media_info_sheet.dart';
import 'widgets/psd_layer_sheet.dart';
import 'widgets/rename_dialog.dart';
import '../../gallery/presentation/widgets/delete_confirmation_sheet.dart';
import '../../../core/widgets/feedback_pill.dart';
import '../../../core/services/translation/translation_models.dart';
import '../../../core/services/translation/mlkit_translation_engine.dart';
import '../../../core/services/translation/translation_isolate_coordinator.dart';
import 'widgets/manga_translation_overlay.dart';
import 'widgets/zigzag_progress_bar.dart';

// 4096px cap fits imageCache while staying sharp up to 3x zoom.
ImageProvider displayImage(String path, {int maxDimension = 4096}) =>
    ResizeImage(
      FileImage(File(path)),
      width: maxDimension,
      height: maxDimension,
      policy: ResizeImagePolicy.fit,
    );

/// Screen-fit provider (~1440px) for smooth page swiping.
ImageProvider screenDisplayImage(String path, [int maxDim = 1440]) =>
    ResizeImage(
      FileImage(File(path)),
      width: maxDim,
      height: maxDim,
      policy: ResizeImagePolicy.fit,
    );

/// Cached thumbnail, shown instantly while the full image decodes.
Widget _thumb(String id, [String? path, Uint8List? psdFallbackBytes]) {
  final hr = ThumbnailService.instance.getMemoryHighResThumbnail(id);
  final mem = hr ?? ThumbnailService.instance.getMemoryThumbnail(id);
  final disk = mem == null ? ThumbnailService.instance.getCachedFile(id) : null;
  final isVid = path != null &&
      (path.toLowerCase().endsWith('.mp4') ||
          path.toLowerCase().endsWith('.mkv') ||
          path.toLowerCase().endsWith('.webm') ||
          path.toLowerCase().endsWith('.mov') ||
          path.toLowerCase().endsWith('.avi') ||
          path.toLowerCase().endsWith('.3gp'));
  final isPsd = path != null && PsdService.isPsd(path);
  final ImageProvider? p = mem != null
      ? MemoryImage(mem)
      : (disk != null
          ? FileImage(disk)
          : (isPsd && psdFallbackBytes != null && psdFallbackBytes.isNotEmpty
              ? MemoryImage(psdFallbackBytes)
              : (path != null && !isVid && !isPsd
                  ? screenDisplayImage(path)
                  : null)));
  if (p == null) return const SizedBox.shrink();
  return Image(
    image: p,
    fit: BoxFit.contain,
    gaplessPlayback: true,
    filterQuality: FilterQuality.medium,
  );
}

/// Morphing flight shuttle between grid (cover crop) and viewer (contain aspect ratio).
Widget _buildHeroShuttle({
  required Animation<double> animation,
  required HeroFlightDirection flightDirection,
  required String id,
  String? path,
  Widget? fallbackChild,
  Uint8List? psdFallbackBytes,
}) {
  final hr = ThumbnailService.instance.getMemoryHighResThumbnail(id);
  final mem = hr ?? ThumbnailService.instance.getMemoryThumbnail(id);
  final disk = mem == null ? ThumbnailService.instance.getCachedFile(id) : null;
  final isPsd = path != null && PsdService.isPsd(path);
  final ImageProvider? p = mem != null
      ? MemoryImage(mem)
      : (disk != null
          ? FileImage(disk)
          : (isPsd && psdFallbackBytes != null && psdFallbackBytes.isNotEmpty
              ? MemoryImage(psdFallbackBytes)
              : (path != null && !isPsd ? screenDisplayImage(path) : null)));

  final Widget content = p != null
      ? Image(
          image: p,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          filterQuality: FilterQuality.medium,
        )
      : (fallbackChild ?? const SizedBox.shrink());

  final curved = CurvedAnimation(
    parent: animation,
    curve: const Cubic(0.2, 0.0, 0.0, 1.0),
  );

  return AnimatedBuilder(
    animation: curved,
    builder: (context, child) {
      final t = curved.value;
      final radius = (1.0 - t) * 8.0;

      if (radius <= 0.05) return child!;

      return ClipRRect(
        borderRadius: BorderRadius.circular(radius.clamp(0.0, 8.0)),
        clipBehavior: Clip.hardEdge,
        child: child,
      );
    },
    child: content,
  );
}

/// Full-screen swipeable image viewer with delete support.
class ImageViewerScreen extends ConsumerStatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.items,
    required this.initialIndex,
    this.isTrash = false,
    this.startSlideshow = false,
    this.initialMangaMode = false,
  });

  final List<MediaItem> items;
  final int initialIndex;
  final bool isTrash;
  final bool startSlideshow;
  final bool initialMangaMode;

  @override
  ConsumerState<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends ConsumerState<ImageViewerScreen>
    with TickerProviderStateMixin {
  late final PageController _page;
  late int _current;
  bool _barsVisible = true;
  // Drag translation notifier avoids rebuilding the viewer hierarchy.
  final ValueNotifier<Offset> _drag = ValueNotifier(Offset.zero);
  final ValueNotifier<bool> _isDraggingDown = ValueNotifier(false);
  final ValueNotifier<bool> _isDismissing = ValueNotifier(false);
  bool _isSwipingHorizontal = false;
  late final AnimationController _settle;
  Offset _settleFrom = Offset.zero;
  VelocityTracker _vt = VelocityTracker.withKind(PointerDeviceKind.touch);
  double? _startDragY;
  double? _startDragX;
  late final TransformationController _transformationController;
  AnimationController? _zoomAnimController;
  TapDownDetails? _doubleTapDetails;
  bool _isPhotoZoomed = false;
  bool _isDeepZoomed = false;
  bool _isPinching = false;
  bool _isMultiTouch = false;
  final Set<int> _activePointers = {};
  final ValueNotifier<bool> _isSwipingPage = ValueNotifier<bool>(false);
  late bool _isMangaMode;
  late final ScrollController _mangaScrollController;
  final GlobalKey _mangaListKey = GlobalKey();
  RenderSliverMultiBoxAdaptor? _cachedMangaSliver;
  TranslationRenderMode? _translationMode;
  TranslationSourceLanguage _translationLanguage =
      TranslationSourceLanguage.auto;
  TranslationTargetLanguage _translationTargetLanguage =
      TranslationTargetLanguage.indonesian;
  late List<MediaItem> _cachedMangaList;
  late final ValueNotifier<int> _activeMangaPageNotifier;

  void _updateMangaList() {
    _cachedMangaList = widget.items
        .where((it) => !it.isVideo && !PsdService.isPsd(it.path))
        .toList();
  }

  RenderSliverMultiBoxAdaptor? _getMangaSliver() {
    if (_cachedMangaSliver != null && _cachedMangaSliver!.attached) {
      return _cachedMangaSliver;
    }
    final ro = _mangaListKey.currentContext?.findRenderObject();
    if (ro == null) return null;
    RenderSliverMultiBoxAdaptor? found;
    void search(RenderObject obj) {
      if (obj is RenderSliverMultiBoxAdaptor) {
        found = obj;
        return;
      }
      obj.visitChildren((child) {
        if (found == null) search(child);
      });
    }

    search(ro);
    _cachedMangaSliver = found;
    return found;
  }

  late final TranslationIsolateCoordinator _translationCoordinator;
  Timer? _slideshowTimer;
  bool _isSlideshowPlaying = false;
  bool _didSetMaxBrightness = false;
  final Set<String> _precachedImagePaths = {};

  final Map<String, List<PsdLayerInfo>> _psdLayersCache = {};
  final Map<String, Set<int>> _psdHiddenLayers = {};
  final Map<String, Uint8List> _psdRenderedBytes = {};
  final Map<String, bool> _psdRendering = {};
  final Map<String, bool> _psdRenderComplete = {};
  final Map<String, bool> _psdLoadError = {};
  final Map<String, String> _psdLoadStatus = {};
  final Map<String, int> _psdRenderSeq = {};

  void _loadPsdDataIfNeeded(String path, {bool force = false}) {
    if (!PsdService.isPsd(path)) return;

    if (force) {
      _psdLoadError.remove(path);
      _psdRenderComplete.remove(path);
      _psdRenderedBytes.remove(path);
    }

    if (_psdRendering[path] == true) return;
    if (_psdRenderedBytes.containsKey(path) &&
        _psdRenderComplete[path] == true) {
      return;
    }
    if (!force && _psdLoadError[path] == true) return;

    _psdRendering[path] = true;
    _psdLoadError[path] = false;
    _psdLoadStatus[path] = 'Reading Photoshop document...';
    if (force && mounted) {
      setState(() {});
    }

    if (!_psdLayersCache.containsKey(path)) {
      PsdService.instance.getLayers(path).then((layers) {
        if (mounted) {
          setState(() {
            _psdLayersCache[path] = layers;
          });
        }
      });
    }

    final savedHidden = PsdService.instance.getSavedLayerVisibility(path);
    if (savedHidden != null) {
      _psdHiddenLayers[path] = Set<int>.from(savedHidden);
      PsdService.instance
          .renderWithLayers(
        path,
        hiddenLayerIndices: savedHidden,
        maxDimension: 1600,
      )
          .then((bytes) {
        if (!mounted) return;
        setState(() {
          if (bytes != null && bytes.isNotEmpty) {
            _psdRenderedBytes[path] = bytes;
            _psdRenderComplete[path] = true;
            _psdRendering[path] = false;
            _psdLoadError[path] = false;
          } else {
            _psdRendering[path] = false;
            _psdLoadError[path] = true;
            _psdLoadStatus[path] = 'Failed to load document';
          }
        });
      }).catchError((_) {
        if (!mounted) return;
        setState(() {
          _psdRendering[path] = false;
          _psdLoadError[path] = true;
          _psdLoadStatus[path] = 'Failed to load document';
        });
      });
      return;
    }

    PsdService.instance.loadPsdDocument(path, maxDimension: 2048).then((bytes) {
      if (!mounted) return;
      setState(() {
        if (bytes != null && bytes.isNotEmpty) {
          _psdRenderedBytes[path] = bytes;
          _psdRenderComplete[path] = true;
          _psdRendering[path] = false;
          _psdLoadError[path] = false;
        } else {
          _psdRendering[path] = false;
          _psdLoadError[path] = true;
          _psdLoadStatus[path] = 'Failed to load document';
        }
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _psdRendering[path] = false;
        _psdLoadError[path] = true;
        _psdLoadStatus[path] = 'Failed to load document';
      });
    });
  }

  Future<void> _openPsdLayerSheet(MediaItem item) async {
    final path = item.path;
    List<PsdLayerInfo>? layers = _psdLayersCache[path];
    if (layers == null || layers.isEmpty) {
      layers = await PsdService.instance.getLayers(path);
      if (mounted) {
        setState(() {
          _psdLayersCache[path] = layers!;
        });
      }
    }
    if (!mounted) return;

    final effectiveLayers = _psdLayersCache[path] ?? layers;
    if (!_psdHiddenLayers.containsKey(path)) {
      final savedHidden = PsdService.instance.getSavedLayerVisibility(path);
      _psdHiddenLayers[path] = savedHidden ??
          effectiveLayers
              .where((l) => !l.isVisible)
              .map((l) => l.index)
              .toSet();
    }
    final hidden = _psdHiddenLayers[path]!;
    final cachedThumbs = PsdService.instance.getCachedLayerThumbnails(path);

    PsdLayerSheet.show(
      context: context,
      filePath: path,
      layers: effectiveLayers,
      hiddenIndices: hidden,
      initialThumbnails: cachedThumbs,
      onVisibilityChanged: (newHidden) async {
        final seq = (_psdRenderSeq[path] ?? 0) + 1;
        _psdRenderSeq[path] = seq;
        setState(() {
          _psdHiddenLayers[path] = Set<int>.from(newHidden);
          _psdRendering[path] = true;
        });
        final bytes = await PsdService.instance.renderWithLayers(
          path,
          hiddenLayerIndices: newHidden,
          maxDimension: 1600,
        );
        if (mounted && _psdRenderSeq[path] == seq) {
          setState(() {
            if (bytes != null && bytes.isNotEmpty) {
              _psdRenderedBytes[path] = bytes;
              _psdRenderComplete[path] = true;
            }
            _psdRendering[path] = false;
          });
        }
      },
    );
  }

  void _startSlideshow() {
    setState(() {
      _isSlideshowPlaying = true;
      _barsVisible = false;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    final interval = ref.read(settingsNotifierProvider).slideshowInterval;
    _slideshowTimer?.cancel();
    _slideshowTimer = Timer.periodic(Duration(seconds: interval), (_) {
      if (!mounted) return;
      if (_current < widget.items.length - 1) {
        _page.nextPage(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      } else {
        _stopSlideshow();
      }
    });
  }

  void _stopSlideshow() {
    _slideshowTimer?.cancel();
    _slideshowTimer = null;
    if (_isSlideshowPlaying && mounted) {
      setState(() {
        _isSlideshowPlaying = false;
        _barsVisible = true;
      });
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
    }
  }

  bool get _isCurrentlyZoomed =>
      _transformationController.value.getMaxScaleOnAxis() > 1.05;

  @override
  void initState() {
    super.initState();
    _current = widget.initialIndex;
    _updateMangaList();
    final hasValidManga = _cachedMangaList.isNotEmpty;
    _isMangaMode = widget.initialMangaMode && hasValidManga;
    final initialActive = _cachedMangaList.isNotEmpty
        ? _cachedMangaList
            .indexOf(_currentItem)
            .clamp(0, _cachedMangaList.length - 1)
        : 0;
    _activeMangaPageNotifier = ValueNotifier<int>(initialActive);
    _mangaScrollController = ScrollController();
    _mangaScrollController.addListener(_onMangaScroll);
    _translationCoordinator = TranslationIsolateCoordinator();

    if (_isMangaMode && widget.initialIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentInManga();
      });
    }
    _page = PageController(initialPage: _current);
    _transformationController = TransformationController();
    _settle = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        final val = _settle.value;
        if (val.abs() < 0.01) {
          _setDrag(Offset.zero);
        } else {
          _setDrag(_settleFrom * val);
        }
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed ||
            status == AnimationStatus.dismissed) {
          _setDrag(Offset.zero);
        }
      });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
    );
    final settings = ref.read(settingsNotifierProvider);
    if (settings.keepScreenOn) {
      ScreenKeeperService.setKeepScreenOn(true);
    }
    if (settings.maxBrightnessOnMedia) {
      _didSetMaxBrightness = true;
      ScreenKeeperService.setMaxBrightness(true);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _activeMediaNotifier = ref.read(activeViewerMediaIdProvider.notifier);
      }
      _precacheAdjacent(_current);
      if (widget.items.isNotEmpty && _current < widget.items.length) {
        _loadPsdDataIfNeeded(widget.items[_current].path);
      }
      if (widget.startSlideshow && mounted) {
        _startSlideshow();
      }
    });
  }

  StateController<String?>? _activeMediaNotifier;

  void _precacheAdjacent(int index) {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Pre-cache immediate and upcoming neighbor images (±2 window).
      for (final offset in const [-1, 1, -2, 2]) {
        final target = index + offset;
        if (target >= 0 && target < widget.items.length) {
          final item = widget.items[target];
          if (item.isVideo || PsdService.isPsd(item.path)) continue;
          if (_precachedImagePaths.add(item.path)) {
            final mem = ThumbnailService.instance.getMemoryThumbnail(item.id);
            if (mem != null) {
              precacheImage(MemoryImage(mem), context);
            }
            precacheImage(screenDisplayImage(item.path), context);
          }
        }
      }
    });
  }

  @override
  void didUpdateWidget(ImageViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      _updateMangaList();
    }
  }

  @override
  void dispose() {
    _activeMangaPageNotifier.dispose();
    _translationCoordinator.dispose();
    _mangaScrollController.removeListener(_onMangaScroll);
    _mangaScrollController.dispose();
    _stopSlideshow();
    final notifier = _activeMediaNotifier;
    if (notifier != null) {
      Future.microtask(() {
        if (notifier.mounted) {
          notifier.state = null;
        }
      });
    }
    ScreenKeeperService.setKeepScreenOn(false);
    if (_didSetMaxBrightness) {
      ScreenKeeperService.setMaxBrightness(false);
    }
    _transformationController.dispose();
    _zoomAnimController?.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _settle.dispose();
    _isDraggingDown.dispose();
    _isDismissing.dispose();
    _isSwipingPage.dispose();
    _drag.dispose();
    _page.dispose();
    super.dispose();
  }

  void _onMangaScroll() {
    final mangaList = _mangaItems;
    if (!_mangaScrollController.hasClients || mangaList.isEmpty) return;
    final position = _mangaScrollController.position;
    final offset = position.pixels;
    final maxScroll = position.maxScrollExtent;
    final viewportHeight = position.viewportDimension;

    int activeMangaIndex = 0;

    if (maxScroll > 0 && offset >= maxScroll - 24.0) {
      activeMangaIndex = mangaList.length - 1;
    } else if (offset <= 24.0) {
      activeMangaIndex = 0;
    } else {
      final sliver = _getMangaSliver();
      int? foundIndex;
      if (sliver != null && sliver.attached) {
        final focalLine = offset + (viewportHeight * 0.35).clamp(60.0, 300.0);
        int? fallbackIndex;

        RenderBox? child = sliver.firstChild;
        while (child != null) {
          final parentData = child.parentData;
          if (parentData is SliverMultiBoxAdaptorParentData &&
              parentData.layoutOffset != null &&
              parentData.index != null) {
            final layoutOffset = parentData.layoutOffset!;
            final childBottom = layoutOffset + child.size.height;
            final idx = parentData.index!;

            if (focalLine >= layoutOffset && focalLine < childBottom) {
              foundIndex = idx;
              break;
            }

            if (fallbackIndex == null &&
                childBottom > offset &&
                layoutOffset < offset + viewportHeight) {
              fallbackIndex = idx;
            }
          }
          child = sliver.childAfter(child);
        }
        foundIndex ??= fallbackIndex;
      }

      if (foundIndex != null &&
          foundIndex >= 0 &&
          foundIndex < mangaList.length) {
        activeMangaIndex = foundIndex;
      } else if (maxScroll > 0) {
        activeMangaIndex = ((mangaList.length - 1) * (offset / maxScroll))
            .round()
            .clamp(0, mangaList.length - 1);
      }
    }

    final activeItem = mangaList[activeMangaIndex];
    final globalIndex = widget.items.indexOf(activeItem);

    if (globalIndex != -1 && globalIndex != _current) {
      _current = globalIndex;
      _activeMediaNotifier?.state = activeItem.id;
    }
    if (_activeMangaPageNotifier.value != activeMangaIndex) {
      _activeMangaPageNotifier.value = activeMangaIndex;
    }

    if (_isMangaMode && _translationMode != null) {
      final it = mangaList[activeMangaIndex];
      final screenWidth = MediaQuery.sizeOf(context).width;
      final w = (it.width != null && it.width! > 0)
          ? it.width!.toDouble()
          : screenWidth;
      final h = (it.height != null && it.height! > 0)
          ? it.height!.toDouble()
          : screenWidth;
      _translationCoordinator.scheduleTranslation(
        imagePath: it.path,
        imageSize: Size(w, h),
        mode: _translationMode!,
        language: _translationLanguage,
        targetLanguage: _translationTargetLanguage,
      );
    }
  }

  void _setTranslationLanguage(TranslationSourceLanguage lang) {
    if (_translationLanguage == lang) return;
    setState(() {
      _translationLanguage = lang;
    });
    _translationCoordinator.clearCache();
    if (_translationMode != null && _mangaItems.isNotEmpty) {
      _onMangaScroll();
    }
  }

  void _setTranslationTargetLanguage(TranslationTargetLanguage lang) {
    if (_translationTargetLanguage == lang) return;
    setState(() {
      _translationTargetLanguage = lang;
    });
    _translationCoordinator.clearCache();
    if (_translationMode != null && _mangaItems.isNotEmpty) {
      _onMangaScroll();
    }
  }

  void _setTranslationMode(TranslationRenderMode? mode) {
    setState(() {
      _translationMode = mode;
    });
    if (mode != null && _mangaItems.isNotEmpty) {
      _onMangaScroll();
    } else {
      _translationCoordinator.cancelPending();
    }
  }

  void _showTranslationSheet() {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FutureBuilder<ModelPairStatus>(
              future: MlKitTranslationEngine.instance.getPairStatus(
                _translationLanguage,
                _translationTargetLanguage,
              ),
              builder: (context, snapshot) {
                final pairStatus = snapshot.data ??
                    const ModelPairStatus(
                      sourceDownloaded: false,
                      targetDownloaded: false,
                      sourceLangName: '',
                      targetLangName: '',
                      totalNeededMb: 60.0,
                      isReady: false,
                    );
                final isModelLoading =
                    snapshot.connectionState == ConnectionState.waiting;

                return SafeArea(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Drag handle
                          Center(
                            child: Container(
                              width: 40,
                              height: 4,
                              margin: const EdgeInsets.only(bottom: 16),
                              decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),

                          // Header
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: primary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(Icons.translate_rounded,
                                    color: primary, size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  loc.mangaTranslation,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close_rounded,
                                    color: Colors.white70, size: 22),
                                onPressed: () => Navigator.pop(sheetContext),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // Section 1: Source Language
                          Text(
                            loc.sourceLanguage.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                _buildLanguageChip(
                                  label: '🌐 ${loc.autoDetect}',
                                  selected: _translationLanguage ==
                                      TranslationSourceLanguage.auto,
                                  onTap: () {
                                    setSheetState(() {});
                                    _setTranslationLanguage(
                                        TranslationSourceLanguage.auto);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _buildLanguageChip(
                                  label: '🇯🇵 ${loc.langJapanese}',
                                  selected: _translationLanguage ==
                                      TranslationSourceLanguage.japanese,
                                  onTap: () {
                                    setSheetState(() {});
                                    _setTranslationLanguage(
                                        TranslationSourceLanguage.japanese);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _buildLanguageChip(
                                  label: '🇰🇷 ${loc.langKorean}',
                                  selected: _translationLanguage ==
                                      TranslationSourceLanguage.korean,
                                  onTap: () {
                                    setSheetState(() {});
                                    _setTranslationLanguage(
                                        TranslationSourceLanguage.korean);
                                  },
                                ),
                                const SizedBox(width: 8),
                                _buildLanguageChip(
                                  label: '🇨🇳 ${loc.langChinese}',
                                  selected: _translationLanguage ==
                                      TranslationSourceLanguage.chinese,
                                  onTap: () {
                                    setSheetState(() {});
                                    _setTranslationLanguage(
                                        TranslationSourceLanguage.chinese);
                                  },
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Section 2: Target Language
                          Text(
                            loc.targetLanguage.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              _buildLanguageChip(
                                label: '🇮🇩 ${loc.langIndonesian}',
                                selected: _translationTargetLanguage ==
                                    TranslationTargetLanguage.indonesian,
                                onTap: () {
                                  setSheetState(() {});
                                  _setTranslationTargetLanguage(
                                      TranslationTargetLanguage.indonesian);
                                },
                              ),
                              const SizedBox(width: 8),
                              _buildLanguageChip(
                                label: '🇺🇸 ${loc.langEnglish}',
                                selected: _translationTargetLanguage ==
                                    TranslationTargetLanguage.english,
                                onTap: () {
                                  setSheetState(() {});
                                  _setTranslationTargetLanguage(
                                      TranslationTargetLanguage.english);
                                },
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                                                    // Section 3: AI Model Status Card
                          ValueListenableBuilder<TranslationDownloadProgress>(
                            valueListenable:
                                MlKitTranslationEngine.instance.downloadProgressNotifier,
                            builder: (context, downloadProgress, _) {
                              final isDownloading = downloadProgress.isDownloading;
                              final hasError = !isDownloading &&
                                  !pairStatus.isReady &&
                                  downloadProgress.errorMessage != null &&
                                  downloadProgress.errorMessage!.isNotEmpty;
                              final isReady = pairStatus.isReady && !isDownloading;

                              Color cardBg;
                              Color borderColor;
                              if (isReady) {
                                cardBg = const Color(0xFF132A1C);
                                borderColor = Colors.greenAccent.withValues(alpha: 0.3);
                              } else if (isDownloading) {
                                cardBg = const Color(0xFF131D2A);
                                borderColor =
                                    const Color(0xFF00E5FF).withValues(alpha: 0.35);
                              } else if (hasError) {
                                cardBg = const Color(0xFF2C1517);
                                borderColor =
                                    Colors.redAccent.withValues(alpha: 0.35);
                              } else {
                                cardBg = const Color(0xFF24201A);
                                borderColor =
                                    Colors.orangeAccent.withValues(alpha: 0.3);
                              }

                              return Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  color: cardBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: borderColor, width: 1),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                          isReady
                                              ? Icons.check_circle_rounded
                                              : isDownloading
                                                  ? Icons.downloading_rounded
                                                  : hasError
                                                      ? Icons.error_outline_rounded
                                                      : Icons.cloud_download_rounded,
                                          color: isReady
                                              ? Colors.greenAccent
                                              : isDownloading
                                                  ? const Color(0xFF00E5FF)
                                                  : hasError
                                                      ? Colors.redAccent
                                                      : Colors.orangeAccent,
                                          size: 22,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                isReady
                                                    ? '✓ ${loc.modelReady}'
                                                    : isDownloading
                                                        ? downloadProgress.currentStep
                                                        : hasError
                                                            ? loc.modelDownloadFailed
                                                            : loc.downloadModelPrompt,
                                                style: TextStyle(
                                                  color: isReady
                                                      ? Colors.greenAccent
                                                      : isDownloading
                                                          ? const Color(0xFF00E5FF)
                                                          : hasError
                                                              ? Colors.redAccent
                                                              : Colors.orangeAccent,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                isReady
                                                    ? 'Google Neural MT (100% On-Device Offline)'
                                                    : isDownloading
                                                        ? '${downloadProgress.downloadedMb.toStringAsFixed(1)} MB / ${downloadProgress.totalMb.toStringAsFixed(1)} MB (${(downloadProgress.progress * 100).toInt()}%)'
                                                        : hasError
                                                            ? (downloadProgress
                                                                    .errorMessage ??
                                                                '')
                                                            : loc.modelDownloadRequired,
                                                style: TextStyle(
                                                  color: Colors.white
                                                      .withValues(alpha: 0.65),
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        if (!isReady && !isDownloading && !hasError) ...[
                                          const SizedBox(width: 8),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              backgroundColor: Colors.orangeAccent
                                                  .withValues(alpha: 0.2),
                                              foregroundColor: Colors.orangeAccent,
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 6),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: isModelLoading
                                                ? null
                                                : () async {
                                                    final success =
                                                        await MlKitTranslationEngine
                                                            .instance
                                                            .downloadPairWithProgress(
                                                      _translationLanguage,
                                                      _translationTargetLanguage,
                                                    );
                                                    if (success && sheetContext.mounted) {
                                                      showFeedbackPill(
                                                        sheetContext,
                                                        message:
                                                            loc.modelDownloadSuccess,
                                                        icon: Icons.check_circle_rounded,
                                                      );
                                                    }
                                                    setSheetState(() {});
                                                  },
                                            child: Text(
                                              'Download (~${pairStatus.totalNeededMb.toInt()} MB)',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ] else if (hasError) ...[
                                          const SizedBox(width: 8),
                                          TextButton(
                                            style: TextButton.styleFrom(
                                              backgroundColor: Colors.redAccent
                                                  .withValues(alpha: 0.2),
                                              foregroundColor: Colors.redAccent,
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 12, vertical: 6),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                            ),
                                            onPressed: () async {
                                              final success =
                                                  await MlKitTranslationEngine.instance
                                                      .downloadPairWithProgress(
                                                _translationLanguage,
                                                _translationTargetLanguage,
                                              );
                                              if (success && sheetContext.mounted) {
                                                showFeedbackPill(
                                                  sheetContext,
                                                  message: loc.modelDownloadSuccess,
                                                  icon: Icons.check_circle_rounded,
                                                );
                                              }
                                              setSheetState(() {});
                                            },
                                            child: Text(
                                              loc.retry,
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    if (isDownloading) ...[
                                      const SizedBox(height: 10),
                                      ZigzagProgressBar(
                                        progress: downloadProgress.progress,
                                        isProcessing: true,
                                        color: const Color(0xFF00E5FF),
                                        deepColor: const Color(0xFF007799),
                                        crestColor: Colors.white,
                                        height: 20,
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),

                          const SizedBox(height: 16),

// Section 4: Render Mode Option Cards
                          _buildModeCard(
                            title: loc.translateSpeechBubbles,
                            subtitle: loc.translateSpeechBubblesSubtitle,
                            icon: Icons.chat_bubble_outline_rounded,
                            selected: _translationMode ==
                                TranslationRenderMode.speechBubblesOnly,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _setTranslationMode(
                                  TranslationRenderMode.speechBubblesOnly);
                              showFeedbackPill(
                                context,
                                message: '${loc.mangaTranslation}...',
                                icon: Icons.translate_rounded,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          _buildModeCard(
                            title: loc.translateFullPage,
                            subtitle: loc.translateFullPageSubtitle,
                            icon: Icons.auto_stories_outlined,
                            selected: _translationMode ==
                                TranslationRenderMode.fullImageWithSfx,
                            onTap: () {
                              Navigator.pop(sheetContext);
                              _setTranslationMode(
                                  TranslationRenderMode.fullImageWithSfx);
                              showFeedbackPill(
                                context,
                                message: '${loc.mangaTranslation}...',
                                icon: Icons.translate_rounded,
                              );
                            },
                          ),

                          // Section 5: Turn off translation
                          if (_translationMode != null) ...[
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.redAccent,
                                  side: BorderSide(
                                      color: Colors.redAccent
                                          .withValues(alpha: 0.4)),
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                icon: const Icon(
                                    Icons.power_settings_new_rounded,
                                    size: 18),
                                label: Text(
                                  loc.disableTranslation,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600),
                                ),
                                onPressed: () {
                                  Navigator.pop(sheetContext);
                                  _setTranslationMode(null);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildModeCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.12)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? primary : Colors.white12,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color:
                    selected ? primary.withValues(alpha: 0.2) : Colors.white10,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: selected ? primary : Colors.white70,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: primary, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? primary.withValues(alpha: 0.25) : Colors.white10,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? primary : Colors.white24,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  void _scrollToCurrentInManga() {
    final mangaList = _mangaItems;
    if (!_mangaScrollController.hasClients || mangaList.isEmpty) return;
    final currentItem = _currentItem;
    int mangaIdx = mangaList.indexOf(currentItem);
    if (mangaIdx < 0) mangaIdx = 0;
    if (mangaIdx == 0) return;

    final maxScroll = _mangaScrollController.position.maxScrollExtent;
    if (mangaIdx == mangaList.length - 1 && maxScroll > 0) {
      _mangaScrollController.jumpTo(maxScroll);
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    double targetOffset = 0.0;
    for (int i = 0; i < mangaIdx; i++) {
      final it = mangaList[i];
      final ar = (it.width != null &&
              it.height != null &&
              it.width! > 0 &&
              it.height! > 0)
          ? (it.width! / it.height!)
          : 0.7; // Portrait manga fallback
      targetOffset += screenWidth / ar;
    }
    _mangaScrollController.jumpTo(targetOffset.clamp(0.0, maxScroll));
  }

  void _toggleMangaMode() {
    final mangaList = _mangaItems;
    if (mangaList.isEmpty) {
      showFeedbackPill(
        context,
        message: context.tr.noPhotosFound,
        icon: Icons.auto_stories_rounded,
      );
      return;
    }

    setState(() {
      _isMangaMode = !_isMangaMode;
    });
    if (!_isMangaMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_page.hasClients) {
          _page.jumpToPage(_current);
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToCurrentInManga();
      });
    }
  }

  Widget _buildMangaView() {
    final mangaList = _mangaItems;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _toggleBars,
      child: ListView.builder(
        key: _mangaListKey,
        controller: _mangaScrollController,
        padding: EdgeInsets.zero,
        scrollCacheExtent: const ScrollCacheExtent.pixels(2500.0),
        physics: const BouncingScrollPhysics(),
        itemCount: mangaList.length,
        itemBuilder: (context, index) {
          final it = mangaList[index];
          Widget imageWidget = Image(
            image: screenDisplayImage(it.path),
            fit: BoxFit.fitWidth,
            width: double.infinity,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) return child;
              return _thumb(it.id, it.path);
            },
            errorBuilder: (_, __, ___) => Container(
              height: 300,
              color: Colors.black26,
              alignment: Alignment.center,
              child: const Icon(Icons.broken_image,
                  size: 60, color: Colors.white38),
            ),
          );

          if (it.width != null &&
              it.height != null &&
              it.width! > 0 &&
              it.height! > 0) {
            final ar = it.width! / it.height!;
            if (ar > 0.1 && ar < 5.0) {
              imageWidget = AspectRatio(
                aspectRatio: ar,
                child: imageWidget,
              );
            }
          }

          return RepaintBoundary(
            child: Stack(
              children: [
                imageWidget,
                if (_translationMode != null)
                  Positioned.fill(
                    child: ValueListenableBuilder<TranslationResult?>(
                      valueListenable:
                          _translationCoordinator.getResultNotifier(it.path),
                      builder: (context, result, _) {
                        if (result == null ||
                            !result.isSuccess ||
                            result.blocks.isEmpty) {
                          return const SizedBox.shrink();
                        }
                        return MangaTranslationOverlay(
                          result: result,
                          mode: _translationMode!,
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<MediaItem> get _mangaItems => _cachedMangaList;

  MediaItem get _currentItem => widget.items[_current];

  void _setDrag(Offset o) {
    _drag.value = o;
    final isDown = o.dy > 8.0;
    if (_isDraggingDown.value != isDown) {
      _isDraggingDown.value = isDown;
      if (isDown && _page.hasClients && _page.page != null) {
        final snapped = _page.page!.round().clamp(0, widget.items.length - 1);
        if (_current != snapped) {
          _current = snapped;
        }
        if ((_page.page! - _current).abs() > 0.001) {
          _page.jumpToPage(_current);
        }
      }
    }
  }

  void _springBack(double vy) {
    _settleFrom = _drag.value;
    if (_settleFrom == Offset.zero || _settleFrom.distance < 1.0) {
      _setDrag(Offset.zero);
      return;
    }
    final v = _settleFrom.dy.abs() > 1 ? vy / _settleFrom.dy : 0.0;
    _settle.value = 1.0;
    _settle
        .animateWith(SpringSimulation(
      SpringDescription.withDampingRatio(
          mass: 1.0, stiffness: 320, ratio: 0.82),
      1.0,
      0.0,
      v.clamp(-8.0, 8.0),
    ))
        .whenCompleteOrCancel(() {
      _setDrag(Offset.zero);
    });
  }

  void _toggleBars() {
    if (_isSlideshowPlaying) {
      _stopSlideshow();
      return;
    }
    if (!_isCurrentlyZoomed && !_isPinching) {
      final nextVisible = !_barsVisible;
      setState(() => _barsVisible = nextVisible);
      if (nextVisible) {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        SystemChrome.setSystemUIOverlayStyle(
          const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarIconBrightness: Brightness.light,
          ),
        );
      } else {
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      }
    }
  }

  void _resetPhotoZoom() {
    if (!_isPhotoZoomed && _transformationController.value.isIdentity()) return;
    _zoomAnimController?.stop();
    _zoomAnimController?.dispose();

    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    final animation = Matrix4Tween(
      begin: _transformationController.value,
      end: Matrix4.identity(),
    ).animate(CurvedAnimation(
      parent: _zoomAnimController!,
      curve: Curves.easeOutCubic,
    ));

    animation.addListener(() {
      _transformationController.value = animation.value;
    });

    _zoomAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _transformationController.value = Matrix4.identity();
        if (mounted) {
          setState(() {
            _isPhotoZoomed = false;
            _isDeepZoomed = false;
          });
        }
      }
    });

    _zoomAnimController!.forward();
  }

  void _zoomToPosition(Offset tapPos) {
    _zoomAnimController?.stop();
    _zoomAnimController?.dispose();

    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final bool isZoomed = currentScale > 1.05 || _isPhotoZoomed;

    final Matrix4 endMatrix;
    if (isZoomed) {
      endMatrix = Matrix4.identity();
    } else {
      const double targetScale = 2.5;
      endMatrix = Matrix4.identity()
        ..translateByDouble(tapPos.dx, tapPos.dy, 0.0, 1.0)
        ..scaleByDouble(targetScale, targetScale, 1.0, 1.0)
        ..translateByDouble(-tapPos.dx, -tapPos.dy, 0.0, 1.0);
    }

    _zoomAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );

    final animation = Matrix4Tween(
      begin: _transformationController.value,
      end: endMatrix,
    ).animate(CurvedAnimation(
      parent: _zoomAnimController!,
      curve: Curves.easeOutCubic,
    ));

    animation.addListener(() {
      _transformationController.value = animation.value;
    });

    _zoomAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        if (isZoomed) {
          _transformationController.value = Matrix4.identity();
        }
        setState(() {
          _isPhotoZoomed = !isZoomed;
          _isDeepZoomed = !isZoomed;
        });
      }
    });

    HapticFeedback.lightImpact();
    _zoomAnimController!.forward();
  }

  void _handleDoubleTap() {
    if (_doubleTapDetails == null) return;
    _zoomToPosition(_doubleTapDetails!.localPosition);
  }

  Widget _buildPhotoPage(MediaItem it, {bool isCurrent = false}) {
    if (it.isVideo) {
      return Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            _thumb(it.id, it.path),
            const Icon(Icons.play_circle_fill_rounded,
                size: 64, color: Colors.white70),
          ],
        ),
      );
    }

    if (PsdService.isPsd(it.path)) {
      _loadPsdDataIfNeeded(it.path);
      final rendered = _psdRenderedBytes[it.path];
      if (rendered != null && rendered.isNotEmpty) {
        final isRenderingThis = _psdRendering[it.path] == true;
        Widget content = Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              duration: const Duration(milliseconds: 150),
              opacity: isRenderingThis ? 0.65 : 1.0,
              child: Image(
                key: ValueKey(
                    'psd_${it.path}_${_psdHiddenLayers[it.path]?.length}_${_psdHiddenLayers[it.path]?.join('_')}_${rendered.length}'),
                image: MemoryImage(rendered),
                fit: BoxFit.contain,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
              ),
            ),
            if (isRenderingThis)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(20),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 12,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF31A8FF)),
                      ),
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Rendering PSD...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );

        final ar = (it.width != null &&
                it.height != null &&
                it.width! > 0 &&
                it.height! > 0)
            ? (it.width! / it.height!)
            : ThumbnailService.instance.getThumbnailAspectRatio(it.id);

        if (ar != null && ar > 0) {
          content = AspectRatio(
            aspectRatio: ar,
            child: content,
          );
        }

        return content;
      } else if (_psdLoadError[it.path] == true) {
        return Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 24),
            padding: const EdgeInsets.all(24),
            constraints: const BoxConstraints(maxWidth: 380),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black45,
                  blurRadius: 20,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF31A8FF),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'PSD',
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  it.name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Text(
                  'Could not load Photoshop document',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: () => _loadPsdDataIfNeeded(it.path, force: true),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Retry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF31A8FF),
                    foregroundColor: Colors.black,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    textStyle: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
      } else {
        final sizeMb = (it.size / (1024 * 1024)).toStringAsFixed(1);
        final status =
            _psdLoadStatus[it.path] ?? 'Reading Photoshop document...';

        return Center(
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: Opacity(
                  opacity: 0.25,
                  child: _thumb(it.id, it.path, null),
                ),
              ),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(24),
                constraints: const BoxConstraints(maxWidth: 380),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black45,
                      blurRadius: 20,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF31A8FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'PSD',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      it.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$sizeMb MB',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SizedBox(
                      width: 140,
                      child: LinearProgressIndicator(
                        backgroundColor: Colors.white12,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Color(0xFF31A8FF)),
                        minHeight: 3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      status,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }
    }

    Widget content = Image(
      image: (isCurrent && _isDeepZoomed)
          ? displayImage(it.path, maxDimension: 4096)
          : screenDisplayImage(it.path),
      fit: BoxFit.contain,
      gaplessPlayback: true,
      filterQuality: FilterQuality.medium,
      frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded || frame != null) {
          return child;
        }
        return _thumb(it.id, it.path);
      },
      errorBuilder: (_, __, ___) => const Center(
        child: Icon(Icons.broken_image, size: 80, color: Colors.white38),
      ),
    );

    final ar = (it.width != null &&
            it.height != null &&
            it.width! > 0 &&
            it.height! > 0)
        ? (it.width! / it.height!)
        : ThumbnailService.instance.getThumbnailAspectRatio(it.id);

    if (ar != null && ar > 0) {
      content = AspectRatio(
        aspectRatio: ar,
        child: content,
      );
    }

    return content;
  }

  Future<void> _restoreCurrentItem() async {
    final item = _currentItem;
    await ref.read(trashProvider.notifier).restore(item.id);
    ref.read(mediaListProvider.notifier).restoreItems([item.id]);
    ref.read(mediaListProvider.notifier).refresh();

    if (mounted) {
      showFeedbackPill(
        context,
        message: context.tr.itemRestored(item.name),
        icon: Icons.restore_rounded,
      );
      if (widget.items.length <= 1) {
        Navigator.of(context).pop();
      } else {
        widget.items.removeAt(_current);
        setState(() {
          _current = _current.clamp(0, widget.items.length - 1);
          _transformationController.value = Matrix4.identity();
          _isPhotoZoomed = false;
          _isDeepZoomed = false;
        });
        _page.jumpToPage(_current);
      }
    }
  }

  Future<void> _deleteCurrentItem() async {
    final item = _currentItem;

    if (widget.isTrash) {
      final ok = await showDeleteConfirmationSheet(
        context,
        title: context.tr.deletePermanentlyTitle,
        contentText: context.tr.deletePermanentlyConfirm(item.name),
        isTrash: false,
      );
      if (ok != true || !mounted) return;

      await ref.read(trashProvider.notifier).permanentDelete(item.id);
      if (mounted) {
        showFeedbackPill(
          context,
          message: context.tr.itemDeleted(item.name),
          icon: Icons.delete_outline_rounded,
        );
        if (widget.items.length <= 1) {
          Navigator.of(context).pop();
        } else {
          widget.items.removeAt(_current);
          setState(() {
            _current = _current.clamp(0, widget.items.length - 1);
            _transformationController.value = Matrix4.identity();
            _isPhotoZoomed = false;
            _isDeepZoomed = false;
          });
          _page.jumpToPage(_current);
        }
      }
      return;
    }

    final settings = ref.read(settingsNotifierProvider);
    final isTrash = settings.enableTrash;

    final ok = await showDeleteConfirmationSheet(
      context,
      title: isTrash
          ? context.tr.moveToTrashTitle
          : context.tr.deletePermanentlyTitle,
      contentText: isTrash
          ? context.tr.moveToTrashConfirm(item.name)
          : context.tr.deletePermanentlyConfirm(item.name),
      isTrash: isTrash,
    );
    if (ok != true || !mounted) return;

    final hasPerm = await PermissionService.instance.ensureManageStorage();
    if (!hasPerm) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr.manageFilesPermissionRequired),
          ),
        );
      }
      return;
    }

    ref.read(mediaListProvider.notifier).removeItems({item.id});

    try {
      if (settings.enableTrash) {
        await ref.read(trashProvider.notifier).moveToTrash(
              id: item.id,
              path: item.path,
              isVideo: item.isVideo,
            );
      } else {
        final f = File(item.path);
        if (await f.exists()) await f.delete();
        try {
          await PhotoManager.editor.deleteWithIds([item.id]);
        } catch (_) {}
      }
      ref.read(mediaListProvider.notifier).refresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr.failedToDelete(e.toString()))),
        );
      }
      return;
    }

    if (!mounted) return;
    showFeedbackPill(
      context,
      message: isTrash
          ? context.tr.itemMovedToTrash(item.name)
          : context.tr.itemDeleted(item.name),
      icon:
          isTrash ? Icons.delete_outline_rounded : Icons.delete_forever_rounded,
    );
    if (widget.items.length <= 1) {
      Navigator.of(context).pop();
    } else {
      widget.items.removeAt(_current);
      setState(() {
        _current = _current.clamp(0, widget.items.length - 1);
        _transformationController.value = Matrix4.identity();
        _isPhotoZoomed = false;
        _isDeepZoomed = false;
      });
      _page.jumpToPage(_current);
    }
  }

  Widget _buildStaggeredBar({
    required BuildContext context,
    required bool showBars,
    bool isTopBar = true,
    required Widget child,
  }) {
    final anim = ModalRoute.of(context)?.animation;
    return AnimatedSlide(
      offset: showBars
          ? Offset.zero
          : (isTopBar ? const Offset(0, -0.2) : const Offset(0, 0.2)),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedOpacity(
        opacity: showBars ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        child: ValueListenableBuilder<Offset>(
          valueListenable: _drag,
          builder: (context, d, _) {
            final dragFade = (1.0 - (d.dy / 35.0)).clamp(0.0, 1.0);
            if (anim == null) {
              return Opacity(
                opacity: dragFade,
                child: IgnorePointer(
                  ignoring: !showBars || d.dy > 4,
                  child: child,
                ),
              );
            }
            return AnimatedBuilder(
              animation: anim,
              builder: (context, _) {
                final entrance =
                    const Interval(0.65, 1.0, curve: Curves.easeOut)
                        .transform(anim.value);
                final opacity = (dragFade * entrance).clamp(0.0, 1.0);
                return Opacity(
                  opacity: opacity,
                  child: IgnorePointer(
                    ignoring: !showBars || d.dy > 4 || opacity < 0.5,
                    child: child,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = _currentItem;
    final showBars = _barsVisible && !_isCurrentlyZoomed && !_isPinching;
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          if (_page.hasClients && _page.page != null) {
            final snapped =
                _page.page!.round().clamp(0, widget.items.length - 1);
            _current = snapped;
          }
          _isDismissing.value = true;
          _activeMediaNotifier?.state = _currentItem.id;
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Listener(
          onPointerDown: (e) {
            _activePointers.add(e.pointer);
            _settle.stop();
            _zoomAnimController?.stop();
            _isSwipingHorizontal = false;
            if (_isMangaMode) {
              if (_drag.value != Offset.zero) _setDrag(Offset.zero);
              return;
            }
            if (_activePointers.length == 1) {
              _setDrag(Offset.zero);
              _isMultiTouch = false;
              _isPinching = false;
              if (_transformationController.value.getMaxScaleOnAxis() <= 1.05) {
                _isPhotoZoomed = false;
                _isDeepZoomed = false;
              }
            }
            if (_activePointers.length >= 2 || _isCurrentlyZoomed) {
              _isMultiTouch = true;
              _isPinching = true;
              _startDragY = null;
              _startDragX = null;
              if (_drag.value != Offset.zero) _setDrag(Offset.zero);
              return;
            }
            if (_page.hasClients && _page.page != null) {
              final snapped =
                  _page.page!.round().clamp(0, widget.items.length - 1);
              if (_current != snapped) {
                _current = snapped;
              }
            }
            _startDragY = e.position.dy;
            _startDragX = e.position.dx;
            _vt = VelocityTracker.withKind(e.kind);
            _vt.addPosition(e.timeStamp, e.position);
          },
          onPointerMove: (e) {
            if (_isMangaMode) return;
            if (_startDragY == null ||
                _startDragX == null ||
                _isCurrentlyZoomed ||
                _isPinching ||
                _isMultiTouch ||
                _activePointers.length >= 2) {
              if (_drag.value != Offset.zero) _setDrag(Offset.zero);
              return;
            }

            final dx = e.position.dx - _startDragX!;
            final dy = e.position.dy - _startDragY!;
            final adx = dx.abs();
            final ady = dy.abs();

            if (!_isSwipingHorizontal && _drag.value == Offset.zero) {
              if (adx > 6 && adx > ady) {
                _isSwipingHorizontal = true;
                return;
              }
            }

            if (_isSwipingHorizontal) return;

            _vt.addPosition(e.timeStamp, e.position);

            if (_drag.value != Offset.zero || (dy > 18 && dy > adx * 1.5)) {
              final dampedDx = dx * 0.45;
              final dragY = (dy - 18).clamp(0.0, 650.0);
              _setDrag(Offset(dampedDx, dragY));
            }
          },
          onPointerUp: (e) {
            _vt.addPosition(e.timeStamp, e.position);
            _activePointers.remove(e.pointer);

            if (_activePointers.isEmpty) {
              final wasMultiTouch = _isMultiTouch;
              _isMultiTouch = false;
              _isPinching = false;
              _isSwipingHorizontal = false;
              _startDragY = null;
              _startDragX = null;
              if (_isMangaMode) {
                if (_drag.value != Offset.zero) _setDrag(Offset.zero);
                return;
              }
              final d = _drag.value;
              final vy = _vt.getVelocity().pixelsPerSecond.dy;

              if (!wasMultiTouch &&
                  !_isCurrentlyZoomed &&
                  d.dy > 0 &&
                  (d.dy > 85 || (vy > 550 && d.dy > 20))) {
                if (_page.hasClients && _page.page != null) {
                  final targetIndex =
                      _page.page!.round().clamp(0, widget.items.length - 1);
                  _current = targetIndex;
                  _page.jumpToPage(_current);
                }
                _isDismissing.value = true;
                _activeMediaNotifier?.state = _currentItem.id;
                Navigator.of(context).pop();
                return;
              } else if (d != Offset.zero) {
                _springBack(vy);
                return;
              } else {
                _setDrag(Offset.zero);
              }
            }
          },
          onPointerCancel: (e) {
            _activePointers.remove(e.pointer);
            if (_activePointers.isEmpty) {
              _isMultiTouch = false;
              _isPinching = false;
              _isSwipingHorizontal = false;
              _startDragY = null;
              _startDragX = null;
              if (_drag.value != Offset.zero) {
                _springBack(0);
              } else {
                _setDrag(Offset.zero);
              }
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (_drag.value.dy < 10) {
                _toggleBars();
              }
            },
            onDoubleTapDown: (details) {
              _doubleTapDetails = details;
            },
            onDoubleTap: _handleDoubleTap,
            child: Stack(
              children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: ModalRoute.of(context)?.animation ??
                        kAlwaysCompleteAnimation,
                    builder: (context, _) {
                      final routeAnim =
                          ModalRoute.of(context)?.animation?.value ?? 1.0;
                      final curved = const Cubic(0.2, 0.0, 0.0, 1.0)
                          .transform(routeAnim.clamp(0.0, 1.0));
                      return ValueListenableBuilder<Offset>(
                        valueListenable: _drag,
                        builder: (_, d, __) {
                          final dragFade =
                              (1.0 - (d.dy / 320.0)).clamp(0.0, 1.0);
                          return ColoredBox(
                            color: Colors.black.withValues(
                              alpha: (curved * dragFade).clamp(0.0, 1.0),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                ValueListenableBuilder<Offset>(
                  valueListenable: _drag,
                  builder: (_, d, child) {
                    final s = (1.0 - (d.dy / 1000.0) * 0.28).clamp(0.72, 1.0);
                    final radius =
                        (d.dy > 0 ? (d.dy / 12.0).clamp(0.0, 20.0) : 0.0);
                    return Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.translationValues(d.dx, d.dy, 0)
                        ..scaleByDouble(s, s, 1.0, 1.0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        clipBehavior: radius > 0 ? Clip.antiAlias : Clip.none,
                        child: child,
                      ),
                    );
                  },
                  child: ValueListenableBuilder<bool>(
                    valueListenable: _isDraggingDown,
                    builder: (context, isDraggingDown, child) {
                      return IgnorePointer(
                        ignoring: isDraggingDown,
                        child: child,
                      );
                    },
                    child: _isMangaMode
                        ? _buildMangaView()
                        : NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollStartNotification) {
                                if (notification.dragDetails != null) {
                                  _isSwipingPage.value = true;
                                }
                              } else if (notification
                                  is ScrollEndNotification) {
                                _isSwipingPage.value = false;
                                _precacheAdjacent(_current);
                                _activeMediaNotifier?.state =
                                    widget.items[_current].id;
                              }
                              return false;
                            },
                            child: PageView.builder(
                              controller: _page,
                              dragStartBehavior: DragStartBehavior.down,
                              itemCount: widget.items.length,
                              onPageChanged: (i) {
                                setState(() {
                                  _current = i;
                                  _isPhotoZoomed = false;
                                  _isDeepZoomed = false;
                                  _isPinching = false;
                                  _transformationController.value =
                                      Matrix4.identity();
                                });
                                _precacheAdjacent(i);
                                if (widget.items.isNotEmpty &&
                                    i < widget.items.length) {
                                  _loadPsdDataIfNeeded(widget.items[i].path);
                                }
                              },
                              physics: (_isCurrentlyZoomed ||
                                      _isPinching ||
                                      _isMultiTouch ||
                                      _activePointers.length >= 2)
                                  ? const NeverScrollableScrollPhysics()
                                  : const PageScrollPhysics(),
                              itemBuilder: (context, index) {
                                final it = widget.items[index];
                                final isCur = index == _current;
                                return ListenableBuilder(
                                  listenable: Listenable.merge(
                                      [_isDraggingDown, _isDismissing]),
                                  builder: (context, child) {
                                    if ((_isDraggingDown.value ||
                                            _isDismissing.value) &&
                                        !isCur) {
                                      return const SizedBox.shrink();
                                    }
                                    return child!;
                                  },
                                  child: RepaintBoundary(
                                    child: Center(
                                      child: ClipRect(
                                        child: isCur
                                            ? InteractiveViewer(
                                                key: ValueKey(
                                                    'iv_${it.id}_${MediaQuery.orientationOf(context)}'),
                                                transformationController:
                                                    _transformationController,
                                                minScale: 1.0,
                                                maxScale: 8.0,
                                                panEnabled:
                                                    _isCurrentlyZoomed &&
                                                        (_psdLoadError[
                                                                it.path] !=
                                                            true),
                                                scaleEnabled:
                                                    (!PsdService.isPsd(
                                                            it.path) ||
                                                        (_psdRenderedBytes[
                                                                    it.path] !=
                                                                null &&
                                                            _psdRenderedBytes[
                                                                    it.path]!
                                                                .isNotEmpty)),
                                                clipBehavior: Clip.hardEdge,
                                                onInteractionStart: (details) {
                                                  _zoomAnimController?.stop();
                                                  if (details.pointerCount >=
                                                      2) {
                                                    _isPinching = true;
                                                  }
                                                },
                                                onInteractionUpdate: (details) {
                                                  final scale =
                                                      _transformationController
                                                          .value
                                                          .getMaxScaleOnAxis();
                                                  final isZoomed = scale > 1.05;
                                                  if (isZoomed !=
                                                      _isPhotoZoomed) {
                                                    setState(() {
                                                      _isPhotoZoomed = isZoomed;
                                                    });
                                                  }
                                                },
                                                onInteractionEnd: (details) {
                                                  _isPinching = false;
                                                  final scale =
                                                      _transformationController
                                                          .value
                                                          .getMaxScaleOnAxis();
                                                  if (scale <= 1.02) {
                                                    _resetPhotoZoom();
                                                  } else {
                                                    final shouldDeepZoom =
                                                        scale > 1.2;
                                                    if ((!_isPhotoZoomed ||
                                                            _isDeepZoomed !=
                                                                shouldDeepZoom) &&
                                                        mounted) {
                                                      setState(() {
                                                        _isPhotoZoomed = true;
                                                        _isDeepZoomed =
                                                            shouldDeepZoom;
                                                      });
                                                    }
                                                  }
                                                },
                                                child: Center(
                                                  child: Hero(
                                                    tag: it.id,
                                                    flightShuttleBuilder: (
                                                      flightContext,
                                                      animation,
                                                      flightDirection,
                                                      fromHeroContext,
                                                      toHeroContext,
                                                    ) =>
                                                        _buildHeroShuttle(
                                                      animation: animation,
                                                      flightDirection:
                                                          flightDirection,
                                                      id: it.id,
                                                      path: it.path,
                                                      psdFallbackBytes:
                                                          _psdRenderedBytes[
                                                              it.path],
                                                      fallbackChild:
                                                          flightDirection ==
                                                                  HeroFlightDirection
                                                                      .push
                                                              ? toHeroContext
                                                                  .widget
                                                              : fromHeroContext
                                                                  .widget,
                                                    ),
                                                    child: _buildPhotoPage(it,
                                                        isCurrent: true),
                                                  ),
                                                ),
                                              )
                                            : Center(
                                                child: _buildPhotoPage(it,
                                                    isCurrent: false),
                                              ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _buildStaggeredBar(
                    context: context,
                    showBars: showBars,
                    isTopBar: true,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black87,
                            Colors.black54,
                            Colors.transparent,
                          ],
                          stops: [0.0, 0.7, 1.0],
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 4),
                          child: Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.arrow_back_ios_new,
                                    color: Colors.white, size: 20),
                                onPressed: () {
                                  if (_page.hasClients && _page.page != null) {
                                    final snapped = _page.page!
                                        .round()
                                        .clamp(0, widget.items.length - 1);
                                    if (_current != snapped) {
                                      _current = snapped;
                                    }
                                    _page.jumpToPage(_current);
                                  }
                                  _isDismissing.value = true;
                                  _activeMediaNotifier?.state = _currentItem.id;
                                  Navigator.of(context).pop();
                                },
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      _isMangaMode && item.albumName.isNotEmpty
                                          ? item.albumName
                                          : MediaUtils.formatViewerDate(
                                              item.date),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _isMangaMode
                                          ? item.name
                                          : MediaUtils.formatViewerTime(
                                              item.date),
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 12,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              if (!widget.isTrash &&
                                  PsdService.isPsd(item.path))
                                IconButton(
                                  icon: Icon(
                                    (_psdHiddenLayers[item.path]?.isNotEmpty ??
                                            false)
                                        ? Icons.layers
                                        : Icons.layers_outlined,
                                    color: Colors.white,
                                    size: 22,
                                  ),
                                  tooltip: 'Layers',
                                  onPressed: () => _openPsdLayerSheet(item),
                                ),
                              if (!item.isVideo &&
                                  !PsdService.isPsd(item.path)) ...[
                                if (_isMangaMode)
                                  IconButton(
                                    key: const ValueKey(
                                        'manga_translation_button'),
                                    icon: Icon(
                                      Icons.translate_rounded,
                                      color: _translationMode != null
                                          ? Theme.of(context)
                                              .colorScheme
                                              .primary
                                          : Colors.white,
                                      size: 22,
                                    ),
                                    tooltip: 'Manga Translation',
                                    onPressed: _showTranslationSheet,
                                  ),
                                IconButton(
                                  icon: Icon(
                                    Icons.auto_stories_rounded,
                                    color: _isMangaMode
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white,
                                    size: 22,
                                  ),
                                  tooltip: context.tr.mangaMode,
                                  onPressed: _toggleMangaMode,
                                ),
                              ],
                              if (!widget.isTrash)
                                IconButton(
                                  icon: const Icon(Icons.info_outline,
                                      color: Colors.white, size: 22),
                                  tooltip: context.tr.details,
                                  onPressed: () =>
                                      showMediaInfoSheet(context, item),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (_isMangaMode)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: IgnorePointer(
                      child: SafeArea(
                        bottom: false,
                        child: AnimatedPadding(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOutCubic,
                          padding: EdgeInsets.only(
                            top: showBars ? 58 : 8,
                            left: showBars ? 0 : 16,
                            right: showBars ? 0 : 16,
                          ),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.easeInOutCubic,
                            alignment: showBars
                                ? Alignment.topCenter
                                : Alignment.topLeft,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.black
                                    .withValues(alpha: showBars ? 0.75 : 0.6),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.18),
                                  width: 0.6,
                                ),
                              ),
                              child: ValueListenableBuilder<int>(
                                valueListenable: _activeMangaPageNotifier,
                                builder: (context, activeIdx, _) {
                                  final mangaList = _mangaItems;
                                  final pageStr = mangaList.isNotEmpty
                                      ? '${activeIdx + 1} / ${mangaList.length}'
                                      : '${_current + 1} / ${widget.items.length}';
                                  return Text(
                                    pageStr,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 0.5,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!_isMangaMode)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: _buildStaggeredBar(
                      context: context,
                      showBars: showBars,
                      isTopBar: false,
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black87,
                              Colors.black54,
                              Colors.transparent,
                            ],
                            stops: [0.0, 0.7, 1.0],
                          ),
                        ),
                        child: SafeArea(
                          top: false,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: widget.isTrash
                                ? Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _ViewerActionButton(
                                        icon: const Icon(Icons.restore,
                                            color: Colors.white, size: 22),
                                        label: context.tr.restore,
                                        onTap: _restoreCurrentItem,
                                      ),
                                      _ViewerActionButton(
                                        icon: const Icon(Icons.info_outline,
                                            color: Colors.white, size: 22),
                                        label: context.tr.details,
                                        onTap: () =>
                                            showMediaInfoSheet(context, item),
                                      ),
                                      _ViewerActionButton(
                                        icon: const Icon(Icons.delete_forever,
                                            color: Colors.white, size: 22),
                                        label: context.tr.delete,
                                        onTap: _deleteCurrentItem,
                                      ),
                                    ],
                                  )
                                : Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceAround,
                                    children: [
                                      _ViewerActionButton(
                                        icon: const Icon(Icons.share_outlined,
                                            color: Colors.white, size: 22),
                                        label: context.tr.share,
                                        onTap: () => ShareService.shareSingle(
                                            item.path,
                                            isVideo: false),
                                      ),
                                      Consumer(
                                        builder: (context, ref, _) {
                                          final isFav = ref.watch(
                                            settingsNotifierProvider.select(
                                              (s) => s.favoriteIds
                                                  .contains(item.id),
                                            ),
                                          );
                                          return _ViewerActionButton(
                                            icon: Icon(
                                              isFav
                                                  ? Icons.favorite
                                                  : Icons.favorite_border,
                                              color: isFav
                                                  ? Colors.redAccent
                                                  : Colors.white,
                                              size: 22,
                                            ),
                                            label: context.tr.favorite,
                                            onTap: () {
                                              HapticFeedback.lightImpact();
                                              final currentFavs =
                                                  Set<String>.from(
                                                ref
                                                    .read(
                                                        settingsNotifierProvider)
                                                    .favoriteIds,
                                              );
                                              if (currentFavs
                                                  .contains(item.id)) {
                                                currentFavs.remove(item.id);
                                              } else {
                                                currentFavs.add(item.id);
                                              }
                                              ref
                                                  .read(settingsNotifierProvider
                                                      .notifier)
                                                  .update(
                                                    (s) => s.copyWith(
                                                        favoriteIds: currentFavs
                                                            .toList()),
                                                  );
                                            },
                                          );
                                        },
                                      ),
                                      _ViewerActionButton(
                                        icon: const Icon(Icons.delete_outline,
                                            color: Colors.white, size: 22),
                                        label: context.tr.delete,
                                        onTap: _deleteCurrentItem,
                                      ),
                                      PopupMenuButton<String>(
                                        tooltip: context.tr.moreOptions,
                                        color: const Color(0xFF222222),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        constraints: const BoxConstraints(
                                            minWidth: 130, maxWidth: 195),
                                        onSelected: (value) async {
                                          if (value == 'slideshow') {
                                            if (_isSlideshowPlaying) {
                                              _stopSlideshow();
                                            } else {
                                              _startSlideshow();
                                            }
                                          } else if (value == 'rename') {
                                            final updated =
                                                await showRenameMediaDialog(
                                                    context, item, ref);
                                            if (updated != null && mounted) {
                                              setState(() {
                                                widget.items[_current] =
                                                    updated;
                                              });
                                            }
                                          } else if (value == 'wallpaper') {
                                            ShareService.setAsWallpaper(
                                                item.path);
                                          } else if (value == 'manga') {
                                            _toggleMangaMode();
                                          }
                                        },
                                        itemBuilder: (context) => [
                                          if (!item.isVideo &&
                                              !PsdService.isPsd(item.path))
                                            PopupMenuItem(
                                              value: 'manga',
                                              height: 40,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 14),
                                              child: Row(
                                                children: [
                                                  Icon(
                                                    Icons.auto_stories_rounded,
                                                    size: 18,
                                                    color: _isMangaMode
                                                        ? Theme.of(context)
                                                            .colorScheme
                                                            .primary
                                                        : Colors.white,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    context.tr.mangaMode,
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 13.5),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          PopupMenuItem(
                                            value: 'slideshow',
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14),
                                            child: Row(
                                              children: [
                                                Icon(
                                                  _isSlideshowPlaying
                                                      ? Icons
                                                          .pause_circle_outline_rounded
                                                      : Icons.slideshow_rounded,
                                                  size: 18,
                                                  color: Colors.white,
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  _isSlideshowPlaying
                                                      ? context.tr.pause
                                                      : context.tr.slideshow,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13.5),
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'rename',
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14),
                                            child: Row(
                                              children: [
                                                const Icon(Icons.edit_outlined,
                                                    size: 18,
                                                    color: Colors.white),
                                                const SizedBox(width: 10),
                                                Text(
                                                  context.tr.rename,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13.5),
                                                ),
                                              ],
                                            ),
                                          ),
                                          PopupMenuItem(
                                            value: 'wallpaper',
                                            height: 40,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                    Icons.wallpaper_outlined,
                                                    size: 18,
                                                    color: Colors.white),
                                                const SizedBox(width: 10),
                                                Text(
                                                  context.tr.setAsWallpaper,
                                                  style: const TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 13.5),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                        child: _ViewerActionButton(
                                          icon: const Icon(Icons.more_vert,
                                              color: Colors.white, size: 22),
                                          label: context.tr.more,
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                        ),
                      ),
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

class _ViewerActionButton extends StatelessWidget {
  const _ViewerActionButton({
    required this.icon,
    required this.label,
    this.onTap,
  });

  final Widget icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return BouncyTap(
      onTap: onTap!,
      child: content,
    );
  }
}
