import SwiftUI

@main
struct SoundTouchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        #if os(macOS)
        .defaultSize(width: 420, height: 560)
        #endif
    }
}
