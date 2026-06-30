import SwiftUI
import MintoCore

@main
struct MintoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                viewModel: appDelegate.viewModel,
                onRequestStart: { appDelegate.requestStartSession() },
                onStopRecording: { appDelegate.handleStopRecording() },
                onOpacityChange: appDelegate.floatingWindowManager.setOpacity,
                onOpenLibrary: { appDelegate.mainWindowManager.show() }
            )
            .tint(MintoDesignTokens.brandTeal)
        } label: {
            if let icon = AppAssets.menuBarIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "waveform.circle.fill")
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: appDelegate.viewModel)
                .tint(MintoDesignTokens.brandTeal)
        }
    }
}
