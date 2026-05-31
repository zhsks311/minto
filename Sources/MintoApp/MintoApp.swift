import SwiftUI
import MintoCore

@main
struct MintoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra("Minto", systemImage: "waveform.circle.fill") {
            MenuBarView(
                viewModel: appDelegate.viewModel,
                onRequestStart: { appDelegate.requestStartSession() },
                onStopRecording: { appDelegate.floatingWindowManager.hide() },
                onOpacityChange: appDelegate.floatingWindowManager.setOpacity
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
        }
    }
}
