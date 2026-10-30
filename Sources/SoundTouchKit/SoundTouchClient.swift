import Foundation

/// Sends HTTP requests. `URLSession` conforms; tests swap in a fake.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await data(for: request)
    }
}

/// Talks to one speaker through its local web API (port 8090). Nothing goes
/// through Bose's cloud.
public struct SoundTouchClient: Sendable {
    public static let defaultPort = 8090

    public let host: String
    public let port: Int
    public var timeout: TimeInterval
    private let transport: any HTTPTransport

    public init(
        host: String,
        port: Int = SoundTouchClient.defaultPort,
        timeout: TimeInterval = 5,
        transport: any HTTPTransport = URLSession.shared
    ) {
        self.host = host
        self.port = port
        self.timeout = timeout
        self.transport = transport
    }

    // MARK: State

    public func info() async throws -> DeviceInfo {
        try DeviceInfo(xml: await get("/info"))
    }

    public func nowPlaying() async throws -> NowPlaying {
        try NowPlaying(xml: await get("/now_playing"))
    }

    public func volume() async throws -> Volume {
        try Volume(xml: await get("/volume"))
    }

    public func sources() async throws -> [SourceItem] {
        let xml = try await get("/sources")
        guard xml.name == "sources" else { throw SoundTouchError.invalidResponse }
        return try xml.children(named: "sourceItem").map(SourceItem.init(xml:))
    }

    public func isPoweredOn() async throws -> Bool {
        try await !nowPlaying().isStandby
    }

    // MARK: Commands

    /// Presses and releases a button, like the physical remote does.
    public func press(_ key: Key) async throws {
        for state in ["press", "release"] {
            try await post("/key", body: #"<key state="\#(state)" sender="Gabbo">\#(key.rawValue)</key>"#)
        }
    }

    public func setVolume(_ value: Int) async throws {
        try await post("/volume", body: "<volume>\(min(max(value, 0), 100))</volume>")
    }

    public func volumeUp() async throws { try await press(.volumeUp) }
    public func volumeDown() async throws { try await press(.volumeDown) }

    /// `POWER` toggles, so these check the current state first.
    public func powerOn() async throws {
        if try await !isPoweredOn() { try await press(.power) }
    }

    public func powerOff() async throws {
        if try await isPoweredOn() { try await press(.power) }
    }

    /// Switches to a source returned by `sources()`. A source the model does
    /// not have (e.g. Bluetooth on an original SoundTouch 20) throws
    /// `SoundTouchError.api(code: 1005, ...)`.
    public func select(_ source: SourceItem) async throws {
        var attributes = #"source="\#(xmlEscaped(source.source))""#
        if let account = source.sourceAccount {
            attributes += #" sourceAccount="\#(xmlEscaped(account))""#
        }
        try await post("/select", body: "<ContentItem \(attributes)></ContentItem>")
    }

    // MARK: HTTP

    @discardableResult
    private func get(_ path: String) async throws -> XMLTree {
        try await send(path, method: "GET", body: nil)
    }

    @discardableResult
    private func post(_ path: String, body: String) async throws -> XMLTree {
        try await send(path, method: "POST", body: body)
    }

    private func send(_ path: String, method: String, body: String?) async throws -> XMLTree {
        var request = URLRequest(url: baseURL.appendingPathComponent(String(path.dropFirst())), timeoutInterval: timeout)
        request.httpMethod = method
        if let body {
            request.httpBody = Data(body.utf8)
            request.setValue("text/xml", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await transport.send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        let xml = try? XMLTree.parse(data)

        // Errors can come back with a 200 status, so check the body either way.
        if let xml, let error = SoundTouchError(xml: xml) { throw error }
        guard (200..<300).contains(status) else { throw SoundTouchError.http(status: status) }
        guard let xml else { throw SoundTouchError.invalidResponse }
        return xml
    }

    var baseURL: URL {
        URL(string: "http://\(urlHost):\(port)/")!
    }

    /// IPv6 addresses need brackets inside a URL.
    var urlHost: String {
        host.contains(":") ? "[\(host)]" : host
    }
}

// MARK: - Change notifications

extension SoundTouchClient {
    /// Port of the speaker's WebSocket, which pushes a message on every change.
    public static let notificationPort = 8080

    /// Yields each time the speaker reports a change (volume, source, power,
    /// track...), including changes made with its buttons or remote. Read the
    /// new state with the other methods. The stream ends when the connection
    /// drops; start a new one to reconnect.
    public func changes() -> AsyncStream<Void> {
        let url = URL(string: "ws://\(urlHost):\(Self.notificationPort)/")!
        return AsyncStream { continuation in
            let task = URLSession.shared.webSocketTask(with: url, protocols: ["gabbo"])

            @Sendable func receiveNext() {
                task.receive { result in
                    switch result {
                    case .success:
                        continuation.yield()
                        receiveNext()
                    case .failure:
                        continuation.finish()
                    }
                }
            }

            continuation.onTermination = { _ in task.cancel(with: .goingAway, reason: nil) }
            task.resume()
            receiveNext()
        }
    }
}
