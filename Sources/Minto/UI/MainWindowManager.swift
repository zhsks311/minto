import AppKit
import SwiftUI

/// 회의 목록·상세를 보여주는 메인 윈도우(리사이즈 가능). 메뉴바·런치 시 연다.
@MainActor
public final class MainWindowManager: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let viewModel: TranscriptionViewModel
    private let onNewMeeting: () -> Void
    private let onShowOverlay: () -> Void

    public init(
        viewModel: TranscriptionViewModel,
        onNewMeeting: @escaping () -> Void,
        onShowOverlay: @escaping () -> Void
    ) {
        self.viewModel = viewModel
        self.onNewMeeting = onNewMeeting
        self.onShowOverlay = onShowOverlay
        super.init()
    }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = MeetingLibraryView(
            store: .shared,
            viewModel: viewModel,
            onNewMeeting: onNewMeeting,
            onShowOverlay: onShowOverlay
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Minto — 회의"
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        // 저장된 프레임이 있으면 복원, 없을 때만 중앙 정렬(center가 복원 위치를 덮어쓰지 않게).
        window.setFrameAutosaveName("MintoMainWindow")
        if !window.setFrameUsingName("MintoMainWindow") {
            window.center()
        }

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
