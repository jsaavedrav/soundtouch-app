import SwiftUI
import SoundTouchKit

/// What the speaker is playing, with play/pause (and skip for Spotify).
/// Hidden while the speaker plays a physical input or is off.
struct NowPlayingRow: View {
    let speaker: SpeakerModel

    var body: some View {
        if speaker.isOn, let playing = speaker.nowPlaying,
           !speaker.inputs.contains(where: { $0.source == playing.source }) {
            HStack(spacing: 12) {
                AsyncImage(url: playing.artURL ?? speaker.station?.faviconURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Image(systemName: playing.source == "UPNP" ? "radio" : "music.note")
                        .foregroundStyle(.secondary)
                }
                .frame(width: 44, height: 44)
                .background(.quaternary)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title(of: playing)).lineLimit(1)
                    Text(subtitle(of: playing))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                let isSpotify = playing.source == "SPOTIFY"
                if isSpotify {
                    Button {
                        Task { await speaker.previousTrack() }
                    } label: {
                        Image(systemName: "backward.fill")
                    }
                    .accessibilityLabel("Anterior")
                }
                Button {
                    Task { await speaker.playPause() }
                } label: {
                    Image(systemName: playPauseIcon(for: playing)).font(.title3)
                }
                .accessibilityLabel(playing.isPlaying ? "Pausar" : "Reproducir")
                if isSpotify {
                    Button {
                        Task { await speaker.nextTrack() }
                    } label: {
                        Image(systemName: "forward.fill")
                    }
                    .accessibilityLabel("Siguiente")
                }
            }
            .buttonStyle(.borderless)
        }
    }

    private func title(of playing: NowPlaying) -> String {
        speaker.station?.name
            ?? playing.track
            ?? playing.stationName
            ?? playing.itemName
            ?? displayName(of: playing.source)
    }

    private func subtitle(of playing: NowPlaying) -> String {
        let source = displayName(of: playing.source)
        if speaker.station == nil, let artist = playing.artist {
            return "\(artist) · \(source)"
        }
        return source
    }

    private func playPauseIcon(for playing: NowPlaying) -> String {
        if playing.source == "UPNP" { return "stop.fill" }
        return playing.isPlaying ? "pause.fill" : "play.fill"
    }
}

/// The favorite radios as numbered buttons, like the presets on the speaker.
struct FavoriteStationsGrid: View {
    let speaker: SpeakerModel
    var onAdd: () -> Void

    @Environment(FavoriteStations.self) private var favorites

    var body: some View {
        if favorites.stations.isEmpty {
            Button(action: onAdd) {
                Label("Agregar radios favoritas", systemImage: "radio")
            }
        } else {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(Array(favorites.stations.enumerated()), id: \.element.id) { index, station in
                    Button {
                        Task { await speaker.play(station) }
                    } label: {
                        VStack(spacing: 2) {
                            Text("\(index + 1)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(station.name)
                                .font(.footnote)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .padding(6)
                        .background(
                            speaker.station?.id == station.id ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 8)
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("Quitar de favoritas", role: .destructive) { favorites.toggle(station) }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
}

/// Searches radio-browser.info and manages the favorite radios.
struct RadioSearchView: View {
    /// Names of the speaker's old presets, offered as searches.
    var oldPresetNames: () async -> [String]

    @Environment(FavoriteStations.self) private var favorites
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [RadioStation] = []
    @State private var suggestions: [String] = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    private let browser = RadioBrowser()

    var body: some View {
        NavigationStack {
            List {
                if !favorites.stations.isEmpty {
                    Section("Favoritas (\(favorites.stations.count) de \(FavoriteStations.limit))") {
                        ForEach(favorites.stations) { StationRow(station: $0) }
                    }
                }
                if query.isEmpty, !suggestions.isEmpty {
                    Section {
                        ForEach(suggestions, id: \.self) { name in
                            Button {
                                query = name
                            } label: {
                                Label(name, systemImage: "magnifyingglass")
                            }
                        }
                    } header: {
                        Text("Tus presets antiguos")
                    } footer: {
                        Text("Dejaron de funcionar con la nube de Bose. Tócalos para buscar esas radios.")
                    }
                }
                if !results.isEmpty {
                    Section("Resultados") {
                        ForEach(results) { StationRow(station: $0) }
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red)
                }
            }
            .overlay {
                if isSearching { ProgressView() }
            }
            .searchable(text: $query, prompt: "Buscar radio")
            .task(id: query) { await search() }
            .task { suggestions = await oldPresetNames() }
            .navigationTitle("Radios")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard text.count >= 2 else {
            results = []
            return
        }
        // Wait for the user to stop typing; a new query cancels this task.
        try? await Task.sleep(for: .milliseconds(400))
        guard !Task.isCancelled else { return }

        isSearching = true
        defer { isSearching = false }
        do {
            let found = try await browser.search(name: text)
            guard !Task.isCancelled else { return }
            results = found
            errorMessage = nil
        } catch {
            if !Task.isCancelled {
                errorMessage = "No pude buscar radios. Revisa tu conexión a internet."
            }
        }
    }
}

struct StationRow: View {
    let station: RadioStation

    @Environment(FavoriteStations.self) private var favorites

    var body: some View {
        HStack {
            AsyncImage(url: station.faviconURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                Image(systemName: "radio").foregroundStyle(.secondary)
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading) {
                Text(station.name).lineLimit(1)
                Text(details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            let isFavorite = favorites.contains(station)
            Button {
                favorites.toggle(station)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
            }
            .buttonStyle(.borderless)
            .disabled(!isFavorite && favorites.isFull)
            .accessibilityLabel(isFavorite ? "Quitar de favoritas" : "Agregar a favoritas")
        }
    }

    private var details: String {
        [station.countryCode, station.codec, station.bitrate.map { "\($0) kbps" }]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
