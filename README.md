# Loom for iOS

**English** | [简体中文](README.zh-CN.md)

A native SwiftUI workspace for comparing answers from multiple AI models on **iPhone and iPad**. Built with system Liquid Glass. Requires **iOS / iPadOS 26 or later**.

## Features

- **Adaptive reading:** model tabs and swipe navigation in narrow windows; independently scrolling answer columns at widths of 700 pt or more. iPhone is portrait only; iPad supports portrait and landscape. Layout changes preserve the selected model, draft, and references.
- **1–5 models:** OpenAI-compatible APIs and Anthropic, with presets for OpenAI, Claude, Gemini, DeepSeek, Qwen, Kimi, GLM, and Grok. Enter your API key to fetch available models, or enter a model ID manually. Reorder models by dragging in settings; disable a model without deleting its history or credentials.
- **Highlight and follow up:** tap a sentence to highlight it, or select text and choose “高亮” (Highlight) from the system menu. Double-tap mode is available in settings. Adjacent highlights merge; removing a reference also removes its source highlight. Every enabled model receives the same question and references, with its own conversation context.
- **Rich answers:** native Markdown, code blocks, basic tables, links, and embedded SVG. Text around SVG remains selectable. SVG JavaScript and external resource loading are disabled.
- **Conversation drawer:** open the top-left button or drag from the left edge to create, search, and switch conversations. Long-press a conversation to delete it with confirmation. Access settings from the drawer and backup from settings.
- **Reading controls:** jump between rounds using the left-side markers, keep independent reading positions per model and conversation, and copy prompts or share answers.
- **Local persistence and backup:** conversations, drafts, highlights, model configurations, and preferences are saved locally. Export/import through Files, including iCloud Drive. API keys are excluded by default.
- **Request controls:** send to enabled models in parallel, stop generation, and retry a failed answer. Switching conversations cancels active requests. The composer supports multiple lines and moves with the keyboard.

The app interface is currently in Simplified Chinese. It supports system dark mode, Dynamic Type, and VoiceOver. Bilingual documentation does not change the app's interface language.

## Preview

Launch with `--demo` to use local sample answers without calling model providers or writing to your real conversation history.

| iPhone | iPad |
| --- | --- |
| ![iPhone](docs/iphone.jpg) | ![iPad](docs/ipad.jpg) |

## Run in Xcode

1. Open `Loom.xcodeproj` in **Xcode 26 or later**.
2. Select the `Loom` scheme and an iPhone or iPad simulator, then run.
3. Open the conversation drawer → settings, select a provider, enter your API key, choose a model, and save.
4. Write a question to send it to all enabled models.

For a physical device, select your own development team in **Signing & Capabilities**. Signing certificates, provisioning profiles, and a development team ID are not included in the repository.

The project has no third-party runtime dependencies. `project.yml` manages project configuration; regenerate the Xcode project after changing targets or build settings:

```sh
brew install xcodegen
xcodegen generate
```

## Data and networking

All chat requests and model-list requests go **directly to the configured provider**. Relay settings from older files and backups can be read for migration but do not re-enable relay requests.

- API keys are stored in the system Keychain using `WhenUnlockedThisDeviceOnly`, outside normal conversation JSON. Backup files include keys only when you explicitly enable that option.
- Providers receive the configured API key, conversation context, and highlighted references. Network availability depends on your provider and device connection.
- Local state is saved atomically in the app sandbox at `Application Support/Loom/state.json` with system file protection. Corrupt records are retained rather than overwritten.
- File backups support manual migration. There is no account system, automatic cross-device synchronization, or web-history migration.
- Answers appear after the complete response arrives; streaming is not currently supported. Background completion is not guaranteed. Interrupted requests become retryable when the app next opens.
- Deleting the app deletes local conversations; Keychain credentials may remain.

## Optional native iCloud backup

File export to iCloud Drive uses the system Files picker. Direct cloud backup is a separate, optional CloudKit feature using a private database and one replaceable latest archive.

To enable it, configure `iCloud.online.minidesk.loom`, CloudKit, and matching signing profiles in your developer account. Use `Configuration/iCloud.entitlements`, then build with `CODE_SIGN_ENTITLEMENTS=Configuration/iCloud.entitlements` and `SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG LOOM_ICLOUD'` (`LOOM_ICLOUD` for Release).

Before release, deploy the `LoomBackup` record type with `archive` (Asset) and `createdAt` (Date/Time) to production in CloudKit Console. Development saves can create the schema; production cannot. Without the entitlement, the app reports that native iCloud backup is unavailable. Actual cloud backup/restore still needs verification with an entitled build and a signed-in test account.

## Validation

Recent checks used Xcode 27 / iOS 27 simulators; the deployment target remains iOS 26.

- 36 unit tests passed, covering persistence, backup, highlights, model enablement, request cancellation, failure isolation, and credential handling.
- iPhone rotation checks passed: both landscape device orientations keep the interface in portrait and retain model selection and the draft.
- iPad mini rotation and parallel-reading checks passed. A signed build was installed and launched on iPhone 15 Pro.
- Network tests use mocked services; they do not consume real model credits. Real provider responses require your own credentials and network verification.
- The installed Xcode does not provide an iPhone Duo simulator. Folding between inner and outer displays still requires a Duo device or corresponding simulator. Haptics and long-conversation performance need physical-device evaluation.

Run tests with an available simulator name:

```sh
xcodebuild test -project Loom.xcodeproj -scheme Loom \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro' \
  -parallel-testing-enabled NO
```

For demo previews, add `--demo` under the scheme's Run → Arguments.

## Contributing and release history

Ideas, bug reports, and code contributions are welcome through [GitHub issues](https://github.com/xiangjianan/loom-ios/issues) and pull requests.

See the [version history (Simplified Chinese)](docs/CHANGELOG.zh-CN.md) for earlier features, screenshots, and validation records. App Store distribution also requires a privacy policy, privacy disclosures, signing, and real-provider testing.
