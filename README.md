<div align="center">
  <img src="assets/app_icon_readme.png" alt="Phantek Gallery" width="120" />

  # Phantek Gallery

  **Offline Android gallery for photos, videos, PSD files, and manga, with on-device translation via Google ML Kit or local GGUF LLMs.**

  [![Version](https://img.shields.io/badge/Version-v2.19.5-3b82f6.svg?style=flat-square)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Platform](https://img.shields.io/badge/Platform-Android%208.0%2B-10b981.svg?style=flat-square&logo=android&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Architecture](https://img.shields.io/badge/Arch-arm64--v8a-8b5cf6.svg?style=flat-square&logo=arm&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Engine](https://img.shields.io/badge/Engine-Flutter%20%7C%20llama.cpp%20%7C%20ML%20Kit-6366f1.svg?style=flat-square)](https://github.com/ggml-org/llama.cpp)
  [![License](https://img.shields.io/badge/License-MIT-f59e0b.svg?style=flat-square&logo=open-source-initiative&logoColor=white)](LICENSE)

  [Download APK](https://github.com/zerabyte88/phantek-gallery/releases/latest) • [Features](#features) • [Translation Setup](#translation-setup) • [Supported Formats](#supported-formats) • [Tech Stack](#tech-stack) • [Permissions](#permissions) • [Build](#build-from-source) • [License](#license)
</div>

---

## Overview

Phantek Gallery is an offline gallery for photos, videos, Adobe Photoshop (`.psd`) files, and manga. Your media remains strictly on your device with zero tracking, no telemetry, and no cloud dependencies. 

For comic and manga readers, Phantek Gallery features dual offline translation engines:
1. **Google ML Kit On-Device Translation**: Instant, zero-config neural translation directly on your device.
2. **Local GGUF LLM Engine**: Advanced comic dialogue localization powered by `llama.cpp` using your choice of quantized GGUF models.

---

## Features

### Gallery and Viewing

- **PSD Layer Viewer**: Open Adobe Photoshop (`.psd`) documents with embedded-JPEG previews and a dedicated sheet for toggling individual layer visibilities.
- **Hardware Video Playback**: Built on AndroidX Media3 / ExoPlayer. Includes double-tap seek, gesture-based brightness and volume controls, and resume playback.
- **EXIF and Technical Inspector**: Detailed photo metadata (ISO, aperture, shutter speed, focal length, resolution) and video properties (bitrate, fps, codec, channels).

### Manga Reader & Offline Translation

- **Dual Offline Translation Engines**: Choose between Google ML Kit (fast, lightweight, zero-configuration) and Local LLM (nuanced comic dialogue localization via GGUF).
- **Manual Target Language Selection**: Choose your source language with dedicated buttons:
  - **Japanese** (`JA → EN`)
  - **Chinese** (`ZH → EN`)
  - **Korean** (`KO → EN`)
  - **Auto-Detect** (Script detection across Kanji/Kana, Hanzi, and Hangul)
- **Natural Comic Speech Bubble Geometry**:
  - **Preserved Original Bubble Contours**: Speech bubbles retain their natural comic outline and original bounding dimensions, completely eliminating artificial ballooning or obscuring character artwork.
  - **Vertical Dialogue Flow**: Automatically rotates English translations for tall, narrow Asian speech bubbles (90° clockwise with RTL column flow) so vertical dialogue fits cleanly and reads naturally without forced horizontal distortion.
- **Manga Reader with Natural Sort**: Continuous vertical reading mode with edge-to-edge layout, chapter progress indicators, and natural alphanumeric sorting (`Chapter 1`, `1.1`, `2.1`, `10`).

### Privacy and Security

- **100% Local-First**: No analytics, no tracking, no network calls during browsing or translation.
- **Screen Protection**: Optional Android `FLAG_SECURE` integration to prevent screen captures, video recordings, and task switcher previews.
- **Recycle Bin**: Staged `.trash` directory with configurable auto-purge intervals (7, 14, 30 days, or never) and batch restore.

### Personalization

- **Visual Themes**: *Dark Mode*, *Light Mode*, *Sunlight*, *Snowfall*, *Midnight*, and *Sakura* with dynamic theme headers.

---

## Translation Setup

Phantek Gallery offers two translation options to suit your preferences:

### Option A: Google ML Kit (Recommended for Zero-Config Setup)

Google ML Kit provides lightweight neural translation directly on your device with no external file setup needed.

1. Open **Settings > Google ML Kit**.
2. Select your **Source Language** (**Auto-Detect**, **Japanese**, **Chinese**, or **Korean**).
3. Tap the download icon next to your desired offline language model:
   - **Japanese** (`ja`)
   - **Chinese** (`zh`)
   - **Korean** (`ko`)
   - **English** (`en`)
4. In the viewer, open any manga page, tap the **Translate** button in the bottom bar, select your language button (**Japan**, **China**, or **Korea**), and enjoy offline translation.

---

### Option B: Local LLM Engine (GGUF / llama.cpp)

For higher dialogue nuance, slang preservation, and comic localization, you can run a local quantized LLM.

#### Recommended GGUF Models

Models can be downloaded from Hugging Face and placed in the app's models directory:

| Model | Format | Size | Recommended For | Hugging Face Download |
| :--- | :---: | :---: | :--- | :--- |
| **Qwen 2.5 0.5B abliterated (Q4_K_M)** | GGUF | ~380 MB | Ultra-fast inference on mobile devices, low memory footprint (~500 MB RAM). | [Download Qwen2.5-0.5B-Instruct-abliterated.Q4_K_M.gguf](https://huggingface.co/failspy/Qwen2.5-0.5B-Instruct-abliterated-GGUF/resolve/main/Qwen2.5-0.5B-Instruct-abliterated.Q4_K_M.gguf?download=true) |
| **Qwen 2.5 1.5B abliterated (Q4_K_M)** | GGUF | ~986 MB | Higher translation nuance and grammar accuracy for devices with 4 GB+ RAM. | [Download Qwen2.5-1.5B-Instruct-abliterated.Q4_K_M.gguf](https://huggingface.co/failspy/Qwen2.5-1.5B-Instruct-abliterated-GGUF/resolve/main/Qwen2.5-1.5B-Instruct-abliterated.Q4_K_M.gguf?download=true) |

#### Step-by-Step GGUF Installation

1. **Prepare Directory**: Open Phantek Gallery once. The app automatically creates the model folder:
   ```text
   /storage/emulated/0/models/
   ```
2. **Download Model**: Download your desired `.gguf` file (e.g. `Qwen2.5-0.5B-Instruct-abliterated.Q4_K_M.gguf`).
3. **Place Model**: Move the downloaded `.gguf` file into `/storage/emulated/0/models/`.
4. **Select in Settings**:
   - Go to **Settings > Manga Translation > Manga AI Model**.
   - Tap your model file to activate it.
5. **Switch Engine**: In the reader translation sheet, switch the engine toggle to **Local LLM**.

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
| **On-Device LLM** | `flutter_llama` (`^1.2.1`) | Offline manga translation via llama.cpp engine |
| **On-Device Translation** | `google_mlkit_translation` (`^0.11.0`) | On-device neural translation for Japanese, Chinese, Korean, English |
| **On-Device OCR** | `google_mlkit_text_recognition` (`^0.13.0`) | Offline script recognition (Japanese, Chinese, Korean, Latin) |
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
| `MANAGE_EXTERNAL_STORAGE` | Direct file handling for the `.trash` recycle bin and model access |
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
