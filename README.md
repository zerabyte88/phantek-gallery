# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" alt="Phantek Gallery Icon" width="120" style="border-radius: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.25);" />
</p>

<div align="center">
  <img src="https://img.shields.io/static/v1?label=Platform&message=Android&color=059669&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Platform" />
  <img src="https://img.shields.io/static/v1?label=Architecture&message=arm64-v8a&color=7c3aed&style=for-the-badge&logo=arm&logoColor=white&labelColor=0f172a" alt="Architecture" />
  <img src="https://img.shields.io/static/v1?label=Application%20ID&message=com.phantek.virgo.spica&color=6366f1&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Application ID" />
  <a href="https://github.com/zerabyte88/phantek-gallery/releases"><img src="https://img.shields.io/static/v1?label=Version&message=v2.6.4&color=2563eb&style=for-the-badge&logo=github&logoColor=white&labelColor=0f172a" alt="Version" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/static/v1?label=License&message=GPLv3&color=475569&style=for-the-badge&logo=gnu&logoColor=white&labelColor=0f172a" alt="License" /></a>
</div>

<br/>

**Phantek Gallery** is an offline-first, high-performance photo and video gallery application for Android (`com.phantek.virgo.spica`). Built with Flutter and powered by the native MPV playback engine via MediaKit, it delivers fluid media rendering, responsive navigation, and complete data privacy without third-party tracking, analytics, or mandatory cloud dependencies. Fully compliant with modern Android standards, including Android 14+ / 16 partial media grants and edge-to-edge layouts.

---

## Key Features

### 1. Modern & Sleek User Interface
- **Theme-Adaptive Animated Headers:** Procedural real-time animations customized for every theme mode (AMOLED glowing crescent moon, twinkling starfield & falling meteors; AMOLED Sakura drifting cherry blossoms & delicate tree branch; Dark mode flowing cyber plasma aurora ribbons & cosmic embers; Light mode radiant morning sunburst & golden sparkles).
- **Harmonized Title Badges:** Adaptive animated title badge with dynamic sweep shader gradients and icons matching active themes.
- **Glitch-Free Sliding Capsule Navigation:** Unified, single-indicator capsule tab filter bar (`All`, `Photos`, `Videos`, `Albums`) with real-time 1:1 finger tracking via `PageController` and synchronized text styling.
- **Natural Fluid Swipe-to-Dismiss:** Dynamic image scaling, smooth corner rounding, instant background/overlay reactivity, and organic spring physics for viewer dismissal.
- **Tactile Bouncy Feedback:** Spring-scale micro-animations (`BouncyTap`) across all interactive cards, chips, dialogs, and controls.

### 2. High-Performance Media Organization & Search
- **120 FPS Butter-Smooth Tab Swiping:** GPU `RepaintBoundary` texture layer isolation, instant `animateToPage` curve transitions, and O(1) tab list memoization to eliminate frame drops and raster jitter during category swipe.
- **Smart Timeline & Album Grouping:** Browse media chronologically or organized into native folders (Camera, DCIM, Screenshots, Downloads, etc.).
- **Native Directory Picker for Excluded Folders:** Seamless folder exclusion selection directly via Android's native file manager / SAF folder picker without manual path typing.
- **In-Album Filtering & Sorting:** Comprehensive filtering (`All`, `Photos`, `Videos`) and 4-way sorting (Newest, Oldest, Name A-Z, Name Z-A) inside individual album detail screens.
- **Customizable Grid Columns:** Interactive column picker dialog with visual mini-grid previews for 2, 3, 4, or 5 grid columns for photos and albums independently.
- **Folder Blacklisting & Favorites:** Pin favorite media items and exclude unwanted private or system folders from indexing.

### 3. Hardware-Accelerated Video Playback & Technical Inspection
- **Configurable Auto-Playback:** Toggleable instant playback on screen entry or swipe, complete with seamless thumbnail crossfade and zero black screen flashes.
- **MediaKit & MPV Engine:** Native MPV and FFmpeg integration for stutter-free playback of MKV, MP4, MOV, and high-bitrate video streams up to 4K 60FPS.
- **Auto-Copy Hardware Decoding:** Seamless hardware-to-software fallback decoding (`hwdec: auto-copy`) across H.264, H.265/HEVC, and VP9 codecs.
- **Technical Video Inspector:** Live extraction and display of video **Frame Rate (FPS)** and **Video Codec** directly inside the media Details sheet.
- **Interactive 5x Video Zoom:** Pinch-to-zoom and pan during live playback, paused state, or preview poster, complete with animated floating scale indicator and instant one-tap reset.
- **Proactive Texture Optimization:** Instant GPU texture detaching on horizontal swipe to free decoder pipelines and enable fluid 60/120 FPS swiping with zero black flashes.
- **Elevated Controls & Fading Playback Indicator:** Centered play button with automatic fade-out during swipe navigation, elevated seekbar (+32dp) with timestamps and fullscreen button.

### 4. High-Fidelity Photo Viewer & Gesture Dismissal
- **Spring-Damped Drag-to-Dismiss:** Natural pull-down gesture physics with velocity tracking and proportional scaling.
- **Pixel-Perfect Hero Return:** Smooth morphing shuttle with contain-to-cover crossfade and hard-edge grid clipping, ensuring photos and videos land precisely within their grid cell without flicker or over-expansion.
- **Interactive Pinch-to-Zoom:** High-resolution zoom with elastic overscroll bounds, multi-touch gesture isolation, and auto-fading overlay controls.
- **Streamlined Actions:** Ergonomic 4-button footer (Share, Favorite, Details, Delete) and clean bottom-sheet More menu for Rename, Set as Wallpaper, and Copy Path.

### 5. Secure Recycle Bin & Optimistic File Management
- **Recycle Bin (`.trash`):** Safely stage deleted items in a local hidden trash directory with instant one-tap restoration.
- **Dedicated Trash Viewer:** Streamlined bottom action bar in the trash viewer with direct access to Restore, Details, and Permanent Delete.
- **0ms Optimistic UI Removal:** Deleted or trashed items vanish immediately from the UI with zero latency while file I/O executes asynchronously.
- **Batch Selection Mode:** Multi-select photos, videos, or albums for bulk deletion or restoration.

### 6. Multi-Language Internationalization & Theming
- **11 Supported Languages:** English, Indonesian (Bahasa Indonesia), Chinese Simplified (简体中文), Spanish (Español), Portuguese (Português), Japanese (日本語), Korean (한국어), Hindi (हिन्दी), Arabic (العربية), French (Français), and Russian (Русский).
- **Material 3 Themes:** System Default, Clean Light, and Slate Dark.
- **Pure AMOLED Pitch-Black:** Deep true black (`#000000`) surfaces for maximum OLED battery savings.
- **Secret AMOLED Sakura Theme 🌸:** Exclusive Japanese Sakura pink accent theme over pure black.
- **Developer Easter Egg:** Tap the maintainer avatar or Phantek title 10 times in Settings or Appbar to unlock the secret AMOLED Sakura mode!

### 7. Over-The-Air (OTA) Updates & 64-Bit Architecture
- **Automated GitHub Releases Updater:** In-app version verification, background APK download with live progress bar, and automated installation dispatch via Android `FileProvider`.
- **Streamlined 64-Bit ARM Build (`arm64-v8a`):** Stripped of legacy 32-bit and heavy x86 binaries for optimal execution speed, reduced binary size, and maximum memory efficiency.

---

## Format & Codec Matrix

| Category | Container / Format | Codecs Supported | Technical Notes |
| :--- | :--- | :--- | :--- |
| **Photo** | `.jpg`, `.jpeg`, `.png`, `.webp`, `.heic`, `.gif`, `.bmp` | Standard Image Codecs | Capped downsampling at 4096px to prevent out-of-memory on 100MP+ sensors |
| **Video** | `.mp4` | H.264 / AVC, H.265 / HEVC, VP9 | Hardware accelerated with `+faststart` streaming support |
| **Video** | `.mkv` | H.264 / AVC, H.265 / HEVC, VP9 | Full subtitle and multi-audio track parsing via MPV |
| **Video** | `.mov` | H.264 / AVC, H.265 / HEVC | Native QuickTime video stream playback |
| **Video** | `.webm` | VP8, VP9, AV1 | Native playback support |

---

## Architecture and Tech Stack

| Component | Technology | Description |
| :--- | :--- | :--- |
| **Application ID** | `com.phantek.virgo.spica` | Android package identifier |
| **UI Framework** | Flutter 3.47+ (Dart 3.x) | Modern declarative reactive UI framework |
| **State Management** | Flutter Riverpod 2 (`flutter_riverpod`) | Compile-safe reactive state architecture |
| **Video Engine** | MediaKit (`media_kit`, `media_kit_video`) | High-performance MPV + FFmpeg native playback pipeline |
| **Media Extraction** | `photo_manager`, `permission_handler` | Scoped storage access and Android 14+/16 partial media grants |
| **Preferences** | `shared_preferences` | On-device key-value persistence for settings |
| **OTA Delivery** | `http`, `package_info_plus`, `path_provider` | In-app GitHub Releases OTA client and APK installer |

---

## Build & Compilation

Phantek Gallery utilizes native C/C++ libraries bundled through MediaKit and MPV. The application is compiled specifically for **64-bit ARM (`arm64-v8a`)** architectures for peak memory and rendering efficiency.

### Local APK Build Command

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```

The compiled release APK will be generated at:
`build/app/outputs/flutter-apk/Phantek-Gallery-arm64-v8a.apk`

---

## Android Permissions

| Permission | Minimum Version | Description |
| :--- | :--- | :--- |
| `READ_MEDIA_IMAGES` | Android 13 (API 33+) | Read access to local photo media files |
| `READ_MEDIA_VIDEO` | Android 13 (API 33+) | Read access to local video media files |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Android 14 (API 34+) | Granular partial media access selected by the user |
| `READ_EXTERNAL_STORAGE` | Android 12 & below (API ≤ 32) | Legacy read access to storage files |
| `WRITE_EXTERNAL_STORAGE` | Android 10 & below (API ≤ 29) | Legacy file deletion and renaming access |
| `MANAGE_EXTERNAL_STORAGE` | Android 11+ (API 30+) | Deep storage access for complete recycle bin management |
| `ACCESS_MEDIA_LOCATION` | Android 10+ (API 29+) | Reading media metadata and location coordinates from EXIF tags |
| `INTERNET` | All versions | Required exclusively for checking and downloading updates from GitHub Releases |
| `REQUEST_INSTALL_PACKAGES` | Android 8+ (API 26+) | Direct prompt to install downloaded OTA update APKs |

---

## Version History

### v2.6.4 (Build 29)
* **Landscape Player Bottom Controls Redesign:** Compacted the bottom control bar and seekbar closer to the screen edge in horizontal orientation. Replaced bottom action buttons with dedicated icon-only controls for Playback Speed, Loop, Fullscreen, Screen Rotation, and More (⋮).
* **Vertical Video Display & Fullscreen Button Removal:** Vertical (portrait) videos now expand to fill the screen (`BoxFit.cover`) within `SafeArea` without letterbox zoom-out artifacts, both before and during playback. The fullscreen button is automatically hidden for vertical videos across all toolbars and the More menu, while remaining fully accessible for horizontal videos.
* **Non-Obstructive Portrait Play Button:** Center play button in portrait mode now only appears initially prior to the first playback and stays hidden when paused, preventing obstruction during video zooming/pinching.

### v2.6.3 (Build 28)
* **Keep Screen On While Viewing:** Added configurable native window flag toggle (`FLAG_KEEP_SCREEN_ON`) in Settings (Appearance) to keep screen illuminated during photo viewing and video playback without external dependencies.
* **Full 11-Language Localization Overhaul:** Complete dictionary coverage and translations across all supported languages (ID, EN, ZH, ES, PT, JA, KO, HI, AR, FR, RU), eliminating all remaining hardcoded English text.
* **Auto-Playback & Performance Tuning:** Configurable instant video auto-playback on view/swipe, plus butter-smooth 120 FPS tab swiping optimizations with zero black frame flashes.
* **Elevated Controls & Visual Enhancements:** Refined AMOLED falling meteors trajectory, enhanced Dark aurora ribbon animations, and redesigned Clean Light daytime theme.

### v2.6.2 (Build 27)
* **Header Search Bar & Filter Bar Collision Fix:** Constrained the search capsule strictly within the 56dp toolbar height (`topPadding + kToolbarHeight`), cleanly separating it from category filter chips (All, Photos, Videos, Albums) with zero overlapping.
* **Landscape Video Fullscreen Boundary & Inset Fix:** Reconfigured `SafeArea` insets for fullscreen landscape playback, implemented dynamic orientation keys on `InteractiveViewer`, and synchronized window metric resets to expand landscape videos edge-to-edge without shrinking or excessive black bars.
* **Large Video Aspect Ratio & Frame 0 Precision:** Introduced direct JPEG `SOF0`/`SOF2` header parsing in `ThumbnailService` to resolve visual orientation on frame 0, eliminating momentary zoom-in snaps for large (>200MB, ≥ 720×1280) and rotated videos.

### v2.6.1 (Build 26)
* **Centered Phantek Header Title:** Restored clean dead-center alignment for "Phantek" in the `AppBar` with responsive action alignment.
* **Smooth Unified Search Overlay:** Re-engineered search bar into a single-row flex overlay in `flexibleSpace` with cubic easing, eliminating boundary overlaps and rightward bleed into the Cancel button.
* **Video Orientation & Large Video Zoom Fix:** Corrected width/height swaps for 90° / 270° rotated videos and resolved frame 0 aspect ratio fallback for unindexed large video files (>100MB).
* **Instant Cold-Start Hero Animations & Gesture Reliability:** Added display fallback for cold start image transitions and refined gesture tracking to prevent stuck swipe-to-dismiss.

### v2.6.0 (Build 25)
* **Zero-Delay Video Transitions & Black Screen Elimination:** Eliminated momentary black screen flashes upon tapping videos or swiping horizontally between videos by retaining instant 0ms cached thumbnails until video frames render.
* **Aspect Ratio Preserved Hero Transitions:** Fixed vertical stretch distortion on landscape/non-square photos and videos during tap-to-open and swipe-to-dismiss Hero animations.
* **Animated Search Bar & Theme-Adaptive Cancel:** Redesigned the gallery search bar to expand smoothly from left to right across the `AppBar` with title fade-out and a theme-adaptive Cancel button.

### v2.5.17 (Build 24)
* **Seamless Continuous Header Animations:** Synchronized all harmonic frequencies and movement cycles to integer multiples, eliminating loop stutter across all themes.
* **Extended Header Canvas:** Header animation spans continuously across both `AppBar` and Filter/Sort Bar, eliminating empty spaces.
* **Enriched Sakura Tree Visuals:** Multi-tier natural branching, fresh green sakura leaves, and clustered radiant blossoms with buds.
* **Dark Theme Cyber Aurora Badge:** Synchronized border gradient and shimmer spark badge icon for Dark Mode.
* **Direct Tab Jump & Butter-Smooth Capsule Glides:** Direct navigation between tabs without intermediate page scrolling, paired with 60/120 FPS jitter-free capsule transitions via lazy page evaluation.

### v2.5.16 (Build 23)
* **Theme-Adaptive Animated Headers:** Procedural lightweight 60fps animations for AMOLED (moon, stars & meteors), AMOLED Sakura (falling sakura petals & branch), Dark (cyber plasma aurora waves & embers), and Light (radiant sunburst & sparkles).
* **Theme-Harmonized Title Badge:** Dynamic gradient borders and icons in `AnimatedFlameTitle` matching active theme mode while preserving the 10-tap Easter Egg.
* **Glitch-Free Tab Bar Animations:** Replaced separated tab backgrounds with a single sliding capsule indicator and synchronized typography to eliminate momentary white flashes.
* **Refined Swipe-to-Dismiss:** Proportionate drag scaling, corner radius morphing, instant overlay fading, and organic damping spring simulation.
* **Optimized Selection UI:** Replaced the favorite button with Select All in the multi-select bar for faster bulk management.
  
---

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**. Please see the [LICENSE](LICENSE) file for full license terms.

---

<div align="center">
  <br/>
  <a href="https://github.com/zerabyte88">
    <img src="https://github.com/zerabyte88.png" width="48" height="48" style="border-radius: 50%;" alt="zerabyte88" />
  </a>
  <br/>
  <sub>Developed with ❤️ by <a href="https://github.com/zerabyte88">zerabyte88</a> (Creator & Maintainer)</sub>
</div>