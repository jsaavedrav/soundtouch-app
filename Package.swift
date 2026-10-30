// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SoundTouchKit",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SoundTouchKit", targets: ["SoundTouchKit"]),
        .executable(name: "soundtouch", targets: ["soundtouch"]),
    ],
    targets: [
        .target(name: "SoundTouchKit"),
        .executableTarget(name: "soundtouch", dependencies: ["SoundTouchKit"]),
        .testTarget(name: "SoundTouchKitTests", dependencies: ["SoundTouchKit"]),
    ]
)
