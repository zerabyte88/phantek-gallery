# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" width="115" height="115" alt="Phantek Gallery" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PLATFORM-ANDROID-059669?style=for-the-badge&logo=android&logoColor=white&labelColor=0F172A" alt="Platform" />
  <img src="https://img.shields.io/badge/FLUTTER-3.47+-0284C7?style=for-the-badge&logo=flutter&logoColor=white&labelColor=0F172A" alt="Flutter" />
  <img src="https://img.shields.io/badge/APPLICATION_ID-com.phantek.virgo.spica-6366F1?style=for-the-badge&logo=android&logoColor=white&labelColor=0F172A" alt="Application ID" />
  <img src="https://img.shields.io/badge/VERSION-v1.1.0-2563EB?style=for-the-badge&logo=github&logoColor=white&labelColor=0F172A" alt="Version" />
  <img src="https://img.shields.io/badge/LICENSE-GPLv3-475569?style=for-the-badge&logo=gnu&logoColor=white&labelColor=0F172A" alt="License" />
</p>

Phantek Gallery is a high-performance, offline-first photo and video gallery application for Android (`com.phantek.virgo.spica`). Built with Flutter and powered by the MPV playback engine via MediaKit, it delivers smooth media rendering, responsive navigation, and complete data privacy without third-party tracking or mandatory cloud dependencies. Fully compliant with modern Android standards, including Android 16 (API 36/37) partial media selection and mandatory edge-to-edge layouts.

---

## Table of Contents

- [Overview](#overview)
- [Key Features](#key-features)
- [Architecture and Tech Stack](#architecture-and-tech-stack)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
  - [Prerequisites](#prerequisites)
  - [Installation](#installation)
- [Build and Release](#build-and-release)
  - [Debug Build](#debug-build)
  - [Release Build](#release-build)
  - [Split ABI Build](#split-abi-build)
  - [Keystore Configuration](#keystore-configuration)
- [Android Permissions](#android-permissions)
- [CI/CD Workflow](#cicd-workflow)
- [License](#license)

---

## Overview

Modern mobile galleries often require persistent network connections, cloud synchronization, and background analytics. Phantek Gallery takes an offline-first approach: your photos and videos stay strictly on your local device storage. Network access is restricted entirely to user-directed over-the-air (OTA) update checks against official GitHub Releases.

---

## Key Features

### High-Performance Media Grid & Album Organization
- **Smart Grouping**: View all media or browse by organized folder albums (DCIM, Camera, Downloads, Screenshots, etc.).
- **Centered Category Navigation**: Enlarged, centered filter switcher (`All`, `Photos`, `Videos`, `Albums`).
- **Compact Sort Menu**: 3-dots popup menu with quick sorting (Newest First, Oldest First, Name A → Z, Name Z → A).
- **Independent Grid Layouts**: Customize grid columns for both the main gallery feed and albums grid (2 to 5 columns) with clean listbox dialogs.
- **Folder Exclusions**: Blacklist unwanted system directories from being indexed.
- **Android 14+ / 16 Compliance**: Seamless partial photo selection support (`READ_MEDIA_VISUAL_USER_SELECTED`).

### Hardware-Accelerated Video Playback
- **MediaKit & MPV Engine**: Native MPV and FFmpeg integration for ultra-smooth playback of MKV, MP4, WebM, and high-bitrate video streams.
- **Centered Controls**: Ergonomic centered overlay controls (Play/Pause, Seek Backward 10s, Seek Forward 10s).
- **Hardware Acceleration**: Configurable GPU decoding and screen orientation controls.

### High-Fidelity Photo Viewer
- **Gesture Support**: Smooth zooming, panning, and double-tap gestures powered by PhotoView.
- **Modern Top Bar**: Clean header with quick navigation, filename display, timestamp, and quick-action menu (copy path, file details, share).
- **Bottom Action Bar**: Dedicated bottom bar featuring direct move-to-trash/delete, share, and metadata inspection.

### Instant Optimistic Deletion & Trash System
- **Recycle Bin (`.trash`)**: Stage deleted files safely in a local trash folder with one-tap restoration.
- **Zero-Latency UI Removal**: Deleted or trashed items vanish immediately (0ms delay) with optimistic in-memory state updates.
- **Unclipped Dialogs**: Clean, responsive confirmation dialogs formatted to prevent broken text wraps and overflow across all screen sizes.
- **Automatic Media Store Sync**: Automatic cache clearing ensuring deleted files do not reappear.

### Comprehensive Theming & Easter Egg
- **Material 3 Theming**: System Default, Light Mode, and Dark Mode.
- **Pure AMOLED Mode**: True pitch-black (`#000000`) surfaces for maximum OLED battery savings.
- **AMOLED Sakura Mode 🌸**: Secret theme featuring Japanese Sakura pink accents over deep pitch-black backgrounds.
- **Easter Egg**: Tap the developer profile avatar 10 times in Settings to unlock the secret AMOLED Sakura theme!
- **Developer Card**: Dedicated About & Maintainer card in Settings with GitHub repository shortcuts.

### Over-The-Air (OTA) Updates
- Integrated update service that queries GitHub Releases for newer application versions.
- In-app APK downloading with download progress tracking.
- Automated installation dispatch using Android FileProvider (`com.phantek.virgo.spica.fileprovider`) without external app stores.
- Automatic cleanup of temporary installer packages upon completion.

---

## Architecture and Tech Stack

| Category | Technology | Purpose |
|---|---|---|
| Application ID | `com.phantek.virgo.spica` | Unique package identifier for Android OS |
| Framework | Flutter 3.47+ (Dart 3.x) | Cross-platform UI toolkit targeting Android |
| State Management | Flutter Riverpod 2 (`flutter_riverpod`, `riverpod_annotation`) | Reactive, compile-safe dependency injection and state |
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
|   |-- services/                # MediaKit setup, PhotoManager, permission, and trash services
|   `-- utils/                   # Formatting, duration, date helpers, and file utilities
|-- features/
|   |-- gallery/                 # Grid gallery, albums view, album detail screen, and filter bar
|   |-- player/                  # Image viewer and MPV-based video player screens
|   |-- settings/                # User preferences, column counts, exclusions, and Developer card
|   |-- trash/                   # Recycle bin management and restoration UI
|   `-- update/                  # GitHub Releases client, download service, and OTA dialog
`-- main.dart                    # Application entry point, boot sequence, and initialization
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

### Split ABI Build
To produce smaller architecture-specific packages for ARM devices (arm64-v8a, armeabi-v7a):
```bash
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
```

### Keystore Configuration
For signed release distributions, create a `key.properties` file in the `android/` directory:

```properties
storePassword=your_keystore_password
keyPassword=your_key_password
keyAlias=your_key_alias
storeFile=path/to/your_keystore.jks
```

If `key.properties` is absent, the Gradle build will automatically fall back to the default debug signing configuration.

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
- Default split-per-ABI packaging producing strictly two ARM APKs (64-bit `arm64-v8a` and 32-bit `armeabi-v7a`), without building heavy universal or x86 APKs.
- Artifact upload retaining APK builds for 30 days.

---

## License

Phantek Gallery is free and open-source software licensed under the [GNU General Public License v3.0 (GPLv3)](LICENSE).

- Freedom to run the software for any purpose.
- Freedom to study how the program works and adapt it to your needs.
- Freedom to redistribute copies to help others.
- Freedom to improve the program and release your improvements to the public under the same copyleft license terms.

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