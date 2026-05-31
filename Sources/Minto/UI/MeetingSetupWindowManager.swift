import AppKit
import SwiftUI

/// "회의 시작" 시트 창을 관리한다. 녹음 시작 직전에 띄워 회의 맥락을 입력받는다.
/// 매번 새 입력을 위해, 닫히면(시작/취소/창 X 모두) window 참조를 비워 다음엔 빈 필드로 새로 띄운다.
@MainActor
public final class MeetingSetupWindowManager: NSObject, NSWindowDelegate {

    private var window: NSWindow?

    public override init() { super.init() }

    /// - Parameters:
    ///   - onStart: 사용자가 "시작"을 누르면 (topic, glossary)와 함께 호출
    ///   - onCancel: 사용자가 "취소"하거나 창을 닫으면 호출
    public func show(
        onStart: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        // 이미 떠 있으면 앞으로만 가져온다 (중복 생성 방지)
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = MeetingSetupView(
            onStart: { [weak self] topic, glossary in
                self?.close()
                onStart(topic, glossary)
            },
            onCancel: { [weak self] in
                self?.close()
                onCancel()
            }
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "회의 시작"
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self   // 창 X 닫기도 windowWillClose로 받아 상태를 초기화
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        // LSUIElement 앱이라 명시적으로 활성화해야 창이 앞으로 나오고 포커스를 받는다.
        NSApp.activate(ignoringOtherApps: true)
    }

    public func close() {
        window?.close()
        window = nil
    }

    // 모든 닫힘 경로(시작/취소/창 X)에서 참조를 비워 다음 표시 때 새 빈 폼이 뜨게 한다.
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
