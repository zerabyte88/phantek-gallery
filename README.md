<div align="center">
  <img src="assets/app_icon.png" alt="Phantek Gallery" width="120" />

  # Phantek - Gallery

  **Fast, privacy-focused offline photo and video gallery for Android with PSD layer support.**

  [![Version](https://img.shields.io/badge/Version-v2.14.1-3b82f6.svg?style=flat-square)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Platform](https://img.shields.io/badge/Platform-Android%208.0%2B-10b981.svg?style=flat-square&logo=android&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Architecture](https://img.shields.io/badge/Arch-arm64--v8a-8b5cf6.svg?style=flat-square&logo=arm&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Engine](https://img.shields.io/badge/Engine-Flutter%20%7C%20ExoPlayer-6366f1.svg?style=flat-square)](https://developer.android.com/media/media3)
  [![License](https://img.shields.io/badge/License-MIT-f59e0b.svg?style=flat-square&logo=open-source-initiative&logoColor=white)](LICENSE)

  [Download APK](https://github.com/zerabyte88/phantek-gallery/releases/latest) • [Features](#features) • [Supported Formats](#supported-formats) • [Tech Stack](#tech-stack) • [Permissions](#permissions) • [Build](#build-from-source) • [License](#license)
</div>

---

## Features

- **Ultra-Fast Media Grid** : Native hardware thumbnail acceleration via `MediaStore.loadThumbnail` (1–2ms), in-memory cache indexing, and isolate-backed decoding for smooth 120Hz scrolling.
- **PSD Layer Viewer** : Full Adobe Photoshop (`.psd`) support with seekable embedded JPEG extraction (<1ms) and interactive layer visibility toggle sheet.
- **Hardware Video Playback** : Powered by AndroidX Media3 / ExoPlayer with double-tap seek, smart zoom, gesture controls for brightness and volume, and playback position resume.
- **Recycle Bin & Safe Deletion** : Staged `.trash` bin with configurable auto-purge (7, 14, 30 days or never) and batch restore/permanent delete.
- **Privacy & Security** : Enforce Android `FLAG_SECURE` to block screenshots, screen recordings, and blur recent apps switcher previews.
- **EXIF & Media Inspector** : Detailed technical metadata for photos (ISO, aperture, focal length, resolution) and videos (bitrate, fps, codec, channels).
- **Custom Visual Themes** : 6 hand-crafted visual themes (*Dark Mode*, *Light Mode*, *Snowfall*, *Clean Light*, *Midnight*, *Sakura*) with dynamic artistic headers.
- **Multilingual Support** : Complete localization across 22 languages with instant runtime switching without app restart.
- **100% Offline & Private** : Zero cloud sync, zero telemetry, zero analytics, and zero unsolicited network requests.

---

## Supported Formats

<div align="center">

| Type | Container / Extension | Codec / Details | Notes |
| :---: | :---: | :---: | :---: |
| **Photos** | `.jpg`, `.jpeg`, `.png`, `.webp`, `.heic`, `.bmp` | Standard image decoders | EXIF metadata extraction and downsampled caching |
| **Animation** | `.gif` | Multi-frame decoder | Frame-by-frame animation playback |
| **Design** | `.psd` | Adobe Photoshop Document | Seekable embedded JPEG preview + per-layer toggle |
| **Videos** | `.mp4`, `.mkv`, `.mov`, `.webm` | H.264, H.265 (HEVC), VP9, AV1 | Hardware accelerated via AndroidX Media3 / ExoPlayer |

</div>

---

## Tech Stack

<div align="center">

| Layer | Package / Tool | Role |
| :---: | :---: | :---: |
| **Framework** | Flutter (Dart SDK `^3.5`) | UI rendering, animations, gestures, and localization |
| **State Management** | `flutter_riverpod` (`^2.5.1`) | Reactive state management and dependency injection |
| **Video Engine** | `video_player` (`^2.9.2`) | AndroidX Media3 / ExoPlayer hardware video playback |
| **Media Scanning** | `photo_manager`, `permission_handler` | Scoped storage media queries and permission handling |
| **Native Bridge** | Kotlin MethodChannels | Android `FLAG_SECURE`, MediaStore thumbnail loader, FileProvider |
| **Storage & Caching** | `shared_preferences`, `path_provider` | Key-value settings persistence and thumbnail disk caching |

</div>

---

## Permissions

<div align="center">

| Permission | Purpose |
| :--- | :--- |
| `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` | Access photos and videos on Android 13+ (API 33+) |
| `READ_MEDIA_VISUAL_USER_SELECTED` | User-selected partial media access on Android 14+ (API 34+) |
| `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` | Storage access on Android 12 and below |
| `MANAGE_EXTERNAL_STORAGE` | Direct file manipulation for `.trash` recycle bin management |
| `ACCESS_MEDIA_LOCATION` | Read geographic and EXIF location metadata from camera photos |
| `INTERNET` | Optional network access for loading developer avatar in About card |

</div>

---

## Build from Source

### Prerequisites

- Flutter SDK `^3.5`
- Android SDK & Java 17+

### Steps

```bash
# Clone repository
git clone https://github.com/zerabyte88/phantek-gallery.git
cd phantek-gallery

# Install dependencies
flutter pub get

# Build 64-bit release APK
flutter build apk --release --target-platform android-arm64
```

Compiled binary (64-bit ARM) : `build/app/outputs/flutter-apk/app-release.apk`

---

## License

This project is open-source software licensed under the **[MIT License](LICENSE)**.

Third-party components (AndroidX Media3, Flutter, and bundled plugins) are subject to their respective open-source licenses (Apache 2.0, BSD, MIT) and can be inspected in-app under **Settings > About > License**.
