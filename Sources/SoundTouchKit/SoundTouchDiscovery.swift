#if canImport(Network)
import Foundation
import Network

/// A speaker found on the local network.
public struct DiscoveredSpeaker: Sendable, Hashable, Identifiable {
    /// The name set in the speaker, or its Bonjour name if `/info` failed.
    public var name: String
    public var host: String
    public var deviceID: String?
    public var type: String?

    public var id: String { deviceID ?? host }

    public func client(timeout: TimeInterval = 5) -> SoundTouchClient {
        SoundTouchClient(host: host, timeout: timeout)
    }
}

/// Finds SoundTouch speakers through Bonjour (`_soundtouch._tcp`).
///
/// On iOS the app needs `NSLocalNetworkUsageDescription` and
/// `NSBonjourServices = [_soundtouch._tcp]` in its Info.plist.
public enum SoundTouchDiscovery {
    public static let serviceType = "_soundtouch._tcp"

    public static func discover(browseFor seconds: TimeInterval = 3) async -> [DiscoveredSpeaker] {
        let services = await browse(for: seconds)
        return await withTaskGroup(of: DiscoveredSpeaker?.self) { group in
            for (name, endpoint) in services {
                group.addTask {
                    guard let host = await resolveIPv4(endpoint) else { return nil }
                    let info = try? await SoundTouchClient(host: host, timeout: 3).info()
                    return DiscoveredSpeaker(name: info?.name ?? name, host: host, deviceID: info?.deviceID, type: info?.type)
                }
            }
            var speakers: [DiscoveredSpeaker] = []
            for await speaker in group {
                if let speaker { speakers.append(speaker) }
            }
            return speakers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }

    private static func browse(for seconds: TimeInterval) async -> [(String, NWEndpoint)] {
        await withCheckedContinuation { continuation in
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
            let queue = DispatchQueue(label: "SoundTouchDiscovery.browse")
            let once = Once()

            browser.stateUpdateHandler = { state in
                if case .failed = state {
                    once.run {
                        browser.cancel()
                        continuation.resume(returning: [])
                    }
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + seconds) {
                once.run {
                    let found = browser.browseResults.compactMap { result -> (String, NWEndpoint)? in
                        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
                        return (name, result.endpoint)
                    }
                    browser.cancel()
                    continuation.resume(returning: found)
                }
            }
        }
    }

    /// Bonjour gives a service name, not an address. Opening a TCP connection
    /// to the service is the supported way to learn the address behind it.
    private static func resolveIPv4(_ endpoint: NWEndpoint, timeout: TimeInterval = 3) async -> String? {
        await withCheckedContinuation { continuation in
            let parameters = NWParameters.tcp
            if let ip = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ip.version = .v4
            }
            let connection = NWConnection(to: endpoint, using: parameters)
            let queue = DispatchQueue(label: "SoundTouchDiscovery.resolve")
            let once = Once()
            let finish: @Sendable (String?) -> Void = { host in
                once.run {
                    connection.cancel()
                    continuation.resume(returning: host)
                }
            }

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if case let .hostPort(host, _)? = connection.currentPath?.remoteEndpoint,
                       case let .ipv4(address) = host {
                        finish(address.rawValue.map(String.init).joined(separator: "."))
                    } else {
                        finish(nil)
                    }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }
}

/// Runs a block at most once, from any thread.
private final class Once: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false

    func run(_ block: () -> Void) {
        lock.lock()
        let first = !done
        done = true
        lock.unlock()
        if first { block() }
    }
}
#endif
