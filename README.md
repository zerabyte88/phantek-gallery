<div align="center">
  <img src="assets/app_icon_readme.png" alt="Phantek Gallery" width="120" />

  # Phantek Gallery

  **Offline Android gallery for photos, videos, PSD files, and manga, with on-device manga OCR and dialogue localization via Local AI Server (LM Studio / Ollama).**

  [![Version](https://img.shields.io/badge/Version-v2.19.21-3b82f6.svg?style=flat-square)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Platform](https://img.shields.io/badge/Platform-Android%208.0%2B-10b981.svg?style=flat-square&logo=android&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Architecture](https://img.shields.io/badge/Arch-arm64--v8a-8b5cf6.svg?style=flat-square&logo=arm&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Engine](https://img.shields.io/badge/Engine-Flutter%20%7C%20LM%20Studio-6366f1.svg?style=flat-square)](https://lmstudio.ai/)
  [![License](https://img.shields.io/badge/License-MIT-f59e0b.svg?style=flat-square&logo=open-source-initiative&logoColor=white)](LICENSE)

  [Download APK](https://github.com/zerabyte88/phantek-gallery/releases/latest) • [Features](#features) • [Translation Setup](#translation-setup) • [Supported Formats](#supported-formats) • [Tech Stack](#tech-stack) • [Permissions](#permissions) • [Build](#build-from-source) • [License](#license)
</div>

---

## Overview

Phantek Gallery is an offline gallery for photos, videos, Adobe Photoshop (`.psd`) files, and manga. Your media remains strictly on your device with zero tracking, no telemetry, and no cloud dependencies. 

For comic and manga readers, Phantek Gallery pairs on-device OCR (**Google ML Kit Text Recognition**) with your private **Local AI Server (LM Studio / Ollama)** connected over local Wi-Fi/LAN (OpenAI-compatible REST API) for natural comic dialogue localization without phone thermal or RAM overhead.

---

## Features

### Gallery and Viewing

- **Fast Navigation & Selection**: Instant native-style tab switching across grid and album views, virtualized date-grouped timeline, right-edge fast-scroll handle with Month/Year indicator, in-album search, and drag-to-select.
- **PSD Layer Viewer**: Open Adobe Photoshop (`.psd`) documents with embedded-JPEG previews and a dedicated sheet for toggling individual layer visibilities.
- **Hardware Video Playback**: Built on AndroidX Media3 / ExoPlayer. Includes double-tap seek, gesture-based brightness and volume controls, fast seekbar frame preview with lift-off stabilization, and resume playback.
- **EXIF and Technical Inspector**: Detailed photo metadata (ISO, aperture, shutter speed, focal length, resolution) and video properties (bitrate, fps, codec, channels).

### Manga Reader & Translation

- **Local AI Server Translation**: Nuanced comic dialogue localization via LM Studio or Ollama over your private local network (LAN).
- **Customizable Overlay Styles & Text Size**: Choose between *Google Lens*, *Classic Manga*, *Dark Contrast*, and *Translucent* bubble styles plus adjustable font scale with live JP→EN preview in Settings.
- **Natural Comic Speech Bubble Geometry**:
  - **Preserved Original Bubble Contours**: Speech bubbles retain their natural comic outline and original bounding dimensions, completely eliminating artificial ballooning or obscuring character artwork.
  - **Vertical Dialogue Flow**: Automatically rotates English translations for tall, narrow Asian speech bubbles (90° clockwise with RTL column flow) so vertical dialogue fits cleanly and reads naturally without forced horizontal distortion.
- **Manga Reader with Natural Sort**: Continuous vertical reading mode with edge-to-edge layout, chapter progress indicators, and natural alphanumeric sorting (`Chapter 1`, `1.1`, `2.1`, `10`).

### Privacy and Security

- **100% Local & Private**: No analytics, no tracking. OCR runs entirely on-device and translation runs across your private local network (LM Studio / Ollama) without external cloud APIs.
- **Biometric App Lock**: Minimalist fingerprint, face unlock, or device PIN lock screen with configurable auto-lock timeout (*Immediately*, *30s*, *1m*, *5m*).
- **Screen Protection**: Optional Android `FLAG_SECURE` integration to prevent screen captures, video recordings, and task switcher previews.
- **Recycle Bin**: Staged `.trash` directory with configurable auto-purge intervals (7, 14, 30 days, or never) and batch restore.

### Personalization

- **Visual Themes**: *Dark Mode*, *Light Mode*, *Sunlight*, *Snowfall*, *Midnight*, and *Sakura* with dynamic theme headers.

---

## Translation Setup

### Local AI Server (LM Studio / Ollama)

For natural dialogue nuance, comic slang preservation, and contextual localization without straining phone battery or thermal limits, connect Phantek Gallery to your local PC or home server running LM Studio, Ollama, or any OpenAI-compatible inference server.

#### Why Local AI Server?
- **Zero Phone Thermal & Memory Overhead**: High-parameter LLMs (e.g. Qwen 2.5 7B / 14B, Llama 3) run on your desktop GPU/CPU instead of draining your mobile device RAM and battery.
- **Strict Privacy**: Requests are sent over your private Wi-Fi / Local Area Network (LAN) directly from your phone to your PC. No third-party cloud APIs, no external telemetry, and no data leaves your home network.
- **Uncensored Comic Slang & Dialogue**: Ideal for preserving raw dialogue, emotional cues, and colloquial comic speech.

#### Setup Guide (LM Studio Example)

1. **Start Server on PC**:
   - Open **LM Studio** on your PC and load your favorite translation model (e.g. `Qwen/Qwen2.5-7B-Instruct` or `Qwen2.5-1.5B-Instruct`).
   - Navigate to the **Local Server** tab (`<->`).
   - Turn **ON** the server.
   - Note the port (default: `1234`) and your PC's local IP address (e.g. `http://192.168.1.100:1234`).
   - *(Optional)* Ensure your PC firewall allows incoming connections on port `1234` from devices on your local network.

2. **Configure in Phantek Gallery**:
   - Open **Settings > Manga Translation > LM Studio / Local AI Server**.
   - Enter your **Server URL** (e.g., `http://192.168.1.100:1234` or `http://10.0.2.2:1234` if using Android Emulator).
   - *(Optional)* Enter an API Key if your server requires authentication.
   - Tap **Test Connection** to verify reachability and automatically fetch available loaded models.
   - Select your active model from the list.

3. **Translate in Reader**:
   - In the reader translation sheet, select your render mode to translate speech bubbles using your private desktop AI server (source language is automatically detected)!

---

## Supported Formats

<div align="center">

| Type | Extension | Codec / Details | Notes |
| :---: | :---: | :---: | :---: |
| **Photos** | `.jpg`, `.jpeg`, `.png`, `.webp`, `.heic`, `.bmp` | Standard image decoders | EXIF extraction and downsampled caching |
| **Animation** | `.gif` | Multi-frame decoder | Frame-by-frame playback |
| **Design** | `.psd` | Adobe Photoshop Document | Embedded JPEG preview and per-layer toggle |
| **Videos** | `.mp4`, `.mkv`, `.mov`, `.webm` | H.264, H.265 (HEVC), VP9, AV1 | Hardware accelerated via AndroidX Media3 / ExoPlayer |

</div>

---

## Tech Stack

<div align="center">

| Layer | Package / Tool | Role |
| :---: | :---: | :---: |
| **Framework** | Flutter (Dart SDK `^3.5`) | UI rendering, animations, gestures, and localization |
| **State Management** | `flutter_riverpod` (`^2.5.1`) | Reactive state and dependency injection |
| **Video Engine** | `video_player` (`^2.9.2`) | Hardware video playback via AndroidX Media3 / ExoPlayer |
| **Local AI Server** | OpenAI-compatible REST API | Advanced manga dialogue localization via LM Studio / Ollama |
| **On-Device OCR** | `google_mlkit_text_recognition` (`^1.0.1`) | Offline script recognition (Japanese, Chinese, Korean, Latin) |
| **Media Scanning** | `photo_manager`, `permission_handler` | Scoped storage media queries and permission handling |
| **Native Bridge** | Kotlin MethodChannels | `FLAG_SECURE`, MediaStore thumbnail loader, FileProvider |
| **Storage and Caching** | `shared_preferences`, `path_provider` | Settings persistence and thumbnail disk cache |

</div>

---

## Permissions

<div align="center">

| Permission | Purpose |
| :--- | :--- |
| `READ_MEDIA_IMAGES` / `READ_MEDIA_VIDEO` | Access photos and videos on Android 13+ (API 33+) |
| `READ_MEDIA_VISUAL_USER_SELECTED` | Partial, user-selected media access on Android 14+ (API 34+) |
| `READ_EXTERNAL_STORAGE` / `WRITE_EXTERNAL_STORAGE` | Storage access on Android 12 and below |
| `MANAGE_EXTERNAL_STORAGE` | Direct file handling for the `.trash` recycle bin and raw file operations |
| `ACCESS_MEDIA_LOCATION` | Read location metadata from camera photos |

</div>

---

## Build from Source

### Prerequisites

- Flutter SDK `^3.5`
- Android SDK and Java 17+

### Steps

```bash
# Clone the repository
git clone https://github.com/zerabyte88/phantek-gallery.git
cd phantek-gallery

# Install dependencies
flutter pub get

# Build a 64-bit release APK
flutter build apk --release --target-platform android-arm64
```

The compiled APK (`arm64-v8a`) is output to `build/app/outputs/flutter-apk/app-release.apk`.

---

## License

This project is open-source software licensed under the **[MIT License](LICENSE)**.

Third-party components (AndroidX Media3, Flutter, and bundled plugins) are subject to their own open-source licenses (Apache 2.0, BSD, MIT), which can be viewed in the app under **Settings > About > License**.
