import Foundation

/// Plays audio URLs on a speaker through its UPnP/DLNA renderer (port 8091).
///
/// The speaker downloads the stream itself, so playback continues after the
/// app closes. Verified with internet radio (HTTP MP3) on a SoundTouch 10 and
/// an original SoundTouch 20.
public struct UPnPRenderer: Sendable {
    public static let defaultPort = 8091

    public let host: String
    public var timeout: TimeInterval
    private let transport: any HTTPTransport

    public init(
        host: String,
        timeout: TimeInterval = 5,
        transport: any HTTPTransport = URLSession.shared
    ) {
        self.host = host
        self.timeout = timeout
        self.transport = transport
    }

    var controlURL: URL {
        let urlHost = host.contains(":") ? "[\(host)]" : host
        return URL(string: "http://\(urlHost):\(Self.defaultPort)/AVTransport/Control")!
    }

    /// Starts playing `url`. `title` is what the speaker shows while it plays.
    public func play(_ url: URL, title: String, mimeType: String = "audio/mpeg") async throws {
        try await call("SetAVTransportURI", arguments: """
            <InstanceID>0</InstanceID>\
            <CurrentURI>\(xmlEscaped(url.absoluteString))</CurrentURI>\
            <CurrentURIMetaData>\(xmlEscaped(Self.metadata(url: url, title: title, mimeType: mimeType)))</CurrentURIMetaData>
            """)
        try await call("Play", arguments: "<InstanceID>0</InstanceID><Speed>1</Speed>")
    }

    public func stop() async throws {
        try await call("Stop", arguments: "<InstanceID>0</InstanceID>")
    }

    /// DIDL-Lite describing a live audio stream. Some renderers refuse a URI
    /// without metadata.
    static func metadata(url: URL, title: String, mimeType: String) -> String {
        """
        <DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" \
        xmlns:dc="http://purl.org/dc/elements/1.1/" \
        xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/">\
        <item id="1" parentID="0" restricted="1">\
        <dc:title>\(xmlEscaped(title))</dc:title>\
        <upnp:class>object.item.audioItem.audioBroadcast</upnp:class>\
        <res protocolInfo="http-get:*:\(mimeType):*">\(xmlEscaped(url.absoluteString))</res>\
        </item></DIDL-Lite>
        """
    }

    private func call(_ action: String, arguments: String) async throws {
        let service = "urn:schemas-upnp-org:service:AVTransport:1"
        var request = URLRequest(url: controlURL, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue(#"text/xml; charset="utf-8""#, forHTTPHeaderField: "Content-Type")
        request.setValue("\"\(service)#\(action)\"", forHTTPHeaderField: "SOAPACTION")
        request.httpBody = Data("""
            <?xml version="1.0" encoding="utf-8"?>\
            <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" \
            s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">\
            <s:Body><u:\(action) xmlns:u="\(service)">\(arguments)</u:\(action)></s:Body>\
            </s:Envelope>
            """.utf8)

        let (data, response) = try await transport.send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else {
            throw Self.fault(in: data) ?? SoundTouchError.http(status: status)
        }
    }

    /// Reads the `<UPnPError>` inside a SOAP fault.
    static func fault(in data: Data) -> SoundTouchError? {
        guard let xml = try? XMLTree.parse(data),
              let error = xml.first(named: "UPnPError")
        else { return nil }
        return .upnp(
            code: error.text(of: "errorCode").flatMap(Int.init) ?? 0,
            description: error.text(of: "errorDescription") ?? "UPnP error"
        )
    }
}

extension XMLTree {
    /// Depth-first search for an element by local name, ignoring namespace prefixes.
    func first(named name: String) -> XMLTree? {
        if self.name == name || self.name.hasSuffix(":" + name) { return self }
        for child in children {
            if let match = child.first(named: name) { return match }
        }
        return nil
    }
}
