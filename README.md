# Phantek Gallery

<p align="center">
  <img src="assets/app_icon.jpg" width="115" height="115" alt="Phantek Gallery" />
</p>

<p align="center">
  <img src="https://img.shields.io/badge/PLATFORM-ANDROID-059669?style=for-the-badge&logo=android&logoColor=white&labelColor=0F172A" alt="Platform" />
  <img src="https://img.shields.io/badge/FLUTTER-3.47.0-0284C7?style=for-the-badge&logo=flutter&logoColor=white&labelColor=0F172A" alt="Flutter" />
  <img src="https://img.shields.io/badge/VERSION-v1.0.0-2563EB?style=for-the-badge&logo=github&logoColor=white&labelColor=0F172A" alt="Version" />
  <img src="https://img.shields.io/badge/LICENSE-GPLv3-475569?style=for-the-badge&logo=gnu&logoColor=white&labelColor=0F172A" alt="License" />
</p>

# Phantek Gallery

Phantek Gallery is a high-performance, offline-first photo and video gallery application for Android. Built with Flutter and powered by the MPV playback engine via MediaKit, it delivers smooth media rendering, responsive navigation, and complete data privacy without third-party tracking or mandatory cloud dependencies.

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

### High-Performance Media Grid
- Fast media indexing and thumbnail generation utilizing native Android MediaStore APIs.
- Configurable grid column layout ranging from 2 to 5 columns.
- Flexible sorting options (Newest First, Oldest First) and media filtering (All, Photos Only, Videos Only).
- Folder exclusion management to prevent unwanted directories from appearing in the main feed.

### Hardware-Accelerated Video Playback
- Powered by MediaKit with native MPV and FFmpeg integration.
- Hardware GPU decoding support for high-bitrate video streams.
- Configurable auto-play behavior and screen orientation control.

### High-Fidelity Photo Viewer
- Smooth zooming, panning, and double-tap gestures powered by PhotoView.
- Responsive swipe transitions between adjacent media items.

### Recycle Bin (Trash System)
- Soft deletion support allowing users to stage files for deletion in a protected local directory.
- Easy restoration back to the original storage directory or permanent deletion on demand.

### Over-The-Air (OTA) Updates
- Integrated update service that queries GitHub Releases for newer application versions.
- In-app APK downloading with download progress tracking.
- Automated installation dispatch using Android FileProvider without requiring external app stores.
- Automatic cleanup of temporary installer packages upon completion.

### Modern Material 3 UI
- Clean Material Design 3 interface with dynamic color theming.
- Supports Light Mode, Dark Mode (OLED-friendly true black), and System Default synchronization.

---

## Architecture and Tech Stack

| Category | Technology | Purpose |
|---|---|---|
| Framework | Flutter 3.x (Dart 3.x) | Cross-platform UI toolkit targeting Android |
| State Management | Flutter Riverpod 2 (`flutter_riverpod`, `riverpod_annotation`) | Reactive, compile-safe dependency injection and state |
| Video Engine | MediaKit (`media_kit`, `media_kit_video`, `media_kit_libs_android_video`) | Native MPV and FFmpeg playback pipeline |
| Image Viewer | PhotoView (`photo_view`) | High-resolution image viewing with gesture support |
| Media Management | `photo_manager`, `permission_handler` | Scoped storage access and runtime permissions |
| Local Preferences | `shared_preferences` | Key-value persistence for user settings |
| Networking | `http` | Lightweight HTTP client for GitHub Releases OTA checks |
| Target Platform | Android 5.0+ (API 21 to 34+) | Comprehensive Android version compatibility |

---

## Project Structure

```text
lib/
|-- app/
|   |-- router.dart              # Application route definitions and navigation
|   `-- theme.dart               # Material 3 light and dark theme configurations
|-- core/
|   |-- enums/                   # Filter, sort, and theme enumeration models
|   |-- models/                  # Settings and preference data structures
|   |-- providers/               # Global Riverpod state providers
|   |-- services/                # MediaKit setup, permissions, and storage services
|   `-- utils/                   # Formatting, date helpers, and file utilities
|-- features/
|   |-- gallery/                 # Grid gallery screen, media cards, and filter bar
|   |-- player/                  # Image viewer and MPV-based video player screens
|   |-- settings/                # User preferences, folder exclusions, and theming
|   |-- trash/                   # Recycle bin management and restoration UI
|   `-- update/                  # GitHub Releases client, download service, and OTA dialog
`-- main.dart                    # Application entry point, boot sequence, and initialization
```

---

## Getting Started

### Prerequisites

Ensure the following tools are installed on your workstation:

- Flutter SDK (version 3.24.0 or newer recommended)
- Android SDK (API Level 34 platform tools and build tools)
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
To produce smaller architecture-specific packages (arm64-v8a, armeabi-v7a, x86_64):
```bash
flutter build apk --release --split-per-abi
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

Phantek Gallery declares only the permissions necessary for local media discovery and self-hosted updates:

| Permission | Scope | Justification |
|---|---|---|
| `READ_MEDIA_IMAGES` | Android 13+ (API 33+) | Read access to photo media files |
| `READ_MEDIA_VIDEO` | Android 13+ (API 33+) | Read access to video media files |
| `READ_EXTERNAL_STORAGE` | Android 12 and below | Legacy read access to local media storage |
| `WRITE_EXTERNAL_STORAGE` | Android 10 and below | Legacy write access for file deletion operations |
| `MANAGE_EXTERNAL_STORAGE` | Android 11+ (API 30+) | Optional permission for deep trash management across external storage |
| `ACCESS_MEDIA_LOCATION` | Android 10+ (API 29+) | Reading media metadata and location coordinates from EXIF tags |
| `INTERNET` | All versions | Required exclusively for checking and downloading updates from GitHub Releases |
| `REQUEST_INSTALL_PACKAGES` | Android 8+ (API 26+) | Direct prompt to install downloaded OTA update APKs |

---

## CI/CD Workflow

The repository includes an automated GitHub Actions workflow configured in `.github/workflows/build-apk.yml`. It supports manual dispatch (`workflow_dispatch`) to compile release or debug APKs on Ubuntu runners with:

- Automated JDK 17 and Flutter stable setup.
- Keystore decoding via repository secrets (`KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`).
- Optional per-ABI packaging.
- Artifact upload retaining APK builds for 30 days.

---

## License

[![License: GPL v3](https://img.shields.io/badge/LICENSE-GPLv3-475569?style=for-the-badge&logo=gnu&logoColor=white&labelColor=0F172A)](LICENSE)

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