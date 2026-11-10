import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../../core/services/translation/gguf_local_llm_engine.dart';
import '../../../core/services/translation/mlkit_translation_engine.dart';
import '../../../core/services/translation/translation_models.dart';
import '../../../core/localization/app_language.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../core/models/settings_model.dart';
import '../../../core/enums/thumbnail_crop_style.dart';
import '../../../core/enums/timeline_grouping.dart';
import '../../../core/enums/trash_cleanup_interval.dart';
import '../../../core/enums/startup_screen.dart';
import '../../../core/enums/video_double_tap_action.dart';
import '../../../core/providers/media_provider.dart';
import '../../../core/providers/settings_provider.dart';
import '../../../core/services/folder_picker_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/services/thumbnail_service.dart';
import '../../../core/widgets/bouncy_tap.dart';
import 'widgets/developer_about_card.dart';
import 'widgets/modern_theme_grid.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen>
    with WidgetsBindingObserver {
  String _cacheSizeStr = 'Calculating...';
  bool _hasManageStorage = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCacheSize();
    _checkManageStoragePermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkManageStoragePermission();
      _loadCacheSize();
    }
  }

  Future<void> _checkManageStoragePermission() async {
    final granted =
        await PermissionService.instance.hasManageStoragePermission();
    if (mounted && _hasManageStorage != granted) {
      setState(() => _hasManageStorage = granted);
    }
  }

  Future<void> _loadCacheSize() async {
    final sizeStr = await ThumbnailService.instance.getFormattedCacheSize();
    if (mounted) {
      setState(() => _cacheSizeStr = sizeStr);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final settings = ref.watch(settingsNotifierProvider);

    void patch(SettingsModel Function(SettingsModel) fn) {
      ref.read(settingsNotifierProvider.notifier).update(fn);
    }

    const availableThemeModes = [
      AppThemeMode.system,
      AppThemeMode.cleanLight,
      AppThemeMode.light,
      AppThemeMode.amoledPure,
      AppThemeMode.amoledSnowfall,
      AppThemeMode.amoledMidnight,
      AppThemeMode.amoledSakura,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr.settings,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        scrolledUnderElevation: 0,
      ),
      body: Theme(
        data: Theme.of(context).copyWith(
          splashFactory: NoSplash.splashFactory,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
        ),
        child: ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 32),
          children: [
            _SectionHeader(title: context.tr.appearance),
            _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      BouncyTap(
                        scaleDown: 0.985,
                        onTap: () async {
                          final chosen = await _showModernThemeDialog(
                            context,
                            settings.themeMode,
                            availableThemeModes,
                          );
                          if (chosen != null) {
                            patch((s) => s.copyWith(themeMode: chosen));
                          }
                        },
                        child: Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: cs.primary
                                    .withValues(alpha: isDark ? 0.14 : 0.10),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(
                                Icons.palette_outlined,
                                color: cs.primary,
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr.theme,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w500,
                                      color: cs.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    context.tr
                                        .themeModeLabel(settings.themeMode),
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 20,
                              color:
                                  cs.onSurfaceVariant.withValues(alpha: 0.38),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      ModernThemeGrid(
                        currentTheme: settings.themeMode,
                        onThemeSelected: (chosen) {
                          patch((s) => s.copyWith(themeMode: chosen));
                        },
                      ),
                    ],
                  ),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.translate_rounded,
                  title: context.tr.language,
                  subtitle: settings.language.nativeName,
                  onTap: () async {
                    final chosen = await _showModernLanguageDialog(
                      context,
                      settings.language,
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(language: chosen));
                    }
                  },
                ),
              ],
            ),
            _SectionHeader(title: context.tr.gridAndLayout),
            _SettingsCard(
              children: [
                _ModernTile(
                  icon: Icons.grid_view_rounded,
                  title: context.tr.gridColumns,
                  subtitle: context.tr.columnsCount(settings.gridColumns),
                  onTap: () async {
                    final chosen = await _showModernGridColumnsDialog(
                      context,
                      settings.gridColumns,
                      isAlbum: false,
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(gridColumns: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.photo_library_outlined,
                  title: context.tr.albumsGridColumns,
                  subtitle: context.tr.columnsCount(settings.albumGridColumns),
                  onTap: () async {
                    final chosen = await _showModernGridColumnsDialog(
                      context,
                      settings.albumGridColumns,
                      isAlbum: true,
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(albumGridColumns: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.aspect_ratio_rounded,
                  title: context.tr.thumbnailCropStyle,
                  subtitle: context.tr
                      .thumbnailCropStyleLabel(settings.thumbnailCropStyle),
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<ThumbnailCropStyle>(
                      context,
                      title: context.tr.thumbnailCropStyle,
                      subtitle: context.tr.chooseVisualMode,
                      headerIcon: Icons.aspect_ratio_rounded,
                      currentValue: settings.thumbnailCropStyle,
                      options: [
                        _OptionItem(
                          value: ThumbnailCropStyle.square,
                          title: context.tr.cropSquare,
                          icon: Icons.crop_square_rounded,
                        ),
                        _OptionItem(
                          value: ThumbnailCropStyle.adaptive,
                          title: context.tr.cropAdaptive,
                          icon: Icons.aspect_ratio_rounded,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(thumbnailCropStyle: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.view_agenda_outlined,
                  title: context.tr.timelineGrouping,
                  subtitle: context.tr
                      .timelineGroupingLabel(settings.timelineGrouping),
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<TimelineGrouping>(
                      context,
                      title: context.tr.timelineGrouping,
                      subtitle: context.tr.chooseVisualMode,
                      headerIcon: Icons.view_agenda_outlined,
                      currentValue: settings.timelineGrouping,
                      options: [
                        _OptionItem(
                          value: TimelineGrouping.continuous,
                          title: context.tr.groupContinuous,
                          icon: Icons.view_agenda_outlined,
                        ),
                        _OptionItem(
                          value: TimelineGrouping.daily,
                          title: context.tr.groupDaily,
                          icon: Icons.calendar_today_outlined,
                        ),
                        _OptionItem(
                          value: TimelineGrouping.monthly,
                          title: context.tr.groupMonthly,
                          icon: Icons.calendar_month_outlined,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(timelineGrouping: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.badge_outlined,
                  title: context.tr.showDurationBadges,
                  subtitle: context.tr.showDurationBadgesSubtitle,
                  value: settings.showBadges,
                  onChanged: (v) => patch((s) => s.copyWith(showBadges: v)),
                ),
              ],
            ),
            _SectionHeader(title: context.tr.playback),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.play_circle_outline_rounded,
                  title: context.tr.autoPlayVideo,
                  subtitle: context.tr.autoPlayVideoSubtitle,
                  value: settings.autoPlayVideo,
                  onChanged: (v) => patch((s) => s.copyWith(autoPlayVideo: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.volume_off_outlined,
                  title: context.tr.startMuted,
                  subtitle: context.tr.startMutedDesc,
                  value: settings.startMuted,
                  onChanged: (v) => patch((s) => s.copyWith(startMuted: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.touch_app_outlined,
                  title: context.tr.videoDoubleTapAction,
                  subtitle: context.tr
                      .videoDoubleTapActionLabel(settings.videoDoubleTapAction),
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<VideoDoubleTapAction>(
                      context,
                      title: context.tr.videoDoubleTapAction,
                      subtitle: context.tr.playback,
                      headerIcon: Icons.touch_app_outlined,
                      currentValue: settings.videoDoubleTapAction,
                      options: [
                        _OptionItem(
                          value: VideoDoubleTapAction.smart,
                          title: context.tr.doubleTapActionSmart,
                          icon: Icons.auto_awesome_rounded,
                        ),
                        _OptionItem(
                          value: VideoDoubleTapAction.seekOnly,
                          title: context.tr.doubleTapActionSeekOnly,
                          icon: Icons.fast_forward_rounded,
                        ),
                        _OptionItem(
                          value: VideoDoubleTapAction.zoomOnly,
                          title: context.tr.doubleTapActionZoomOnly,
                          icon: Icons.zoom_in_rounded,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(videoDoubleTapAction: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernSliderTile(
                  icon: Icons.fast_forward_rounded,
                  title: context.tr.doubleTapSeek,
                  valueLabel:
                      context.tr.secondsCount(settings.doubleTapSeekInterval),
                  value: settings.doubleTapSeekInterval.toDouble(),
                  min: 5,
                  max: 60,
                  divisions: 11,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    patch((s) => s.copyWith(doubleTapSeekInterval: v.round()));
                  },
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.replay_rounded,
                  title: context.tr.resumeVideoPlayback,
                  subtitle: context.tr.resumeVideoPlaybackDesc,
                  value: settings.resumeVideoPlayback,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(resumeVideoPlayback: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.memory_rounded,
                  title: context.tr.hardwareAcceleration,
                  subtitle: context.tr.hardwareAccelerationSubtitle,
                  value: settings.hardwareAcceleration,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(hardwareAcceleration: v)),
                ),
              ],
            ),
            _SectionHeader(title: context.tr.displayAndSlideshow),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.brightness_high_rounded,
                  title: context.tr.maxBrightnessOnMedia,
                  subtitle: context.tr.maxBrightnessOnMediaDesc,
                  value: settings.maxBrightnessOnMedia,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(maxBrightnessOnMedia: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.light_mode_outlined,
                  title: context.tr.keepScreenOn,
                  subtitle: context.tr.keepScreenOnSubtitle,
                  value: settings.keepScreenOn,
                  onChanged: (v) => patch((s) => s.copyWith(keepScreenOn: v)),
                ),
                const _CardDivider(),
                _ModernSliderTile(
                  icon: Icons.slideshow_rounded,
                  title: context.tr.slideshowInterval,
                  valueLabel:
                      context.tr.secondsCount(settings.slideshowInterval),
                  value: settings.slideshowInterval.toDouble(),
                  min: 1,
                  max: 10,
                  divisions: 9,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    patch((s) => s.copyWith(slideshowInterval: v.round()));
                  },
                ),
              ],
            ),
            _SectionHeader(title: context.tr.browsingAndNavigation),
            _SettingsCard(
              children: [
                _ModernTile(
                  icon: Icons.home_outlined,
                  title: context.tr.startupScreen,
                  subtitle:
                      context.tr.startupScreenLabel(settings.startupScreen),
                  onTap: () async {
                    final chosen = await _showModernOptionDialog<StartupScreen>(
                      context,
                      title: context.tr.startupScreen,
                      subtitle: context.tr.browsingAndNavigation,
                      headerIcon: Icons.home_outlined,
                      currentValue: settings.startupScreen,
                      options: [
                        _OptionItem(
                          value: StartupScreen.all,
                          title: context.tr.all,
                          icon: Icons.grid_view_rounded,
                        ),
                        _OptionItem(
                          value: StartupScreen.photosOnly,
                          title: context.tr.photos,
                          icon: Icons.photo_outlined,
                        ),
                        _OptionItem(
                          value: StartupScreen.videosOnly,
                          title: context.tr.videos,
                          icon: Icons.videocam_outlined,
                        ),
                        _OptionItem(
                          value: StartupScreen.albums,
                          title: context.tr.albums,
                          icon: Icons.photo_library_outlined,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(startupScreen: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.filter_alt_outlined,
                  title: context.tr.filterSmallImages,
                  subtitle: context.tr.filterSmallImagesDesc,
                  value: settings.filterSmallImages,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(filterSmallImages: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.visibility_outlined,
                  title: context.tr.showHiddenFiles,
                  subtitle: context.tr.showHiddenFilesDesc,
                  value: settings.showHiddenFiles,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(showHiddenFiles: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.folder_off_outlined,
                  title: context.tr.excludedFolders,
                  subtitle: context.tr.excludedFoldersDescription,
                  onTap: () =>
                      _showExcludedFoldersDialog(context, ref, settings),
                ),
              ],
            ),
            _SectionHeader(title: context.tr.storageAndCache),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.delete_outline_rounded,
                  title: context.tr.trashBin,
                  subtitle: context.tr.trashBinSubtitle,
                  value: settings.enableTrash,
                  onChanged: (v) => patch((s) => s.copyWith(enableTrash: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.auto_delete_outlined,
                  title: context.tr.autoTrashCleanup,
                  subtitle: context.tr
                      .trashCleanupIntervalLabel(settings.autoTrashCleanup),
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<TrashCleanupInterval>(
                      context,
                      title: context.tr.autoTrashCleanup,
                      subtitle: context.tr.storageAndCache,
                      headerIcon: Icons.auto_delete_outlined,
                      currentValue: settings.autoTrashCleanup,
                      options: [
                        _OptionItem(
                          value: TrashCleanupInterval.never,
                          title: context.tr.cleanupNever,
                          icon: Icons.block_rounded,
                        ),
                        _OptionItem(
                          value: TrashCleanupInterval.days7,
                          title: context.tr.cleanup7Days,
                          icon: Icons.schedule_rounded,
                        ),
                        _OptionItem(
                          value: TrashCleanupInterval.days14,
                          title: context.tr.cleanup14Days,
                          icon: Icons.schedule_rounded,
                        ),
                        _OptionItem(
                          value: TrashCleanupInterval.days30,
                          title: context.tr.cleanup30Days,
                          icon: Icons.schedule_rounded,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(autoTrashCleanup: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.cleaning_services_rounded,
                  title: context.tr.clearThumbnailCache,
                  subtitle: context.tr.diskSize(_cacheSizeStr),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) {
                        final dTheme = Theme.of(ctx);
                        final dCs = dTheme.colorScheme;
                        final dIsDark = dTheme.brightness == Brightness.dark;
                        return AlertDialog(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: dCs.outlineVariant
                                  .withValues(alpha: dIsDark ? 0.12 : 0.18),
                              width: 1,
                            ),
                          ),
                          title: Text(
                            context.tr.clearThumbnailCache,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                              color: dCs.onSurface,
                            ),
                          ),
                          content: Text(
                            '${context.tr.clearCacheConfirm}\n\n${context.tr.diskSize(_cacheSizeStr)}',
                            style: TextStyle(
                              fontSize: 13.5,
                              color: dCs.onSurfaceVariant,
                              height: 1.4,
                            ),
                          ),
                          actionsAlignment: MainAxisAlignment.spaceBetween,
                          actionsPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          actions: [
                            TextButton(
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 16),
                              ),
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(context.tr.cancel),
                            ),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                backgroundColor: dCs.primary,
                                foregroundColor: dCs.onPrimary,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 10, horizontal: 16),
                              ),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(context.tr.clearCache),
                            ),
                          ],
                        );
                      },
                    );
                    if (confirmed == true) {
                      await ThumbnailService.instance.clearAll();
                      await _loadCacheSize();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              context.tr.cacheCleared,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
              ],
            ),
            _SectionHeader(title: context.tr.mangaTranslation),
            _SettingsCard(
              children: [
                _ModernTile(
                  icon: Icons.language_rounded,
                  title: context.tr.sourceLanguage,
                  subtitle: switch (settings.translationSourceLanguage) {
                    TranslationSourceLanguage.japanese =>
                      context.tr.langJapanese,
                    TranslationSourceLanguage.chinese => context.tr.langChinese,
                    TranslationSourceLanguage.korean => context.tr.langKorean,
                    TranslationSourceLanguage.auto => context.tr.autoDetect,
                  },
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<TranslationSourceLanguage>(
                      context,
                      title: context.tr.sourceLanguage,
                      subtitle: context.tr.mangaTranslation,
                      headerIcon: Icons.language_rounded,
                      currentValue: settings.translationSourceLanguage,
                      options: [
                        _OptionItem(
                          value: TranslationSourceLanguage.japanese,
                          title: context.tr.langJapanese,
                          subtitle: 'JA → EN',
                          icon: Icons.translate_rounded,
                        ),
                        _OptionItem(
                          value: TranslationSourceLanguage.chinese,
                          title: context.tr.langChinese,
                          subtitle: 'ZH → EN',
                          icon: Icons.translate_rounded,
                        ),
                        _OptionItem(
                          value: TranslationSourceLanguage.korean,
                          title: context.tr.langKorean,
                          subtitle: 'KO → EN',
                          icon: Icons.translate_rounded,
                        ),
                        _OptionItem(
                          value: TranslationSourceLanguage.auto,
                          title: context.tr.autoDetect,
                          icon: Icons.auto_awesome_rounded,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) =>
                          s.copyWith(translationSourceLanguage: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.translate_rounded,
                  title: context.tr.translationEngine,
                  subtitle: settings.translationEngineType ==
                          TranslationEngineType.googleMlKit
                      ? context.tr.engineGoogleMlKit
                      : context.tr.engineLocalLlm,
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<TranslationEngineType>(
                      context,
                      title: context.tr.translationEngine,
                      subtitle: context.tr.mangaTranslation,
                      headerIcon: Icons.translate_rounded,
                      currentValue: settings.translationEngineType,
                      options: [
                        _OptionItem(
                          value: TranslationEngineType.googleMlKit,
                          title: context.tr.engineGoogleMlKit,
                          icon: Icons.bolt_rounded,
                        ),
                        _OptionItem(
                          value: TranslationEngineType.localLlm,
                          title: context.tr.engineLocalLlm,
                          icon: Icons.smart_toy_outlined,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(translationEngineType: chosen));
                    }
                  },
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.psychology_outlined,
                  title: context.tr.mangaAiModel,
                  subtitle: settings.activeAiModelPath.isNotEmpty
                      ? p.basename(settings.activeAiModelPath)
                      : '/storage/emulated/0/models/ (${context.tr.defaultAutoDetect})',
                  onTap: () =>
                      _showAiModelManagerDialog(context, ref, settings),
                ),
                const _CardDivider(),
                _GoogleMlKitModelTile(
                  bcpCode: 'ja',
                  languageName: context.tr.langJapanese,
                ),
                const _CardDivider(),
                _GoogleMlKitModelTile(
                  bcpCode: 'zh',
                  languageName: context.tr.langChinese,
                ),
                const _CardDivider(),
                _GoogleMlKitModelTile(
                  bcpCode: 'ko',
                  languageName: context.tr.langKorean,
                ),
                const _CardDivider(),
                _GoogleMlKitModelTile(
                  bcpCode: 'en',
                  languageName: context.tr.langEnglish,
                ),
              ],
            ),
            _SectionHeader(title: context.tr.privacyAndSecurity),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.security_rounded,
                  title: context.tr.secureScreen,
                  subtitle: context.tr.secureScreenDesc,
                  value: settings.secureScreen,
                  onChanged: (v) => patch((s) => s.copyWith(secureScreen: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: _hasManageStorage
                      ? Icons.verified_user_rounded
                      : Icons.folder_shared_outlined,
                  iconColor: _hasManageStorage ? const Color(0xFF10B981) : null,
                  title: context.tr.allFilesAccess,
                  subtitle: _hasManageStorage
                      ? context.tr.allFilesGranted
                      : context.tr.allFilesAccessSubtitle,
                  trailing: _hasManageStorage
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF10B981).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.check_circle_rounded,
                                size: 13,
                                color: Color(0xFF10B981),
                              ),
                              SizedBox(width: 4),
                              Text(
                                'Granted',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            ],
                          ),
                        )
                      : null,
                  onTap: () async {
                    if (_hasManageStorage) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              context.tr.allFilesGranted,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        );
                      }
                      return;
                    }
                    final granted =
                        await PermissionService.instance.requestManageStorage();
                    await _checkManageStoragePermission();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            granted
                                ? context.tr.allFilesGranted
                                : context.tr.allFilesNotGranted,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            const DeveloperAboutCard(),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
  });

  final String title;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: cs.onSurfaceVariant.withValues(alpha: 0.8),
        ),
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
      decoration: BoxDecoration(
        color: isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _ModernTile extends StatelessWidget {
  const _ModernTile({
    required this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return BouncyTap(
      scaleDown: onTap != null ? 0.985 : 1.0,
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (iconColor ?? cs.primary)
                      .withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  color: iconColor ?? cs.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: cs.onSurfaceVariant,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ] else if (onTap != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.38),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernSwitchTile extends StatelessWidget {
  const _ModernSwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return BouncyTap(
      scaleDown: 0.99,
      onTap: () => onChanged(!value),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  color: cs.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: value,
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModernSliderTile extends StatelessWidget {
  const _ModernSliderTile({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  color: cs.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest
                      .withValues(alpha: isDark ? 0.6 : 0.7),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: cs.primary,
              inactiveTrackColor:
                  cs.outlineVariant.withValues(alpha: isDark ? 0.25 : 0.35),
              thumbColor: cs.primary,
              overlayColor: cs.primary.withValues(alpha: 0.12),
              trackHeight: 3.0,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      endIndent: 0,
      color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
    );
  }
}

Future<void> _showAiModelManagerDialog(
  BuildContext context,
  WidgetRef ref,
  SettingsModel settings,
) async {
  await GgufLocalLlmEngine.ensureModelsDirectoryExists();

  if (!context.mounted) return;

  final dTheme = Theme.of(context);
  final cs = dTheme.colorScheme;
  final isDark = dTheme.brightness == Brightness.dark;

  List<DiscoveredAiModel> models = [];
  bool isLoading = true;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setSt) {
          void refreshModels() {
            setSt(() => isLoading = true);
            GgufLocalLlmEngine.scanAvailableModels().then((result) {
              if (ctx.mounted) {
                setSt(() {
                  models = result;
                  isLoading = false;
                });
              }
            });
          }

          if (isLoading && models.isEmpty) {
            refreshModels();
          }

          final currentPath = settings.activeAiModelPath;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color:
                    cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
                width: 1,
              ),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.psychology_outlined,
                    color: cs.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr.mangaAiModel,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: context.tr.rescanModels,
                  icon: const Icon(Icons.refresh_rounded, size: 20),
                  onPressed: refreshModels,
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: isDark ? 0.4 : 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 16,
                            color: cs.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              context.tr.modelsDirectoryNotice,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(
                        currentPath.isEmpty
                            ? Icons.radio_button_checked
                            : Icons.radio_button_off,
                        color: currentPath.isEmpty
                            ? cs.primary
                            : cs.onSurfaceVariant,
                        size: 20,
                      ),
                      title: Text(
                        context.tr.defaultAutoDetect,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: currentPath.isEmpty
                              ? FontWeight.w600
                              : FontWeight.w400,
                          color: cs.onSurface,
                        ),
                      ),
                      subtitle: Text(
                        '/storage/emulated/0/models/',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      onTap: () async {
                        ref.read(settingsNotifierProvider.notifier).update(
                              (s) => s.copyWith(activeAiModelPath: ''),
                            );
                        await GgufLocalLlmEngine.instance.initializeSession(
                          modelPath: null,
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                    ),
                    const Divider(height: 16),
                    if (isLoading) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      ),
                    ] else if (models.isEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: Text(
                            context.tr.noModelsFound,
                            style: TextStyle(
                              fontSize: 13,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      ...models.map((model) {
                        final isSelected = currentPath == model.path;
                        return ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          leading: Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color:
                                isSelected ? cs.primary : cs.onSurfaceVariant,
                            size: 20,
                          ),
                          title: Text(
                            model.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: cs.onSurface,
                            ),
                          ),
                          subtitle: Text(
                            '${model.formattedSize} • ${model.path}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          onTap: () async {
                            ref.read(settingsNotifierProvider.notifier).update(
                                  (s) =>
                                      s.copyWith(activeAiModelPath: model.path),
                                );
                            await GgufLocalLlmEngine.instance.initializeSession(
                              modelPath: model.path,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                          },
                        );
                      }),
                    ],
                    const Divider(height: 16),
                    ListTile(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: Icon(
                        Icons.edit_road_outlined,
                        color: cs.primary,
                        size: 20,
                      ),
                      title: Text(
                        context.tr.customModelPath,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: cs.onSurface,
                        ),
                      ),
                      subtitle: currentPath.isNotEmpty &&
                              !models.any((m) => m.path == currentPath)
                          ? Text(
                              currentPath,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                color: cs.primary,
                              ),
                            )
                          : null,
                      trailing:
                          const Icon(Icons.chevron_right_rounded, size: 20),
                      onTap: () async {
                        final controller =
                            TextEditingController(text: currentPath);
                        final customPath = await showDialog<String>(
                          context: ctx,
                          builder: (subCtx) => AlertDialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            title: Text(
                              context.tr.customModelPath,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            content: TextField(
                              controller: controller,
                              autofocus: true,
                              decoration: const InputDecoration(
                                hintText: '/path/to/model.gguf',
                                isDense: true,
                              ),
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(subCtx),
                                child: Text(context.tr.cancel),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.pop(
                                    subCtx, controller.text.trim()),
                                child: Text(context.tr.ok),
                              ),
                            ],
                          ),
                        );

                        if (customPath != null && customPath.isNotEmpty) {
                          ref.read(settingsNotifierProvider.notifier).update(
                                (s) =>
                                    s.copyWith(activeAiModelPath: customPath),
                              );
                          await GgufLocalLlmEngine.instance.initializeSession(
                            modelPath: customPath,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                        }
                      },
                    ),
                  ],
                ),
              ),
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              TextButton(
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                ),
                onPressed: () => Navigator.pop(ctx),
                child: Text(context.tr.cancel),
              ),
            ],
          );
        },
      );
    },
  );
}

Future<void> _showExcludedFoldersDialog(
  BuildContext context,
  WidgetRef ref,
  SettingsModel settings,
) async {
  final current = List<String>.from(settings.excludedFolders);
  final mediaItems = ref.read(mediaListProvider).valueOrNull ?? [];
  final detectedFolders = mediaItems
      .map((e) => p.dirname(e.path))
      .where(
          (path) => path.isNotEmpty && path != '/' && !path.contains('.trash'))
      .toSet()
      .toList()
    ..sort();

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      final dTheme = Theme.of(ctx);
      final cs = dTheme.colorScheme;
      final isDark = dTheme.brightness == Brightness.dark;

      return StatefulBuilder(
        builder: (ctx, setSt) {
          final availableAlbums =
              detectedFolders.where((f) => !current.contains(f)).toList();

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(
                color:
                    cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
                width: 1,
              ),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            title: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.folder_off_outlined,
                    color: cs.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr.excludedFolders,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr.excludedFoldersDescription,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: cs.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: BouncyTap(
                        scaleDown: 0.98,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.folder_open_rounded, size: 18),
                          label: Text(
                            context.tr.pickFromManager,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13.5,
                            ),
                          ),
                          style: FilledButton.styleFrom(
                            alignment: Alignment.center,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                          ),
                          onPressed: () async {
                            final path =
                                await FolderPickerService.instance.pickFolder();
                            if (path != null &&
                                path.isNotEmpty &&
                                !current.contains(path)) {
                              setSt(() => current.add(path));
                            }
                          },
                        ),
                      ),
                    ),
                    if (availableAlbums.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(
                        context.tr.pickFromAlbums,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 120),
                        child: SingleChildScrollView(
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: availableAlbums.map((folder) {
                              final folderName = p.basename(folder);
                              return ActionChip(
                                avatar: const Icon(Icons.add, size: 15),
                                label: Text(
                                  folderName.isEmpty ? folder : folderName,
                                  style: const TextStyle(fontSize: 12),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                tooltip: folder,
                                onPressed: () {
                                  setSt(() => current.add(folder));
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ),
                    ],
                    if (current.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            '${context.tr.excludedFolders} (${current.length})',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                          BouncyTap(
                            scaleDown: 0.96,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setSt(() => current.clear());
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 4),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.delete_sweep_outlined,
                                    size: 16,
                                    color: cs.primary,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    context.tr.clearAll,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: cs.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Divider(
                        height: 1,
                        thickness: 1,
                        color: cs.outlineVariant
                            .withValues(alpha: isDark ? 0.12 : 0.18),
                      ),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 160),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: current.length,
                          itemBuilder: (ctx, i) {
                            final item = current[i];
                            return ListTile(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                Icons.folder_off_outlined,
                                size: 18,
                                color: cs.primary,
                              ),
                              title: Text(
                                item,
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 16),
                                onPressed: () =>
                                    setSt(() => current.remove(item)),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actionsPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            actions: [
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(context.tr.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                    ),
                    onPressed: () {
                      ref
                          .read(settingsNotifierProvider.notifier)
                          .update((s) => s.copyWith(excludedFolders: current));
                      Navigator.pop(ctx);
                    },
                    child: Text(context.tr.save),
                  ),
                ],
              ),
            ],
          );
        },
      );
    },
  );
}

Future<AppLanguage?> _showModernLanguageDialog(
  BuildContext context,
  AppLanguage currentLanguage,
) {
  final dTheme = Theme.of(context);
  final cs = dTheme.colorScheme;
  final isDark = dTheme.brightness == Brightness.dark;

  return showDialog<AppLanguage>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    Icons.translate_rounded,
                    color: cs.primary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr.chooseLanguage,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        context.tr.supportedLanguagesCount,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: AppLanguage.sortedLanguages
                      .map(
                        (lang) => _ModernLanguageOptionCard(
                          language: lang,
                          selected: currentLanguage == lang,
                          onTap: () async {
                            await Future.delayed(
                                const Duration(milliseconds: 100));
                            if (ctx.mounted) Navigator.pop(ctx, lang);
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ModernLanguageOptionCard extends StatelessWidget {
  const _ModernLanguageOptionCard({
    required this.language,
    required this.selected,
    required this.onTap,
  });

  final AppLanguage language;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: BouncyTap(
        scaleDown: 0.98,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: isDark ? 0.12 : 0.08)
                : (isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest
                      .withValues(alpha: isDark ? 0.45 : 0.55),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: language.flagEmoji != null
                    ? Text(
                        language.flagEmoji!,
                        style: const TextStyle(fontSize: 20),
                      )
                    : Icon(
                        Icons.language_rounded,
                        size: 20,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.nativeName,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      language.englishName,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.6),
                    width: selected ? 2 : 1.5,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 13, color: cs.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<AppThemeMode?> _showModernThemeDialog(
  BuildContext context,
  AppThemeMode currentTheme,
  List<AppThemeMode> availableThemeModes,
) {
  final dTheme = Theme.of(context);
  final cs = dTheme.colorScheme;
  final isDark = dTheme.brightness == Brightness.dark;

  return showDialog<AppThemeMode>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      Icons.palette_outlined,
                      color: cs.primary,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr.selectTheme,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          context.tr.chooseVisualMode,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...availableThemeModes.map(
                (m) => _ThemeOptionCard(
                  mode: m,
                  selected: currentTheme == m,
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (ctx.mounted) Navigator.pop(ctx, m);
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

class _ThemeOptionCard extends StatelessWidget {
  const _ThemeOptionCard({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  final AppThemeMode mode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final (icon, iconColor, bgPreview, description) = switch (mode) {
      AppThemeMode.system => (
          Icons.brightness_auto_rounded,
          const Color(0xFF2563EB),
          const LinearGradient(
            colors: [Color(0xFFF8FAFC), Color(0xFF000000)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          context.tr.themeSystemDesc,
        ),
      AppThemeMode.light => (
          Icons.wb_sunny_rounded,
          const Color(0xFFF59E0B),
          const LinearGradient(
            colors: [Color(0xFFFFFBEB), Color(0xFFFEF3C7)],
          ),
          context.tr.themeLightDesc,
        ),
      AppThemeMode.cleanLight => (
          Icons.light_mode_rounded,
          const Color(0xFF2563EB),
          const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFEDF2FA)],
          ),
          context.tr.themeCleanLightDesc,
        ),
      AppThemeMode.amoledSnowfall => (
          Icons.ac_unit_rounded,
          const Color(0xFF38BDF8),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF0D1830)],
          ),
          context.tr.themeDarkDesc,
        ),
      AppThemeMode.amoledMidnight => (
          Icons.nights_stay_rounded,
          const Color(0xFFA78BFA),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF130E20)],
          ),
          context.tr.themeAmoledDesc,
        ),
      AppThemeMode.amoledPure => (
          Icons.dark_mode_rounded,
          const Color(0xFF3B82F6),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF111620)],
          ),
          context.tr.themeAmoledPureDesc,
        ),
      AppThemeMode.amoledSakura => (
          Icons.local_florist_rounded,
          const Color(0xFFF472B6),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF140D13)],
          ),
          context.tr.themeSakuraDesc,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: BouncyTap(
        scaleDown: 0.98,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: isDark ? 0.12 : 0.08)
                : (isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: bgPreview,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: cs.outlineVariant.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr.themeModeLabel(mode),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.6),
                    width: selected ? 2 : 1.5,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 13, color: cs.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<int?> _showModernGridColumnsDialog(
  BuildContext context,
  int currentCols, {
  required bool isAlbum,
}) {
  final dTheme = Theme.of(context);
  final cs = dTheme.colorScheme;
  final isDark = dTheme.brightness == Brightness.dark;
  final title = isAlbum
      ? context.tr.selectAlbumsGridColumns
      : context.tr.selectGridColumns;
  final subtitle = isAlbum
      ? context.tr.chooseAlbumDensity
      : context.tr.chooseThumbnailDensity;

  return showDialog<int>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
          width: 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: isDark ? 0.14 : 0.10),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      isAlbum
                          ? Icons.photo_library_outlined
                          : Icons.grid_view_rounded,
                      color: cs.primary,
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
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          subtitle,
                          style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ...[2, 3, 4, 5].map(
                (c) => _ColumnOptionCard(
                  columns: c,
                  selected: currentCols == c,
                  isAlbum: isAlbum,
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 100));
                    if (ctx.mounted) Navigator.pop(ctx, c);
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

class _ColumnOptionCard extends StatelessWidget {
  const _ColumnOptionCard({
    required this.columns,
    required this.selected,
    required this.onTap,
    required this.isAlbum,
  });

  final int columns;
  final bool selected;
  final VoidCallback onTap;
  final bool isAlbum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final subtitle = switch (columns) {
      2 => context.tr.largeComfortableView,
      3 => context.tr.standardBalanced,
      4 => context.tr.compactDetailedView,
      5 => context.tr.denseHighCapacity,
      _ => context.tr.columnsCount(columns),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: BouncyTap(
        scaleDown: 0.98,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: isDark ? 0.12 : 0.08)
                : (isDark ? cs.surfaceContainerLow : cs.surfaceContainerLowest),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? cs.primary
                  : cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 34,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest
                      .withValues(alpha: isDark ? 0.45 : 0.55),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: List.generate(
                    columns,
                    (index) => Expanded(
                      child: Container(
                        margin: EdgeInsets.only(
                          left: index == 0 ? 0 : 2,
                          right: index == columns - 1 ? 0 : 2,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? cs.primary
                              : cs.onSurface.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr.columnsCount(columns),
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w500,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outlineVariant.withValues(alpha: 0.6),
                    width: selected ? 2 : 1.5,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 13, color: cs.onPrimary)
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionItem<T> {
  const _OptionItem({
    required this.value,
    required this.title,
    this.subtitle,
    required this.icon,
  });

  final T value;
  final String title;
  final String? subtitle;
  final IconData icon;
}

Future<T?> _showModernOptionDialog<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  IconData? headerIcon,
  Color? headerColor,
  required T currentValue,
  required List<_OptionItem<T>> options,
}) {
  final dTheme = Theme.of(context);
  final cs = dTheme.colorScheme;
  final isDark = dTheme.brightness == Brightness.dark;

  return showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: cs.outlineVariant.withValues(alpha: isDark ? 0.12 : 0.18),
          width: 1,
        ),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      title: Row(
        children: [
          if (headerIcon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (headerColor ?? cs.primary)
                    .withValues(alpha: isDark ? 0.14 : 0.10),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                headerIcon,
                size: 18,
                color: headerColor ?? cs.primary,
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.normal,
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((item) {
            final isSelected = item.value == currentValue;
            return InkWell(
              onTap: () => Navigator.pop(ctx, item.value),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primary.withValues(alpha: isDark ? 0.18 : 0.12)
                            : cs.surfaceContainerHighest
                                .withValues(alpha: isDark ? 0.45 : 0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        item.icon,
                        size: 18,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: isSelected ? cs.primary : cs.onSurface,
                            ),
                          ),
                          if (item.subtitle != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              item.subtitle!,
                              style: TextStyle(
                                fontSize: 12,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (isSelected)
                      Icon(Icons.check_circle_rounded,
                          color: cs.primary, size: 20)
                    else
                      Icon(
                        Icons.circle_outlined,
                        color: cs.outlineVariant.withValues(alpha: 0.6),
                        size: 20,
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.tr.cancel),
        ),
      ],
    ),
  );
}


class _GoogleMlKitModelTile extends StatefulWidget {
  const _GoogleMlKitModelTile({
    required this.bcpCode,
    required this.languageName,
  });

  final String bcpCode;
  final String languageName;

  @override
  State<_GoogleMlKitModelTile> createState() => _GoogleMlKitModelTileState();
}

class _GoogleMlKitModelTileState extends State<_GoogleMlKitModelTile> {
  bool _isDownloaded = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final downloaded =
        await MlKitTranslationEngine.instance.isModelDownloaded(widget.bcpCode);
    if (mounted) {
      setState(() => _isDownloaded = downloaded);
    }
  }

  Future<void> _download() async {
    setState(() => _isLoading = true);
    final ok =
        await MlKitTranslationEngine.instance.downloadModel(widget.bcpCode);
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isDownloaded = ok;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${widget.languageName}: ${context.tr.languagePackDownloaded}'
                : '${widget.languageName}: Download failed',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final ok =
        await MlKitTranslationEngine.instance.deleteModel(widget.bcpCode);
    if (mounted) {
      setState(() => _isDownloaded = !ok ? _isDownloaded : false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? '${widget.languageName}: Deleted'
                : '${widget.languageName}: Delete failed',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _ModernTile(
      icon: Icons.language_rounded,
      title: widget.languageName,
      subtitle: _isDownloaded
          ? context.tr.languagePackDownloaded
          : context.tr.languagePackNotDownloaded,
      trailing: _isLoading
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: Icon(
                _isDownloaded
                    ? Icons.delete_outline_rounded
                    : Icons.download_rounded,
                color: _isDownloaded ? cs.error : cs.primary,
                size: 20,
              ),
              tooltip: _isDownloaded
                  ? context.tr.deleteLanguagePack
                  : context.tr.downloadLanguagePack,
              onPressed: _isDownloaded ? _delete : _download,
            ),
    );
  }
}
