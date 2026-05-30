import AppKit
import SwiftUI

public final class AppDelegate: NSObject, NSApplicationDelegate, ObservableObject, @unchecked Sendable {
    public let viewModel: TranscriptionViewModel
    public let floatingWindowManager: FloatingWindowManager

    override init() {
        let (vm, manager) = MainActor.assumeIsolated {
            let vm = TranscriptionViewModel()
            return (vm, FloatingWindowManager(viewModel: vm))
        }
        viewModel = vm
        floatingWindowManager = manager
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        // UserDefaults에서 저장된 모델 선택 읽기 (구버전 small → turbo 마이그레이션)
        let defaultModel = "openai_whisper-large-v3-v20240930_turbo"
        var savedVariant = UserDefaults.standard.string(forKey: "selectedModel") ?? defaultModel
        if savedVariant == "openai_whisper-small" {
            savedVariant = defaultModel
            UserDefaults.standard.set(defaultModel, forKey: "selectedModel")
        }
        Task {
            await viewModel.loadModel(variant: savedVariant)
        }
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
