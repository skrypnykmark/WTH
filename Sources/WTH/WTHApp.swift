import AppKit
import SwiftUI

@main
struct WTHApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(model)
        } label: {
            Image(systemName: "photo.on.rectangle.angled")
                .accessibilityLabel("WTH")
        }
        .menuBarExtraStyle(.window)
    }
}
