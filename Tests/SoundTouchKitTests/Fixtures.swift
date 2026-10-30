import Foundation

// Responses captured from a SoundTouch 10 and an original SoundTouch 20
// (firmware 27.0.6), trimmed and with identifiers and accounts replaced.
enum Fixtures {
    static let info = """
    <?xml version="1.0" encoding="UTF-8" ?><info deviceID="AABBCCDDEEFF"><name>Living SoundTouch 20</name><type>SoundTouch 20</type><components><component><componentCategory>SCM</componentCategory><softwareVersion>27.0.6.46330.5043500 epdbuild.trunk.hepdswbld04.2022-08-04T11:20:29</softwareVersion><serialNumber>X</serialNumber></component></components><networkInfo type="SCM"><macAddress>AABBCCDDEEFF</macAddress><ipAddress>192.168.1.169</ipAddress></networkInfo><moduleType>scm</moduleType><variant>spotty</variant></info>
    """

    static let volume = """
    <?xml version="1.0" encoding="UTF-8" ?><volume deviceID="AABBCCDDEEFF"><targetvolume>12</targetvolume><actualvolume>10</actualvolume></volume>
    """

    static let nowPlayingSpotify = """
    <?xml version="1.0" encoding="UTF-8" ?><nowPlaying deviceID="AABBCCDDEEFF" source="SPOTIFY" sourceAccount="account1"><ContentItem source="SPOTIFY" type="tracklisturl" location="/playback/container/x" sourceAccount="account1" isPresetable="true"><itemName>Go</itemName></ContentItem><track>Jesus of Suburbia</track><artist>Green Day</artist><album>American Idiot</album><stationName></stationName><playStatus>PLAY_STATE</playStatus></nowPlaying>
    """

    static let nowPlayingStandby = """
    <?xml version="1.0" encoding="UTF-8" ?><nowPlaying deviceID="AABBCCDDEEFF" source="STANDBY"><ContentItem source="STANDBY" isPresetable="false" /></nowPlaying>
    """

    /// An original SoundTouch 20: AUX but no Bluetooth.
    static let sourcesST20 = """
    <?xml version="1.0" encoding="UTF-8" ?><sources deviceID="AABBCCDDEEFF"><sourceItem source="AUX" sourceAccount="AUX" status="READY" isLocal="true" multiroomallowed="true">AUX IN</sourceItem><sourceItem source="AIRPLAY" status="READY" isLocal="false" multiroomallowed="false" /><sourceItem source="SPOTIFY" sourceAccount="account1" status="READY" isLocal="false" multiroomallowed="true">someone@example.com</sourceItem><sourceItem source="QPLAY" sourceAccount="QPlay1UserName" status="UNAVAILABLE" isLocal="true" multiroomallowed="true">QPlay1UserName</sourceItem></sources>
    """

    /// A SoundTouch 10: Bluetooth is listed as unavailable but can be selected.
    static let sourcesST10 = """
    <?xml version="1.0" encoding="UTF-8" ?><sources deviceID="112233445566"><sourceItem source="AUX" sourceAccount="AUX" status="READY" isLocal="true" multiroomallowed="true">AUX IN</sourceItem><sourceItem source="BLUETOOTH" status="UNAVAILABLE" isLocal="true" multiroomallowed="true" /><sourceItem source="ALEXA" status="READY" isLocal="false" multiroomallowed="true" /></sources>
    """

    static let unknownSourceError = """
    <?xml version="1.0" encoding="UTF-8" ?><errors deviceID="AABBCCDDEEFF"><error value="1005" name="UNKNOWN_SOURCE_ERROR" severity="Unknown">1005</error></errors>
    """

    static func status(_ path: String) -> String {
        #"<?xml version="1.0" encoding="UTF-8" ?><status>\#(path)</status>"#
    }
}
