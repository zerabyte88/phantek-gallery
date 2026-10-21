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
      AppThemeMode.light,
      AppThemeMode.dark,
      AppThemeMode.amoled,
      AppThemeMode.amoledSakura,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr.settings,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: false,
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
                _ModernTile(
                  icon: Icons.fast_forward_rounded,
                  iconColor: const Color(0xFF38BDF8),
                  title: context.tr.doubleTapSeek,
                  subtitle:
                      context.tr.secondsCount(settings.doubleTapSeekInterval),
                  onTap: () async {
                    final chosen = await _showModernOptionDialog<int>(
                      context,
                      title: context.tr.doubleTapSeek,
                      subtitle: context.tr.playback,
                      headerIcon: Icons.fast_forward_rounded,
                      headerColor: const Color(0xFF38BDF8),
                      currentValue: settings.doubleTapSeekInterval,
                      options: [
                        _OptionItem(
                          value: 5,
                          title: context.tr.secondsCount(5),
                          icon: Icons.replay_5_rounded,
                        ),
                        _OptionItem(
                          value: 10,
                          title: context.tr.secondsCount(10),
                          icon: Icons.replay_10_rounded,
                        ),
                        _OptionItem(
                          value: 15,
                          title: context.tr.secondsCount(15),
                          icon: Icons.replay_30_rounded,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(doubleTapSeekInterval: chosen));
                    }
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
                _ModernTile(
                  icon: Icons.slideshow_rounded,
                  iconColor: const Color(0xFF8B5CF6),
                  title: context.tr.slideshowInterval,
                  subtitle: context.tr.secondsCount(settings.slideshowInterval),
                  onTap: () async {
                    final chosen = await _showModernOptionDialog<int>(
                      context,
                      title: context.tr.slideshowInterval,
                      subtitle: context.tr.playback,
                      headerIcon: Icons.slideshow_rounded,
                      headerColor: const Color(0xFF8B5CF6),
                      currentValue: settings.slideshowInterval,
                      options: [
                        _OptionItem(
                          value: 3,
                          title: context.tr.secondsCount(3),
                          icon: Icons.timer_outlined,
                        ),
                        _OptionItem(
                          value: 5,
                          title: context.tr.secondsCount(5),
                          icon: Icons.timer_outlined,
                        ),
                        _OptionItem(
                          value: 10,
                          title: context.tr.secondsCount(10),
                          icon: Icons.timer_outlined,
                        ),
                      ],
                    );
                    if (chosen != null) {
                      patch((s) => s.copyWith(slideshowInterval: chosen));
                    }
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
              ],
            ),

            // ── Actions ──
            const SizedBox(height: 4),
            _SettingsCard(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ModernActionButton(
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
                ),
                const _CardDivider(),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ModernActionButton(
                    icon: _hasManageStorage
                        ? Icons.verified_user_rounded
                        : Icons.security_rounded,
                    iconColor: _hasManageStorage
                        ? const Color(0xFF10B981)
                        : const Color(0xFFEF4444),
                    title: context.tr.allFilesAccess,
                    subtitle: _hasManageStorage
                        ? context.tr.allFilesGranted
                        : context.tr.allFilesAccessSubtitle,
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
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: _ModernActionButton(
                    icon: Icons.system_update_alt_rounded,
                    iconColor: const Color(0xFF8B5CF6),
                    title: context.tr.checkUpdateNow,
                    subtitle: context.tr.checkGitHubReleasesSubtitle,
                    isLoading: update.isLoading,
                    enabled: !update.isLoading,
                    onTap: () => ref
                        .read(updateNotifierProvider.notifier)
                        .checkForUpdate(silent: false),
                  ),
                ),
              ],
            ),

            // ── About App (untouched) ──
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
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
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.60),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: cs.outline.withValues(alpha: 0.14),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: children,
        ),
      ),
    );
  }
}

class _ModernActionButton extends StatelessWidget {
  const _ModernActionButton({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle,
    this.isLoading = false,
    this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final bool isLoading;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isClickable = enabled && !isLoading && onTap != null;

    return BouncyTap(
      scaleDown: isClickable ? 0.96 : 1.0,
      onTap: isClickable ? onTap : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: iconColor.withValues(alpha: 0.28),
            width: 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: iconColor,
                    ),
                  )
                else
                  Icon(icon, color: iconColor, size: 20),
                const SizedBox(width: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: enabled
                        ? (cs.brightness == Brightness.dark
                            ? Colors.white
                            : cs.onSurface)
                        : cs.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurfaceVariant,
                ),
              ),
            ],
          ],
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
    this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BouncyTap(
      scaleDown: onTap != null ? 0.98 : 1.0,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
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
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: cs.onSurfaceVariant.withValues(alpha: 0.6),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
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

class _CardDivider extends StatelessWidget {
  const _CardDivider();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Divider(
      height: 1,
      thickness: 1,
      indent: 68,
      endIndent: 16,
      color: cs.outline.withValues(alpha: 0.08),
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
          const Color(0xFF6B48FF),
          LinearGradient(
            colors: [Colors.grey.shade300, Colors.grey.shade900],
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
      AppThemeMode.dark => (
          Icons.ac_unit_rounded,
          const Color(0xFF38BDF8),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF0F172A)],
          ),
          context.tr.themeDarkDesc,
        ),
      AppThemeMode.amoled => (
          Icons.phone_android_rounded,
          const Color(0xFF38BDF8),
          const LinearGradient(
            colors: [Color(0xFF000000), Color(0xFF0A0A0A)],
          ),
          context.tr.themeAmoledDesc,
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
