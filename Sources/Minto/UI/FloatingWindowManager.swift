import AppKit
import SwiftUI

@MainActor
public final class FloatingWindowManager {

    private var overlayWindow: NSPanel?
    private let viewModel: TranscriptionViewModel

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public func show() {
        if overlayWindow == nil {
            let panel = NSPanel(
                contentRect: initialFrame(),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .floating
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isMovableByWindowBackground = true

            let hostingController = NSHostingController(
                rootView: TranscriptionOverlayView(viewModel: viewModel)
            )
            panel.contentViewController = hostingController

            overlayWindow = panel
        }

        overlayWindow?.orderFront(nil)
    }

    public func hide() {
        overlayWindow?.orderOut(nil)
    }

    public func setOpacity(_ value: Double) {
        overlayWindow?.alphaValue = value
    }

    // MARK: - Private

    private func initialFrame() -> NSRect {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let windowWidth: CGFloat = 444  // view 420 + padding 12*2
        let windowHeight: CGFloat = 544 // view 520 + padding 12*2
        let margin: CGFloat = 20
        return NSRect(
            x: screenFrame.maxX - windowWidth - margin,
            y: screenFrame.minY + margin,
            width: windowWidth,
            height: windowHeight
        )
    }
}
