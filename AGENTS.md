# Flux — Agent Guide

Flux is an **on-device AI assistant** for mobile, tablet, and desktop. It runs LLM inference locally using `flutter_gemma` (Dart package wrapping Google's LiteRT-LM / MediaPipe GenAI with Gemma model support).

## Supported Platforms

| Platform | Status |
|---|---|
| Android | ✅ |
| iOS | ✅ |
| macOS | ✅ |
| Windows | ✅ |
| Linux | ✅ |
| HarmonyOS (OHOS) | ✅ |

## Architecture

```
lib/
  main.dart                          # Entry point, routing, app bootstrap
  core/
    constants/                       # App-wide constants (version, responsive)
    models/                          # Data models (ChatSession, HF model)
    providers/                       # Riverpod state providers (models, downloads)
    services/                        # Business logic (inference, model mgmt, search)
    theme/                           # Light/dark theme definitions
    widgets/                         # Reusable shared widgets (shell, animations, renderers)
  features/
    chat/                            # Chat conversation UI
    creations/                       # AI creation gallery, editor, and viewer
    models/                          # Model management screen
    onboarding/                      # First-launch onboarding flow
    settings/                        # Settings and about screens
  l10n/                              # Generated localization + .arb sources (6 locales)
```

### Key Dependencies

| Package | Purpose |
|---|---|
| `flutter_gemma` ^0.14.5 | On-device LLM inference via LiteRT-LM / MediaPipe (Gemma models) |
| `hive_flutter` | Local key-value storage (models, settings, chats, creations) |
| `flutter_riverpod` | State management |
| `go_router` | Declarative routing with ShellRoute (tab navigation) |
| `webview_flutter` | WebView for HTML content rendering |
| `image_picker` | Camera/gallery image selection (for multimodal models) |
| `flutter_svg` | SVG rendering |
| `google_fonts` | Font loading |

### Inference Service

The `InferenceService` (`lib/core/services/inference_service.dart`) manages:
- `flutter_gemma` model lifecycle (load, unload)
- Streaming chat with conversation history
- Token/speed metrics tracking

Models are downloaded via `FlutterGemma.installModel()` and loaded with `FlutterGemma.getActiveModel()` — the package handles the underlying LiteRT-LM engine automatically.

## Building

### Standard platforms (Android, iOS, macOS, Windows, Linux)

```sh
flutter pub get
flutter run
flutter build apk  # Android
flutter build ios  # iOS
```

### HarmonyOS (OHOS)

**OHOS builds must be done from DevEco Studio.** The Flutter OHOS tooling invokes hvigor, but CLI `hvigorw` v6.x has SDK validation issues requiring a DevEco Studio-managed SDK.

#### Prerequisites

1. **Flutter OHOS SDK** — Clone and configure:
   ```sh
   git clone https://github.com/Finn-Technologies/flutter.git ~/flutter_ohos
   export PATH="$HOME/flutter_ohos/bin:$PATH"
   flutter config --enable-ohos
   ```

2. **DevEco Studio** — Install from https://developer.harmonyos.com/cn/develop/deveco-studio

3. **OpenHarmony SDK** — Install via DevEco Studio SDK Manager (API 20 or 26, components: ArkTS, JS, Native, Previewer, Toolchains, HMS)

4. **Rosetta 2** (Apple Silicon):
   ```sh
   sudo softwareupdate --install-rosetta --agree-to-license
   ```

#### Environment

```sh
export DEVECO_SDK_HOME=/Users/abhi/Library/OpenHarmony/Sdk
export PATH=/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:$PATH
export PATH=/Applications/DevEco-Studio.app/Contents/tools/node/bin:$PATH
```

#### DevEco Studio Build

1. Open `ohos/` as a project in DevEco Studio
2. Wait for ohpm dependency resolution
3. `Build → Build Hap(s)`
4. Output: `ohos/entry/build/default/outputs/default/entry-default-signed.hap`

#### OHOS Project Structure

```
ohos/
  build-profile.json5               # Project build config (API version, signing)
  oh-package.json5                   # Root dependencies
  hvigorfile.ts                      # Hvigor entry (appTasks + flutter-hvigor-plugin)
  hvigorconfig.ts                    # Hvigor config (injectNativeModules)
  debug.p12 / debug.cer              # Debug signing materials
  flutter_embedding_debug.har        # Flutter engine for OHOS
  arm64_v8a_debug.har               # Native engine library
  entry/
    build-profile.json5              # Module build config (stage model)
    oh-package.json5                 # Module dependencies (@ohos/flutter_ohos)
    src/main/
      ets/entryability/EntryAbility.ets  # Entry point extending FlutterAbility
      ets/pages/Index.ets                # FlutterPage UI
      module.json5                       # Module manifest
      resources/                         # Icons, strings, colors
    src/ohosTest/                        # Test runner and test files
  AppScope/
    app.json5                        # App manifest (bundle, vendor, version)
  hvigor/                            # Hvigor config
```

## Upgrading flutter_gemma

When upgrading `flutter_gemma`, ensure the Dart SDK constraint in `pubspec.yaml` is compatible. The OHOS Flutter SDK uses Dart 3.11.5 (Flutter 3.41.9). See `AGENTS.md` in the Flutter SDK repo for more.

## Adding OHOS Plugins

Plugins with OHOS native code need their `ohos` platform implementations. The `GeneratedPluginRegistrant.ets` in `ohos/entry/src/main/ets/plugins/` is auto-generated by the Flutter tool during `flutter pub get`. It's gitignored and regenerated automatically.

## Known Issues

1. **OHOS builds require DevEco Studio** — CLI `flutter build hap` may fail with `SDK component missing`. Use DevEco Studio for final .hap generation.
2. **Apple Silicon + Rosetta** — The `hdc` binary is x86_64 and requires Rosetta 2.
3. **Engine HARs** — The `flutter_embedding_debug.har` and `arm64_v8a_debug.har` must be manually provided. They're from the Flutter OHOS engine cache (not on public ohpm registry).
4. **Analyzer warning** — `flutter analyze` shows `unknown_platform` for `ohos` in pubspec.yaml. This is cosmetic; the ohos analyzer platform is not yet upstreamed.
