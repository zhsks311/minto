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
                rootView: TranscriptionOverlayView(viewModel: viewModel) { [weak panel] collapsed in
                    Self.resize(
                        panel,
                        to: collapsed
                            ? TranscriptionOverlayView.collapsedWindowSize
                            : TranscriptionOverlayView.expandedWindowSize
                    )
                }
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
        let windowSize = TranscriptionOverlayView.expandedWindowSize
        let margin: CGFloat = 20
        return NSRect(
            x: screenFrame.maxX - windowSize.width - margin,
            y: screenFrame.minY + margin,
            width: windowSize.width,
            height: windowSize.height
        )
    }

    private static func resize(_ panel: NSPanel?, to size: NSSize) {
        guard let panel else { return }

        let currentFrame = panel.frame
        let nextFrame = NSRect(
            x: currentFrame.maxX - size.width,
            y: currentFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
        panel.setFrame(nextFrame, display: true, animate: true)
    }
}
