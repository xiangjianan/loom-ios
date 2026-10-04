# Architecture

- `Models/Models.swift`: Codable model configurations, conversation snapshots, messages, UTF-16 highlight ranges, quotes and provider payloads. Conversations preserve model identity after their first message.
- `Services/LoomStore.swift`: Main-actor Observation state, independent per-model tasks, cancellation, history switching, Keychain configuration and atomic local persistence. Pending assistant placeholders persist so interrupted requests can be retried after relaunch.
- `Services/ProviderClient.swift`: Default direct HTTPS provider client, OpenAI-compatible / Anthropic authentication and response normalization, model listing, redirect rejection. Native apps do not require CORS relays.
- `Services/RelayClient.swift`: HTTPS JSON relay client; OpenAI-compatible and Anthropic requests use the existing Loom relay contract. URLSession injection supports deterministic network tests.
- `Services/KeychainStore.swift`: Device-only, unlocked Keychain storage; credentials are absent from Codable models.
- `Views/WorkspaceView.swift`: Window-width based layout. Wide iPad windows show horizontally scrollable model columns; narrower windows use top Liquid Glass buttons and native page-style TabView. One selection binding synchronizes taps and page swipes.
- `Views/SelectableAnswer.swift`: UIKit text selection bridged into SwiftUI with a self-sizing, noneditable UITextView. Uses `AnswerRenderer.swift` to render full block and inline Markdown, links, code, Dynamic Type and persistent yellow highlights. UTF-16 ranges target rendered text, not Markdown source. `HighlightResolver` reanchors legacy ranges by selected text after formatting changes. Stable native selections emit after 650 ms; dragging handles updates overlaps.
- `Views/ComposerView.swift`: Shared fixed safe-area composer, quote tray and send/stop control.
- `Views/SettingsView.swift`, `Views/HistoryView.swift`: Native forms, model editing, model discovery and searchable local history.

Only navigation and controls use glass; answer text remains on a plain reading surface. No third-party Swift package dependencies are required.
