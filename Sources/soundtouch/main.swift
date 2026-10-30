import Foundation
import SoundTouchKit

// Small command-line tool to try SoundTouchKit against real speakers.

let usage = """
Uso:
  soundtouch discover
  soundtouch <ip> status
  soundtouch <ip> on | off
  soundtouch <ip> volume [0-100 | up | down]
  soundtouch <ip> sources
  soundtouch <ip> source <AUX | BLUETOOTH | ...>
  soundtouch <ip> play <url-del-stream> [nombre]
  soundtouch <ip> stop
  soundtouch radio <nombre>
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func printStatus(_ client: SoundTouchClient) async throws {
    let info = try await client.info()
    let playing = try await client.nowPlaying()
    let volume = try await client.volume()
    print("\(info.name) (\(info.type)) en \(client.host)")
    print("  Encendido: \(playing.isStandby ? "no" : "sí")")
    print("  Fuente:    \(playing.source)")
    print("  Volumen:   \(volume.actual)\(volume.isMuted ? " (silenciado)" : "")")
    if let track = playing.track {
        print("  Sonando:   \(track)\(playing.artist.map { " – \($0)" } ?? "")")
    }
}

let args = Array(CommandLine.arguments.dropFirst())

do {
    switch (args.first, args.dropFirst().first) {
    case ("discover"?, _):
        let speakers = await SoundTouchDiscovery.discover()
        if speakers.isEmpty { fail("No encontré parlantes en la red.") }
        for speaker in speakers {
            print("\(speaker.host)\t\(speaker.name)\t\(speaker.type ?? "")")
        }

    case ("radio"?, let name?):
        for station in try await RadioBrowser().search(name: name, limit: 10) {
            print("\(station.streamURL)\t\(station.name)\t\(station.countryCode ?? "")")
        }

    case let (host?, command?):
        let client = SoundTouchClient(host: host)
        let value = args.dropFirst(2).first

        switch command {
        case "status":
            try await printStatus(client)
        case "on":
            try await client.powerOn()
        case "off":
            try await client.powerOff()
        case "volume":
            switch value {
            case nil: break
            case "up": try await client.volumeUp()
            case "down": try await client.volumeDown()
            case let number?:
                guard let level = Int(number) else { fail(usage) }
                try await client.setVolume(level)
            }
            let volume = try await client.volume()
            print("Volumen: \(volume.actual)")
        case "sources":
            for item in try await client.sources() where item.isPhysicalInput {
                print(item.source)
            }
        case "source":
            guard let name = value?.uppercased() else { fail(usage) }
            let sources = try await client.sources()
            guard let item = sources.first(where: { $0.source == name }) else {
                fail("Este parlante no tiene la fuente \(name).")
            }
            try await client.select(item)
        case "play":
            guard let value, let url = URL(string: value) else { fail(usage) }
            try await client.powerOn()
            try await client.renderer.play(url, title: args.dropFirst(3).first ?? "Radio")
        case "stop":
            try await client.renderer.stop()
        default:
            fail(usage)
        }

    default:
        fail(usage)
    }
} catch SoundTouchError.api(let code, let name) {
    fail("El parlante rechazó el comando: \(code) \(name)")
} catch {
    fail("Error: \(error.localizedDescription)")
}
