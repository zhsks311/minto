import SwiftUI

public struct MenuBarView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    public var onRequestStart: (() -> Void)?
    public var onStopRecording: (() -> Void)?
    public var onOpacityChange: ((Double) -> Void)?
    public var onOpenLibrary: (() -> Void)?

    @State private var opacity: Double = 1.0
    @State private var isRecoveringModel = false

    public init(
        viewModel: TranscriptionViewModel,
        onRequestStart: (() -> Void)? = nil,
        onStopRecording: (() -> Void)? = nil,
        onOpacityChange: ((Double) -> Void)? = nil,
        onOpenLibrary: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self.onRequestStart = onRequestStart
        self.onStopRecording = onStopRecording
        self.onOpacityChange = onOpacityChange
        self.onOpenLibrary = onOpenLibrary
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            modelStatusRow
            if isRecoverableModelFailure {
                modelRecoveryButton
            }
            Divider()
            recordingButton
            if viewModel.isRecording && !viewModel.allText.isEmpty {
                copyButton
            }
            Button("회의 목록 열기") { onOpenLibrary?() }
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

    private var modelRecoveryButton: some View {
        Button {
            recoverCurrentModelCache()
        } label: {
            if isRecoveringModel {
                Text("모델 다시 받는 중...")
            } else {
                Text("캐시 정리 후 다시 받기")
            }
        }
        .disabled(isModelBusy || isRecoveringModel)
    }

    @ViewBuilder
    private var modelStateText: some View {
        switch viewModel.modelState {
        case .loaded:
            Text(viewModel.modelDisplayName)
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
                    // 종료·요약 생성·보고서 마감 전 과정을 AppDelegate가 오케스트레이션한다.
                    onStopRecording?()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            } else {
                Button("녹음 시작") {
                    onRequestStart?()
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

    private var isModelBusy: Bool {
        switch viewModel.modelState {
        case .downloading, .loading:
            return true
        case .loaded, .failed, .unloaded:
            return false
        }
    }

    private var isRecoverableModelFailure: Bool {
        guard case .failed = viewModel.modelState else { return false }
        return viewModel.cacheRecoveryVariant != nil
    }

    private func recoverCurrentModelCache() {
        guard let variant = viewModel.cacheRecoveryVariant else { return }
        isRecoveringModel = true

        Task { @MainActor in
            await viewModel.recoverModelCacheAndReload(variant: variant)
            isRecoveringModel = false
        }
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
