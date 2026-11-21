import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/physics.dart';

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
import '../../../core/widgets/styled_popup_menu.dart';
import 'widgets/media_info_sheet.dart';
import 'widgets/psd_layer_sheet.dart';
import 'widgets/rename_dialog.dart';
import '../../gallery/presentation/widgets/delete_confirmation_sheet.dart';
import '../../../core/widgets/feedback_pill.dart';
import '../../../core/services/translation/translation_models.dart';
import '../../../core/services/translation/mlkit_translation_engine.dart';
import '../../../core/services/translation/translation_isolate_coordinator.dart';
import 'widgets/manga_translation_overlay.dart';
import '../../../core/services/settings_service.dart';
import 'video_player_screen.dart';

// 4096px cap fits imageCache while staying sharp up to 3x zoom.
ImageProvider displayImage(String path, {int maxDimension = 4096}) =>
    ResizeImage(
      FileImage(File(path)),
      width: maxDimension,
      height: maxDimension,
      policy: ResizeImagePolicy.fit,
    );

/// Screen-fit provider (~1440px) for smooth page swiping.
ImageProvider screenDisplayImage(String path, [int maxDim = 1440]) {
  final mem =
      ThumbnailService.instance.getMemoryPreview(path, maxDimension: maxDim);
  if (mem != null) return MemoryImage(mem);
  final cachedFile =
      ThumbnailService.instance.getCachedPreviewFile(path, maxDimension: maxDim);
  if (cachedFile != null) return FileImage(cachedFile);
  return ResizeImage(
    FileImage(File(path)),
    width: maxDim,
    height: maxDim,
    policy: ResizeImagePolicy.fit,
  );
}

/// Cached thumbnail, shown instantly while the full image decodes.
Widget _thumb(String id, [String? path, Uint8List? psdFallbackBytes]) {
  final hr = ThumbnailService.instance.getMemoryHighResThumbnail(id);
  final mem = hr ?? ThumbnailService.instance.getMemoryThumbnail(id);
  final disk = mem == null
      ? (ThumbnailService.instance.getCachedHighResFile(id) ??
          ThumbnailService.instance.getIndexedDiskFile(id))
      : null;
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
  final disk = mem == null
      ? (ThumbnailService.instance.getCachedHighResFile(id) ??
          ThumbnailService.instance.getIndexedDiskFile(id))
      : null;
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
  final Map<String, GlobalKey> _viewerKeys = {};
  GlobalKey _viewerKeyFor(String id) =>
      _viewerKeys.putIfAbsent(id, GlobalKey.new);
  late bool _isMangaMode;
  late final PageController _mangaPageController;

  TranslationRenderMode? _translationMode;
  List<MediaItem>? _cachedMangaList;
  late final ValueNotifier<int> _activeMangaPageNotifier;
  bool _isScrubbingMangaSlider = false;
  int? _mangaScrubTargetPage;

  late final TranslationIsolateCoordinator _translationCoordinator;
  Timer? _slideshowTimer;
  Timer? _precacheTimer;
  bool _isSlideshowPlaying = false;
  Timer? _videoHandoffTimer;
  bool _didHandoffToVideo = false;
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

    if (!force) {
      final cachedLayers = PsdService.instance.getCachedLayersSync(path);
      if (cachedLayers != null && !_psdLayersCache.containsKey(path)) {
        _psdLayersCache[path] = cachedLayers;
      }

      final cachedRender =
          PsdService.instance.getCachedRenderedPreviewSync(path);
      if (cachedRender != null && cachedRender.isNotEmpty) {
        _psdRenderedBytes[path] = cachedRender;
        _psdRenderComplete[path] = true;
        _psdRendering[path] = false;
        _psdLoadError[path] = false;
        final savedHidden = PsdService.instance.getSavedLayerVisibility(path);
        if (savedHidden != null) {
          _psdHiddenLayers[path] = Set<int>.from(savedHidden);
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
        return;
      }
    }

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
    if (widget.initialMangaMode) {
      final mangaList = _mangaItems;
      final hasValidManga = mangaList.isNotEmpty;
      _isMangaMode = hasValidManga;
      final initialActive = hasValidManga
          ? mangaList.indexOf(_currentItem).clamp(0, mangaList.length - 1)
          : 0;
      _activeMangaPageNotifier = ValueNotifier<int>(initialActive);
      _mangaPageController = PageController(initialPage: initialActive);
    } else {
      _isMangaMode = false;
      _activeMangaPageNotifier = ValueNotifier<int>(0);
      _mangaPageController = PageController(initialPage: 0);
    }
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
    _precacheTimer?.cancel();
    _precacheTimer = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      for (final offset in const [-1, 1]) {
        final target = index + offset;
        if (target >= 0 && target < widget.items.length) {
          final item = widget.items[target];
          if (item.isVideo) continue;
          if (_precachedImagePaths.add(item.path)) {
            if (PsdService.isPsd(item.path)) {
              unawaited(PsdService.instance.prewarmPsdDocument(item.path));
            } else {
              precacheImage(screenDisplayImage(item.path), context);
            }
          }
        }
      }
    });
  }

  @override
  void didUpdateWidget(ImageViewerScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.items != oldWidget.items) {
      _cachedMangaList = null;
    }
  }

  @override
  void dispose() {
    _precacheTimer?.cancel();
    _precacheTimer = null;
    _videoHandoffTimer?.cancel();
    _videoHandoffTimer = null;
    _activeMangaPageNotifier.dispose();
    _translationCoordinator.dispose();
    _mangaPageController.dispose();
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

  void _triggerMangaTranslationForActivePage() {
    _translationCoordinator.cancelPending();
    if (_translationMode == null) return;
    if (widget.items.isEmpty) return;

    final it = _isMangaMode &&
            _activeMangaPageNotifier.value >= 0 &&
            _activeMangaPageNotifier.value < _mangaItems.length
        ? _mangaItems[_activeMangaPageNotifier.value]
        : widget.items[_current.clamp(0, widget.items.length - 1)];

    if (it.isVideo || PsdService.isPsd(it.path)) return;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final w = (it.width != null && it.width! > 0)
        ? it.width!.toDouble()
        : screenWidth;
    final h = (it.height != null && it.height! > 0)
        ? it.height!.toDouble()
        : screenHeight;

    _translationCoordinator.scheduleTranslation(
      imagePath: it.path,
      imageSize: Size(w, h),
      mode: _translationMode!,
      language: TranslationSourceLanguage.auto,
      targetLanguage: TranslationTargetLanguage.english,
      debounceDuration: const Duration(milliseconds: 300),
    );
  }

  Future<void> _setTranslationMode(TranslationRenderMode? mode) async {
    setState(() {
      _translationMode = mode;
    });
    if (mode != null && widget.items.isNotEmpty) {
      final status = MlKitTranslationEngine.instance.lastStatusMessage;
      if (status != null && mounted) {
        showFeedbackPill(
          context,
          message: status,
          icon: Icons.info_outline_rounded,
        );
      }
      _triggerMangaTranslationForActivePage();
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
      backgroundColor: const Color(0xFF161618),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.translate_rounded,
                            color: primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          loc.mangaTranslation,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Colors.white70, size: 20),
                        onPressed: () => Navigator.pop(sheetContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                          width: 1),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: Colors.tealAccent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.dns_outlined,
                            color: Colors.tealAccent,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      loc.engineLmStudio,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.tealAccent
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      loc.modelActive,
                                      style: const TextStyle(
                                        color: Colors.tealAccent,
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 3),
                              Text(
                                SettingsService.instance.settings.lmStudioModel
                                        .isNotEmpty
                                    ? '${SettingsService.instance.settings.lmStudioModel} • ${SettingsService.instance.settings.lmStudioServerUrl}'
                                    : SettingsService
                                        .instance.settings.lmStudioServerUrl,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.6),
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
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
                  if (_translationMode != null) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.redAccent.shade100,
                          side: BorderSide(
                            color: Colors.redAccent.withValues(alpha: 0.25),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.power_settings_new_rounded,
                            size: 16),
                        label: Text(
                          loc.disableTranslation,
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
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
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selected
              ? primary.withValues(alpha: 0.08)
              : Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? primary.withValues(alpha: 0.55)
                : Colors.white.withValues(alpha: 0.08),
            width: selected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: selected
                    ? primary.withValues(alpha: 0.18)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                icon,
                color: selected ? primary : Colors.white70,
                size: 18,
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
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
              color: selected ? primary : Colors.white24,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToCurrentInManga() {
    final mangaList = _mangaItems;
    if (!_mangaPageController.hasClients || mangaList.isEmpty) return;
    final currentItem = _currentItem;
    int mangaIdx = mangaList.indexOf(currentItem);
    if (mangaIdx < 0) mangaIdx = 0;
    _mangaPageController.jumpToPage(mangaIdx);
  }

  void _jumpToMangaPage(
    int targetIndex, {
    bool triggerTranslation = true,
  }) {
    final mangaList = _mangaItems;
    if (mangaList.isEmpty) return;
    final clamped = targetIndex.clamp(0, mangaList.length - 1);
    final changed = _activeMangaPageNotifier.value != clamped;

    _transformationController.value = Matrix4.identity();
    _isPhotoZoomed = false;
    _isDeepZoomed = false;
    _isPinching = false;
    _activeMangaPageNotifier.value = clamped;

    final globalIndex = widget.items.indexOf(mangaList[clamped]);
    if (globalIndex != -1) {
      _current = globalIndex;
      _activeMediaNotifier?.state = mangaList[clamped].id;
      _precacheAdjacent(globalIndex);
    }

    if (_mangaPageController.hasClients && changed) {
      _mangaPageController.jumpToPage(clamped);
    }

    if (mounted) {
      setState(() {});
    }

    if (triggerTranslation && _translationMode != null) {
      _triggerMangaTranslationForActivePage();
    }
  }

  Future<void> _showMangaJumpToPageDialog(int currentIdx, int total) async {
    if (total <= 1) return;
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => _MangaJumpToPageDialog(
        currentPage: currentIdx + 1,
        totalPages: total,
        title: context.tr.goToPage,
        cancelLabel: context.tr.cancel,
        confirmLabel: context.tr.jump,
      ),
    );
    if (picked != null && mounted) {
      _jumpToMangaPage(picked);
    }
  }

  Widget _buildMangaPageJumpBar(BuildContext context, bool showBars) {
    final total = _mangaItems.length;
    if (total <= 1) return const SizedBox.shrink();

    final primary = Theme.of(context).colorScheme.primary;
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: _buildStaggeredBar(
        context: context,
        showBars: showBars,
        isTopBar: false,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: ValueListenableBuilder<int>(
              valueListenable: _activeMangaPageNotifier,
              builder: (context, activeIdx, _) {
                final maxPageIdx = total - 1;
                final displayIdx = (_isScrubbingMangaSlider
                        ? (_mangaScrubTargetPage ?? activeIdx)
                        : activeIdx)
                    .clamp(0, maxPageIdx);

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_isScrubbingMangaSlider)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.85),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.18),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              '${displayIdx + 1}/$total',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ),
                      Container(
                        key: const ValueKey('manga_page_jump_bar'),
                        height: 50,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.16),
                            width: 0.8,
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              key: const ValueKey('manga_prev_page_button'),
                              icon: Icon(
                                Icons.chevron_left_rounded,
                                size: 22,
                                color: displayIdx > 0
                                    ? Colors.white
                                    : Colors.white30,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 34,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: displayIdx > 0
                                  ? () => _jumpToMangaPage(displayIdx - 1)
                                  : null,
                            ),
                            BouncyTap(
                              key: const ValueKey('manga_jump_page_button'),
                              scaleDown: 0.92,
                              onTap: () => _showMangaJumpToPageDialog(
                                displayIdx,
                                total,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 9, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${displayIdx + 1}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: primary,
                                  inactiveTrackColor: Colors.white24,
                                  thumbColor: Colors.white,
                                  overlayColor: primary.withValues(alpha: 0.2),
                                  tickMarkShape: SliderTickMarkShape.noTickMark,
                                  trackHeight: 3.5,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 7,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 15,
                                  ),
                                ),
                                child: Slider(
                                  key: const ValueKey('manga_page_slider'),
                                  min: 0,
                                  max: maxPageIdx.toDouble(),
                                  divisions: maxPageIdx,
                                  value: displayIdx.toDouble(),
                                  onChangeStart: (v) {
                                    setState(() {
                                      _isScrubbingMangaSlider = true;
                                      _mangaScrubTargetPage =
                                          v.round().clamp(0, maxPageIdx);
                                    });
                                  },
                                  onChanged: (v) {
                                    final target =
                                        v.round().clamp(0, maxPageIdx);
                                    if (target != _mangaScrubTargetPage) {
                                      HapticFeedback.selectionClick();
                                      _mangaScrubTargetPage = target;
                                      _jumpToMangaPage(
                                        target,
                                        triggerTranslation: false,
                                      );
                                    }
                                  },
                                  onChangeEnd: (v) {
                                    final target =
                                        v.round().clamp(0, maxPageIdx);
                                    setState(() {
                                      _isScrubbingMangaSlider = false;
                                      _mangaScrubTargetPage = null;
                                    });
                                    _jumpToMangaPage(
                                      target,
                                      triggerTranslation: true,
                                    );
                                  },
                                ),
                              ),
                            ),
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => _showMangaJumpToPageDialog(
                                displayIdx,
                                total,
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 6),
                                child: Text(
                                  '$total',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    fontFeatures: [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              key: const ValueKey('manga_next_page_button'),
                              icon: Icon(
                                Icons.chevron_right_rounded,
                                size: 22,
                                color: displayIdx < maxPageIdx
                                    ? Colors.white
                                    : Colors.white30,
                              ),
                              constraints: const BoxConstraints(
                                minWidth: 34,
                                minHeight: 34,
                              ),
                              padding: EdgeInsets.zero,
                              onPressed: displayIdx < maxPageIdx
                                  ? () => _jumpToMangaPage(displayIdx + 1)
                                  : null,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
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
        _triggerMangaTranslationForActivePage();
      });
    }
  }

  Widget _buildTranslatingOverlay(String imagePath) {
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder<bool>(
          valueListenable:
              _translationCoordinator.getLoadingNotifier(imagePath),
          builder: (context, isLoading, _) {
            if (!isLoading) return const SizedBox.shrink();
            return Center(
              child: _MangaTranslatingIndicator(
                label: context.tr.translatingPage,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMangaView() {
    final mangaList = _mangaItems;
    return PageView.builder(
      controller: _mangaPageController,
      physics: (_isCurrentlyZoomed ||
              _isPinching ||
              _isMultiTouch ||
              _activePointers.length >= 2)
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      itemCount: mangaList.length,
      onPageChanged: (index) {
        setState(() {
          _activeMangaPageNotifier.value = index;
          _isPhotoZoomed = false;
          _isDeepZoomed = false;
          _isPinching = false;
          _transformationController.value = Matrix4.identity();
          final globalIndex = widget.items.indexOf(mangaList[index]);
          if (globalIndex != -1 && globalIndex != _current) {
            _current = globalIndex;
            _activeMediaNotifier?.state = mangaList[index].id;
          }
        });
        if (!_isScrubbingMangaSlider) {
          _triggerMangaTranslationForActivePage();
        }
      },
      itemBuilder: (context, index) {
        final it = mangaList[index];
        return RepaintBoundary(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ValueListenableBuilder<int>(
                valueListenable: _activeMangaPageNotifier,
                builder: (context, activeIndex, _) {
                  final isActive = index == activeIndex;
                  final Widget imageWidget = Image(
                    image: (isActive && _isDeepZoomed)
                        ? displayImage(it.path, maxDimension: 4096)
                        : screenDisplayImage(it.path),
                    fit: BoxFit.contain,
                    width: double.infinity,
                    height: double.infinity,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                    frameBuilder:
                        (context, child, frame, wasSynchronouslyLoaded) {
                      if (wasSynchronouslyLoaded || frame != null) return child;
                      if (_isDeepZoomed) {
                        return Image(
                          image: screenDisplayImage(it.path),
                          fit: BoxFit.contain,
                          width: double.infinity,
                          height: double.infinity,
                          gaplessPlayback: true,
                          filterQuality: FilterQuality.medium,
                        );
                      }
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

                  final Widget pageContent = Stack(
                    fit: StackFit.expand,
                    children: [
                      imageWidget,
                      if (_translationMode != null)
                        Positioned.fill(
                          child: ValueListenableBuilder<TranslationResult?>(
                            valueListenable: _translationCoordinator
                                .getResultNotifier(it.path),
                            builder: (context, result, _) {
                              if (result == null ||
                                  !result.isSuccess ||
                                  result.blocks.isEmpty) {
                                return const SizedBox.shrink();
                              }
                               return MangaTranslationOverlay(
                                 result: result,
                                 mode: _translationMode!,
                                 fontScale: ref.watch(
                                   settingsNotifierProvider
                                       .select((s) => s.translationFontScale),
                                 ),
                                 overlayStyle: ref.watch(
                                   settingsNotifierProvider.select(
                                       (s) => s.translationOverlayStyle),
                                 ),
                               );
                            },
                          ),
                        ),
                    ],
                  );

                  if (!isActive) {
                    return InteractiveViewer(
                      minScale: 1.0,
                      maxScale: 6.0,
                      panEnabled: false,
                      child: pageContent,
                    );
                  }

                  return KeyedSubtree(
                    key: _viewerKeyFor('manga_${it.id}'),
                    child: InteractiveViewer(
                      key: ValueKey('manga_iv_${it.id}'),
                    transformationController: _transformationController,
                    minScale: 1.0,
                    maxScale: 6.0,
                    panEnabled: _isCurrentlyZoomed,
                    clipBehavior: Clip.hardEdge,
                    onInteractionStart: (details) {
                      _zoomAnimController?.stop();
                      if (details.pointerCount >= 2) {
                        _isPinching = true;
                      }
                    },
                    onInteractionUpdate: (details) {
                      final scale =
                          _transformationController.value.getMaxScaleOnAxis();
                      final isZoomed = scale > 1.05;
                      if (isZoomed != _isPhotoZoomed) {
                        setState(() {
                          _isPhotoZoomed = isZoomed;
                        });
                      }
                    },
                    onInteractionEnd: (details) {
                      _isPinching = false;
                      final scale =
                          _transformationController.value.getMaxScaleOnAxis();
                      if (scale <= 1.02) {
                        _resetPhotoZoom();
                      } else {
                        final shouldDeepZoom = scale > 1.2;
                        if ((!_isPhotoZoomed ||
                                _isDeepZoomed != shouldDeepZoom) &&
                            mounted) {
                          setState(() {
                            _isPhotoZoomed = true;
                            _isDeepZoomed = shouldDeepZoom;
                          });
                        }
                      }
                    },
                    child: pageContent,
                    ),
                  );
                },
              ),
              if (_translationMode != null) _buildTranslatingOverlay(it.path),
            ],
          ),
        );
      },
    );
  }

  List<MediaItem> get _mangaItems => _cachedMangaList ??= widget.items
      .where((it) => !it.isVideo && !PsdService.isPsd(it.path))
      .toList();

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

  GlobalKey _activeViewerKey() {
    if (_isMangaMode && _mangaItems.isNotEmpty) {
      final idx =
          _activeMangaPageNotifier.value.clamp(0, _mangaItems.length - 1);
      return _viewerKeyFor('manga_${_mangaItems[idx].id}');
    }
    return _viewerKeyFor('photo_${_currentItem.id}');
  }

  Matrix4 _clampedFocalMatrix(
    Offset focal,
    double targetScale, {
    Size? viewportSize,
  }) {
    return computeClampedFocalZoomMatrix(
      currentMatrix: _transformationController.value,
      localFocal: focal,
      viewportSize: viewportSize ?? (context.size ?? MediaQuery.sizeOf(context)),
      targetScale: targetScale,
    );
  }

  void _animateZoomToScale(
    Matrix4 endMatrix,
    double targetScale, {
    Duration duration = const Duration(milliseconds: 280),
  }) {
    _zoomAnimController?.stop();
    _zoomAnimController?.dispose();

    _zoomAnimController = AnimationController(
      vsync: this,
      duration: duration,
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

    final bool willReset = targetScale <= 1.05;
    _zoomAnimController!.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        if (willReset) {
          _transformationController.value = Matrix4.identity();
        }
        setState(() {
          _isPhotoZoomed = !willReset;
          _isDeepZoomed = targetScale > 1.2;
        });
      }
    });

    _zoomAnimController!.forward();
  }

  void _zoomToPosition(Offset tapPos, {Offset? globalPos}) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final double targetScale = currentScale > 1.05 ? 1.0 : 3.0;

    final (localFocal, viewportSize) = resolveViewerFocalAndSize(
      viewerKey: _activeViewerKey(),
      fallbackLocalPos: tapPos,
      fallbackSize: context.size ?? MediaQuery.sizeOf(context),
      globalPos: globalPos,
    );
    final Matrix4 endMatrix = _clampedFocalMatrix(
      localFocal,
      targetScale,
      viewportSize: viewportSize,
    );
    HapticFeedback.lightImpact();
    _animateZoomToScale(endMatrix, targetScale);
  }

  void _stepZoom(double factor, {bool reset = false}) {
    final currentScale = _transformationController.value.getMaxScaleOnAxis();
    final double targetScale =
        reset ? 1.0 : (currentScale * factor).clamp(1.0, 6.0);
    if (targetScale <= 1.05) {
      _resetPhotoZoom();
      return;
    }
    if ((targetScale - currentScale).abs() < 0.01) return;

    final (_, viewportSize) = resolveViewerFocalAndSize(
      viewerKey: _activeViewerKey(),
      fallbackLocalPos: Offset.zero,
      fallbackSize: context.size ?? MediaQuery.sizeOf(context),
    );
    final focal = Offset(viewportSize.width / 2.0, viewportSize.height / 2.0);
    final Matrix4 endMatrix = _clampedFocalMatrix(
      focal,
      targetScale,
      viewportSize: viewportSize,
    );
    HapticFeedback.selectionClick();
    _animateZoomToScale(
      endMatrix,
      targetScale,
      duration: const Duration(milliseconds: 220),
    );
  }

  void _scheduleVideoHandoff() {
    _videoHandoffTimer?.cancel();
    if (!mounted ||
        _didHandoffToVideo ||
        _isMangaMode ||
        _isSlideshowPlaying ||
        _isDraggingDown.value ||
        _isDismissing.value) {
      return;
    }
    if (_current < 0 || _current >= widget.items.length) return;
    if (!widget.items[_current].isVideo) return;
    _videoHandoffTimer = Timer(const Duration(milliseconds: 220), () {
      if (!mounted || _isSlideshowPlaying) return;
      _handoffToVideoPlayer(forcePlay: false);
    });
  }

  void _handoffToVideoPlayer({required bool forcePlay}) {
    if (!mounted ||
        _didHandoffToVideo ||
        _isMangaMode ||
        _isDismissing.value) {
      return;
    }
    if (_current < 0 || _current >= widget.items.length) return;
    final current = widget.items[_current];
    if (!current.isVideo) return;
    _videoHandoffTimer?.cancel();
    _didHandoffToVideo = true;
    _activeMediaNotifier?.state = current.id;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        opaque: false,
        barrierColor: Colors.transparent,
        transitionDuration: Duration.zero,
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => VideoPlayerScreen(
          items: widget.items,
          initialIndex: _current,
          isTrash: widget.isTrash,
          startSlideshow: _isSlideshowPlaying,
          forceAutoPlay: forcePlay,
        ),
      ),
    );
  }

  void _handleDoubleTap() {
    if (_doubleTapDetails == null || _currentItem.isVideo) return;
    _zoomToPosition(
      _doubleTapDetails!.localPosition,
      globalPos: _doubleTapDetails!.globalPosition,
    );
  }

  Widget _buildPhotoPage(MediaItem it, {bool isCurrent = false}) {
    if (it.isVideo) {
      final thumbRatio =
          ThumbnailService.instance.getThumbnailAspectRatio(it.id);
      final ar = (thumbRatio != null && thumbRatio > 0)
          ? thumbRatio
          : (it.width != null &&
                  it.height != null &&
                  it.width! > 0 &&
                  it.height! > 0)
              ? (it.width! / it.height!)
              : null;

      Widget content = Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          SizedBox.expand(child: _thumb(it.id, it.path)),
          Center(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isCurrent
                  ? () => _handoffToVideoPlayer(forcePlay: true)
                  : null,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.35),
                ),
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ),
        ],
      );

      if (ar != null && ar > 0) {
        content = AspectRatio(
          aspectRatio: ar,
          child: content,
        );
      }

      return content;
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
        if (_isDeepZoomed) {
          return Image(
            image: screenDisplayImage(it.path),
            fit: BoxFit.contain,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          );
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
    } else {
      content = SizedBox.expand(child: content);
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
              final bool wasPinching = _isPinching;
              _isMultiTouch = true;
              _isPinching = true;
              _startDragY = null;
              _startDragX = null;
              if (_drag.value != Offset.zero) _setDrag(Offset.zero);
              if (mounted && _isMangaMode && !wasPinching) {
                setState(() {});
              }
              return;
            }
            if (_isMangaMode) {
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
            if (_activePointers.length >= 2 || _isCurrentlyZoomed) {
              final bool wasPinching = _isPinching;
              _isMultiTouch = true;
              _isPinching = true;
              if (mounted && _isMangaMode && !wasPinching) {
                setState(() {});
              }
            }
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
              final wasPinching = _isPinching;
              _isMultiTouch = false;
              _isPinching = false;
              _isSwipingHorizontal = false;
              _startDragY = null;
              _startDragX = null;
              if (_isMangaMode) {
                if (_drag.value != Offset.zero) _setDrag(Offset.zero);
                if (mounted && wasPinching) {
                  setState(() {});
                }
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
              final wasPinching = _isPinching;
              _isMultiTouch = false;
              _isPinching = false;
              _isSwipingHorizontal = false;
              _startDragY = null;
              _startDragX = null;
              if (_isMangaMode) {
                if (_drag.value != Offset.zero) _setDrag(Offset.zero);
                if (mounted && wasPinching) {
                  setState(() {});
                }
                return;
              }
              if (_drag.value != Offset.zero) {
                _springBack(0);
              } else {
                _setDrag(Offset.zero);
              }
            }
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_drag.value.dy < 10) {
                      _toggleBars();
                    }
                  },
                  onDoubleTapDown: item.isVideo
                      ? null
                      : (details) {
                          _doubleTapDetails = details;
                        },
                  onDoubleTap: item.isVideo ? null : _handleDoubleTap,
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
                          final s =
                              (1.0 - (d.dy / 1000.0) * 0.28).clamp(0.72, 1.0);
                          final radius =
                              (d.dy > 0 ? (d.dy / 12.0).clamp(0.0, 20.0) : 0.0);
                          return Transform(
                            alignment: Alignment.center,
                            transform: Matrix4.translationValues(d.dx, d.dy, 0)
                              ..scaleByDouble(s, s, 1.0, 1.0),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(radius),
                              clipBehavior:
                                  radius > 0 ? Clip.antiAlias : Clip.none,
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
                                    if (notification
                                        is ScrollStartNotification) {
                                      if (notification.dragDetails != null) {
                                        _isSwipingPage.value = true;
                                        _videoHandoffTimer?.cancel();
                                      }
                                    } else if (notification
                                        is ScrollEndNotification) {
                                      _isSwipingPage.value = false;
                                      _precacheAdjacent(_current);
                                      _activeMediaNotifier?.state =
                                          widget.items[_current].id;
                                      _scheduleVideoHandoff();
                                    }
                                    return false;
                                  },
                                  child: PageView.builder(
                                    controller: _page,
                                    dragStartBehavior: DragStartBehavior.down,
                                    itemCount: widget.items.length,
                                    onPageChanged: (i) {
                                      _videoHandoffTimer?.cancel();
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
                                        _loadPsdDataIfNeeded(
                                            widget.items[i].path);
                                      }
                                      if (_translationMode != null) {
                                        _triggerMangaTranslationForActivePage();
                                      }
                                      _scheduleVideoHandoff();
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
                                      return Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          ListenableBuilder(
                                            listenable: Listenable.merge([
                                              _isDraggingDown,
                                              _isDismissing
                                            ]),
                                            builder: (context, child) {
                                              if ((_isDraggingDown.value ||
                                                      _isDismissing.value) &&
                                                  !isCur) {
                                                return const SizedBox.shrink();
                                              }
                                              return child!;
                                            },
                                            child: RepaintBoundary(
                                              child: ClipRect(
                                                child: isCur
                                                    ? KeyedSubtree(
                                                        key: _viewerKeyFor(
                                                            'photo_${it.id}'),
                                                        child:
                                                            InteractiveViewer(
                                                          key: ValueKey(
                                                              'iv_${it.id}_${MediaQuery.orientationOf(context)}'),
                                                          transformationController:
                                                              _transformationController,
                                                          minScale: 1.0,
                                                          maxScale: 8.0,
                                                          panEnabled:
                                                              !it.isVideo &&
                                                                  _isCurrentlyZoomed &&
                                                                  (_psdLoadError[
                                                                          it.path] !=
                                                                      true),
                                                          scaleEnabled: !it
                                                                  .isVideo &&
                                                              (!PsdService
                                                                      .isPsd(it
                                                                          .path) ||
                                                                  (_psdRenderedBytes[it
                                                                              .path] !=
                                                                          null &&
                                                                      _psdRenderedBytes[
                                                                              it.path]!
                                                                          .isNotEmpty)),
                                                          clipBehavior:
                                                              Clip.hardEdge,
                                                          onInteractionStart:
                                                              (details) {
                                                            _zoomAnimController
                                                                ?.stop();
                                                            if (details
                                                                    .pointerCount >=
                                                                2) {
                                                              _isPinching =
                                                                  true;
                                                            }
                                                          },
                                                          onInteractionUpdate:
                                                              (details) {
                                                            final scale =
                                                                _transformationController
                                                                    .value
                                                                    .getMaxScaleOnAxis();
                                                            final isZoomed =
                                                                scale > 1.05;
                                                            if (isZoomed !=
                                                                _isPhotoZoomed) {
                                                              setState(() {
                                                                _isPhotoZoomed =
                                                                    isZoomed;
                                                              });
                                                            }
                                                          },
                                                          onInteractionEnd:
                                                              (details) {
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
                                                                  _isPhotoZoomed =
                                                                      true;
                                                                  _isDeepZoomed =
                                                                      shouldDeepZoom;
                                                                });
                                                              }
                                                            }
                                                          },
                                                          child:
                                                              SizedBox.expand(
                                                            child: Center(
                                                              child: Stack(
                                                                alignment:
                                                                    Alignment
                                                                        .center,
                                                                children: [
                                                                  Hero(
                                                                    tag: it.id,
                                                                    flightShuttleBuilder:
                                                                        (
                                                                      flightContext,
                                                                      animation,
                                                                      flightDirection,
                                                                      fromHeroContext,
                                                                      toHeroContext,
                                                                    ) =>
                                                                            _buildHeroShuttle(
                                                                      animation:
                                                                          animation,
                                                                      flightDirection:
                                                                          flightDirection,
                                                                      id: it.id,
                                                                      path: it
                                                                          .path,
                                                                      psdFallbackBytes:
                                                                          _psdRenderedBytes[
                                                                                  it.path] ??
                                                                              PsdService.instance.getCachedRenderedPreviewSync(it.path),
                                                                      fallbackChild: flightDirection ==
                                                                              HeroFlightDirection
                                                                                  .push
                                                                          ? toHeroContext
                                                                              .widget
                                                                          : fromHeroContext
                                                                              .widget,
                                                                    ),
                                                                    child: _buildPhotoPage(
                                                                        it,
                                                                        isCurrent:
                                                                            true),
                                                                  ),
                                                                  if (_translationMode !=
                                                                          null &&
                                                                      !it.isVideo &&
                                                                      !PsdService
                                                                          .isPsd(it
                                                                              .path))
                                                                    Positioned
                                                                        .fill(
                                                                      child: ValueListenableBuilder<
                                                                          TranslationResult?>(
                                                                        valueListenable:
                                                                            _translationCoordinator
                                                                                .getResultNotifier(it.path),
                                                                        builder:
                                                                            (context,
                                                                                result,
                                                                                _) {
                                                                          if (result ==
                                                                                  null ||
                                                                              !result
                                                                                  .isSuccess ||
                                                                              result
                                                                                  .blocks
                                                                                  .isEmpty) {
                                                                            return const SizedBox
                                                                                .shrink();
                                                                          }
                                                                          return MangaTranslationOverlay(
                                                                            result:
                                                                                result,
                                                                            mode:
                                                                                _translationMode!,
                                                                            fontScale: ref.watch(
                                                                              settingsNotifierProvider.select(
                                                                                  (s) => s.translationFontScale),
                                                                            ),
                                                                            overlayStyle: ref.watch(
                                                                              settingsNotifierProvider.select(
                                                                                  (s) => s.translationOverlayStyle),
                                                                            ),
                                                                          );
                                                                        },
                                                                      ),
                                                                    ),
                                                                ],
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                      )
                                                    : Center(
                                                        child: _buildPhotoPage(
                                                            it,
                                                            isCurrent: false),
                                                      ),
                                              ),
                                            ),
                                          ),
                                          if (_translationMode != null && isCur)
                                            _buildTranslatingOverlay(it.path),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                        ),
                      ),
                    ],
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
                            if (!widget.isTrash && PsdService.isPsd(item.path))
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
                                        ? Theme.of(context).colorScheme.primary
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
              if (_isMangaMode)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  right: 16,
                  bottom: (showBars && _mangaItems.length > 1) ? 80 : 20,
                  child: SafeArea(
                    top: false,
                    left: false,
                    child: ValueListenableBuilder<Matrix4>(
                      valueListenable: _transformationController,
                      builder: (context, matrix, _) {
                        final scale = matrix.getMaxScaleOnAxis();
                        final isZoomed = scale > 1.05;
                        final visible =
                            _barsVisible || _isCurrentlyZoomed || isZoomed;
                        final canZoomIn = scale < 5.95;
                        return IgnorePointer(
                          ignoring: !visible,
                          child: AnimatedOpacity(
                            opacity: visible ? 1.0 : 0.0,
                            duration: const Duration(milliseconds: 200),
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {},
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.72),
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.18),
                                    width: 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      key: const ValueKey(
                                          'manga_zoom_out_button'),
                                      icon: Icon(
                                        Icons.remove_rounded,
                                        size: 18,
                                        color: isZoomed
                                            ? Colors.white
                                            : Colors.white38,
                                      ),
                                      tooltip: 'Zoom out',
                                      constraints: const BoxConstraints(
                                        minWidth: 34,
                                        minHeight: 34,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: isZoomed
                                          ? () => _stepZoom(1 / 1.5)
                                          : null,
                                    ),
                                    GestureDetector(
                                      key: const ValueKey(
                                          'manga_zoom_reset_button'),
                                      behavior: HitTestBehavior.opaque,
                                      onTap: isZoomed ? _resetPhotoZoom : () {},
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 6),
                                        child: Text(
                                          '${scale.toStringAsFixed(1)}x',
                                          style: TextStyle(
                                            color: isZoomed
                                                ? Theme.of(context)
                                                    .colorScheme
                                                    .primary
                                                : Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      key: const ValueKey(
                                          'manga_zoom_in_button'),
                                      icon: Icon(
                                        Icons.add_rounded,
                                        size: 18,
                                        color: canZoomIn
                                            ? Colors.white
                                            : Colors.white38,
                                      ),
                                      tooltip: 'Zoom in',
                                      constraints: const BoxConstraints(
                                        minWidth: 34,
                                        minHeight: 34,
                                      ),
                                      padding: EdgeInsets.zero,
                                      onPressed: canZoomIn
                                          ? () => _stepZoom(1.5)
                                          : null,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (_isMangaMode && _mangaItems.length > 1)
                _buildMangaPageJumpBar(context, showBars),
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
                                            (s) =>
                                                s.favoriteIds.contains(item.id),
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
                                            if (currentFavs.contains(item.id)) {
                                              currentFavs.remove(item.id);
                                            } else {
                                              currentFavs.add(item.id);
                                            }
                                            ref
                                                .read(settingsNotifierProvider
                                                    .notifier)
                                                .update(
                                                  (s) => s.copyWith(
                                                      favoriteIds:
                                                          currentFavs.toList()),
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
                                    StyledMoreMenuButton<String>(
                                      tooltip: context.tr.moreOptions,
                                      placement: StyledMenuPlacement.bottomBar,
                                      forceDark: true,
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
                                              widget.items[_current] = updated;
                                            });
                                          }
                                        } else if (value == 'wallpaper') {
                                          ShareService.setAsWallpaper(
                                              item.path);
                                        } else if (value == 'manga') {
                                          _toggleMangaMode();
                                        }
                                      },
                                      actions: [
                                        if (!item.isVideo &&
                                            !PsdService.isPsd(item.path))
                                          StyledMenuAction(
                                            value: 'manga',
                                            icon: Icons.auto_stories_rounded,
                                            label: context.tr.mangaMode,
                                            isActive: _isMangaMode,
                                          ),
                                        StyledMenuAction(
                                          value: 'slideshow',
                                          icon: _isSlideshowPlaying
                                              ? Icons
                                                  .pause_circle_outline_rounded
                                              : Icons.slideshow_rounded,
                                          label: _isSlideshowPlaying
                                              ? context.tr.pause
                                              : context.tr.slideshow,
                                        ),
                                        StyledMenuAction(
                                          value: 'rename',
                                          icon: Icons.edit_outlined,
                                          label: context.tr.rename,
                                        ),
                                        StyledMenuAction(
                                          value: 'wallpaper',
                                          icon: Icons.wallpaper_outlined,
                                          label: context.tr.setAsWallpaper,
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

@visibleForTesting
Widget buildTranslatingIndicatorForTest(String label) =>
    Center(child: _MangaTranslatingIndicator(label: label));

class _MangaTranslatingIndicator extends StatefulWidget {
  const _MangaTranslatingIndicator({required this.label});

  final String label;

  @override
  State<_MangaTranslatingIndicator> createState() =>
      _MangaTranslatingIndicatorState();
}

class _MangaTranslatingIndicatorState extends State<_MangaTranslatingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('manga_translating_indicator'),
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 28,
          height: 28,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return CustomPaint(
                painter: _OutlinedSpinnerPainter(_controller.value),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Stack(
          alignment: Alignment.center,
          children: [
            ExcludeSemantics(
              child: Text(
                widget.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3.8
                    ..strokeJoin = StrokeJoin.round
                    ..color = Colors.black,
                ),
              ),
            ),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                shadows: [
                  Shadow(color: Colors.black87, blurRadius: 4),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OutlinedSpinnerPainter extends CustomPainter {
  const _OutlinedSpinnerPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const outerStrokeWidth = 5.5;
    const innerStrokeWidth = 2.6;
    const strokeInset = outerStrokeWidth / 2;
    final rect = Rect.fromLTWH(
      strokeInset,
      strokeInset,
      size.width - strokeInset * 2,
      size.height - strokeInset * 2,
    );
    final startAngle = progress * 2 * math.pi - math.pi / 2;
    const sweepAngle = (240 / 360) * 2 * math.pi;

    final outlinePaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.9)
      ..strokeWidth = outerStrokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = innerStrokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(rect, startAngle, sweepAngle, false, outlinePaint);
    canvas.drawArc(rect, startAngle, sweepAngle, false, fillPaint);
  }

  @override
  bool shouldRepaint(_OutlinedSpinnerPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

class _MangaJumpToPageDialog extends StatefulWidget {
  const _MangaJumpToPageDialog({
    required this.currentPage,
    required this.totalPages,
    required this.title,
    required this.cancelLabel,
    required this.confirmLabel,
  });

  final int currentPage;
  final int totalPages;
  final String title;
  final String cancelLabel;
  final String confirmLabel;

  @override
  State<_MangaJumpToPageDialog> createState() => _MangaJumpToPageDialogState();
}

class _MangaJumpToPageDialogState extends State<_MangaJumpToPageDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final initialText = '${widget.currentPage}';
    _controller = TextEditingController(text: initialText)
      ..selection = TextSelection(
        baseOffset: 0,
        extentOffset: initialText.length,
      );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = int.tryParse(_controller.text.trim());
    if (parsed == null) {
      Navigator.of(context).pop();
      return;
    }
    final targetIndex = (parsed - 1).clamp(0, widget.totalPages - 1);
    Navigator.of(context).pop(targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return AlertDialog(
      backgroundColor: const Color(0xFF1A1B20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: Colors.white.withValues(alpha: 0.14),
          width: 0.8,
        ),
      ),
      title: Text(
        widget.title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: TextField(
        key: const ValueKey('manga_jump_page_input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        textInputAction: TextInputAction.go,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          hintText: '1 - ${widget.totalPages}',
          hintStyle: const TextStyle(color: Colors.white38),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: primary, width: 1.5),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            widget.cancelLabel,
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        FilledButton(
          key: const ValueKey('manga_jump_page_confirm'),
          onPressed: _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
