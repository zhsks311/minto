import SwiftUI

public struct MenuBarView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    public var onStartRecording: (() -> Void)?
    public var onStopRecording: (() -> Void)?
    public var onOpacityChange: ((Double) -> Void)?

    @State private var opacity: Double = 1.0

    public init(
        viewModel: TranscriptionViewModel,
        onStartRecording: (() -> Void)? = nil,
        onStopRecording: (() -> Void)? = nil,
        onOpacityChange: ((Double) -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onStartRecording = onStartRecording
        self.onStopRecording = onStopRecording
        self.onOpacityChange = onOpacityChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            modelStatusRow
            Divider()
            recordingButton
            if viewModel.isRecording && !viewModel.allText.isEmpty {
                copyButton
            }
            Divider()
            opacitySlider
            Divider()
            SettingsLink {
                Text("설정…")
            }
            .keyboardShortcut(",", modifiers: .command)
            .simultaneousGesture(TapGesture().onEnded {
                NSApp.activate(ignoringOtherApps: true)
            })
            Button("종료") { NSApp.terminate(nil) }
        }
        .padding(8)
        .frame(minWidth: 240)
    }

    // MARK: - Model status

    private var modelStatusRow: some View {
        HStack(spacing: 6) {
            modelStateIcon
            modelStateText
        }
        .font(.caption)
    }

    @ViewBuilder
    private var modelStateIcon: some View {
        switch viewModel.modelState {
        case .loaded:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .downloading, .loading:
            ProgressView()
                .scaleEffect(0.6)
                .frame(width: 14, height: 14)
        case .failed:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundColor(.orange)
        case .unloaded:
            Image(systemName: "circle")
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var modelStateText: some View {
        switch viewModel.modelState {
        case .loaded:
            Text(viewModel.modelVariantName)
                .foregroundColor(.secondary)
        case .downloading(let p):
            Text("다운로드 \(Int(p * 100))%")
                .foregroundColor(.secondary)
        case .loading:
            Text("초기화 중...")
                .foregroundColor(.secondary)
        case .failed(let msg):
            Text("오류: \(msg)")
                .foregroundColor(.orange)
                .lineLimit(1)
                .truncationMode(.tail)
        case .unloaded:
            Text("모델 미로드")
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Recording

    private var recordingButton: some View {
        Group {
            if viewModel.isRecording {
                Button("녹음 종료") {
                    viewModel.stopRecording()
                    onStopRecording?()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            } else {
                Button("녹음 시작") {
                    viewModel.startRecording()
                    onStartRecording?()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!isModelReady)
            }
        }
    }

    private var isModelReady: Bool {
        if case .loaded = viewModel.modelState { return true }
        return false
    }

    private var copyButton: some View {
        Button("전사 내용 복사") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(viewModel.allText, forType: .string)
        }
    }

    // MARK: - Opacity slider

    private var opacitySlider: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("오버레이 투명도")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                Text("20%")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Slider(value: $opacity, in: 0.2...1.0, step: 0.05)
                    .onChange(of: opacity) { _, newValue in
                        onOpacityChange?(newValue)
                    }
                Text("\(Int(opacity * 100))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }
}
