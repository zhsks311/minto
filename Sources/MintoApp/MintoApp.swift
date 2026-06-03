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
                onStopRecording: { appDelegate.handleStopRecording() },
                onOpacityChange: appDelegate.floatingWindowManager.setOpacity,
                onOpenLibrary: { appDelegate.mainWindowManager.show() }
            )
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
        }
    }
}
