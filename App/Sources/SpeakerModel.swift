import Foundation
import Observation
import SoundTouchKit

/// State and commands for one speaker, kept in sync through its WebSocket.
@MainActor
@Observable
final class SpeakerModel: Identifiable {
    let host: String
    var name: String
    var isOn = false
    var volume = 0
    var source = ""
    /// Physical inputs this model has (AUX, and Bluetooth when present).
    var inputs: [SourceItem] = []
    var errorMessage: String?
    var isLoaded = false

    @ObservationIgnored private let client: SoundTouchClient

    nonisolated var id: String { host }

    init(host: String, name: String) {
        self.host = host
        self.name = name
        self.client = SoundTouchClient(host: host)
    }

    // MARK: State

    func refresh() async {
        let client = client
        do {
            async let playing = client.nowPlaying()
            async let currentVolume = client.volume()
            let (nowPlaying, volume) = try await (playing, currentVolume)
            isOn = !nowPlaying.isStandby
            source = nowPlaying.source
            self.volume = volume.actual

            if !isLoaded {
                inputs = try await client.sources().filter(\.isPhysicalInput)
                name = try await client.info().name
            }
            isLoaded = true
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Refreshes whenever the speaker reports a change, reconnecting if the
    /// connection drops. Runs until the calling task is cancelled.
    func listen() async {
        await refresh()
        while !Task.isCancelled {
            for await _ in client.changes() {
                await refresh()
            }
            try? await Task.sleep(for: .seconds(5))
            await refresh()
        }
    }

    // MARK: Commands

    func setPower(_ on: Bool) async {
        isOn = on
        await perform { client in
            if on { try await client.powerOn() } else { try await client.powerOff() }
        }
    }

    func setVolume(_ value: Int) async {
        volume = value
        await perform { try await $0.setVolume(value) }
    }

    func volumeUp() async { await perform { try await $0.volumeUp() } }
    func volumeDown() async { await perform { try await $0.volumeDown() } }

    func select(_ item: SourceItem) async {
        source = item.source
        await perform { try await $0.select(item) }
    }

    private func perform(_ action: @escaping @Sendable (SoundTouchClient) async throws -> Void) async {
        do {
            try await action(client)
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
        await refresh()
    }

    private static func message(for error: Error) -> String {
        guard case let .api(code, name)? = error as? SoundTouchError else {
            return "No pude conectarme con el parlante."
        }
        if code == 1005 { return "Este parlante no tiene esa fuente." }
        return "El parlante rechazó el comando (\(code) \(name))."
    }
}

/// Speakers found with Bonjour plus the ones added by IP address.
@MainActor
@Observable
final class SpeakerListModel {
    private(set) var speakers: [SpeakerModel] = []
    private(set) var isSearching = false

    private static let manualHostsKey = "manualHosts"

    private var manualHosts: [String] {
        get { UserDefaults.standard.stringArray(forKey: Self.manualHostsKey) ?? [] }
        set { UserDefaults.standard.set(newValue, forKey: Self.manualHostsKey) }
    }

    func discover() async {
        guard !isSearching else { return }
        isSearching = true
        defer { isSearching = false }

        for speaker in await SoundTouchDiscovery.discover() {
            add(host: speaker.host, name: speaker.name)
        }
        for host in manualHosts {
            add(host: host, name: host)
        }
    }

    func addManually(host: String) {
        let host = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else { return }
        if !manualHosts.contains(host) { manualHosts.append(host) }
        add(host: host, name: host)
    }

    private func add(host: String, name: String) {
        guard !speakers.contains(where: { $0.host == host }) else { return }
        speakers.append(SpeakerModel(host: host, name: name))
        speakers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
