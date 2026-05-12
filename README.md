<div align="center">
  <img src="assets/icon/app_icon.png" width="100" alt="Flux Logo">
  <h1 align="center">Flux</h1>
  <p align="center">Your private AI assistant — entirely on-device, entirely yours.</p>

  <p align="center">
    <a href="https://github.com/Finn-Technologies/flux/releases"><img src="https://img.shields.io/badge/version-0.1.9-blue.svg" alt="Version"></a>
    <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-green.svg" alt="License"></a>
  </p>
</div>

---

## Overview

Flux is a **fully offline AI assistant** for Android. It runs quantized LLMs directly on your device using `llamadart` (llama.cpp bindings). No accounts, no cloud, no data leaving your phone — ever.

But it can also **search the web** when you want it to, combining the privacy of local inference with the freshness of live search results.

---

## Features

### Offline AI Chat

| Model | Size | RAM | What it's good at |
|-------|------|-----|-------------------|
| **Flux Lite** | 533 MB | 3 GB+ | Vision-capable, ultra-fast, sub-1B |
| **Flux Steady** | 3.1 GB | 5 GB+ | Multimodal reasoning, vision, balanced speed |
| **Flux Smart** | 5.1 GB | 7 GB+ | Flagship: vision, complex analysis, deep reasoning |

All models are GGUF quantizations of **Qwen 3.5 0.8B** (Lite) and **Gemma 4 E2B/E4B** (Steady/Smart), downloaded directly from Hugging Face inside the app.

### Web Search (Agentic)

Toggle the globe icon and Flux becomes an agent — it decides when to search, calls a `web_search` tool, reads the results, and answers based on what it found. No more pre-fetching; the model controls the search.

When search is off, everything runs 100% offline.

### App Builder ("Creations")

Describe an HTML/CSS/JS mini-app in natural language and Flux Lite will build it. The app gets a live preview, auto-saves to your collection, and you can run, edit, or delete creations.

### Conversation History

Every chat auto-saves. The history sidebar lets you browse, rename, or delete past conversations. When you tap an old chat, the model used for that conversation is automatically restored.

### Context Management

Flux proactively monitors its context window. When it hits 70% capacity, older conversation turns are automatically summarized into a compact history — no context overflows, no lost memory.

### Long Responses Without Crashing

Streaming updates at 60fps for fluid text appearance. Responses that get cut off automatically continue where they left off so no output is lost.

### Localized UI

The entire interface is translated into **6 languages**:

| Language | Locale |
|----------|--------|
| English | `en` |
| Spanish | `es` |
| French | `fr` |
| German | `de` |
| Italian | `it` |
| Chinese | `zh` |

---



## Getting Started

### Prerequisites

- Android device with **4 GB+ RAM** (8 GB recommended for Flux Smart)
- **Flutter SDK** (≥3.0) for development
- Android Studio, VS Code, or IntelliJ

### Installation

```bash
# Clone
git clone https://github.com/Finn-Technologies/flux.git
cd flux

# Dependencies
flutter pub get

# Run on a connected device
flutter run

# Build a release APK
flutter build apk --release --split-per-abi
```

---

## Architecture

```
lib/
├── main.dart                    # Entry point, GoRouter, theming
├── core/
│   ├── constants/               # AppVersion, etc.
│   ├── models/
│   │   ├── hf_model.dart        # AI model data structures
│   │   └── chat_session.dart    # Conversation persistence
│   ├── services/
│   │   ├── inference_service.dart   # llama.cpp streaming inference
│   │   ├── model_service.dart       # RAM-filtered model listing
│   │   └── search_service.dart      # DuckDuckGo HTML scraping
│   ├── providers/
│   │   ├── download_provider.dart   # Download state management
│   │   └── model_provider.dart      # Selected model state
│   ├── theme/                   # FluxColors, light/dark themes
│   └── widgets/                 # Shared UI components
├── features/
│   ├── onboarding/              # Welcome flow + model selection
│   ├── chat/                    # Main chat + message list + streaming
│   ├── models/                  # Download library + storage info
│   ├── creations/               # App builder gallery, editor, preview
│   └── settings/                # Cache, about, version
├── l10n/                        # ARB + generated Dart (6 languages)
└── assets/
    ├── images/                  # SVG icons
    └── icon/                    # App icon (PNG)
```

### Tech Stack

| Layer | Choice |
|-------|--------|
| Framework | Flutter 3.x |
| State | Riverpod 2.x |
| Routing | go_router |
| Local DB | Hive + SharedPreferences |
| AI Engine | llama.cpp via `llamadart` |
| Downloads | `background_downloader` |
| Search | DuckDuckGo HTML (no API key needed) |
| WebView | `webview_flutter` |
| Fonts | Instrument Sans (Google Fonts) |
| Icons | Custom SVGs + Material Symbols |

---

---

## Privacy

Flux is built with privacy as a hard requirement:

- **No account** — download and start using immediately
- **No cloud** — inference runs locally via llama.cpp
- **No telemetry** — zero analytics, zero tracking
- **No internet needed** — fully offline when search is toggled off
- **Open source** — every line of code is auditable

---

## Roadmap

- [x] Offline AI chat with 3 model sizes
- [x] Web search with source display
- [x] HTML/CSS/JS app builder (Creations)
- [x] Conversation history with model restoration
- [x] Context window compaction
- [x] 6-language localization
- [x] Performance: throttled streaming, continuations, debouncing
- [x] Image / vision model support
- [ ] Voice input
- [ ] Export conversations (JSON / text)
- [ ] iOS version

---

---

## What's New in v0.1.9

- **Gemma 4 models** — Flux Steady (Gemma 4 E2B) and Flux Smart (Gemma 4 E4B) replace the previous Qwen models with native vision support and mmproj auto-download
- **Vision for all models** — Flux Lite (Qwen 3.5 0.8B), Steady, and Smart all support image attachments with a paperclip button in the chat bar
- **Agentic web search** — the model decides when to search the web using tool calling instead of pre-fetching results
- **Image memory** — previously uploaded images are remembered in the conversation history
- **Proactive context compaction** — automatically summarizes older conversation turns when the context window reaches 70% capacity
- **Maximum speed** — doubled batch sizes, GPU offload for all models, faster streaming, and per-model context tuning
- **Thinking process UI** — Gemma 4 reasoning (channel/think tags) rendered as a collapsible section with 50% opacity
- **Real desktop detection** — native RAM and storage detection on macOS, Linux, and Windows via sysctl/df/PowerShell
- **Lower RAM requirements** — Lite 3 GB, Steady 5 GB, Smart 7 GB

## License

Flux itself is MIT licensed — see [LICENSE](LICENSE).

The AI models used by Flux are **Qwen 3.5** by Alibaba Cloud, distributed under the **Apache 2.0 license**.  
See [MODEL-LICENSE](MODEL-LICENSE) for the full license text.

---

<div align="center">
  <strong>Made with ❤️ by Finn Technologies</strong>
</div>
