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
    var nowPlaying: NowPlaying?
    /// The radio this app sent to the speaker, while it is still playing it.
    var station: RadioStation?
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
            self.nowPlaying = nowPlaying
            if nowPlaying.source != "UPNP" { station = nil }
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

    /// Plays a radio through the speaker's UPnP renderer, turning it on first.
    func play(_ station: RadioStation) async {
        self.station = station
        await perform { client in
            try await client.powerOn()
            try await client.renderer.play(station.streamURL, title: station.name, mimeType: station.mimeType)
        }
    }

    /// Radio streams cannot pause, so radio stops; anything else toggles.
    func playPause() async {
        if source == "UPNP" {
            await perform { try await $0.renderer.stop() }
        } else {
            await perform { try await $0.press(.playPause) }
        }
    }

    func nextTrack() async { await perform { try await $0.press(.nextTrack) } }
    func previousTrack() async { await perform { try await $0.press(.previousTrack) } }

    /// Names of the radio presets stored in the speaker, to help find those
    /// radios again. They stopped working with Bose's cloud.
    func oldRadioPresetNames() async -> [String] {
        let presets = (try? await client.presets()) ?? []
        var names: [String] = []
        for preset in presets where preset.source == "TUNEIN" || preset.source.contains("RADIO") {
            if let name = preset.name, !names.contains(name) { names.append(name) }
        }
        return names
    }

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
        if case let .upnp(code, description)? = error as? SoundTouchError {
            return "El parlante no pudo reproducir esa radio (\(code) \(description))."
        }
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

/// Up to six favorite radios, shared by every speaker. They replace the
/// presets that depended on Bose's cloud.
@MainActor
@Observable
final class FavoriteStations {
    static let limit = 6
    private static let key = "favoriteStations"

    private(set) var stations: [RadioStation]

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        stations = data.flatMap { try? JSONDecoder().decode([RadioStation].self, from: $0) } ?? []
    }

    var isFull: Bool { stations.count >= Self.limit }

    func contains(_ station: RadioStation) -> Bool {
        stations.contains { $0.id == station.id }
    }

    func toggle(_ station: RadioStation) {
        if contains(station) {
            stations.removeAll { $0.id == station.id }
        } else if !isFull {
            stations.append(station)
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(try? JSONEncoder().encode(stations), forKey: Self.key)
    }
}
