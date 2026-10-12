# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" alt="Phantek Gallery Icon" width="120" style="border-radius: 24px; box-shadow: 0 8px 24px rgba(0,0,0,0.25);" />
</p>

<div align="center">
  <img src="https://img.shields.io/static/v1?label=Platform&message=Android&color=059669&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Platform" />
  <img src="https://img.shields.io/static/v1?label=Architecture&message=arm64-v8a&color=7c3aed&style=for-the-badge&logo=arm&logoColor=white&labelColor=0f172a" alt="Architecture" />
  <img src="https://img.shields.io/static/v1?label=Application%20ID&message=com.phantek.virgo.spica&color=6366f1&style=for-the-badge&logo=android&logoColor=white&labelColor=0f172a" alt="Application ID" />
  <a href="https://github.com/zerabyte88/phantek-gallery/releases"><img src="https://img.shields.io/static/v1?label=Version&message=v2.7.4&color=2563eb&style=for-the-badge&logo=github&logoColor=white&labelColor=0f172a" alt="Version" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/static/v1?label=License&message=GPLv3&color=475569&style=for-the-badge&logo=gnu&logoColor=white&labelColor=0f172a" alt="License" /></a>
</div>

<br/>

**Phantek Gallery** is an offline, photo and video gallery application for Android. Built with Flutter and powered by the native MPV playback engine via MediaKit, it delivers fluid media rendering, responsive navigation, and complete data privacy without third-party tracking, analytics, or mandatory cloud dependencies. Fully compliant with modern Android standards, including Android 14+ / 16 partial media grants and edge-to-edge layouts.

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
- **Elevated Controls & Floating Seekbar Preview:** Centered play button with automatic fade-out during swipe navigation, custom gesture-captured scrubber bar with seek-on-release precision, gapless frame transitions, elevated seekbar (+32dp) with real-time adaptive thumbnail tooltip preview (+44-50dp with pointer caret), and fullscreen controls.

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
- **22 Supported Languages:** English (default), Indonesian (Bahasa Indonesia), Arabic (العربية), Chinese Simplified (简体中文), Chinese Traditional (繁體中文), Danish (Dansk), Dutch (Nederlands), Finnish (Suomi), French (Français), German (Deutsch), Hindi (हिन्दी), Italian (Italiano), Japanese (日本語), Korean (한국어), Malay (Bahasa Melayu), Norwegian (Norsk), Portuguese (Português), Russian (Русский), Spanish (Español), Swedish (Svenska), Thai (ไทย), and Vietnamese (Tiếng Việt). Sorted alphabetically (A-Z) with System Default pinned at top, featuring native country flag emojis inside modern selection cards.
- **Material 3 Themes:** System Default, Clean Light, and Slate Dark.
- **Pure AMOLED Pitch-Black:** Deep true black (`#000000`) surfaces for maximum OLED battery savings.
- **Secret AMOLED Sakura Theme 🌸:** Exclusive Japanese Sakura pink accent theme over pure black.
- **Developer Easter Egg:** Unlocked by tapping the "Phantek" header title 10 times consecutively.

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

### v2.7.5
* **Fluid Morph Expansion Animation (Google Photos / Apple Photos Style):** Redesigned the opening and closing transitions for photos and videos with a unified geometry-preserving `_buildHeroShuttle` using a custom `Cubic(0.2, 0.0, 0.0, 1.0)` curve and a 300ms duration. The corners smoothly morph between the grid tile's 8dp rounded corner and the viewer's 0dp border.
* **Precise Video Aspect Ratio Hero Bounds:** Solved the video opening jump and zoom-in glitch by wrapping destination video Hero instances in their exact natural aspect ratio (`Center(child: AspectRatio(aspectRatio: ar, child: ...))`) instead of expanding to full screen, guaranteeing a zero-jump, pixel-perfect landing for 16:9 and vertical videos alike.
* **Staggered Controls Reveal:** The top app bar, bottom action controls, and center play button remain invisible during the initial 65% of the expansion flight, then smoothly fade in over the remaining 35% (105ms). On dismissal, controls immediately vanish so only clean media flies back into the grid tile.
* **Seamless Video Surface Handoff:** Guarded the MPV video decoder surface behind the high-resolution preview frame until the 300ms route transition completes and the first frame renders, preventing GPU decoder resizing jitter during flight.

### v2.7.4
* **Unified Photo & Video Hero Flight Transition:** Wrapped the active item in `VideoPlayerScreen` with dynamic `Hero` and `_buildHeroShuttle`, perfectly matching `ImageViewerScreen`. When swiping between videos and dismissing via swipe-to-dismiss or back button, the current video smoothly flies back to its corresponding grid tile without flashing or revealing the first video.
* **Eliminated MediaCodec Decoder Preroll Jitter on Video Launch:** Prevented native hardware decoder initial frame advancement when autoplay is disabled by keeping the video surface hidden behind the high-resolution thumbnail until the user explicitly initiates playback.
* **Seamless Continuous Mixed Photo & Video Carousel:** Seamless swiping between photos and videos within the "All" and "Albums" tabs with unified navigation and high-fidelity aspect ratio preservation.
* **Zero-Flicker Scrubber Resumption:** Restored active video surface visibility seamlessly when scrubbing completes without restarting or stalling playback.

### v2.7.3
* **Raw Pointer Listener Video Scrubber & Gesture Arena Immunity:** Replaced Flutter's `GestureDetector` with a low-level `Listener(onPointerDown, onPointerMove, onPointerUp, onPointerCancel)` in `_VideoScrubberBar`. Scrubbing and dragging are completely immune to gesture arena cancellation from vertical thumb displacement, preventing the scrubber and preview tooltip from prematurely disappearing.
* **Active Worker Frame Streaming Queue:** Eliminated aggressive debounce request cancellations in favor of an active worker queue (`_isFetchingFrame` and `_pendingTargetPos`) with 35ms throttling and 80-bucket memory caching. Scrubbing now streams real-time preview frames continuously and reliably without getting stuck at the first second (0s).
* **Accurate Native & Headless MPV Frame Decoding:** Hardened native Android `MediaMetadataRetriever` frame extraction using direct file paths (`retriever.setDataSource(file.absolutePath)`) and non-negative timestamp safety. Added frame render waiting and settling delays in headless MPV frame extraction for reliable random seek decoding.
* **88x Maximum Pinch-to-Zoom for Photos & Videos:** Expanded maximum zoom magnification up to 88x (`maxScale: 88.0`) across both photo viewer and video player `InteractiveViewer` widgets, allowing granular inspection of high-resolution media.
* **Full-Width Portrait Video Layout with Aspect Ratio Preservation:** Removed artificial vertical padding constraints on portrait videos, allowing vertical videos to expand to 100% full screen width and center vertically with true aspect ratio preservation (no distortion or stretching), accompanied by floating auto-hiding overlay controls.
* **National Flag Emojis in Language Selection:** Integrated official Unicode national flag emojis (e.g. 🇮🇩, 🇺🇸, 🇸🇦, 🇧🇷, 🇨🇳, 🇯🇵, etc.) inside modern 44x44 dp selection boxes in the language modal dialog. Cleanly removed technical 2-letter language code abbreviations (`ID`, `EN`, `SYS`) in favor of clear country flags and an adaptive `Icons.language_rounded` icon for System Default.

### v2.7.2
* **Expanded 22 Supported Languages & Alphabetical Sorting:** Integrated all 22 languages matching `phantek-video-toolkit` with English as default fallback and System Default pinned at the top. The language selector now sorts all languages alphabetically (A-Z) by English display name for effortless discovery.
* **Unified Storage & Cache Settings:** Consolidated the separate Thumbnail Cache and Storage sections into a single cohesive "Storage & Cache" card, keeping cache cleanup, trash management, folder exclusion, and storage permissions neatly organized.
* **Excluded Folders Inline Explanation:** Added concise explanatory guidance ("Abaikan folder tertentu dari pemindaian media.") directly on the settings tile and inside the folder exclusion dialog to clarify media scanner isolation.

### v2.7.1
* **Gallery Shimmer Skeleton Loading Animation:** Replaced static gray placeholder icons with smooth, theme-harmonized animated shimmer skeleton tiles across `MediaGridItem` and `AlbumGridItem`. Provides clear, polished visual feedback while thumbnails are decoding on first install or after clearing cache.
* **Native Subsampling Acceleration for Large Photos:** Introduced high-performance native image thumbnail decoding via Android `BitmapFactory.Options.inSampleSize` on background thread pool (`getImageThumbnail`). Large photos (24MP, 48MP, 108MP) are decoded 5x–10x faster by inspecting file headers in <1ms, computing native pixel subsampling (e.g. 1/16th pixels), applying EXIF rotation, and caching directly to persistent disk cache without bloating Dart heap.
* **Boosted Concurrent Decoding Pool:** Scaled thumbnail worker pool concurrency to 6 parallel background workers for rapid multi-tile throughput across modern multi-core devices.
* **Seekbar Preview Gesture Isolation:** Fixed an issue where the root touch listener and page-swipe gesture arenas intercepted seekbar drags, causing the preview tooltip to close prematurely. Added `_isScrubbing` state locking, PageView scroll physics suppression, and bottom control deadzones.
* **Zero-Flicker Memory Thumbnail Priming:** Floating scrubber tooltips are now primed immediately from the synchronous in-memory thumbnail cache (`ThumbnailService.getMemoryThumbnail`), eliminating momentary blank loading spinners when first touching the seekbar.
* **Multi-Attempt Native Frame Extraction:** Hardened native Android `MediaMetadataRetriever` frame extraction with a multi-attempt fallback sequence (`OPTION_CLOSEST_SYNC` -> `OPTION_CLOSEST` -> `OPTION_PREVIOUS_SYNC` -> `0L`), ensuring reliable frame extraction across all video codecs and seek positions.
* **Optimized Portrait Video Layout:** Repositioned vertical portrait videos to `Alignment.topCenter` directly beneath the top header (`topPadding = statusBar + 56.0`) with elevated bottom clearance (`bottomPadding = navigationBar + 116.0`), completely preventing vertical videos from colliding with or occluding seekbar controls.

### v2.7.0
* **Interactive Seekbar Video Preview (Floating Scrubber Tooltip):** Real-time floating video thumbnail preview tooltips while scrubbing the seekbar across portrait and landscape player layouts, powered by native Android background decoding, 60ms debounce, and an in-memory LRU frame cache (up to 30 frames).
* **Aspect-Ratio Adaptive Preview Tooltip:** Tooltip dynamically adapts its bounding dimensions to match video geometry (136x76dp for 16:9 widescreen vs 68x120dp for 9:16 vertical reels) with rounded corners, drop shadows, and timestamp badge.
* **Video Playback Stutter & CPU Overload Fix:** Completely resolved video stuttering and random frame pacing jitter across mid-range chipsets (Snapdragon 4xx/6xx) by eliminating heavy 36-tap chroma upscaling (`cscale=spline36`) and post-processing software sharpen filter passes.
* **Optimized Texture Filtering:** Standardized Flutter video texture sampling on `FilterQuality.medium` (bilinear filtering), ensuring clean edge rendering without compositor bicubic overhead.
* **Robust Stream Geometry Validation:** Maintained lightweight dimension listeners with active hardware decoder verification logging (`hwdec-current`) and zero-overhead player teardown.

### v2.6.5
* **10x Pinch-to-Zoom Expansion:** Upgraded maximum zoom scale from 6x to 10x across both Photo Viewer and Video Player for deeper detail inspection.
* **Aspect Ratio Toggle & Default Fit to Screen:** Landscape horizontal videos now default to *Fit to Screen* (`BoxFit.contain`) to present entire uncropped frames out of the box, with one-tap toggle to *Crop to Fit* (`BoxFit.cover`).
* **Vertical Video Pre-Playback Thumbnail Fix:** Fixed pre-playback portrait video thumbnails appearing shrunken/zoomed-out in a loose container, ensuring the preview image immediately spans the screen between header and footer identically to active playback.
* **Modern Rotate Icon & Portrait Controls:** Replaced the rotate button with a sleek vector `DeviceRotateIcon` matching Samsung Gallery / modern media players. In portrait mode, horizontal videos now feature a direct rotate button next to the duration timestamp to switch to landscape.
* **Cleaned Portrait More Menu:** Removed the redundant Fullscreen option from the portrait More (⋮) sheet.
* **Expanded Playback Speed Range:** Added `0.25x` slow-motion playback speed option to the compact floating speed selector (`0.25x`, `0.5x`, `0.75x`, `1.0x`, `1.25x`, `1.5x`, `2.0x`).
* **Play/Pause Visual Sync Fix:** Fixed visual desynchronization where the play/pause button icon could show incorrectly after fullscreen and orientation transitions.

### v2.6.4
* **Landscape Player Bottom Controls Redesign:** Compacted the bottom control bar and seekbar closer to the screen edge in horizontal orientation. Replaced bottom action buttons with dedicated icon-only controls for Playback Speed, Loop, Fullscreen, Screen Rotation, and More (⋮).
* **Vertical Video Display & Fullscreen Button Removal:** Vertical (portrait) videos now expand to fill the screen (`BoxFit.cover`) within `SafeArea` without letterbox zoom-out artifacts, both before and during playback. The fullscreen button is automatically hidden for vertical videos across all toolbars and the More menu, while remaining fully accessible for horizontal videos.
* **Non-Obstructive Portrait Play Button:** Center play button in portrait mode now only appears initially prior to the first playback and stays hidden when paused, preventing obstruction during video zooming/pinching.

### v2.6.3
* **Keep Screen On While Viewing:** Added configurable native window flag toggle (`FLAG_KEEP_SCREEN_ON`) in Settings (Appearance) to keep screen illuminated during photo viewing and video playback without external dependencies.
* **Full 11-Language Localization Overhaul:** Complete dictionary coverage and translations across all supported languages (ID, EN, ZH, ES, PT, JA, KO, HI, AR, FR, RU), eliminating all remaining hardcoded English text.
* **Auto-Playback & Performance Tuning:** Configurable instant video auto-playback on view/swipe, plus butter-smooth 120 FPS tab swiping optimizations with zero black frame flashes.
* **Elevated Controls & Visual Enhancements:** Refined AMOLED falling meteors trajectory, enhanced Dark aurora ribbon animations, and redesigned Clean Light daytime theme.

### v2.6.2
* **Header Search Bar & Filter Bar Collision Fix:** Constrained the search capsule strictly within the 56dp toolbar height (`topPadding + kToolbarHeight`), cleanly separating it from category filter chips (All, Photos, Videos, Albums) with zero overlapping.
* **Landscape Video Fullscreen Boundary & Inset Fix:** Reconfigured `SafeArea` insets for fullscreen landscape playback, implemented dynamic orientation keys on `InteractiveViewer`, and synchronized window metric resets to expand landscape videos edge-to-edge without shrinking or excessive black bars.
* **Large Video Aspect Ratio & Frame 0 Precision:** Introduced direct JPEG `SOF0`/`SOF2` header parsing in `ThumbnailService` to resolve visual orientation on frame 0, eliminating momentary zoom-in snaps for large (>200MB, ≥ 720×1280) and rotated videos.

### v2.6.1
* **Centered Phantek Header Title:** Restored clean dead-center alignment for "Phantek" in the `AppBar` with responsive action alignment.
* **Smooth Unified Search Overlay:** Re-engineered search bar into a single-row flex overlay in `flexibleSpace` with cubic easing, eliminating boundary overlaps and rightward bleed into the Cancel button.
* **Video Orientation & Large Video Zoom Fix:** Corrected width/height swaps for 90° / 270° rotated videos and resolved frame 0 aspect ratio fallback for unindexed large video files (>100MB).
* **Instant Cold-Start Hero Animations & Gesture Reliability:** Added display fallback for cold start image transitions and refined gesture tracking to prevent stuck swipe-to-dismiss.

### v2.6.0
* **Zero-Delay Video Transitions & Black Screen Elimination:** Eliminated momentary black screen flashes upon tapping videos or swiping horizontally between videos by retaining instant 0ms cached thumbnails until video frames render.
* **Aspect Ratio Preserved Hero Transitions:** Fixed vertical stretch distortion on landscape/non-square photos and videos during tap-to-open and swipe-to-dismiss Hero animations.
* **Animated Search Bar & Theme-Adaptive Cancel:** Redesigned the gallery search bar to expand smoothly from left to right across the `AppBar` with title fade-out and a theme-adaptive Cancel button.

### v2.5.2
* **Seamless Continuous Header Animations:** Synchronized all harmonic frequencies and movement cycles to integer multiples, eliminating loop stutter across all themes.
* **Extended Header Canvas:** Header animation spans continuously across both `AppBar` and Filter/Sort Bar, eliminating empty spaces.
* **Enriched Sakura Tree Visuals:** Multi-tier natural branching, fresh green sakura leaves, and clustered radiant blossoms with buds.
* **Dark Theme Cyber Aurora Badge:** Synchronized border gradient and shimmer spark badge icon for Dark Mode.
* **Direct Tab Jump & Butter-Smooth Capsule Glides:** Direct navigation between tabs without intermediate page scrolling, paired with 60/120 FPS jitter-free capsule transitions via lazy page evaluation.

### v2.5.1
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