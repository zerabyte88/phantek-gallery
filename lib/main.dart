// SPDX-License-Identifier: MIT
// Copyright (C) 2026 zerabyte88

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/router.dart';
import 'app/theme.dart';
import 'core/enums/trash_cleanup_interval.dart';
import 'core/localization/app_language.dart';
import 'core/localization/app_localizations.dart';
import 'core/models/settings_model.dart';
import 'core/providers/settings_provider.dart';
import 'core/services/app_lock_service.dart';
import 'core/services/license_service.dart';
import 'core/services/screen_keeper_service.dart';
import 'core/services/settings_service.dart';
import 'core/services/thumbnail_service.dart';
import 'core/services/trash_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock portrait orientation by default.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  LicenseService.registerLicenses();
  await SettingsService.init();
  await ThumbnailService.init();

  final initialCleanup =
      SettingsService.instance.settings.autoTrashCleanup.inDays;
  if (initialCleanup != null) {
    TrashService().purgeExpired(maxDays: initialCleanup).catchError((_) {});
  }

  // High-capacity imageCache for fast swiping.
  PaintingBinding.instance.imageCache.maximumSizeBytes = 192 * 1024 * 1024;
  PaintingBinding.instance.imageCache.maximumSize = 100;

  runApp(const ProviderScope(child: PhantekGalleryApp()));
}

class PhantekGalleryApp extends ConsumerStatefulWidget {
  const PhantekGalleryApp({super.key});

  @override
  ConsumerState<PhantekGalleryApp> createState() => _PhantekGalleryAppState();
}

class _PhantekGalleryAppState extends ConsumerState<PhantekGalleryApp>
    with WidgetsBindingObserver {
  late bool _isLocked;
  DateTime? _backgroundedAt;
  bool _authInProgress = false;

  @override
  void initState() {
    super.initState();
    _isLocked = ref.read(settingsNotifierProvider).appLockEnabled;
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = ref.read(settingsNotifierProvider);
      if (settings.secureScreen) {
        ScreenKeeperService.setSecure(true);
      }
      if (_isLocked) {
        _promptUnlock();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final appLockEnabled = ref.read(settingsNotifierProvider).appLockEnabled;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (appLockEnabled && !AppLockService.instance.isPromptActive) {
        _backgroundedAt ??= DateTime.now();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (appLockEnabled) {
        final bgAt = _backgroundedAt;
        if (bgAt != null &&
            DateTime.now().difference(bgAt).inSeconds >= 2 &&
            !AppLockService.instance.isPromptActive &&
            !_isLocked) {
          setState(() => _isLocked = true);
          _promptUnlock();
        }
      }
      _backgroundedAt = null;
    }
  }

  Future<void> _promptUnlock() async {
    if (_authInProgress || !mounted) return;
    _authInProgress = true;
    try {
      final locale =
          ref.read(settingsNotifierProvider).language.locale ?? const Locale('en');
      final loc = AppLocalizations(locale);
      final authenticated = await AppLockService.instance.authenticate(
        title: loc.appLockTitle,
        subtitle: loc.appLockAuthReason,
      );
      if (authenticated && mounted) {
        setState(() => _isLocked = false);
      }
    } finally {
      _authInProgress = false;
    }
  }

  @override
  void didHaveMemoryPressure() {
    ThumbnailService.instance.trimMemory();
    PaintingBinding.instance.imageCache.clear();
    super.didHaveMemoryPressure();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(
      settingsNotifierProvider.select((s) => s.secureScreen),
      (_, secure) => ScreenKeeperService.setSecure(secure),
    );
    ref.listen<bool>(
      settingsNotifierProvider.select((s) => s.appLockEnabled),
      (_, enabled) {
        if (!enabled && _isLocked) {
          setState(() => _isLocked = false);
        }
      },
    );

    final themeMode = ref.watch(
      settingsNotifierProvider.select((s) => s.themeMode),
    );
    final language = ref.watch(
      settingsNotifierProvider.select((s) => s.language),
    );
    final appLockEnabled = ref.watch(
      settingsNotifierProvider.select((s) => s.appLockEnabled),
    );

    final darkTheme = switch (themeMode) {
      AppThemeMode.amoledMidnight => AppTheme.amoledMidnight,
      AppThemeMode.amoledSnowfall => AppTheme.amoledSnowfall,
      AppThemeMode.amoledSakura => AppTheme.amoledSakura,
      AppThemeMode.amoledPure ||
      AppThemeMode.system ||
      _ =>
        AppTheme.amoledPure,
    };

    final lightTheme = switch (themeMode) {
      AppThemeMode.light => AppTheme.light,
      AppThemeMode.cleanLight ||
      AppThemeMode.system ||
      _ =>
        AppTheme.cleanLight,
    };

    final flutterThemeMode = switch (themeMode) {
      AppThemeMode.light || AppThemeMode.cleanLight => ThemeMode.light,
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.amoledSnowfall ||
      AppThemeMode.amoledMidnight ||
      AppThemeMode.amoledPure ||
      AppThemeMode.amoledSakura =>
        ThemeMode.dark,
    };

    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'Phantek Gallery',
      debugShowCheckedModeBanner: false,
      locale: language.locale ?? const Locale('en'),
      supportedLocales: AppLanguage.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: flutterThemeMode,
      onGenerateRoute: generateRoute,
      initialRoute: AppRoutes.gallery,
      builder: (context, child) {
        final showLock = _isLocked && appLockEnabled;
        return AnimatedTheme(
          data: Theme.of(context),
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
          child: Stack(
            children: [
              child ?? const SizedBox.shrink(),
              if (showLock)
                Positioned.fill(
                  child: _AppLockOverlay(
                    key: const ValueKey('app_lock_overlay'),
                    onUnlock: _promptUnlock,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AppLockOverlay extends StatelessWidget {
  const _AppLockOverlay({
    super.key,
    required this.onUnlock,
  });

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: cs.primary.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 34,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Phantek Gallery',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  context.tr.appLockAuthReason,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: onUnlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: Text(context.tr.unlock),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 14,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
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
