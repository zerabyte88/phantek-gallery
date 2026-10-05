# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" width="115" height="115" alt="Phantek Gallery" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PLATFORM-ANDROID-059669?style=for-the-badge&logo=android&logoColor=white&labelColor=0F172A" alt="Platform" />
  <img src="https://img.shields.io/badge/FLUTTER-3.47+-0284C7?style=for-the-badge&logo=flutter&logoColor=white&labelColor=0F172A" alt="Flutter" />
  <img src="https://img.shields.io/badge/APPLICATION_ID-com.phantek.virgo.spica-6366F1?style=for-the-badge&logo=android&logoColor=white&labelColor=0F172A" alt="Application ID" />
  <a href="https://github.com/zerabyte88/phantek-gallery/releases"><img src="https://img.shields.io/badge/VERSION-v1.3.10-2563EB?style=for-the-badge&logo=github&logoColor=white&labelColor=0F172A" alt="Version" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/LICENSE-GPLv3-475569?style=for-the-badge&logo=gnu&logoColor=white&labelColor=0F172A" alt="License" /></a>
</p>

Phantek Gallery is a high-performance, offline-first photo and video gallery application for Android (`com.phantek.virgo.spica`). Built with Flutter and powered by the MPV playback engine via MediaKit, it delivers smooth media rendering, responsive navigation, and complete data privacy without third-party tracking or mandatory cloud dependencies. Fully compliant with modern Android standards, including Android 16 (API 36/37) partial media selection and mandatory edge-to-edge layouts.

---

## Overview

Modern mobile galleries often require persistent network connections, cloud synchronization, and background analytics. Phantek Gallery takes an offline-first approach: your photos and videos stay strictly on your local device storage. Network access is restricted entirely to user-directed over-the-air (OTA) update checks against official GitHub Releases.

---

## What's New in v1.3.10

- ⚡ **Ultra-High Resolution Photo Optimization (50MB+ / 100MP+)**: Built-in 4096px display-fit downsampling (`ResizeImage`) reduces memory allocation from ~408 MB down to ~50 MB per photo, fitting seamlessly into the 256MB `imageCache` so returning to viewed photos is instantaneous without repeated decoding.
- 🖼️ **Instant Thumbnail Previews & Hero Flight**: Smooth, non-blocking thumbnail placeholders in `loadingBuilder` and `Hero` flight shuttle transitions eliminate blank screens and decode pauses while sliding through albums.
- 🎬 **Zero Black Flash Video Swiping & GPU Texture Sync**: Seamless `AnimatedOpacity` cross-fade between active `Video()` texture surfaces and underlying high-DPI thumbnails, paired with a 50ms SurfaceTexture binding synchronization delay for buttery smooth 60/120 FPS swiping.
- 🔍 **Double-Tap Focal Point Zooming (2.5x) for Photos & Videos**: Double-tapping on specific regions zooms directly into the tapped focal point at 2.5x magnification across both photos and videos.
- 🔽 **Interactive Pull-Down to Dismiss for Videos**: Matches photo behavior with real-time `SpringSimulation` physics and `Hero` return animation back to the grid.
- 🎨 **Anti-Aliased High-DPI Thumbnails (512px / 90% Quality)**: Increased thumbnail resolution and bicubic `FilterQuality.high` interpolation to eliminate blurriness and compression artifacts across full-screen previews and grid tiles.

---

## Key Features

### Animated Flame Title & Modern Aesthetics
- **Animated Flame Brand**: Sleek centered AppBar badge featuring a continuous looping fiery gradient border, outer flame glow, and dynamic color-pulsing fire icon (`🔥 Phantek`).
- **Tactile Micro-Animations**: Smooth spring-scale tap animations (`BouncyTap`) across interactive chips, dialog options, and controls.
- **Fluid Theme Transitions**: `AnimatedTheme` integration providing a 350ms smooth cross-fade transition when toggling themes.

### High-Performance Media Grid, Search & Organization
- **Smart Grouping**: View all media in a unified timeline or browse organized folders (DCIM, Camera, Downloads, Screenshots, etc.).
- **Quick Search**: Real-time search bar integrated in AppBar with instant filtering across media titles and album collections.
- **Horizontal Category Swipe Navigation**: Smooth horizontal swipe navigation between All, Photos, Videos, and Albums tabs with `KeepAlive` optimization to prevent frame drops.
- **Smooth Stadium Filter Bar**: Anti-aliased pill-shaped filter chips (`All`, `Photos`, `Videos`, `Albums`) with seamless, clipped ink feedback.
- **In-Album Filtering & Sorting**: Full filter bar (`All`, `Photos`, `Videos`) and sorting options available inside individual album detail screens.
- **Compact Sort Menu**: 3-dots popup menu supporting Newest First, Oldest First, Name A → Z, and Name Z → A.
- **Visual Column Dialogs**: Modern dialogs featuring interactive mini-grid layout previews for configuring 2, 3, 4, or 5 grid columns independently for photos and albums.
- **Folder Exclusions**: Blacklist unwanted system directories from being indexed.
- **Android 14+ / 16 Compliance**: Seamless partial photo selection support (`READ_MEDIA_VISUAL_USER_SELECTED`).

### Hardware-Accelerated Video Playback & Advanced Controls
- **MediaKit & MPV Engine**: Native MPV and FFmpeg integration for ultra-smooth playback of MKV, MP4, WebM, and high-bitrate video streams up to 4K 60FPS.
- **Universal Container & Codec Support**: Native playback and scanning for MKV, MOV, WebM, MP4, AVI, and 3GP containers. Automatic hardware-to-software fallback decoding (`hwdec: auto-copy`) across all codecs (VP9, HEVC/H.265, AVC/H.264), ensuring seamless stutter-free playback across all device profiles.
- **Optimized Multi-Worker Thumbnail Engine**: High-throughput extraction engine with keyframe-synchronized decoding (`OPTION_CLOSEST_SYNC`), LIFO priority scheduling, in-flight deduplication, direct native frame extraction via `ThumbnailUtils` and `MediaMetadataRetriever`, and headless MPV fallbacks for exotic codecs (1080p+, 4K, VP9, AV1, HEVC 10-bit).
- **Lag-Free Slider Scrubbing**: Coalesced seek execution updates timestamps smoothly in real-time without flooding decoder pipelines, eliminating audio pops and stutter.
- **Proactive Texture Detachment & Butter-Smooth Swiping**: Proactively unmounts the native MPV `Video()` texture on the first horizontal gesture to free 100% GPU/decoder resources, defers `_player.open()` post-frame, and renders dimension-matched placeholder thumbnails underneath to guarantee 60/120 FPS swiping with zero black flashes.
- **Aspect-Ratio-Aware Smart Fullscreen**: Portrait/vertical videos (Reels, TikTok, Shorts) expand into immersive full portrait without shrinking, while widescreen videos automatically rotate to landscape.
- **Playback Speed Selector**: Native speed controls (`0.5x`, `0.75x`, `1.0x`, `1.25x`, `1.5x`, `2.0x`) powered by `_player.setRate(speed)`.
- **Repeat / Loop Mode**: One-tap toggle in the bottom controls and options menu for continuous looping of short clips.
- **Interactive Video Zoom In/Out**: Full pinch-to-zoom and pan support up to 5x magnification across all playback states — before playing (preview poster), during live 60 FPS playback, and while paused. Features an animated floating scale pill with instant one-tap zoom reset and gesture conflict isolation against page swiping or pull-to-dismiss.
- **YouTube-Style Double-Tap Seek**: Split-screen double-tap seek (-10s / +10s) with animated feedback pill.
- **Ergonomic Controls**: Prominent 64dp Play/Pause button, 36dp Rewind 10s, and 36dp Fast-Forward 10s buttons with spring tap physics.

### High-Fidelity Photo Viewer & Media Tools
- **Spring-Damped Drag-to-Dismiss with Hero Return**: Pull down on any photo with natural spring damping (`SpringSimulation`) and proportional scaling. On release, the photo seamlessly flies back into its exact grid tile via dynamic Hero shared element transitions.
- **Refined Pinch-To-Zoom & Auto-Hiding Controls**: Seamless zoom in/out transitions with elastic bounds; top and bottom bars automatically fade out when zooming/pinching and reappear upon returning to normal scale.
- **Multi-Touch Gesture Isolation**: Dedicated multi-touch pointer tracking prevents accidental pull-down dismissals while pinching or panning zoomed images.
- **Native "Set as Wallpaper"**: Direct integration with Android system wallpaper chooser via `ACTION_ATTACH_DATA`.
- **Rename Media**: Local file renaming dialog updating storage, Android MediaStore, and global UI state in real-time.
- **Modern Top Bar**: Clean header with quick navigation, filename display, timestamp, and quick-action menu (rename, copy path, file details, share).
- **Bottom Action Bar**: Dedicated bottom bar featuring direct move-to-trash/delete, share, and metadata inspection.

### Instant Optimistic Deletion & Trash System
- **Recycle Bin (`.trash`)**: Stage deleted files safely in a local trash folder with one-tap restoration.
- **Zero-Latency UI Removal**: Deleted or trashed items vanish immediately (0ms delay) with optimistic in-memory state updates.
- **Unclipped Dialogs**: Clean, responsive confirmation dialogs formatted to prevent broken text wraps and overflow across all screen sizes.
- **Automatic Media Store Sync**: Automatic cache clearing ensuring deleted files do not reappear.

### Comprehensive Theming & Easter Egg
- **Modern Card-Based Theme Picker**: Interactive cards featuring badge icons, gradient previews, and descriptions for each visual mode.
- **Material 3 Theming**: System Default, Light Mode, and Dark Mode.
- **Pure AMOLED Mode**: True pitch-black (`#000000`) surfaces for maximum OLED battery savings.
- **AMOLED Sakura Mode 🌸**: Secret theme featuring Japanese Sakura pink accents over deep pitch-black backgrounds.
- **Easter Egg**: Tap the developer profile avatar 10 times in Settings to unlock the secret AMOLED Sakura theme!
- **Developer Card**: Dedicated About & Maintainer card in Settings with build and architecture information.

### Over-The-Air (OTA) Updates & 64-Bit Architecture
- Integrated update service that queries GitHub Releases for newer application versions.
- **Dedicated 64-Bit ARM Build**: Streamlined specifically for modern 64-bit ARM devices (`arm64-v8a`), maximizing runtime performance, decoding speed, and memory efficiency.
- **Package Conflict Prevention**: Standardized release signing keys across all version updates, eliminating `INSTALL_FAILED_UPDATE_INCOMPATIBLE` errors.
- **Reliable OTA Dialog Delivery**: Top-level `rootNavigatorKey` integration guarantees update confirmation modals and download progress sheets reliably mount from any screen context.
- In-app APK downloading with live progress tracking and automated installation dispatch via Android FileProvider (`com.phantek.virgo.spica.fileprovider`).
- Automatic cleanup of temporary installer packages upon completion.

### Memory & Performance Architecture
- **Persistent Disk Thumbnail Caching**: Two-layer cache (memory + local disk storage) ensures instantaneous grid loading on subsequent launches without redundant CPU decoding.
- **Optimized Global ImageCache**: Configured with a 256MB / 100-item cache boundary, paired with background lifecycle memory trimming (`trimMemory()`) when minimized to prevent Android Low Memory Killer (LMK) eviction.
- **Dependency Pruning**: Removed 40 redundant sub-dependencies from the build chain to keep the application binary lean and fast.

---

## Architecture and Tech Stack

| Category | Technology | Purpose |
|---|---|---|
| Application ID | `com.phantek.virgo.spica` | Unique package identifier for Android OS |
| Framework | Flutter 3.47+ (Dart 3.x) | Cross-platform UI toolkit targeting Android |
| State Management | Flutter Riverpod 2 (`flutter_riverpod`) | Reactive, compile-safe dependency injection and state |
| Video Engine | MediaKit (`media_kit`, `media_kit_video`, `media_kit_libs_android_video`) | Native MPV and FFmpeg playback pipeline |
| Image Viewer | PhotoView (`photo_view`) | High-resolution image viewing with gesture support |
| Media Management | `photo_manager`, `permission_handler` | Scoped storage access, Android 14+ partial grants, and permissions |
| Local Preferences | `shared_preferences` | Key-value persistence for user settings |
| Networking | `http`, `url_launcher` | GitHub Releases OTA checks and external repository links |
| Target Platform | Android 5.0+ to Android 16 (API 21 to 36/37) | Comprehensive compatibility across Android versions |

---

## Project Structure

```text
lib/
|-- app/
|   |-- router.dart              # Application route definitions and navigation extensions
|   `-- theme.dart               # Material 3 Light, Dark, AMOLED, and AMOLED Sakura themes
|-- core/
|   |-- enums/                   # Filter, sort, and theme enumeration models
|   |-- models/                  # MediaItem, Album, TrashItem, and SettingsModel data structures
|   |-- providers/               # Global Riverpod state providers (media, trash, settings)
|   |-- services/                # MediaKit setup, PhotoManager, permission, trash, share, and update services
|   |-- utils/                   # Formatting, duration, date helpers, and file utilities
|   `-- widgets/                 # Reusable UI components (AnimatedFlameTitle, BouncyTap)
|-- features/
|   |-- gallery/                 # Grid gallery, albums view, album detail screen, and filter bar
|   |-- player/                  # Image viewer, MPV-based video player, and rename dialog
|   |-- settings/                # User preferences, modern dialogs, exclusions, and Developer card
|   |-- trash/                   # Recycle bin management and restoration UI
|   `-- update/                  # GitHub Releases client, download service, and OTA dialog
`-- main.dart                    # Application entry point, smooth theme transitions, and boot sequence
```

---

## Getting Started

### Prerequisites

Ensure the following tools are installed on your workstation:

- Flutter SDK (version 3.47.0 or newer)
- Android SDK (API Level 36/37 platform tools and build tools)
- Java Development Kit (JDK 17)
- Git

Verify your environment readiness by running:
```bash
flutter doctor
```

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/zerabyte88/phantek-gallery.git
   cd phantek-gallery
   ```

2. Fetch project dependencies:
   ```bash
   flutter pub get
   ```

3. Connect an Android device or launch an emulator, then execute:
   ```bash
   flutter run
   ```

---

## Build and Release

### Debug Build
Generate a debug APK for development and testing:
```bash
flutter build apk --debug
```

### Release Build
Generate an optimized release APK:
```bash
flutter build apk --release
```
The output file is located at `build/app/outputs/flutter-apk/app-release.apk`.

### 64-Bit ARM Release Build
To produce a lightweight, optimized release package specifically for 64-bit ARM devices (`arm64-v8a`):
```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```

### Keystore Configuration
For signed release distributions, configure GitHub Repository Secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) for automated CI/CD builds, or create a `key.properties` file in the `android/` directory for local builds:

```properties
storePassword=your_keystore_password
keyPassword=your_key_password
keyAlias=your_key_alias
storeFile=path/to/your_keystore.jks
```

If `key.properties` is absent, local Gradle builds will automatically fall back to the default debug signing configuration.

---

## Android Permissions

Phantek Gallery declares only the permissions necessary for local media discovery and self-hosted updates, with version-conditional scoping:

| Permission | Scope | Justification |
|---|---|---|
| `READ_MEDIA_IMAGES` | Android 13+ (API 33+) | Read access to photo media files |
| `READ_MEDIA_VIDEO` | Android 13+ (API 33+) | Read access to video media files |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Android 14+ (API 34+) | Granular / partial access when user selects specific photos or videos |
| `READ_EXTERNAL_STORAGE` | Android 12 and below (API ≤ 32) | Legacy read access to local media storage |
| `WRITE_EXTERNAL_STORAGE` | Android 10 and below (API ≤ 29) | Legacy write access for file deletion operations |
| `MANAGE_EXTERNAL_STORAGE` | Android 11+ (API 30+) | Optional permission for deep trash management across external storage |
| `ACCESS_MEDIA_LOCATION` | Android 10+ (API 29+) | Reading media metadata and location coordinates from EXIF tags |
| `INTERNET` | All versions | Required exclusively for checking and downloading updates from GitHub Releases |
| `REQUEST_INSTALL_PACKAGES` | Android 8+ (API 26+) | Direct prompt to install downloaded OTA update APKs |

---

## CI/CD Workflow

The repository includes an automated GitHub Actions workflow configured in `.github/workflows/build-apk.yml`. It supports one-click manual dispatch (`workflow_dispatch`) to compile release APKs on Ubuntu runners with:

- Automated JDK 17 and Flutter stable setup.
- Keystore decoding via repository secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`).
- Dedicated 64-bit ARM packaging (`arm64-v8a`) producing `Phantek-Gallery-arm64-v8a.apk`, stripped of legacy 32-bit and heavy x86 binaries.
- Standardized signing keys ensuring seamless, conflict-free OTA updates across releases.
- Artifact upload retaining APK builds for 30 days.

---

## License

Phantek Gallery is free and open-source software licensed under the **[GNU General Public License v3.0 (GPLv3)](LICENSE)**.

- **Freedom to run** the software for any purpose.
- **Freedom to study** how the program works and adapt it to your needs.
- **Freedom to redistribute** copies to help others.
- **Freedom to improve** the program and release your improvements to the public under the same copyleft license terms.

This copyleft licensing complies with the distribution requirements for bundled native media playback dependencies, including MediaKit (`media_kit_libs_android_video` / MPV player engine / FFmpeg).

For the full legal terms and conditions, please consult the [LICENSE](LICENSE) file located in the root of this repository.

---

<div align="center">
  <br/>
  <a href="https://github.com/zerabyte88">
    <img src="https://github.com/zerabyte88.png" width="48" height="48" style="border-radius: 50%;" alt="zerabyte88" />
  </a>
  <br/>
  <sub>Developed with ❤️ by <a href="https://github.com/zerabyte88">zerabyte88</a> (Creator & Maintainer)</sub>
</div>