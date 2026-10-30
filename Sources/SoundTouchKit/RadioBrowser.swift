import Foundation

/// An internet radio station from radio-browser.info.
public struct RadioStation: Sendable, Hashable, Identifiable, Codable {
    public var id: String
    public var name: String
    public var streamURL: URL
    public var faviconURL: URL?
    public var countryCode: String?
    public var codec: String?
    public var bitrate: Int?

    public init(id: String, name: String, streamURL: URL, faviconURL: URL? = nil, countryCode: String? = nil, codec: String? = nil, bitrate: Int? = nil) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.faviconURL = faviconURL
        self.countryCode = countryCode
        self.codec = codec
        self.bitrate = bitrate
    }

    /// MIME type for the UPnP renderer, from the codec radio-browser reports.
    public var mimeType: String {
        switch codec?.uppercased() {
        case "AAC", "AAC+": return "audio/aac"
        case "OGG": return "audio/ogg"
        case "FLAC": return "audio/flac"
        default: return "audio/mpeg"
        }
    }
}

/// Searches the open radio-browser.info directory.
public struct RadioBrowser: Sendable {
    public static let defaultServer = URL(string: "https://all.api.radio-browser.info")!

    public var server: URL
    private let transport: any HTTPTransport

    public init(server: URL = RadioBrowser.defaultServer, transport: any HTTPTransport = URLSession.shared) {
        self.server = server
        self.transport = transport
    }

    /// Stations whose name contains `name`, most voted first. Broken
    /// stations are left out.
    public func search(name: String, countryCode: String? = nil, limit: Int = 30) async throws -> [RadioStation] {
        var components = URLComponents(url: server.appendingPathComponent("json/stations/search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "hidebroken", value: "true"),
            URLQueryItem(name: "order", value: "votes"),
            URLQueryItem(name: "reverse", value: "true"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let countryCode {
            components.queryItems?.append(URLQueryItem(name: "countrycode", value: countryCode))
        }

        var request = URLRequest(url: components.url!, timeoutInterval: 10)
        // radio-browser asks clients to identify themselves.
        request.setValue("soundtouch-app/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await transport.send(request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        guard (200..<300).contains(status) else { throw SoundTouchError.http(status: status) }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> [RadioStation] {
        struct Entry: Decodable {
            var stationuuid: String
            var name: String
            var url_resolved: String?
            var url: String
            var favicon: String?
            var countrycode: String?
            var codec: String?
            var bitrate: Int?
        }
        return try JSONDecoder().decode([Entry].self, from: data).compactMap { entry in
            let stream = entry.url_resolved.flatMap { $0.isEmpty ? nil : $0 } ?? entry.url
            guard let streamURL = URL(string: stream), streamURL.scheme?.hasPrefix("http") == true else { return nil }
            return RadioStation(
                id: entry.stationuuid,
                name: entry.name.trimmingCharacters(in: .whitespacesAndNewlines),
                streamURL: streamURL,
                faviconURL: entry.favicon.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                countryCode: entry.countrycode.flatMap { $0.isEmpty ? nil : $0 },
                codec: entry.codec,
                bitrate: entry.bitrate.flatMap { $0 > 0 ? $0 : nil }
            )
        }
    }
}
