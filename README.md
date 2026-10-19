# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" alt="Phantek Gallery Icon" width="108" style="border-radius: 22px; box-shadow: 0 6px 20px rgba(0,0,0,0.25);" />
</p>

<div align="center">
  <img src="https://img.shields.io/static/v1?label=Status&message=pre-release&color=orange&style=flat-square&labelColor=0f172a" alt="Status" />
  <img src="https://img.shields.io/static/v1?label=Platform&message=Android&color=059669&style=flat-square&logo=android&logoColor=white&labelColor=0f172a" alt="Platform" />
  <img src="https://img.shields.io/static/v1?label=Architecture&message=arm64-v8a&color=7c3aed&style=flat-square&logo=arm&logoColor=white&labelColor=0f172a" alt="Architecture" />
  <a href="https://github.com/zerabyte88/phantek-gallery/releases"><img src="https://img.shields.io/static/v1?label=Version&message=v2.8.1&color=2563eb&style=flat-square&logo=github&logoColor=white&labelColor=0f172a" alt="Version" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/static/v1?label=License&message=GPLv3&color=475569&style=flat-square&logo=gnu&logoColor=white&labelColor=0f172a" alt="License" /></a>

  <p>
    <a href="https://github.com/zerabyte88/phantek-gallery/releases/latest"><b>Download APK</b></a> •
    <a href="#overview">Overview</a> •
    <a href="#features">Features</a> •
    <a href="#supported-formats">Formats</a> •
    <a href="#tech-stack">Tech Stack</a> •
    <a href="#building-from-source">Build</a>
  </p>
</div>

---

## Overview

**Phantek Gallery** is a fast, offline photo and video gallery for Android. Built with Flutter and powered by the native MPV engine via MediaKit, it offers smooth media viewing, responsive gestures, and complete privacy with zero telemetry, tracking, or mandatory internet connectivity.

> [!WARNING]
> **Active Development & Pre-Release Notice**:  
> Phantek Gallery is currently under active development and in pre-release stage. You may encounter bugs, instability, or unexpected behavior.

---

## Features

### Media Organization & Browsing
- **Timeline & Albums:** Browse your media chronologically or organized by on-device folders (Camera, Screenshots, Downloads, etc.).
- **Grid Customization:** Adjust grid layout between 2, 3, 4, or 5 columns independently for photos and albums.
- **Favorites & Exclusions:** Pin frequently accessed media to Favorites and exclude private or system folders from indexing via the native Android directory picker.
- **In-Album Filtering & Sorting:** Filter items by type (All, Photos, Videos) and sort by date or filename.

### Photo Viewer
- **Fluid Gestures:** Pinch-to-zoom with elastic boundaries, double-tap to zoom, horizontal swipe between items, and swipe down to dismiss.
- **Quick Actions:** Share, favorite, view EXIF details, set as wallpaper, rename, or delete directly from the viewer.

### Video Player (MPV Engine)
- **Wide Format Support:** Hardware-accelerated playback for MKV, MP4, MOV, and WebM using native MPV and FFmpeg libraries.
- **Playback Controls:** Selectable playback speed (0.25x to 2.0x), single loop toggle with unobtrusive pill notifications, and optional auto-play.
- **Timeline Scrubbing:** Precise seekbar with real-time frame previews.
- **Video Zoom:** Pinch-to-zoom up to 5x with pan support and quick reset.

### Recycle Bin
- **Safe Staging:** Deleted items move to a local `.trash` directory rather than immediate removal.
- **Batch Operations:** Select multiple items to restore or permanently delete at once.

### Theming & Internationalization
- **Theme Modes:** System default, Light, and Dark themes with subtle seasonal headers (Snowfall, Sunburst, Midnight).
- **Multi-Language:** 22 supported languages including English, Indonesian, Japanese, Korean, Spanish, French, German, and more.

### Over-The-Air (OTA) Updates
- **GitHub Releases Integration:** Check for updates, download releases in the background, and install updates directly from within the app.

---

## Supported Formats

| Type | Formats / Containers | Notes |
| :--- | :--- | :--- |
| **Photos** | `.jpg`, `.jpeg`, `.png`, `.webp`, `.heic`, `.gif`, `.bmp` | EXIF metadata extraction and downsampled rendering |
| **Videos** | `.mp4`, `.mkv`, `.mov`, `.webm` | H.264, H.265/HEVC, and VP9 with hardware acceleration |

---

## System Requirements

| Specification | Requirement |
| :--- | :--- |
| **Operating System** | Android 8.0 (API 26) or higher |
| **Architecture** | 64-bit ARM (`arm64-v8a`) |
| **Internet Access** | Optional (used solely for OTA updates from GitHub Releases) |

---

## Tech Stack

- **Framework:** [Flutter](https://flutter.dev) (Dart 3.x)
- **State Management:** [Flutter Riverpod](https://riverpod.dev)
- **Video Engine:** [MediaKit](https://github.com/media-kit/media-kit) (Native MPV + FFmpeg)
- **Media Scanning:** `photo_manager` & `permission_handler`
- **Preferences:** `shared_preferences`

---

## Building from Source

Phantek Gallery compiles against native C/C++ libraries bundled via MediaKit and MPV. The release build targets 64-bit ARM architectures.

```bash
flutter build apk --release --split-per-abi --target-platform android-arm64
```

The compiled release APK will be located at:
```
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

---

## Permissions

| Permission | Purpose |
| :--- | :--- |
| `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` | Access photos and videos on Android 13+ (API 33+) |
| `READ_MEDIA_VISUAL_USER_SELECTED` | User-selected partial media access on Android 14+ (API 34+) |
| `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` | Storage access on Android 12 and below |
| `MANAGE_EXTERNAL_STORAGE` | Direct file manipulation for `.trash` recycle bin management |
| `ACCESS_MEDIA_LOCATION` | Read location metadata from EXIF tags |
| `INTERNET` | Check and download OTA updates via GitHub Releases |
| `REQUEST_INSTALL_PACKAGES` | Prompt to install downloaded update APKs |

---

## License

This project is licensed under the **GNU General Public License v3.0 (GPLv3)**. See the [LICENSE](LICENSE) file for complete details.

### Third-Party Licenses & Acknowledgments

- **MediaKit & MPV:** Video playback is powered by [MediaKit](https://github.com/media-kit/media-kit) (MIT License) utilizing native builds of [mpv](https://mpv.io) and [FFmpeg](https://ffmpeg.org) under LGPL/GPL.
- **Flutter & Dependencies:** Third-party Dart and Flutter packages are licensed under their respective open-source licenses (BSD-3-Clause, MIT, Apache 2.0). Complete open-source licenses can be inspected directly inside the application under **Settings > About > License**.

---

<div align="center">
  <br/>
  <a href="https://github.com/zerabyte88">
    <img src="https://github.com/zerabyte88.png" width="48" height="48" style="border-radius: 50%;" alt="zerabyte88" />
  </a>
  <br/>
  <sub>Developed with ❤️ by <a href="https://github.com/zerabyte88">zerabyte88</a></sub>
</div>