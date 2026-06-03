import AppKit
import SwiftUI

/// 회의 목록·상세를 보여주는 메인 윈도우(리사이즈 가능). 메뉴바·런치 시 연다.
@MainActor
public final class MainWindowManager: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let onNewMeeting: () -> Void

    public init(onNewMeeting: @escaping () -> Void) {
        self.onNewMeeting = onNewMeeting
        super.init()
    }

    public func show() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = MeetingLibraryView(store: .shared, onNewMeeting: onNewMeeting)
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
        window.setFrameAutosaveName("MintoMainWindow")
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
