# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" alt="Phantek Gallery Icon" width="120" style="border-radius: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.25);" />
</p>

<div align="center">
  <img src="https://img.shields.io/static/v1?label=Platform&message=Android&color=059669&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Platform" />
  <img src="https://img.shields.io/static/v1?label=Architecture&message=arm64-v8a&color=7c3aed&style=for-the-badge&logo=arm&logoColor=white&labelColor=0f172a" alt="Architecture" />
  <img src="https://img.shields.io/static/v1?label=Application%20ID&message=com.phantek.virgo.spica&color=6366f1&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Application ID" />
  <a href="https://github.com/zerabyte88/phantek-gallery/releases"><img src="https://img.shields.io/static/v1?label=Version&message=v2.7.9&color=2563eb&style=for-the-badge&logo=github&logoColor=white&labelColor=0f172a" alt="Version" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/static/v1?label=License&message=GPLv3&color=475569&style=for-the-badge&logo=gnu&logoColor=white&labelColor=0f172a" alt="License" /></a>
</div>

<br/>

**Phantek Gallery** is an offline, photo and video gallery application for Android. Built with Flutter and powered by the native MPV playback engine via MediaKit, it delivers fluid media rendering, responsive navigation, and complete data privacy without third-party tracking, analytics, or mandatory cloud dependencies. Fully compliant with modern Android standards, including Android 14+ / 16 partial media grants and edge-to-edge layouts.

---

## Key Features

### 1. Modern & Sleek User Interface
- **Theme-Adaptive Animated Headers:** Procedural real-time animations customized for every theme mode (**Snowfall** Nordic Winter Village with snow-capped rolling hills, cozy glowing cabins with animated chimney smoke, snowy pine trees, and drifting crystalline snowflakes; **Midnight** glowing crescent moon, twinkling starfield & falling meteors; secret **Sakura** drifting cherry blossoms & delicate tree branch; **Sunburst** radiant morning sunrise & golden sparkles).
- **Harmonized Title Badges:** Adaptive animated title badge with dynamic sweep shader gradients and icons matching active themes (including Nordic Frost Ice Blue and snowflake icon for Snowfall mode).
- **Glitch-Free Sliding Capsule Navigation:** Unified, single-indicator capsule tab filter bar (`All`, `Photos`, `Videos`, `Albums`) with real-time 1:1 finger tracking via `PageController` and synchronized text styling.
- **Natural Fluid Swipe-to-Dismiss:** Dynamic image scaling, smooth corner rounding, instant background/overlay reactivity, synchronized underlying grid scrolling, and organic spring physics for viewer dismissal.
- **Tactile Bouncy Feedback:** Spring-scale micro-animations (`BouncyTap`) across all interactive cards, chips, dialogs, and controls.

### 2. High-Performance Media Organization & Search
- **Butter-Smooth Tab Swiping:** GPU `RepaintBoundary` texture layer isolation, instant `animateToPage` curve transitions, and O(1) tab list memoization to deliver a stutter-free, smooth experience without frame drops or raster jitter during category swipe.
- **Smart Timeline & Album Grouping:** Browse media chronologically or organized into native folders (Camera, DCIM, Screenshots, Downloads, etc.).
- **Native Directory Picker for Excluded Folders:** Seamless folder exclusion selection directly via Android's native file manager / SAF folder picker without manual path typing.
- **In-Album Filtering & Sorting:** Comprehensive filtering (`All`, `Photos`, `Videos`) and 4-way sorting (Newest, Oldest, Name A-Z, Name Z-A) inside individual album detail screens.
- **Customizable Grid Columns:** Interactive column picker dialog with visual mini-grid previews for 2, 3, 4, or 5 grid columns for photos and albums independently.
- **Folder Blacklisting & Favorites:** Pin favorite media items and exclude unwanted private or system folders from indexing.

### 3. Hardware-Accelerated Video Playback & Technical Inspection
- **Configurable Auto-Playback:** Toggleable instant playback on screen entry or swipe, complete with seamless thumbnail crossfade and zero black screen flashes.
- **MediaKit & MPV Engine:** Native MPV and FFmpeg integration for stutter-free playback of MKV, MP4, MOV, and high-bitrate 4K video streams with a smooth playback experience.
- **Auto-Copy Hardware Decoding:** Seamless hardware-to-software fallback decoding (`hwdec: auto-copy`) across H.264, H.265/HEVC, and VP9 codecs.
- **Technical Video Inspector:** Live extraction and display of video **Frame Rate (FPS)** and **Video Codec** directly inside the media Details sheet.
- **Interactive 5x Video Zoom:** Pinch-to-zoom and pan during live playback, paused state, or preview poster, complete with animated floating scale indicator and instant one-tap reset.
- **Proactive Texture Optimization:** Instant GPU texture detaching on horizontal swipe to free decoder pipelines and enable a fluid, ultra-smooth swiping experience with zero black flashes.
- **Elevated Controls & Floating Seekbar Preview:** Centered play button with automatic fade-out during swipe navigation, custom gesture-captured scrubber bar with seek-on-release precision, gapless frame transitions, elevated seekbar (+32dp) with real-time adaptive thumbnail tooltip preview (+44-50dp with pointer caret), and fullscreen controls.

### 4. High-Fidelity Photo Viewer & Gesture Dismissal
- **Spring-Damped Drag-to-Dismiss:** Natural pull-down gesture physics with velocity tracking and proportional scaling.
- **Pixel-Perfect Hero Return & Active Grid Sync:** Smooth morphing shuttle with contain-to-cover crossfade, fallback shuttle rendering, and real-time active grid viewport synchronization, ensuring that swiping between media and dismissing always flies seamlessly back to the active grid tile without visual glitches or cut-offs.
- **Interactive Pinch-to-Zoom:** High-resolution zoom with elastic overscroll bounds, multi-touch gesture isolation, and auto-fading overlay controls.
- **Streamlined Actions:** Ergonomic 4-button footer (Share, Favorite, Details, Delete) and clean bottom-sheet More menu for Rename, Set as Wallpaper, and Copy Path.

### 5. Secure Recycle Bin & Optimistic File Management
- **Recycle Bin (`.trash`):** Safely stage deleted items in a local hidden trash directory with instant one-tap restoration.
- **Dedicated Trash Viewer & Unified Dialogs:** Streamlined bottom action bar in the trash viewer with direct access to Restore, Details, and Permanent Delete, with uniform delete confirmation sheets matching the main gallery.
- **0ms Optimistic UI Removal:** Deleted or trashed items vanish immediately from the UI with zero latency while file I/O executes asynchronously.
- **Batch Selection Mode:** Multi-select photos, videos, or albums for bulk deletion or restoration.

### 6. Multi-Language Internationalization & Theming
- **22 Supported Languages:** English (default), Indonesian (Bahasa Indonesia), Arabic (العربية), Chinese Simplified (简体中文), Chinese Traditional (繁體中文), Danish (Dansk), Dutch (Nederlands), Finnish (Suomi), French (Français), German (Deutsch), Hindi (हिन्दी), Italian (Italiano), Japanese (日本語), Korean (한국어), Malay (Bahasa Melayu), Norwegian (Norsk), Portuguese (Português), Russian (Русский), Spanish (Español), Swedish (Svenska), Thai (ไทย), and Vietnamese (Tiếng Việt). Sorted alphabetically (A-Z) with System Default pinned at top, featuring native country flag emojis inside modern selection cards.
- **Distinct Thematic Visual Modes:** System Default (follows device appearance), **Sunburst** (warm and bright radiant golden sunrise), **Snowfall** (serene snowy winter village), and **Midnight** (starry night sky with glowing crescent moon and meteors).
- **Secret Thematic Easter Egg:** Unlock the hidden **Sakura** 🌸 theme (soft elegance of drifting cherry blossom petals and delicate floral ambiance) by tapping the "Phantek" header title 10 times consecutively.

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

## System Requirements

| Requirement | MINIMUM | RECOMMENDED |
| :--- | :--- | :--- |
| **OS** | Android 8.0 (API 26) or higher | Android 13+ (API 33+) / Android 14+ (API 34+) |
| **Processor** | 64-bit Octa-Core 2.0 GHz (Snapdragon 685, Helio G99, Unisoc T820) | Qualcomm Snapdragon 7/8 series, MediaTek Dimensity 7000/8000+ series |
| **Memory** | 3 GB RAM | 6 GB RAM or higher |
| **Graphics** | Adreno 610 / Mali-G57 or equivalent (OpenGL ES 3.0 support) | Adreno 642L / Mali-G68 or higher (OpenGL ES 3.2 / Vulkan support) |
| **Storage** | 150 MB available space (eMMC 5.1) | 500 MB available space (UFS 2.2 / UFS 3.1+) |
| **Additional Notes** | 64-bit ARM architecture (`arm64-v8a`) required. Disabling **Auto-Play Video** in Settings is recommended for entry-level storage. | Enables gapless hardware-accelerated 4K 60fps video playback, instant timeline scrolling, and smooth 100MP+ photo zoom. |

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