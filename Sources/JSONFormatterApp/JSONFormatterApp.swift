import SwiftUI

@main
struct JSONFormatterApp: App {
    var body: some Scene {
        WindowGroup("JSON Formatter") {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open…") {
                    NotificationCenter.default.post(name: .jfOpenFile, object: nil)
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                Button("Save") {
                    NotificationCenter.default.post(name: .jfSaveOutput, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)

                Button("Save As…") {
                    NotificationCenter.default.post(name: .jfSaveOutputAs, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }
        }
    }
}
