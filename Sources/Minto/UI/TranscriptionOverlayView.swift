import SwiftUI
import AppKit

private enum OverlayLayout {
    static let outerPadding: CGFloat = 12
    static let expandedContentWidth: CGFloat = 420
    static let expandedContentHeight: CGFloat = 520
    static let collapsedContentWidth: CGFloat = 280
    static let collapsedContentHeight: CGFloat = 40
}

public struct TranscriptionOverlayView: View {
    public static let expandedWindowSize = NSSize(
        width: OverlayLayout.expandedContentWidth + OverlayLayout.outerPadding * 2,
        height: OverlayLayout.expandedContentHeight + OverlayLayout.outerPadding * 2
    )
    public static let collapsedWindowSize = NSSize(
        width: OverlayLayout.collapsedContentWidth + OverlayLayout.outerPadding * 2,
        height: OverlayLayout.collapsedContentHeight + OverlayLayout.outerPadding * 2
    )

    @ObservedObject public var viewModel: TranscriptionViewModel
    @ObservedObject private var llmService = LLMCorrectionService.shared
    @State private var isCollapsed = false
    private let onCollapseChange: (Bool) -> Void

    public init(
        viewModel: TranscriptionViewModel,
        onCollapseChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.viewModel = viewModel
        self.onCollapseChange = onCollapseChange
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isCollapsed {
                collapsedHeaderView
            } else {
                headerView
                Divider()
                mainContentView
                Divider()
                footerView
            }
        }
        // 접힘 상태에서는 NSPanel도 함께 줄여 회의 화면을 덜 가린다.
        .frame(width: overlayContentSize.width, height: overlayContentSize.height)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        .padding(OverlayLayout.outerPadding)
        .animation(.easeInOut(duration: 0.18), value: isCollapsed)
        .onChange(of: isCollapsed) { _, collapsed in
            onCollapseChange(collapsed)
        }
    }

    // MARK: - Header

    private var overlayContentSize: CGSize {
        isCollapsed
            ? CGSize(width: OverlayLayout.collapsedContentWidth, height: OverlayLayout.collapsedContentHeight)
            : CGSize(width: OverlayLayout.expandedContentWidth, height: OverlayLayout.expandedContentHeight)
    }

    private var headerView: some View {
        HStack(spacing: 8) {
            recordingDotView

            if viewModel.isRecording {
                Text(formatDuration(viewModel.recordingDuration))
                    .font(.system(.caption, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(.primary)
                    .animation(nil, value: viewModel.recordingDuration)
            } else {
                Text(isModelReady ? "대기 중" : " ")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button { setCollapsed(true) } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("오버레이 접기")

            if llmService.activeCorrections > 0 {
                HStack(spacing: 3) {
                    Text("✦")
                        .font(.system(size: 9))
                        .foregroundColor(.blue)
                    Text("교정 중")
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.12))
                .clipShape(Capsule())
            }

            modelStateBadge
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    private var collapsedHeaderView: some View {
        HStack(spacing: 10) {
            recordingDotView

            Text(viewModel.isRecording ? formatDuration(viewModel.recordingDuration) : "대기 중")
                .font(.system(.caption, design: viewModel.isRecording ? .monospaced : .default))
                .monospacedDigit()
                .foregroundColor(.primary)
                .animation(nil, value: viewModel.recordingDuration)

            audioLevelMeter

            Spacer(minLength: 0)

            Button { setCollapsed(false) } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.borderless)
            .help("오버레이 펼치기")
        }
        .padding(.horizontal, 14)
        .frame(height: OverlayLayout.collapsedContentHeight)
    }

    private func setCollapsed(_ collapsed: Bool) {
        withAnimation(.easeInOut(duration: 0.18)) {
            isCollapsed = collapsed
        }
    }

    private var recordingDotView: some View {
        ZStack {
            if viewModel.isRecording {
                Circle()
                    .fill(Color.red.opacity(0.25))
                    .frame(width: 18, height: 18)
                    .modifier(PulsingScaleModifier())
            }
            Circle()
                .fill(viewModel.isRecording ? Color.red : Color.secondary.opacity(0.3))
                .frame(width: 8, height: 8)
        }
        .frame(width: 18, height: 18)
    }

    @ViewBuilder
    private var modelStateBadge: some View {
        switch viewModel.modelState {
        case .loaded:
            Text(viewModel.modelDisplayName)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12))
                .clipShape(Capsule())
        case .downloading(let p):
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
                Text("다운로드 \(Int(p * 100))%")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        case .loading:
            HStack(spacing: 5) {
                ProgressView()
                    .scaleEffect(0.55)
                    .frame(width: 14, height: 14)
                Text("초기화 중")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        case .failed:
            Label("로드 실패", systemImage: "exclamationmark.circle")
                .font(.system(size: 10))
                .foregroundColor(.orange)
        case .unloaded:
            EmptyView()
        }
    }

    // MARK: - Main content

    @ViewBuilder
    private var mainContentView: some View {
        if viewModel.isPermissionDenied {
            permissionDeniedView
        } else if isModelLoading {
            modelLoadingView
        } else {
            transcriptView
        }
    }

    private var isModelReady: Bool {
        if case .loaded = viewModel.modelState { return true }
        return false
    }

    private var isModelLoading: Bool {
        switch viewModel.modelState {
        case .downloading, .loading: return !viewModel.isRecording
        default: return false
        }
    }

    // MARK: - Model loading view

    private var modelLoadingView: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            switch viewModel.modelState {
            case .downloading(let p):
                VStack(spacing: 12) {
                    Text("음성 인식 모델 다운로드 중")
                        .font(.headline)
                    ProgressView(value: p)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 280)
                    Text("\(Int(p * 100))%  ·  처음 한 번만 다운로드돼요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            case .loading:
                VStack(spacing: 12) {
                    Text("모델 초기화 중")
                        .font(.headline)
                    ProgressView()
                    Text("CoreML 컴파일 중... 잠시 기다려 주세요")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            default:
                EmptyView()
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 28)
    }

    // MARK: - Permission denied view

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "mic.slash.fill")
                .font(.system(size: 44))
                .foregroundColor(.secondary)
            Text("마이크 권한이 필요해요")
                .font(.headline)
            Text("시스템 설정 > 개인 정보 보호 및 보안 > 마이크에서\nMinto를 허용해 주세요.")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("시스템 설정 열기") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(ProminentActionButtonStyle())
            Spacer()
        }
        .padding(.horizontal, 28)
    }

    // MARK: - Transcript view (MoonshineNoteTaker의 streaming line UX 참고)

    private var transcriptView: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if viewModel.committedSegments.isEmpty && viewModel.pendingSegment == nil {
                        emptyStateView
                    } else {
                        ForEach(viewModel.committedSegments) { segment in
                            committedRow(segment)
                                .id(segment.id)
                        }
                        if let pending = viewModel.pendingSegment {
                            pendingRow(pending)
                                .id("pending")
                        }
                    }
                    Color.clear.frame(height: 4).id("bottom")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .onChange(of: viewModel.committedSegments.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onChange(of: viewModel.pendingSegment?.text) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("pending", anchor: .bottom)
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack {
            Spacer()
            Text(viewModel.isRecording ? "말씀하세요..." : "녹음을 시작하면 여기에 전사돼요")
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(height: 360)
    }

    // 확정된 세그먼트: 타임스탬프 + 텍스트 (LineCompleted 상태)
    private func committedRow(_ segment: Segment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTimestamp(segment.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary)
                .fixedSize()
                .padding(.top, 2)
            if let speaker = SpeakerLabel.normalized(segment.speaker) {
                Text(speaker)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: 64, alignment: .leading)
                    .padding(.top, 2)
            }
            Text(segment.text)
                .font(.callout)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 1)
    }

    // 인식 중인 세그먼트: 희미하게 + 펄스 (LineTextChanged 상태)
    private func pendingRow(_ segment: Segment) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(formatTimestamp(segment.timestamp))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.secondary.opacity(0.6))
                .fixedSize()
                .padding(.top, 2)
            Text(segment.text)
                .font(.callout)
                .foregroundColor(.primary.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .modifier(PulsingOpacityModifier())
        }
        .padding(.vertical, 1)
    }

    // MARK: - Footer

    private var footerView: some View {
        HStack(spacing: 10) {
            audioLevelMeter

            Spacer()

            if !viewModel.allText.isEmpty {
                Button(action: copyTranscript) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("전사 내용 복사")

                Button(action: viewModel.clearTranscript) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("전사 내용 초기화")
            }

            if let msg = viewModel.errorMessage {
                Text(msg)
                    .font(.system(size: 10))
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 200)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
    }

    // 16-bar 오디오 레벨 미터
    private var audioLevelMeter: some View {
        AudioLevelMeterView(audioLevel: viewModel.audioLevel)
    }

    private func copyTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(viewModel.allText, forType: .string)
    }

    // MARK: - Formatters

    private func formatDuration(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }

    private func formatTimestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return "[\(f.string(from: date))]"
    }
}

// MARK: - Animation modifiers

private struct PulsingScaleModifier: ViewModifier {
    @State private var scale: CGFloat = 1.0
    func body(content: Content) -> some View {
        content
            .scaleEffect(scale)
            .animation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true), value: scale)
            .onAppear { scale = 1.6 }
    }
}

private struct PulsingOpacityModifier: ViewModifier {
    @State private var opacity: Double = 1.0
    func body(content: Content) -> some View {
        content
            .opacity(opacity)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: opacity)
            .onAppear { opacity = 0.5 }
    }
}
