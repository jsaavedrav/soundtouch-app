import Foundation

public enum SoundTouchError: Error, Equatable, Sendable {
    /// The speaker answered with something that is not the expected XML.
    case invalidResponse
    /// The speaker answered with a non-2xx HTTP status and no SoundTouch error body.
    case http(status: Int)
    /// The speaker rejected the request, e.g. `1005 UNKNOWN_SOURCE_ERROR`.
    case api(code: Int, name: String)
}

/// Response of `GET /info`.
public struct DeviceInfo: Sendable, Equatable {
    public var deviceID: String
    public var name: String
    public var type: String
    public var softwareVersion: String?
    public var moduleType: String?

    init(xml: XMLTree) throws {
        guard xml.name == "info", let deviceID = xml["deviceID"] else {
            throw SoundTouchError.invalidResponse
        }
        self.deviceID = deviceID
        self.name = xml.text(of: "name") ?? deviceID
        self.type = xml.text(of: "type") ?? "SoundTouch"
        self.softwareVersion = xml.child("components")?
            .children(named: "component")
            .lazy
            .compactMap { $0.text(of: "softwareVersion") }
            .first
        self.moduleType = xml.text(of: "moduleType")
    }
}

/// Response of `GET /volume`. Values go from 0 to 100.
public struct Volume: Sendable, Equatable {
    public var target: Int
    public var actual: Int
    public var isMuted: Bool

    init(xml: XMLTree) throws {
        guard xml.name == "volume",
              let actual = xml.text(of: "actualvolume").flatMap(Int.init)
        else { throw SoundTouchError.invalidResponse }
        self.actual = actual
        self.target = xml.text(of: "targetvolume").flatMap(Int.init) ?? actual
        self.isMuted = xml.text(of: "muteenabled") == "true"
    }
}

/// Response of `GET /now_playing`.
public struct NowPlaying: Sendable, Equatable {
    public var source: String
    public var sourceAccount: String?
    public var itemName: String?
    public var track: String?
    public var artist: String?
    public var album: String?
    public var stationName: String?

    /// The speaker reports `STANDBY` as its source while it is off.
    public var isStandby: Bool { source == "STANDBY" }

    init(xml: XMLTree) throws {
        guard xml.name == "nowPlaying", let source = xml["source"] else {
            throw SoundTouchError.invalidResponse
        }
        self.source = source
        self.sourceAccount = xml["sourceAccount"]
        self.itemName = xml.child("ContentItem")?.text(of: "itemName")
        self.track = xml.text(of: "track")
        self.artist = xml.text(of: "artist")
        self.album = xml.text(of: "album")
        self.stationName = xml.text(of: "stationName")
    }
}

/// One entry of `GET /sources`.
public struct SourceItem: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        case ready, unavailable
        case other(String)
    }

    public var source: String
    public var sourceAccount: String?
    public var status: Status
    public var isLocal: Bool
    /// Label the speaker gives the source. For streaming services it can be
    /// the account's e-mail, so do not log or display it without care.
    public var label: String?

    public var id: String { [source, sourceAccount ?? ""].joined(separator: "|") }

    /// Physical inputs a user can switch to. Bluetooth is included even when
    /// the speaker lists it as unavailable: selecting it starts pairing mode.
    public var isPhysicalInput: Bool {
        switch source {
        case "AUX": return status == .ready
        case "BLUETOOTH": return true
        default: return false
        }
    }

    public init(source: String, sourceAccount: String? = nil, status: Status = .ready, isLocal: Bool = true, label: String? = nil) {
        self.source = source
        self.sourceAccount = sourceAccount
        self.status = status
        self.isLocal = isLocal
        self.label = label
    }

    init(xml: XMLTree) throws {
        guard xml.name == "sourceItem", let source = xml["source"] else {
            throw SoundTouchError.invalidResponse
        }
        self.source = source
        self.sourceAccount = xml["sourceAccount"]
        switch xml["status"] {
        case "READY": self.status = .ready
        case "UNAVAILABLE", nil: self.status = .unavailable
        case let other?: self.status = .other(other)
        }
        self.isLocal = xml["isLocal"] == "true"
        self.label = xml.text.isEmpty ? nil : xml.text
    }
}

/// Buttons accepted by `POST /key`.
public enum Key: String, Sendable, CaseIterable {
    case power = "POWER"
    case volumeUp = "VOLUME_UP"
    case volumeDown = "VOLUME_DOWN"
    case mute = "MUTE"
    case play = "PLAY"
    case pause = "PAUSE"
    case playPause = "PLAY_PAUSE"
    case nextTrack = "NEXT_TRACK"
    case previousTrack = "PREV_TRACK"
    case auxInput = "AUX_INPUT"
    case preset1 = "PRESET_1"
    case preset2 = "PRESET_2"
    case preset3 = "PRESET_3"
    case preset4 = "PRESET_4"
    case preset5 = "PRESET_5"
    case preset6 = "PRESET_6"
}

extension SoundTouchError {
    /// Reads an `<errors><error value="1005" name="...">` body, if that is what it is.
    init?(xml: XMLTree) {
        guard xml.name == "errors", let error = xml.child("error") else { return nil }
        let code = error["value"].flatMap(Int.init) ?? Int(error.text) ?? 0
        self = .api(code: code, name: error["name"] ?? "UNKNOWN")
    }
}
