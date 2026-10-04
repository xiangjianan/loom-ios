import SwiftUI

@main
struct LoomApp: App {
    @State private var store = LoomStore(demo: ProcessInfo.processInfo.arguments.contains("--demo"))
    var body: some Scene {
        WindowGroup { WorkspaceView(store: store).tint(.indigo) }
    }
}
