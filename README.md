<div align="center">
  <img src="assets/app_icon_readme.png" alt="Phantek Gallery" width="120" />

  # Phantek Gallery

  **A fast, privacy-focused Android gallery with PSD layer support and on-device AI manga translation using a local LLM of your choice.**

  [![Version](https://img.shields.io/badge/Version-v2.16.2-3b82f6.svg?style=flat-square)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Platform](https://img.shields.io/badge/Platform-Android%208.0%2B-10b981.svg?style=flat-square&logo=android&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Architecture](https://img.shields.io/badge/Arch-arm64--v8a-8b5cf6.svg?style=flat-square&logo=arm&logoColor=white)](https://github.com/zerabyte88/phantek-gallery/releases)
  [![Engine](https://img.shields.io/badge/Engine-Flutter%20%7C%20ExoPlayer-6366f1.svg?style=flat-square)](https://developer.android.com/media/media3)
  [![License](https://img.shields.io/badge/License-MIT-f59e0b.svg?style=flat-square&logo=open-source-initiative&logoColor=white)](LICENSE)

  [Download APK](https://github.com/zerabyte88/phantek-gallery/releases/latest) • [Features](#features) • [Translation Setup](#translation-setup) • [Supported Formats](#supported-formats) • [Tech Stack](#tech-stack) • [Permissions](#permissions) • [Build](#build-from-source) • [License](#license)
</div>

---

## Overview

Phantek Gallery is a local-first gallery for photos, videos, PSD files, and manga. Your media stays on your device, there is no tracking, no telemetry, and no cloud sync. Manga translation runs on a lightweight local LLM that you download and install yourself, so your pages are never sent to a cloud API.

---

## Features

### Gallery and Viewing

- **Fast Media Grid** : Hardware-accelerated thumbnails through `MediaStore.loadThumbnail` (1–2 ms), in-memory cache indexing, and isolate-backed decoding for smooth scrolling up to 120 Hz.
- **PSD Layer Viewer** : Open Adobe Photoshop (`.psd`) files with instant seekable embedded-JPEG previews (under 1 ms) and a sheet for toggling individual layers on and off.
- **Hardware Video Playback** : Built on AndroidX Media3 / ExoPlayer with a dual SurfaceView pipeline for smooth 2K and 4K playback. Includes double-tap seek, smart zoom, brightness and volume gestures, and playback position resume.
- **EXIF and Media Inspector** : Technical details for photos (ISO, aperture, focal length, resolution) and videos (bitrate, fps, codec, channels).

### Manga

- **Manga Reader with Natural Sort** : Continuous vertical reading with an edge-to-edge view and chapter progress pills. Albums and chapters sort naturally (`Chapter 1`, `1.1`, `2.1`, `10`, `25`).
- **On-Device AI Translation** : Translate manga pages with a lightweight local LLM such as Qwen2.5 0.5B. Everything runs on your device, with no cloud APIs involved.
- **Bring Your Own Model** : Models are not bundled with the app. Download the LLM you prefer and switch models from Settings, allowing you to choose the model size that best fits your device specs.

### Privacy and Safety

- **Local-First and Private** : No tracking, no telemetry, no cloud sync. Media files never leave your device, and translation runs fully on-device with a model you provide.
- **Screen Protection** : Uses Android `FLAG_SECURE` to block screenshots and screen recordings, and to blur the recent apps preview.
- **Recycle Bin** : A staged `.trash` folder with configurable auto-purge (7, 14, or 30 days, or never) and batch restore or permanent delete.

### Personalization

- **Visual Themes** : Six hand-crafted themes (*Dark Mode*, *Light Mode*, *Sunlight*, *Snowfall*, *Midnight*, *Sakura*) with dynamic artistic headers.

---

## Translation Setup

Phantek Gallery translates comic dialogues completely offline on your device using local quantized LLM models. To keep the APK download small (< 100 MB) and give you full control over performance and RAM usage, models are not bundled inside the app.

---

### 1. Recommended Models

For the best balance of speed, low memory footprint, and natural comic dialogue translation (Japanese/Korean/Chinese to English), we recommend **Qwen 2.5 0.5B Instruct abliterated ONNX**:

| Model | Size | Recommended For | Hugging Face Download Link |
| :--- | :---: | :--- | :--- |
| **Qwen 2.5 0.5B Instruct abliterated (Q4)** *(Recommended)* | ~734 MB | Low-end & mid-range devices. Fast, snappy bubble translations. | [onnx-community/Qwen2.5-0.5B-Instruct-abliterated-ONNX](https://huggingface.co/onnx-community/Qwen2.5-0.5B-Instruct-abliterated-ONNX/resolve/main/onnx/model_q4.onnx?download=true) |

> [!TIP]
> Each ONNX model requires its companion **`tokenizer.json`** to tokenize comic text. You can download the official Qwen tokenizer file directly from Hugging Face :

> - **Tokenizer Download** : 
[onnx-community/Qwen2.5-0.5B-Instruct-abliterated-ONNX tokenizer.json](https://huggingface.co/onnx-community/Qwen2.5-0.5B-Instruct-abliterated-ONNX/resolve/main/tokenizer.json?download=true)


---

### 2. Step-by-Step Installation Guide

#### Step 1 : Launch App Once to Prepare Directory
Open Phantek Gallery at least once. The app automatically creates the dedicated model folder on your internal storage:
```text
/storage/emulated/0/models/
```
*(Alternatively, you can manually create the `models` folder in your phone's internal storage root using any file manager).*

#### Step 2 : Download Model & Tokenizer
1. Download the quantized ONNX model file (e.g. `qwen2.5-0.5b-instruct-abliterated-q4.onnx` or `model_q4.onnx` from the link above).
2. Download the companion [`tokenizer.json`](https://huggingface.co/onnx-community/Qwen2.5-0.5B-Instruct-abliterated-ONNX/resolve/main/tokenizer.json?download=true).

#### Step 3 : Copy Files to the `models/` Directory
Place both files together into `/storage/emulated/0/models/`:
```text
/storage/emulated/0/models/
├── qwen2.5-0.5b-instruct-abliterated-q4.onnx
└── tokenizer.json
```

#### Step 4 : Verify in Settings
1. Open Phantek Gallery > **Settings** > scroll to **Manga AI Model**.
2. Tap **Manga AI Model** to see discovered models. You can keep **Auto-detect (Default)** or tap the model name to select it explicitly.

#### Step 5 : Start Translating
Open any manga or image page in the viewer, tap the **Translate icon (文A)** in the bottom bar, and choose **Translate Speech Bubbles** or **Translate Full Page**. The local LLM will translate speech bubbles offline in real-time.

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
| **On-Device LLM** | Local LLM runtime | Manga translation with a user-provided model (e.g. Qwen2.5 0.5B) |
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
| `MANAGE_EXTERNAL_STORAGE` | Direct file handling for the `.trash` recycle bin |
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

The compiled APK (arm64-v8a) is created at `build/app/outputs/flutter-apk/app-release.apk`.

---

## License

This project is open-source software licensed under the **[MIT License](LICENSE)**.

Third-party components (AndroidX Media3, Flutter, and bundled plugins) are subject to their own open-source licenses (Apache 2.0, BSD, MIT), which can be viewed in the app under **Settings > About > License**.
