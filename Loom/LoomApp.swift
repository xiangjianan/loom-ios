import SwiftUI

@main
struct LoomApp: App {
    @State private var store = LoomStore(
        demo: ProcessInfo.processInfo.arguments.contains("--demo"),
        session: previewSession()
    )
    var body: some Scene {
        WindowGroup { WorkspaceView(store: store).tint(.indigo) }
    }
}

private func previewSession() -> URLSession {
    #if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--ui-test-discovery") {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [DiscoveryFixtureProtocol.self]
        return URLSession(configuration: configuration)
    }
    #endif
    return ProviderClient.secureSession
}

#if DEBUG
private final class DiscoveryFixtureProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"data":[{"id":"fixture-chat"},{"id":"fixture-reasoner"}]}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
#endif
