# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" alt="Phantek Gallery Icon" width="120" style="border-radius: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.25);" />
</p>

<div align="center">
  <img src="https://img.shields.io/static/v1?label=Platform&message=Android&color=059669&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Platform" />
  <img src="https://img.shields.io/static/v1?label=Architecture&message=arm64-v8a&color=7c3aed&style=for-the-badge&logo=arm&logoColor=white&labelColor=0f172a" alt="Architecture" />
  <img src="https://img.shields.io/static/v1?label=Application%20ID&message=com.phantek.virgo.spica&color=6366f1&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Application ID" />
  <a href="https://github.com/zerabyte88/phantek-gallery/releases"><img src="https://img.shields.io/static/v1?label=Version&message=v2.4.14&color=2563eb&style=for-the-badge&logo=github&logoColor=white&labelColor=0f172a" alt="Version" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/static/v1?label=License&message=GPLv3&color=475569&style=for-the-badge&logo=gnu&logoColor=white&labelColor=0f172a" alt="License" /></a>
</div>

<br/>

**Phantek Gallery** is an offline-first, high-performance photo and video gallery application for Android (`com.phantek.virgo.spica`). Built with Flutter and powered by the native MPV playback engine via MediaKit, it delivers fluid media rendering, responsive navigation, and complete data privacy without third-party tracking, analytics, or mandatory cloud dependencies. Fully compliant with modern Android standards, including Android 14+ / 16 partial media grants and edge-to-edge layouts.

---

## Key Features

### 1. Modern & Sleek User Interface
- **Unified Segmented Capsule Filter Bar:** Clean, single-row pill navigation (`All`, `Photos`, `Videos`, `Albums`) with glowing active tab highlights and instant sort modal access.
- **Pill-Shaped Modern Search Bar:** Sleek, rounded search bar integrated into the header for real-time media and album filtering without layout clutter.
- **Seamless Header Transition:** Borderless AppBar design without harsh divider lines for a continuous, immersive gallery feed.
- **Animated Flame Brand:** Centered AppBar badge with continuous fiery gradient pulsing and dynamic fire icon (`🔥 Phantek`).
- **Tactile Bouncy Feedback:** Spring-scale micro-animations (`BouncyTap`) across all interactive cards, chips, dialogs, and controls.

### 2. High-Performance Media Organization & Search
- **Smart Timeline & Album Grouping:** Browse media chronologically or organized into native folders (Camera, DCIM, Screenshots, Downloads, etc.).
- **Swipe Category Navigation:** Fluid horizontal gestures between categories with `KeepAlive` state preservation to eliminate frame drops.
- **In-Album Filtering & Sorting:** Comprehensive filtering (`All`, `Photos`, `Videos`) and 4-way sorting (Newest, Oldest, Name A-Z, Name Z-A) inside individual album detail screens.
- **Customizable Grid Columns:** Interactive column picker dialog with visual mini-grid previews for 2, 3, 4, or 5 grid columns for photos and albums independently.
- **Folder Blacklisting & Favorites:** Pin favorite media items and exclude unwanted private or system folders from indexing.

### 3. Hardware-Accelerated Video Playback & Technical Inspection
- **MediaKit & MPV Engine:** Native MPV and FFmpeg integration for stutter-free playback of MKV, MP4, MOV, and high-bitrate video streams up to 4K 60FPS.
- **Auto-Copy Hardware Decoding:** Seamless hardware-to-software fallback decoding (`hwdec: auto-copy`) across H.264, H.265/HEVC, and VP9 codecs.
- **Technical Video Inspector:** Live extraction and display of video **Frame Rate (FPS)** and **Video Codec** directly inside the media Details sheet.
- **Interactive 5x Video Zoom:** Pinch-to-zoom and pan during live playback, paused state, or preview poster, complete with animated floating scale indicator and instant one-tap reset.
- **Proactive Texture Optimization:** Instant GPU texture detaching on horizontal swipe to free decoder pipelines and enable fluid 60/120 FPS swiping with zero black flashes.
- **Advanced Player Controls:** YouTube-style double-tap seek (-10s / +10s), native playback speed selector (`0.5x` - `2.0x`), loop repeat toggle, and smart portrait/landscape aspect ratio expansion.

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

### 6. Comprehensive Theming & Secret Easter Egg
- **Material 3 Themes:** System Default, Clean Light, and Slate Dark.
- **Pure AMOLED Pitch-Black:** Deep true black (`#000000`) surfaces for maximum OLED battery savings.
- **Secret AMOLED Sakura Theme 🌸:** Exclusive Japanese Sakura pink accent theme over pure black.
- **Developer Easter Egg:** Tap the maintainer avatar 10 times in Settings to unlock the secret AMOLED Sakura mode!

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

- **v2.4.14 (Build 20):**
  - **Modern Front Page Redesign:** Unified capsule segmented filter navigation, pill-shaped search bar, borderless header, and refined grid spacing.
  - **Video Technical Metadata:** Live display of video **Frame Rate (FPS)** and **Video Codec** in the Details sheet.
  - **Perfected Swipe-to-Dismiss:** Seamless Hero return transition with contain-to-cover crossfade and hard-edge cell clipping.
  - **Enhanced Trash & Footers:** Dedicated bottom action bar for trash viewer (Restore, Details, Delete), streamlined photo/video action bars, and smooth bottom sheet menus.
- **v1.3.13 (Build 19):**
  - Redesigned modern Settings screen with clean cards, theme-coordinated icon badges, and bouncy tap feedback.
  - Centered video play buttons, natural gesture pull-down dismissal, and unified overlay controls.
  - Reduced memory footprint and streamlined OTA update checks.

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