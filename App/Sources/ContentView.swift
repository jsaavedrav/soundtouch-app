import SwiftUI
import SoundTouchKit

struct ContentView: View {
    @State private var model = SpeakerListModel()
    @State private var favorites = FavoriteStations()
    @State private var isAddingSpeaker = false
    @State private var isShowingRadios = false

    var body: some View {
        NavigationStack {
            Group {
                if !model.speakers.isEmpty {
                    List {
                        ForEach(model.speakers) { speaker in
                            SpeakerSection(speaker: speaker, allSpeakers: model.speakers) { isShowingRadios = true }
                        }
                    }
                    .refreshable { await model.discover() }
                } else if model.isSearching {
                    ProgressView("Buscando parlantes…")
                } else {
                    ContentUnavailableView {
                        Label("No encontré parlantes", systemImage: "hifispeaker.2")
                    } description: {
                        Text("Revisa que estén enchufados y conectados a la misma red Wi-Fi.")
                    } actions: {
                        Button("Buscar de nuevo") { Task { await model.discover() } }
                        Button("Agregar por IP") { isAddingSpeaker = true }
                    }
                }
            }
            .navigationTitle("SoundTouch")
            .toolbar {
                ToolbarItem {
                    Button {
                        isShowingRadios = true
                    } label: {
                        Label("Radios", systemImage: "radio")
                    }
                }
                ToolbarItem {
                    Button {
                        Task { await model.discover() }
                    } label: {
                        Label("Buscar parlantes", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.isSearching)
                }
                ToolbarItem {
                    Button {
                        isAddingSpeaker = true
                    } label: {
                        Label("Agregar por IP", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingSpeaker) {
                AddSpeakerView { model.addManually(host: $0) }
            }
            .sheet(isPresented: $isShowingRadios) {
                RadioSearchView {
                    await model.speakers.first?.oldRadioPresetNames() ?? []
                }
                .environment(favorites)
            }
            .task { await model.discover() }
        }
        .environment(favorites)
    }
}

/// Power, volume and input controls for one speaker.
struct SpeakerSection: View {
    let speaker: SpeakerModel
    let allSpeakers: [SpeakerModel]
    var onAddRadios: () -> Void

    /// The slider keeps its own value so updates from the speaker do not
    /// move it while the user is dragging.
    @State private var sliderVolume: Double = 0
    @State private var isDraggingVolume = false

    var body: some View {
        Section {
            if speaker.isLoaded {
                controls
            } else if speaker.errorMessage == nil {
                ProgressView()
            }
            if let error = speaker.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        } header: {
            Text(speaker.name)
        } footer: {
            Text(speaker.host)
        }
        .onChange(of: speaker.volume, initial: true) { _, volume in
            if !isDraggingVolume { sliderVolume = Double(volume) }
        }
        .task(id: speaker.host) { await speaker.listen() }
    }

    @ViewBuilder private var controls: some View {
        Toggle(isOn: Binding(
            get: { speaker.isOn },
            set: { on in Task { await speaker.setPower(on) } }
        )) {
            Label("Encendido", systemImage: "power")
        }
        .toggleStyle(.switch)

        HStack {
            Button {
                Task { await speaker.volumeDown() }
            } label: {
                Image(systemName: "speaker.fill")
            }
            .accessibilityLabel("Bajar volumen")

            Slider(value: $sliderVolume, in: 0...100, step: 1, onEditingChanged: { dragging in
                isDraggingVolume = dragging
                if !dragging { Task { await speaker.setVolume(Int(sliderVolume)) } }
            })
            .accessibilityLabel("Volumen")

            Button {
                Task { await speaker.volumeUp() }
            } label: {
                Image(systemName: "speaker.wave.3.fill")
            }
            .accessibilityLabel("Subir volumen")

            Text("\(Int(sliderVolume))")
                .monospacedDigit()
                .frame(minWidth: 28, alignment: .trailing)
        }
        .buttonStyle(.borderless)
        .disabled(!speaker.isOn)

        if !speaker.inputs.isEmpty {
            Picker("Fuente", selection: Binding<String?>(
                get: { speaker.source },
                set: { source in
                    guard let item = speaker.inputs.first(where: { $0.source == source }) else { return }
                    Task { await speaker.select(item) }
                }
            )) {
                ForEach(speaker.inputs) { item in
                    Text(displayName(of: item.source)).tag(Optional(item.source))
                }
            }
            .pickerStyle(.segmented)
        }

        NowPlayingRow(speaker: speaker)

        GroupRow(speaker: speaker, allSpeakers: allSpeakers)

        FavoriteStationsGrid(speaker: speaker, onAdd: onAddRadios)
    }
}

func displayName(of source: String) -> String {
    switch source {
    case "AUX": return "AUX"
    case "BLUETOOTH": return "Bluetooth"
    case "SPOTIFY": return "Spotify"
    case "AIRPLAY": return "AirPlay"
    case "UPNP": return "Radio"
    case "TUNEIN": return "TuneIn"
    case "INTERNET_RADIO": return "Radio"
    case "ALEXA": return "Alexa"
    default: return source.capitalized
    }
}

struct AddSpeakerView: View {
    var onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var host = ""

    var body: some View {
        NavigationStack {
            Form {
                TextField("Dirección IP, por ejemplo 192.168.1.20", text: $host)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit(add)
            }
            .navigationTitle("Agregar parlante")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Agregar", action: add)
                        .disabled(host.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 140)
        #endif
    }

    private func add() {
        onAdd(host)
        dismiss()
    }
}
