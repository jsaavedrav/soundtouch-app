import SwiftUI
import SoundTouchKit

/// Groups speakers so they play the same thing. A speaker that follows
/// another one shows who it follows and can leave the group.
struct GroupRow: View {
    let speaker: SpeakerModel
    let allSpeakers: [SpeakerModel]

    var body: some View {
        if let zone = speaker.zone, !speaker.isZoneMaster {
            let master = allSpeakers.first { $0.deviceID == zone.masterID }
            HStack {
                Label("Sonando junto a \(master?.name ?? "otro parlante")", systemImage: "hifispeaker.2")
                Spacer()
                if let master {
                    Button("Separar") {
                        Task { await master.setMember(speaker, included: false) }
                    }
                    .buttonStyle(.borderless)
                }
            }
        } else if speaker.isOn, !candidates.isEmpty {
            Menu {
                ForEach(candidates) { other in
                    Toggle(other.name, isOn: Binding(
                        get: { speaker.leads(other) },
                        set: { included in Task { await speaker.setMember(other, included: included) } }
                    ))
                }
            } label: {
                Label(title, systemImage: "hifispeaker.2")
            }
        }
    }

    /// Other speakers that can join: loaded and not leading a group of their own.
    private var candidates: [SpeakerModel] {
        allSpeakers.filter { $0.id != speaker.id && $0.deviceID != nil && !$0.isZoneMaster }
    }

    private var title: String {
        let members = candidates.filter { speaker.leads($0) }.map(\.name)
        return members.isEmpty ? "Sonar también en…" : "Sonando también en \(members.formatted(.list(type: .and)))"
    }
}
