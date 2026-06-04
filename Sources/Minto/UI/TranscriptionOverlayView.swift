import SwiftUI
import AppKit

public struct TranscriptionOverlayView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    @ObservedObject private var llmService = LLMCorrectionService.shared
    @ObservedObject private var relatedInfo = RelatedInfoService.shared
    @ObservedObject private var notionMCP = NotionMCPService.shared
    @ObservedObject private var confluence = ConfluenceService.shared
    @State private var showRelated = false

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            headerView
            Divider()
            mainContentView
            if showRelated {
                Divider()
                relatedInfoPanel
            }
            Divider()
            footerView
        }
        // 창 높이는 고정 — 관련 패널은 transcript 영역을 나눠 쓴다(NSPanel 리사이즈 불필요, 잘림 방지).
        .frame(width: 420, height: 520)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.25), radius: 20, x: 0, y: 8)
        .padding(12)
    }

    // MARK: - Header

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

            Button { showRelated.toggle() } label: {
                Image(systemName: showRelated ? "lightbulb.fill" : "lightbulb")
                    .font(.system(size: 12))
                    .foregroundColor(showRelated ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .help("전사 기반 관련 정보 (위키·Notion·Confluence)")

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
            Text(viewModel.modelVariantName)
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
                    Text("\(Int(p * 100))%  ·  처음 한 번만 다운로드됩니다")
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
            Text("마이크 권한이 필요합니다")
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
            .buttonStyle(.borderedProminent)
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
            Text(viewModel.isRecording ? "말씀하세요..." : "녹음을 시작하면 여기에 전사됩니다")
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

    // MARK: - Related info (전사 기반 Notion·Confluence 조회)

    private var relatedInfoPanel: some View {
        let keywords = detectedKeywords()
        let query = relatedSearchQuery()
        let isRelatedInfoConfigured = notionMCP.isConfigured || confluence.isConfigured
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles.rectangle.stack").font(.system(size: 11)).foregroundColor(.yellow)
                Text("관련 정보").font(.system(size: 12, weight: .bold))
                Spacer()
                if relatedInfo.isSearching {
                    ProgressView().controlSize(.small)
                } else {
                    Button {
                        Task { await relatedInfo.search(query: query) }
                    } label: {
                        Label("조회", systemImage: "magnifyingglass").font(.system(size: 10))
                    }
                    .buttonStyle(.borderless)
                    .disabled(query.isEmpty || !isRelatedInfoConfigured || relatedInfo.isSearching)
                    .help(isRelatedInfoConfigured ? "감지된 주제로 Notion·Confluence 검색" : "설정에서 Notion/Confluence를 먼저 연동하세요")
                }
            }

            if !keywords.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(keywords, id: \.self) { keyword in
                            Text("#\(keyword)").font(.system(size: 11)).foregroundColor(.primary.opacity(0.8))
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Color.secondary.opacity(0.12)).clipShape(Capsule())
                        }
                    }
                }
            }

            relatedResultsSection
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxHeight: 240, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var relatedResultsSection: some View {
        if !(notionMCP.isConfigured || confluence.isConfigured) {
            Text("설정에서 Notion 또는 Confluence를 연동하면 감지된 주제로 문서를 찾아 드립니다.")
                .font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !relatedInfo.results.isEmpty {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(relatedInfo.results) { doc in
                        relatedDocRow(doc)
                    }
                }
            }
        } else if let message = relatedInfo.statusMessage {
            Text(message).font(.system(size: 10)).foregroundColor(.secondary)
        } else {
            Text("‘조회’를 누르면 감지된 주제로 Notion·Confluence를 검색합니다.")
                .font(.system(size: 10)).foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func relatedDocRow(_ doc: RelatedDoc) -> some View {
        Button {
            if let url = URL(string: doc.url) { NSWorkspace.shared.open(url) }
        } label: {
            HStack(alignment: .top, spacing: 6) {
                Text(doc.source == .notion ? "N" : "C")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 16, height: 16)
                    .background((doc.source == .notion ? Color.primary : Color.blue).opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(doc.title).font(.system(size: 11, weight: .medium)).foregroundColor(.primary).lineLimit(1)
                    if !doc.snippet.isEmpty {
                        Text(doc.snippet).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square").font(.system(size: 9)).foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(doc.url)
    }

    /// 최근 전사 원문을 우선 검색한다. 짧은 한국어 명사구(`컬리 용어 모음집`)가
    /// 토큰 필터에서 `모음집`만 남아 검색 품질이 떨어지는 문제를 피하기 위해서다.
    private func relatedSearchQuery() -> String {
        let recent = viewModel.committedSegments.suffix(4).map(\.text).joined(separator: " ")
        let normalized = recent
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }

        if normalized.count <= 120 { return normalized }
        return String(normalized.suffix(120))
    }

    /// 최근 전사에서 감지한 주제 후보. 한국어 업무 용어는 2글자 명사도 많아
    /// Hangul/CJK 토큰은 2글자부터 표시한다(`컬리`, `용어` 등).
    private func detectedKeywords() -> [String] {
        let recent = viewModel.committedSegments.suffix(4).map(\.text).joined(separator: " ")
        let separators = CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters)
        var seen = Set<String>()
        var out: [String] = []
        for token in recent.components(separatedBy: separators) {
            let w = token.trimmingCharacters(in: .whitespaces)
            guard isRelatedKeyword(w), !seen.contains(w) else { continue }
            seen.insert(w)
            out.append(w)
            if out.count >= 8 { break }
        }
        return out
    }

    private func isRelatedKeyword(_ word: String) -> Bool {
        if word.count >= 3 { return true }
        return word.count >= 2 && word.unicodeScalars.contains { scalar in
            (0xAC00...0xD7A3).contains(Int(scalar.value)) || (0x4E00...0x9FFF).contains(Int(scalar.value))
        }
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
        HStack(spacing: 2) {
            ForEach(0..<16, id: \.self) { i in
                let threshold = Float(i + 1) / 16.0
                let active = viewModel.audioLevel >= threshold
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(active ? levelBarColor(at: Float(i) / 16.0) : Color.secondary.opacity(0.12))
                    .frame(width: 3, height: active ? 12 : 7)
                    .animation(.easeOut(duration: 0.04), value: active)
            }
        }
    }

    private func levelBarColor(at position: Float) -> Color {
        if position < 0.6 { return .green }
        if position < 0.85 { return .yellow }
        return .red
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
