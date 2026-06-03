import AppKit
import SwiftUI

/// 회의 종료 후 요약 창을 관리한다. `MeetingSetupWindowManager` 패턴을 따른다.
/// 종료 직후 `showLoading()`으로 즉시 띄우고, 최종 요약이 준비되면 `showResult(summary:)`로
/// 내용을 갱신한다(같은 창, 상태만 전환). 닫히면(닫기/창 X) window 참조를 비워 다음 회의에 새 창을 띄운다.
@MainActor
public final class MeetingSummaryWindowManager: NSObject, NSWindowDelegate {

    private var window: NSWindow?
    private let model = MeetingSummaryModel()

    public override init() { super.init() }

    /// 로딩 상태로 창을 띄운다(종료 직후 즉시 호출).
    public func showLoading() {
        model.state = .loading

        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let view = MeetingSummaryView(model: model, onClose: { [weak self] in self?.close() })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 512, height: 640),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "회의 결과"
        window.contentViewController = NSHostingController(rootView: view)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()

        self.window = window
        window.makeKeyAndOrderFront(nil)
        // LSUIElement 앱이라 명시적으로 활성화해야 창이 앞으로 나온다.
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 구조화 결과를 표시한다. 로딩 중 사용자가 창을 닫았으면 다시 띄운다(결과 유실 방지).
    public func showResult(_ result: MeetingResult) {
        if window == nil { showLoading() }
        model.state = .result(result)
        window?.makeKeyAndOrderFront(nil)
    }

    /// 요약 생성 실패 상태로 전환한다. 창이 닫혔으면 다시 띄운다.
    public func showFailed() {
        if window == nil { showLoading() }
        model.state = .failed
        window?.makeKeyAndOrderFront(nil)
    }

    public func close() {
        window?.close()
        window = nil
    }

    // 닫기/창 X 모두에서 참조를 비워 다음 표시 때 새 창이 뜨게 한다.
    public func windowWillClose(_ notification: Notification) {
        window = nil
    }
}
