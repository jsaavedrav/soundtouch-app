import Foundation

/// A multiroom group: one master plays and the members follow it.
public struct Zone: Sendable, Equatable {
    public struct Member: Sendable, Hashable {
        public var deviceID: String
        public var ipAddress: String

        public init(deviceID: String, ipAddress: String) {
            self.deviceID = deviceID
            self.ipAddress = ipAddress
        }
    }

    public var masterID: String
    public var members: [Member]

    /// `GET /getZone` answers `<zone />` when the speaker is not grouped.
    init?(xml: XMLTree) {
        guard xml.name == "zone", let master = xml["master"], !master.isEmpty else { return nil }
        masterID = master
        members = xml.children(named: "member").compactMap { member in
            guard let ip = member["ipaddress"], !member.text.isEmpty else { return nil }
            return Member(deviceID: member.text, ipAddress: ip)
        }
    }
}

extension SoundTouchClient {
    /// The group this speaker belongs to, or nil when it plays alone.
    public func zone() async throws -> Zone? {
        Zone(xml: try await get("/getZone"))
    }

    /// Makes this speaker the master of a new group with `members`.
    /// `deviceID` is this speaker's own ID, from `info()`.
    public func createZone(deviceID: String, members: [Zone.Member]) async throws {
        try await post("/setZone", body: Self.zoneBody(masterID: deviceID, senderIP: host, members: members))
    }

    /// Adds members to the group this speaker leads.
    public func addZoneMembers(_ members: [Zone.Member], masterID: String) async throws {
        try await post("/addZoneSlave", body: Self.zoneBody(masterID: masterID, senderIP: nil, members: members))
    }

    /// Removes members from the group this speaker leads. Removing the last
    /// one dissolves the group.
    public func removeZoneMembers(_ members: [Zone.Member], masterID: String) async throws {
        try await post("/removeZoneSlave", body: Self.zoneBody(masterID: masterID, senderIP: nil, members: members))
    }

    static func zoneBody(masterID: String, senderIP: String?, members: [Zone.Member]) -> String {
        var attributes = #"master="\#(xmlEscaped(masterID))""#
        if let senderIP { attributes += #" senderIPAddress="\#(xmlEscaped(senderIP))""# }
        let memberElements = members.map {
            #"<member ipaddress="\#(xmlEscaped($0.ipAddress))">\#(xmlEscaped($0.deviceID))</member>"#
        }
        return "<zone \(attributes)>\(memberElements.joined())</zone>"
    }
}
