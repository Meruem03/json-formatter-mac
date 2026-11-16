import SwiftUI

@main
struct JSONFormatterApp: App {
    var body: some Scene {
        WindowGroup("JSON Formatter") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 720)
    }
}
