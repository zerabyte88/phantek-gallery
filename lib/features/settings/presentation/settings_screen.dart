import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
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
import '../../../features/update/data/update_provider.dart';
import 'widgets/developer_about_card.dart';

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
    final settings = ref.watch(settingsNotifierProvider);
    final update = ref.watch(updateNotifierProvider);

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
          style: const TextStyle(fontWeight: FontWeight.w700),
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
          padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
          children: [
            // ── Appearance ──
            _SectionHeader(
              title: context.tr.appearance,
              icon: Icons.palette_outlined,
              color: const Color(0xFF8B5CF6),
            ),
            _SettingsCard(
              children: [
                _ModernTile(
                  icon: Icons.palette_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: context.tr.theme,
                  subtitle: context.tr.themeModeLabel(settings.themeMode),
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
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.translate_rounded,
                  iconColor: const Color(0xFF06B6D4),
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

            // ── Grid & Layout ──
            _SectionHeader(
              title: context.tr.gridAndLayout,
              icon: Icons.grid_view_rounded,
              color: const Color(0xFF3B82F6),
            ),
            _SettingsCard(
              children: [
                _ModernTile(
                  icon: Icons.grid_view_rounded,
                  iconColor: const Color(0xFF3B82F6),
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
                  icon: Icons.photo_library_rounded,
                  iconColor: const Color(0xFF6366F1),
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
                  iconColor: const Color(0xFFEC4899),
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
                      headerColor: const Color(0xFFEC4899),
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
                  icon: Icons.view_agenda_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: context.tr.timelineGrouping,
                  subtitle: context.tr
                      .timelineGroupingLabel(settings.timelineGrouping),
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<TimelineGrouping>(
                      context,
                      title: context.tr.timelineGrouping,
                      subtitle: context.tr.chooseVisualMode,
                      headerIcon: Icons.view_agenda_rounded,
                      headerColor: const Color(0xFF8B5CF6),
                      currentValue: settings.timelineGrouping,
                      options: [
                        _OptionItem(
                          value: TimelineGrouping.continuous,
                          title: context.tr.groupContinuous,
                          icon: Icons.view_agenda_rounded,
                        ),
                        _OptionItem(
                          value: TimelineGrouping.daily,
                          title: context.tr.groupDaily,
                          icon: Icons.calendar_today_rounded,
                        ),
                        _OptionItem(
                          value: TimelineGrouping.monthly,
                          title: context.tr.groupMonthly,
                          icon: Icons.calendar_month_rounded,
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
                  icon: Icons.badge_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: context.tr.showDurationBadges,
                  subtitle: context.tr.showDurationBadgesSubtitle,
                  value: settings.showBadges,
                  onChanged: (v) => patch((s) => s.copyWith(showBadges: v)),
                ),
              ],
            ),

            // ── Video Playback ──
            _SectionHeader(
              title: context.tr.playback,
              icon: Icons.play_circle_outline_rounded,
              color: const Color(0xFF06B6D4),
            ),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.play_circle_outline_rounded,
                  iconColor: const Color(0xFF06B6D4),
                  title: context.tr.autoPlayVideo,
                  subtitle: context.tr.autoPlayVideoSubtitle,
                  value: settings.autoPlayVideo,
                  onChanged: (v) => patch((s) => s.copyWith(autoPlayVideo: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.volume_off_rounded,
                  iconColor: const Color(0xFFEC4899),
                  title: context.tr.startMuted,
                  subtitle: context.tr.startMutedDesc,
                  value: settings.startMuted,
                  onChanged: (v) => patch((s) => s.copyWith(startMuted: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.touch_app_rounded,
                  iconColor: const Color(0xFF6366F1),
                  title: context.tr.videoDoubleTapAction,
                  subtitle: context.tr
                      .videoDoubleTapActionLabel(settings.videoDoubleTapAction),
                  onTap: () async {
                    final chosen =
                        await _showModernOptionDialog<VideoDoubleTapAction>(
                      context,
                      title: context.tr.videoDoubleTapAction,
                      subtitle: context.tr.playback,
                      headerIcon: Icons.touch_app_rounded,
                      headerColor: const Color(0xFF6366F1),
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
                  iconColor: const Color(0xFF38BDF8),
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
                  iconColor: const Color(0xFF10B981),
                  title: context.tr.resumeVideoPlayback,
                  subtitle: context.tr.resumeVideoPlaybackDesc,
                  value: settings.resumeVideoPlayback,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(resumeVideoPlayback: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.memory_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: context.tr.hardwareAcceleration,
                  subtitle: context.tr.hardwareAccelerationSubtitle,
                  value: settings.hardwareAcceleration,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(hardwareAcceleration: v)),
                ),
              ],
            ),

            // ── Display & Slideshow ──
            _SectionHeader(
              title: context.tr.displayAndSlideshow,
              icon: Icons.slideshow_rounded,
              color: const Color(0xFF8B5CF6),
            ),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.brightness_high_rounded,
                  iconColor: const Color(0xFFF59E0B),
                  title: context.tr.maxBrightnessOnMedia,
                  subtitle: context.tr.maxBrightnessOnMediaDesc,
                  value: settings.maxBrightnessOnMedia,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(maxBrightnessOnMedia: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.light_mode_outlined,
                  iconColor: const Color(0xFFFACC15),
                  title: context.tr.keepScreenOn,
                  subtitle: context.tr.keepScreenOnSubtitle,
                  value: settings.keepScreenOn,
                  onChanged: (v) => patch((s) => s.copyWith(keepScreenOn: v)),
                ),
                const _CardDivider(),
                _ModernSliderTile(
                  icon: Icons.slideshow_rounded,
                  iconColor: const Color(0xFF8B5CF6),
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

            // ── Browsing & Navigation ──
            _SectionHeader(
              title: context.tr.browsingAndNavigation,
              icon: Icons.explore_outlined,
              color: const Color(0xFF3B82F6),
            ),
            _SettingsCard(
              children: [
                _ModernTile(
                  icon: Icons.home_outlined,
                  iconColor: const Color(0xFF3B82F6),
                  title: context.tr.startupScreen,
                  subtitle:
                      context.tr.startupScreenLabel(settings.startupScreen),
                  onTap: () async {
                    final chosen = await _showModernOptionDialog<StartupScreen>(
                      context,
                      title: context.tr.startupScreen,
                      subtitle: context.tr.browsingAndNavigation,
                      headerIcon: Icons.home_outlined,
                      headerColor: const Color(0xFF3B82F6),
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
                          icon: Icons.photo_rounded,
                        ),
                        _OptionItem(
                          value: StartupScreen.videosOnly,
                          title: context.tr.videos,
                          icon: Icons.videocam_rounded,
                        ),
                        _OptionItem(
                          value: StartupScreen.albums,
                          title: context.tr.albums,
                          icon: Icons.photo_library_rounded,
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
                  iconColor: const Color(0xFFF59E0B),
                  title: context.tr.filterSmallImages,
                  subtitle: context.tr.filterSmallImagesDesc,
                  value: settings.filterSmallImages,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(filterSmallImages: v)),
                ),
                const _CardDivider(),
                _ModernSwitchTile(
                  icon: Icons.visibility_outlined,
                  iconColor: const Color(0xFF06B6D4),
                  title: context.tr.showHiddenFiles,
                  subtitle: context.tr.showHiddenFilesDesc,
                  value: settings.showHiddenFiles,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(showHiddenFiles: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.folder_off_rounded,
                  iconColor: const Color(0xFF64748B),
                  title: context.tr.excludedFolders,
                  subtitle: context.tr.excludedFoldersDescription,
                  onTap: () =>
                      _showExcludedFoldersDialog(context, ref, settings),
                ),
              ],
            ),

            // ── Storage & Cache ──
            _SectionHeader(
              title: context.tr.storageAndCache,
              icon: Icons.storage_rounded,
              color: const Color(0xFF14B8A6),
            ),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.delete_outline_rounded,
                  iconColor: const Color(0xFF14B8A6),
                  title: context.tr.trashBin,
                  subtitle: context.tr.trashBinSubtitle,
                  value: settings.enableTrash,
                  onChanged: (v) => patch((s) => s.copyWith(enableTrash: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.auto_delete_outlined,
                  iconColor: const Color(0xFF06B6D4),
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
                      headerColor: const Color(0xFF06B6D4),
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
                  iconColor: const Color(0xFFF97316),
                  title: context.tr.clearThumbnailCache,
                  subtitle: context.tr.diskSize(_cacheSizeStr),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        title: Text(context.tr.clearThumbnailCache),
                        content: Text(
                          '${context.tr.clearCacheConfirm}\n\n${context.tr.diskSize(_cacheSizeStr)}',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: Text(context.tr.cancel),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: Text(context.tr.clearThumbnailCache),
                          ),
                        ],
                      ),
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

            // ── Privacy & Security ──
            _SectionHeader(
              title: context.tr.privacyAndSecurity,
              icon: Icons.shield_outlined,
              color: const Color(0xFF10B981),
            ),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.security_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: context.tr.secureScreen,
                  subtitle: context.tr.secureScreenDesc,
                  value: settings.secureScreen,
                  onChanged: (v) => patch((s) => s.copyWith(secureScreen: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: _hasManageStorage
                      ? Icons.verified_user_rounded
                      : Icons.folder_shared_rounded,
                  iconColor: _hasManageStorage
                      ? const Color(0xFF10B981)
                      : const Color(0xFF3B82F6),
                  title: context.tr.allFilesAccess,
                  subtitle: _hasManageStorage
                      ? context.tr.allFilesGranted
                      : context.tr.allFilesAccessSubtitle,
                  trailing: _hasManageStorage
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            context.tr.allFilesGranted,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF10B981),
                            ),
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
                    final granted = await PermissionService.instance
                        .requestManageStorage();
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

            // ── Updates ──
            _SectionHeader(
              title: context.tr.updates,
              icon: Icons.system_update_outlined,
              color: const Color(0xFF8B5CF6),
            ),
            _SettingsCard(
              children: [
                _ModernSwitchTile(
                  icon: Icons.update_rounded,
                  iconColor: const Color(0xFF10B981),
                  title: context.tr.autoCheckUpdate,
                  subtitle: context.tr.checkUpdateOnLaunchSubtitle,
                  value: settings.autoCheckUpdate,
                  onChanged: (v) =>
                      patch((s) => s.copyWith(autoCheckUpdate: v)),
                ),
                const _CardDivider(),
                _ModernTile(
                  icon: Icons.system_update_alt_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: context.tr.checkUpdateNow,
                  subtitle: context.tr.checkGitHubReleasesSubtitle,
                  trailing: update.isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: update.isLoading
                      ? null
                      : () => ref
                          .read(updateNotifierProvider.notifier)
                          .checkForUpdate(silent: false),
                ),
              ],
            ),

            // ── About App ──
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
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 18, 16, 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: cs.primary,
            ),
          ),
        ],
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
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? cs.surfaceContainerHighest.withValues(alpha: 0.35)
            : cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: cs.outline.withValues(alpha: isDark ? 0.08 : 0.12),
          width: 0.8,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
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
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BouncyTap(
      scaleDown: onTap != null ? 0.985 : 1.0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 19),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12,
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
                color: cs.onSurfaceVariant.withValues(alpha: 0.45),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModernSwitchTile extends StatelessWidget {
  const _ModernSwitchTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BouncyTap(
      scaleDown: 0.99,
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 19),
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
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
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
    );
  }
}

class _ModernSliderTile extends StatelessWidget {
  const _ModernSliderTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 19),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  valueLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: iconColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: iconColor,
              inactiveTrackColor: iconColor.withValues(alpha: 0.2),
              thumbColor: iconColor,
              overlayColor: iconColor.withValues(alpha: 0.15),
              trackHeight: 3.5,
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
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 0.8,
      indent: 66,
      endIndent: 16,
      color: cs.outline.withValues(alpha: 0.07),
    );
  }
}

Future<void> _showExcludedFoldersDialog(
  BuildContext context,
  WidgetRef ref,
  SettingsModel settings,
) async {
  final current = List<String>.from(settings.excludedFolders);
  final cs = Theme.of(context).colorScheme;

  // Retrieve unique folder paths from media items currently loaded in memory.
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
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSt) {
        final availableAlbums =
            detectedFolders.where((f) => !current.contains(f)).toList();

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF64748B).withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.folder_off_rounded,
                  color: Color(0xFF64748B),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  context.tr.excludedFolders,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
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
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: BouncyTap(
                      scaleDown: 0.96,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.folder_open_rounded, size: 20),
                        label: Text(
                          context.tr.pickFromManager,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          alignment: Alignment.center,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 120),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: availableAlbums.map((folder) {
                            final folderName = p.basename(folder);
                            return ActionChip(
                              avatar: const Icon(Icons.add, size: 16),
                              label: Text(
                                folderName.isEmpty ? folder : folderName,
                                style: const TextStyle(fontSize: 12),
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
                          scaleDown: 0.94,
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
                                const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 16,
                                  color: Color(0xFFEF4444),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  context.tr.clearAll,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Divider(height: 1),
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
                            leading: const Icon(
                              Icons.folder_off_rounded,
                              size: 18,
                              color: Color(0xFFEF4444),
                            ),
                            title: Text(item,
                                style: const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18),
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
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Expanded(
                  child: BouncyTap(
                    scaleDown: 0.95,
                    child: TextButton(
                      style: TextButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: () => Navigator.pop(ctx),
                      child:
                          Text(context.tr.cancel, textAlign: TextAlign.center),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BouncyTap(
                    scaleDown: 0.95,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                      ),
                      onPressed: () {
                        ref.read(settingsNotifierProvider.notifier).update(
                            (s) => s.copyWith(excludedFolders: current));
                        Navigator.pop(ctx);
                      },
                      child: Text(context.tr.save, textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );
}

Future<AppLanguage?> _showModernLanguageDialog(
  BuildContext context,
  AppLanguage currentLanguage,
) {
  final cs = Theme.of(context).colorScheme;
  return showDialog<AppLanguage>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.translate_rounded,
                    color: Color(0xFF06B6D4),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr.chooseLanguage,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                                const Duration(milliseconds: 140));
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
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: BouncyTap(
        scaleDown: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : cs.outline.withValues(alpha: 0.15),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.18)
                      : cs.surfaceContainerHighest.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: language.flagEmoji != null
                    ? Text(
                        language.flagEmoji!,
                        style: const TextStyle(
                          fontSize: 22,
                        ),
                      )
                    : Icon(
                        Icons.language_rounded,
                        size: 22,
                        color: selected ? cs.primary : cs.onSurfaceVariant,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      language.nativeName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w600,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outline.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 14, color: cs.onPrimary)
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
  final cs = Theme.of(context).colorScheme;
  return showDialog<AppThemeMode>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.palette_rounded,
                        color: cs.primary, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr.selectTheme,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
              const SizedBox(height: 18),
              ...availableThemeModes.map(
                (m) => _ThemeOptionCard(
                  mode: m,
                  selected: currentTheme == m,
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 140));
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
    final cs = Theme.of(context).colorScheme;

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
            colors: [Color(0xFFFAFAFA), Color(0xFFE2E8F0)],
          ),
          context.tr.themeLightDesc,
        ),
      AppThemeMode.cleanLight => (
          Icons.wb_sunny_outlined,
          const Color(0xFF0EA5E9),
          const LinearGradient(
            colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
          ),
          context.tr.themeCleanLightDesc,
        ),
      AppThemeMode.amoledSnowfall => (
          Icons.ac_unit_rounded,
          const Color(0xFF38BDF8),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF0C1322)],
          ),
          context.tr.themeDarkDesc,
        ),
      AppThemeMode.amoledMidnight => (
          Icons.nights_stay_rounded,
          const Color(0xFF818CF8),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF0A0A0A)],
          ),
          context.tr.themeAmoledDesc,
        ),
      AppThemeMode.amoledPure => (
          Icons.brightness_2_outlined,
          const Color(0xFF60A5FA),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF121214)],
          ),
          context.tr.themeAmoledPureDesc,
        ),
      AppThemeMode.amoledSakura => (
          Icons.local_florist_rounded,
          const Color(0xFFFF7597),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF1E0F16)],
          ),
          context.tr.themeSakuraDesc,
        ),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BouncyTap(
        scaleDown: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : cs.outline.withValues(alpha: 0.15),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: bgPreview,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : Colors.white.withValues(alpha: 0.2),
                    width: 1.5,
                  ),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr.themeModeLabel(mode),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w600,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outline.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 14, color: cs.onPrimary)
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
  final cs = Theme.of(context).colorScheme;
  final title = isAlbum
      ? context.tr.selectAlbumsGridColumns
      : context.tr.selectGridColumns;
  final subtitle = isAlbum
      ? context.tr.chooseAlbumDensity
      : context.tr.chooseThumbnailDensity;

  return showDialog<int>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: cs.primary.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isAlbum
                          ? Icons.photo_library_rounded
                          : Icons.grid_view_rounded,
                      color: cs.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
              const SizedBox(height: 18),
              ...[2, 3, 4, 5].map(
                (c) => _ColumnOptionCard(
                  columns: c,
                  selected: currentCols == c,
                  isAlbum: isAlbum,
                  onTap: () async {
                    await Future.delayed(const Duration(milliseconds: 140));
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
    final cs = Theme.of(context).colorScheme;

    final subtitle = switch (columns) {
      2 => context.tr.largeComfortableView,
      3 => context.tr.standardBalanced,
      4 => context.tr.compactDetailedView,
      5 => context.tr.denseHighCapacity,
      _ => context.tr.columnsCount(columns),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: BouncyTap(
        scaleDown: 0.96,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? cs.primary.withValues(alpha: 0.12)
                : cs.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? cs.primary : cs.outline.withValues(alpha: 0.15),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 38,
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected
                        ? cs.primary.withValues(alpha: 0.5)
                        : cs.outline.withValues(alpha: 0.2),
                  ),
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
                              : cs.onSurface.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
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
                      context.tr.columnsCount(columns),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.w600,
                        color: selected ? cs.primary : cs.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
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
                duration: const Duration(milliseconds: 200),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? cs.primary : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? cs.primary
                        : cs.outline.withValues(alpha: 0.4),
                    width: 2,
                  ),
                ),
                child: selected
                    ? Icon(Icons.check, size: 14, color: cs.onPrimary)
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
  final cs = Theme.of(context).colorScheme;
  return showDialog<T>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      contentPadding: const EdgeInsets.symmetric(vertical: 8),
      title: Row(
        children: [
          if (headerIcon != null) ...[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (headerColor ?? cs.primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                headerIcon,
                size: 20,
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
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
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
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? cs.primaryContainer
                            : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        item.icon,
                        size: 20,
                        color: isSelected ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isSelected ? cs.primary : cs.onSurface,
                            ),
                          ),
                          if (item.subtitle != null) ...[
                            const SizedBox(height: 2),
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
                      Icon(Icons.check_circle_rounded, color: cs.primary)
                    else
                      Icon(
                        Icons.circle_outlined,
                        color: cs.outline.withValues(alpha: 0.4),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.tr.cancel),
        ),
      ],
    ),
  );
}
