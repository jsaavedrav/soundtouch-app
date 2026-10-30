import Foundation
import XCTest
@testable import SoundTouchKit

/// Answers requests from a table and records what was sent.
final class FakeTransport: HTTPTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [String: [(Int, String)]] = [:]
    private(set) var requests: [URLRequest] = []

    /// Queues a response for "METHOD /path". Several calls queue in order;
    /// the last one keeps answering.
    func on(_ route: String, status: Int = 200, _ body: String) {
        lock.lock(); defer { lock.unlock() }
        responses[route, default: []].append((status, body))
    }

    var bodies: [String] {
        lock.lock(); defer { lock.unlock() }
        return requests.compactMap { $0.httpBody.map { String(decoding: $0, as: UTF8.self) } }
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        respond(to: request)
    }

    private func respond(to request: URLRequest) -> (Data, URLResponse) {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        let route = "\(request.httpMethod ?? "GET") \(request.url!.path)"
        guard var queue = responses[route], let next = queue.first else {
            XCTFail("Unexpected request \(route)")
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
        }
        if queue.count > 1 { queue.removeFirst(); responses[route] = queue }
        return (Data(next.1.utf8), HTTPURLResponse(url: request.url!, statusCode: next.0, httpVersion: nil, headerFields: nil)!)
    }
}

final class ParsingTests: XCTestCase {
    private func xml(_ string: String) throws -> XMLTree {
        try XMLTree.parse(Data(string.utf8))
    }

    func testInfo() throws {
        let info = try DeviceInfo(xml: xml(Fixtures.info))
        XCTAssertEqual(info.deviceID, "AABBCCDDEEFF")
        XCTAssertEqual(info.name, "Living SoundTouch 20")
        XCTAssertEqual(info.type, "SoundTouch 20")
        XCTAssertEqual(info.moduleType, "scm")
        XCTAssertTrue(info.softwareVersion?.hasPrefix("27.0.6") ?? false)
    }

    func testVolume() throws {
        let volume = try Volume(xml: xml(Fixtures.volume))
        XCTAssertEqual(volume.actual, 10)
        XCTAssertEqual(volume.target, 12)
        XCTAssertFalse(volume.isMuted)
    }

    func testNowPlaying() throws {
        let playing = try NowPlaying(xml: xml(Fixtures.nowPlayingSpotify))
        XCTAssertEqual(playing.source, "SPOTIFY")
        XCTAssertEqual(playing.itemName, "Go")
        XCTAssertEqual(playing.track, "Jesus of Suburbia")
        XCTAssertNil(playing.stationName)
        XCTAssertFalse(playing.isStandby)

        XCTAssertTrue(try NowPlaying(xml: xml(Fixtures.nowPlayingStandby)).isStandby)
    }

    func testWrongRootIsRejected() throws {
        XCTAssertThrowsError(try Volume(xml: xml(Fixtures.info)))
        XCTAssertThrowsError(try XMLTree.parse(Data("<html><body>Object Not Found".utf8)))
    }

    func testError() throws {
        XCTAssertEqual(SoundTouchError(xml: try xml(Fixtures.unknownSourceError)),
                       .api(code: 1005, name: "UNKNOWN_SOURCE_ERROR"))
        XCTAssertNil(SoundTouchError(xml: try xml(Fixtures.volume)))
    }
}

final class ClientTests: XCTestCase {
    private var transport: FakeTransport!
    private var client: SoundTouchClient!

    override func setUp() {
        transport = FakeTransport()
        client = SoundTouchClient(host: "192.168.1.20", transport: transport)
    }

    func testURL() {
        XCTAssertEqual(client.baseURL.absoluteString, "http://192.168.1.20:8090/")
        XCTAssertEqual(SoundTouchClient(host: "fe80::1").baseURL.absoluteString, "http://[fe80::1]:8090/")
    }

    func testPhysicalInputs() async throws {
        transport.on("GET /sources", Fixtures.sourcesST20)
        transport.on("GET /sources", Fixtures.sourcesST10)

        let st20 = try await client.sources().filter(\.isPhysicalInput).map(\.source)
        let st10 = try await client.sources().filter(\.isPhysicalInput).map(\.source)
        XCTAssertEqual(st20, ["AUX"])
        XCTAssertEqual(st10, ["AUX", "BLUETOOTH"])
    }

    func testPressSendsPressThenRelease() async throws {
        transport.on("POST /key", Fixtures.status("/key"))
        try await client.press(.volumeUp)
        XCTAssertEqual(transport.bodies, [
            #"<key state="press" sender="Gabbo">VOLUME_UP</key>"#,
            #"<key state="release" sender="Gabbo">VOLUME_UP</key>"#,
        ])
    }

    func testPowerOnOnlyWhenInStandby() async throws {
        transport.on("POST /key", Fixtures.status("/key"))

        transport.on("GET /now_playing", Fixtures.nowPlayingSpotify)
        try await client.powerOn()
        XCTAssertEqual(transport.bodies, [])

        try await client.powerOff()
        XCTAssertEqual(transport.bodies.count, 2)
        XCTAssertTrue(transport.bodies[0].contains(">POWER<"))
    }

    func testPowerOnFromStandby() async throws {
        transport.on("POST /key", Fixtures.status("/key"))
        transport.on("GET /now_playing", Fixtures.nowPlayingStandby)

        try await client.powerOff()
        XCTAssertEqual(transport.bodies, [])

        try await client.powerOn()
        XCTAssertEqual(transport.bodies.count, 2)
    }

    func testSetVolumeClamps() async throws {
        transport.on("POST /volume", Fixtures.status("/volume"))
        try await client.setVolume(30)
        try await client.setVolume(150)
        try await client.setVolume(-3)
        XCTAssertEqual(transport.bodies, ["<volume>30</volume>", "<volume>100</volume>", "<volume>0</volume>"])
        XCTAssertEqual(transport.requests.first?.value(forHTTPHeaderField: "Content-Type"), "text/xml")
    }

    func testSelectSendsContentItem() async throws {
        transport.on("POST /select", Fixtures.status("/select"))
        try await client.select(SourceItem(source: "AUX", sourceAccount: "AUX"))
        try await client.select(SourceItem(source: "BLUETOOTH"))
        XCTAssertEqual(transport.bodies, [
            #"<ContentItem source="AUX" sourceAccount="AUX"></ContentItem>"#,
            #"<ContentItem source="BLUETOOTH"></ContentItem>"#,
        ])
    }

    func testSelectMissingSourceThrows() async {
        transport.on("POST /select", Fixtures.unknownSourceError)
        do {
            try await client.select(SourceItem(source: "BLUETOOTH"))
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SoundTouchError, .api(code: 1005, name: "UNKNOWN_SOURCE_ERROR"))
        }
    }

    func testHTTPErrorWithoutBody() async {
        transport.on("GET /volume", status: 404, "<html><body>Object Not Found</body></html>")
        do {
            _ = try await client.volume()
            XCTFail("Expected an error")
        } catch {
            XCTAssertEqual(error as? SoundTouchError, .http(status: 404))
        }
    }
}
