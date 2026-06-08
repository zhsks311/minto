import SwiftUI
import AppKit

private enum LibraryPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let border = Color.secondary.opacity(0.18)
    static let accentSoft = Color.accentColor.opacity(0.12)
}

private struct MeetingSearchMatch {
    let badge: String
    let text: String
}

/// 회의 목록 + 검색 + 선택한 회의 미리보기.
/// v2는 검색을 첫 화면의 중심 작업으로 두고, 상세 리포트 전체보다 빠른 회고/탐색에 집중한다.
public struct MeetingLibraryView: View {
    @ObservedObject private var store: MeetingStore
    @ObservedObject private var viewModel: TranscriptionViewModel
    @ObservedObject private var summaryService = SummaryService.shared
    @ObservedObject private var relatedInfo = RelatedInfoService.shared
    @ObservedObject private var notionMCP = NotionMCPService.shared
    @ObservedObject private var confluence = ConfluenceService.shared
    @State private var selectedID: UUID?
    @State private var searchText = ""
    @State private var showingLiveMeeting = false
    @State private var detailTab: DetailTab = .summary
    @State private var lastRelatedQuery = ""
    @AppStorage("meetingDetailReadableText") private var useReadableDetailText = true
    private let onNewMeeting: () -> Void
    private let onShowOverlay: () -> Void
    private let onStopRecording: () -> Void

    private enum DetailTab {
        case summary
        case transcript
        case related

        var title: String {
            switch self {
            case .summary: return "요약"
            case .transcript: return "전사"
            case .related: return "관련 문서"
            }
        }
    }

    public init(
        store: MeetingStore,
        viewModel: TranscriptionViewModel,
        onNewMeeting: @escaping () -> Void,
        onShowOverlay: @escaping () -> Void,
        onStopRecording: @escaping () -> Void
    ) {
        self.store = store
        self.viewModel = viewModel
        self.onNewMeeting = onNewMeeting
        self.onShowOverlay = onShowOverlay
        self.onStopRecording = onStopRecording
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(LibraryPalette.background)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear {
            if hasLiveMeeting {
                showingLiveMeeting = true
            }
            selectFirstAvailableIfNeeded()
        }
        .onChange(of: store.meetings) { _, _ in selectFirstAvailableIfNeeded() }
        .onChange(of: searchText) { _, _ in
            if hasLiveMeeting {
                showingLiveMeeting = true
                selectedID = nil
            } else {
                selectFirstAvailableIfNeeded(preferFirstResult: true)
            }
        }
        .onChange(of: viewModel.isRecording) { _, isRecording in
            showingLiveMeeting = isRecording || viewModel.isFinalizingMeeting
            if !showingLiveMeeting {
                selectFirstAvailableIfNeeded(preferFirstResult: true)
            }
        }
        .onChange(of: viewModel.isFinalizingMeeting) { _, isFinalizing in
            if isFinalizing {
                showingLiveMeeting = true
            } else if !viewModel.isRecording {
                showingLiveMeeting = false
                selectFirstAvailableIfNeeded(preferFirstResult: true)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Minto")
                    .font(.system(size: 20, weight: .bold))
                Text(isSearching ? "필요한 회의와 근거를 찾고 있어요" : "회의를 찾거나 새로 시작하세요")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 20)

            searchField
                .frame(width: 360)

            Button { onNewMeeting() } label: {
                Label("새 회의", systemImage: "mic.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("회의, 안건, 결정사항 검색", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if isSearching {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("검색 지우기")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 0) {
            resultsColumn
                .frame(width: 360)
            Divider()
            detailColumn
        }
    }

    private var resultsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchReadiness

            if isSearching {
                searchSummary
                suggestionChips
            }

            HStack {
                Text(isSearching ? "검색 결과" : "최근 회의")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(displayedMeetings.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            if hasLiveMeeting {
                liveMeetingRow
            }

            if store.meetings.isEmpty && !hasLiveMeeting {
                emptyState
            } else if isSearching && displayedMeetings.isEmpty {
                noSearchResults
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedMeetings) { record in
                            meetingRow(record)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LibraryPalette.surface.opacity(0.45))
    }

    private var detailColumn: some View {
        Group {
            if showingLiveMeeting, hasLiveMeeting {
                liveMeetingDetail
            } else if let record = selectedRecord {
                meetingPreview(record)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("회의를 선택하면 요약과 전사 근거를 볼 수 있어요")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .textSelection(.enabled)
    }

    // MARK: - Left column blocks

    private var searchReadiness: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    .frame(width: 30, height: 30)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("검색 준비됨")
                    .font(.system(size: 12, weight: .semibold))
                Text("저장된 회의 \(store.meetings.count)개에서 바로 찾습니다")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var searchSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("“\(trimmedSearch)” 검색 중")
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
            Text(displayedMeetings.isEmpty ? "일치하는 회의를 찾지 못했어요" : "가장 가까운 회의부터 보여줍니다")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionChips: some View {
        HStack(spacing: 6) {
            Label("필터", systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(LibraryPalette.elevated)
                .clipShape(Capsule())
            ForEach(["요약", "전사", "주제"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("아직 저장된 회의가 없어요")
                .font(.system(size: 13, weight: .semibold))
            Text("새 회의를 녹음하면 여기에서 검색할 수 있어요")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button { onNewMeeting() } label: {
                Label("첫 회의 시작", systemImage: "mic")
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundColor(.secondary)
            Text("검색 결과가 없어요")
                .font(.system(size: 13, weight: .semibold))
            Text("다른 회의명, 안건, 결정사항으로 다시 검색해 보세요")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var liveMeetingRow: some View {
        let selected = showingLiveMeeting
        return HStack(alignment: .top, spacing: 8) {
            Button {
                selectLiveMeeting()
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(liveTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text(viewModel.isFinalizingMeeting ? "정리 중" : "녹음 중")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(viewModel.isFinalizingMeeting ? .orange : .red)
                    }

                    Text(liveSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    Text(livePrimaryText)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Button { onShowOverlay() } label: {
                Image(systemName: "rectangle.on.rectangle")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("전사 오버레이 열기")
            .disabled(!viewModel.isRecording)

            Button { onStopRecording() } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .help("녹음 종료")
            .disabled(!viewModel.isRecording || viewModel.isFinalizingMeeting)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? LibraryPalette.accentSoft : LibraryPalette.elevated)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(selected ? Color.accentColor.opacity(0.45) : LibraryPalette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .onTapGesture {
            selectLiveMeeting()
        }
    }

    private func meetingRow(_ record: MeetingRecord) -> some View {
        let selected = selectedID == record.id
        let match = primaryMatch(for: record)

        return Button {
            selectedID = record.id
            showingLiveMeeting = false
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayTitle(for: record))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(shortDate(record.startedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text(record.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if isSearching {
                    HStack(spacing: 6) {
                        Text(match.badge)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                        Text(match.text)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                } else if !summaryPreviewText(record.summary).isEmpty {
                    markdownText(summaryPreviewText(record.summary))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? LibraryPalette.accentSoft : LibraryPalette.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : LibraryPalette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.delete(record.id)
                if selectedID == record.id { selectedID = nil }
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    // MARK: - Detail preview

    private var liveMeetingDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(liveTitle)
                                .font(.system(size: 26, weight: .bold))
                                .fixedSize(horizontal: false, vertical: true)
                            Text(liveSubtitle)
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                            if summaryService.activeGenerations > 0 {
                                Label("현재 요약 갱신 중", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        readingModeButton

                        Button { onShowOverlay() } label: {
                            Label("오버레이", systemImage: "rectangle.on.rectangle")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRecording)

                        Button(role: .destructive) { onStopRecording() } label: {
                            Label("녹음 종료", systemImage: "stop.fill")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!viewModel.isRecording || viewModel.isFinalizingMeeting)
                    }

                    detailTabs
                    HStack(spacing: 8) {
                        Button { copyLiveSummary() } label: {
                            Label("요약 복사", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        .disabled(liveRunningSummary.isEmpty)

                        Button { copyLiveTranscript() } label: {
                            Label("전사 복사", systemImage: "text.quote")
                        }
                        .buttonStyle(.bordered)
                        .disabled(liveSegments.isEmpty)
                    }
                }
                .padding(18)
                .background(LibraryPalette.elevated)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if detailTab == .summary {
                    liveSummarySection
                    liveTranscriptSnippet
                } else if detailTab == .transcript {
                    transcriptBlock(liveSegments, emptyText: "아직 전사된 내용이 없습니다.")
                } else {
                    relatedDocsSection(
                        query: liveRelatedSearchQuery,
                        emptyText: "전사가 쌓이면 현재 회의 주제로 관련 문서를 찾을 수 있습니다."
                    )
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LibraryPalette.background)
    }

    private var liveSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("현재까지 요약", systemImage: "list.bullet.rectangle")
            if liveRunningSummary.isEmpty {
                Text("요약은 전사가 충분히 쌓이면 자동으로 갱신됩니다.")
                    .font(.system(size: detailBodyFontSize))
                    .foregroundColor(.secondary)
            } else {
                markdownText(liveRunningSummary)
                    .font(.system(size: detailBodyFontSize))
                    .lineSpacing(detailLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var liveTranscriptSnippet: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("최근 전사", systemImage: "text.quote")
            let recent = liveSegments.suffix(6)
            if recent.isEmpty {
                Text("녹음이 시작되면 여기에 전사가 쌓입니다.")
                    .font(.system(size: detailBodyFontSize))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(recent.enumerated()), id: \.element.id) { _, segment in
                    Text(segment.text)
                        .font(.system(size: detailBodyFontSize))
                        .lineSpacing(detailLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func meetingPreview(_ record: MeetingRecord) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    previewHeader(record)

                    if isSearching {
                        whyThisResult(record)
                    }

                    if detailTab == .summary {
                        leadSummary(record)
                        meetingTableOfContents(record.summary.sections, scrollProxy: proxy)
                        meetingNotes(record.summary.sections)
                        meetingOutcomes(record.summary)
                    } else if detailTab == .transcript {
                        transcriptBlock(record.transcript, emptyText: "전사 내용이 없습니다.", record: record)
                    } else {
                        relatedDocsSection(
                            query: relatedSearchQuery(for: record),
                            emptyText: "이 회의의 요약과 전사로 관련 문서를 찾을 수 있습니다."
                        )
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(LibraryPalette.background)
        }
    }

    private func previewHeader(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle(for: record))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(record.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    if !record.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(record.topic)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                readingModeButton

                Button { MeetingExporter.save(MeetingResult.from(record)) } label: {
                    Label("내보내기", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button { copyFullMeeting(record) } label: {
                    Label("전체 복사", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                Button { copyTranscript(record) } label: {
                    Label("전사 복사", systemImage: "text.quote")
                }
                .buttonStyle(.bordered)
                .disabled(record.transcript.isEmpty)
            }
            detailTabs
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var detailTabs: some View {
        HStack(spacing: 6) {
            ForEach([DetailTab.summary, .transcript, .related], id: \.self) { tab in
                detailTabButton(tab.title, tab)
            }
        }
        .padding(4)
        .background(Color.secondary.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func detailTabButton(_ title: String, _ tab: DetailTab) -> some View {
        let active = detailTab == tab
        return Button { detailTab = tab } label: {
            Text(title)
                .font(.system(size: 13, weight: active ? .bold : .semibold))
                .foregroundColor(active ? .primary : .secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .background(active ? LibraryPalette.elevated : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    private var readingModeButton: some View {
        Button { useReadableDetailText.toggle() } label: {
            Text("Aa")
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(useReadableDetailText ? .accentColor : .secondary)
                .frame(width: 32, height: 26)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help(useReadableDetailText ? "표준 글자 크기로 보기" : "큰 글자 크기로 보기")
        .accessibilityLabel(useReadableDetailText ? "표준 글자 크기로 보기" : "큰 글자 크기로 보기")
    }

    private func whyThisResult(_ record: MeetingRecord) -> some View {
        let match = primaryMatch(for: record)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("이 회의가 먼저 보이는 이유")
                    .font(.system(size: 13, weight: .bold))
            }
            HStack(alignment: .top, spacing: 8) {
                Text(match.badge)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                Text(match.text)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LibraryPalette.accentSoft)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func leadSummary(_ record: MeetingRecord) -> some View {
        let summary = record.summary
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("요약", systemImage: "list.bullet.rectangle")
            if summary.isEmpty {
                Text("요약이 없습니다. 전사 내용을 먼저 확인하세요.")
                    .font(.system(size: detailBodyFontSize))
                    .foregroundColor(.secondary)
            } else {
                if !summary.leadQuestion.isEmpty {
                    Text(summary.leadQuestion)
                        .font(.system(size: detailSubBodyFontSize, weight: .semibold))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !summary.leadAnswer.isEmpty {
                    markdownText(summary.leadAnswer)
                        .font(.system(size: detailBodyFontSize))
                        .lineSpacing(detailLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !summary.keywords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(summary.keywords, id: \.self) { keyword in
                                Text("#\(keyword)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func meetingOutcomes(_ summary: MeetingSummary) -> some View {
        let decisions = visibleDecisions(summary.decisions)
        let actions = visibleActionItems(summary.actionItems)
        let questions = visibleOpenQuestions(summary.openQuestions)

        if !decisions.isEmpty || !actions.isEmpty || !questions.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    sectionTitle("결과 정리", systemImage: "tray.full")
                    Spacer()
                    Button {
                        copyMarkdown(summary.outcomesMarkdown())
                    } label: {
                        Label("전체 복사", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !decisions.isEmpty {
                    outcomeGroup(title: "결정사항", systemImage: "checkmark.seal", copyText: summary.decisionsMarkdown()) {
                        ForEach(Array(decisions.enumerated()), id: \.offset) { _, decision in
                            outcomeTextRow(time: decision.time, text: decision.text)
                        }
                    }
                }

                if !decisions.isEmpty && (!actions.isEmpty || !questions.isEmpty) {
                    Divider()
                }

                if !actions.isEmpty {
                    outcomeGroup(title: "할 일", systemImage: "checklist", copyText: summary.actionItemsMarkdown()) {
                        ForEach(Array(actions.enumerated()), id: \.offset) { _, item in
                            actionItemRow(item)
                        }
                    }
                }

                if !actions.isEmpty && !questions.isEmpty {
                    Divider()
                }

                if !questions.isEmpty {
                    outcomeGroup(title: "미해결 질문", systemImage: "questionmark.circle", copyText: summary.openQuestionsMarkdown()) {
                        ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
                            outcomeTextRow(time: question.time, text: question.text)
                        }
                    }
                }
            }
            .padding(18)
            .background(LibraryPalette.elevated)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func outcomeGroup<Content: View>(
        title: String,
        systemImage: String,
        copyText: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionTitle(title, systemImage: systemImage)
                Spacer()
                Button {
                    copyMarkdown(copyText)
                } label: {
                    Label("\(title) 복사", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(copyText.isEmpty)
            }

            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .textSelection(.enabled)
        }
    }

    private func outcomeTextRow(time: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.system(size: detailBodyFontSize, weight: .bold))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                if !time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    timeBadge(time)
                }
                markdownText(text)
                    .font(.system(size: detailBodyFontSize))
                    .lineSpacing(detailLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func actionItemRow(_ item: MeetingSummary.ActionItem) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "square")
                .font(.system(size: detailSubBodyFontSize, weight: .semibold))
                .foregroundColor(.secondary)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 5) {
                if !item.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    timeBadge(item.time)
                }
                markdownText(item.task)
                    .font(.system(size: detailBodyFontSize))
                    .lineSpacing(detailLineSpacing)
                    .fixedSize(horizontal: false, vertical: true)

                let meta = actionMetadata(item)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: detailTimestampFontSize, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private func timeBadge(_ time: String) -> some View {
        Text(time.trimmingCharacters(in: .whitespacesAndNewlines))
            .font(.system(size: detailTimestampFontSize, weight: .bold, design: .monospaced))
            .foregroundColor(.secondary)
    }

    @ViewBuilder
    private func meetingTableOfContents(_ sections: [MeetingSummary.Section], scrollProxy: ScrollViewProxy) -> some View {
        let entries = meetingTableOfContentsEntries(sections)
        if !entries.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    sectionTitle("목차", systemImage: "list.number")
                    Spacer()
                    Text("\(entries.count)개 구간")
                        .font(.system(size: detailTimestampFontSize, weight: .semibold))
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.offset) { index, entry in
                        Button {
                            withAnimation(.easeInOut(duration: 0.22)) {
                                scrollProxy.scrollTo(tocAnchorID(entry.sectionIndex), anchor: .top)
                            }
                        } label: {
                            tocRow(
                                number: entry.number,
                                title: entry.title,
                                time: entry.time,
                                preview: entry.preview,
                                pointCount: entry.pointCount
                            )
                        }
                        .buttonStyle(.plain)

                        if index < entries.count - 1 {
                            Divider()
                                .padding(.leading, 42)
                        }
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LibraryPalette.elevated)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private func meetingNotes(_ sections: [MeetingSummary.Section]) -> some View {
        let noteSections = meetingNoteSections(sections)
        if !noteSections.isEmpty {
            VStack(alignment: .leading, spacing: detailCardSpacing) {
                sectionTitle("회의 내용 정리", systemImage: "doc.text")

                VStack(alignment: .leading, spacing: detailCardSpacing) {
                    ForEach(Array(noteSections.enumerated()), id: \.element.sectionIndex) { position, section in
                        meetingNoteSection(section)
                            .id(tocAnchorID(section.sectionIndex))

                        if position < noteSections.count - 1 {
                            Divider()
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(LibraryPalette.elevated)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func meetingNoteSection(_ section: MeetingNoteSection) -> some View {
        VStack(alignment: .leading, spacing: detailItemSpacing) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(section.number). \(section.title)")
                    .font(.system(size: detailBodyFontSize, weight: .bold))
                    .foregroundColor(.primary)
                if !section.time.isEmpty {
                    timeBadge(section.time)
                }
            }

            ForEach(Array(section.points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: detailSubItemSpacing) {
                    if !point.text.isEmpty {
                        HStack(alignment: .top, spacing: 7) {
                            Text("•")
                                .font(.system(size: detailBodyFontSize, weight: .bold))
                                .foregroundColor(.secondary)
                            markdownText(point.text)
                                .font(.system(size: detailBodyFontSize, weight: .semibold))
                                .foregroundColor(.primary)
                                .lineSpacing(detailLineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    ForEach(Array(point.subPoints.enumerated()), id: \.offset) { _, subPoint in
                        HStack(alignment: .top, spacing: 7) {
                            Text("-")
                                .font(.system(size: detailBodyFontSize, weight: .medium))
                                .foregroundColor(.secondary)
                            markdownText(subPoint)
                                .font(.system(size: detailBodyFontSize))
                                .foregroundColor(detailSubTextColor)
                                .lineSpacing(detailLineSpacing)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 18)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    private func tocRow(number: Int, title: String, time: String, preview: String, pointCount: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .background(LibraryPalette.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.system(size: detailBodyFontSize, weight: .semibold))
                        .foregroundColor(.primary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 8)

                    if !time.isEmpty {
                        timeBadge(time)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(pointCount)개 항목")
                        .font(.system(size: detailTimestampFontSize, weight: .medium))
                        .foregroundColor(.secondary)

                    if !preview.isEmpty {
                        Text(preview)
                            .font(.system(size: detailTimestampFontSize))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.vertical, 10)
    }

    private func transcriptBlock(
        _ segments: [Segment],
        emptyText: String,
        record: MeetingRecord? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("전사", systemImage: "quote.bubble")
            if segments.isEmpty {
                Text(emptyText)
                    .font(.system(size: detailBodyFontSize))
                    .foregroundColor(.secondary)
            } else {
                ForEach(segments) { segment in
                    HStack(alignment: .top, spacing: 10) {
                        Text(relativeTimestamp(segment, in: record, fallbackSegments: segments))
                            .font(.system(size: detailTimestampFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 46, alignment: .leading)
                        Text(segment.text)
                            .font(.system(size: detailBodyFontSize))
                            .lineSpacing(detailLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func relatedDocsSection(query: String, emptyText: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sectionTitle("관련 문서", systemImage: "sparkles.rectangle.stack")
                Spacer()
                Button {
                    runRelatedSearch(query)
                } label: {
                    Label("현재 회의로 조회", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(query.isEmpty || !relatedInfo.isAnyConfigured || relatedInfo.isSearching)
                .help(relatedInfo.isAnyConfigured ? "현재 회의 요약과 전사로 Notion·Confluence를 검색합니다." : "설정에서 Notion 또는 Confluence를 먼저 연결하세요.")
            }

            HStack(spacing: 8) {
                sourceStatus("Notion", connected: notionMCP.isConfigured)
                sourceStatus("Confluence", connected: confluence.isConfigured)
            }

            if query.isEmpty {
                Text(emptyText)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Text("검색 기준: \(query)")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            let isCurrentQuery = lastRelatedQuery == query

            if relatedInfo.isSearching, isCurrentQuery {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("관련 문서를 찾고 있습니다.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if !relatedInfo.isAnyConfigured {
                Text("설정에서 검색 소스를 연결하면 회의 내용으로 관련 문서를 찾을 수 있습니다.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else if isCurrentQuery, !relatedInfo.results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(relatedInfo.results) { doc in
                        relatedDocRow(doc)
                    }
                }
            } else if isCurrentQuery, let message = relatedInfo.statusMessage {
                Text(message)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                Text("조회 버튼을 누르면 현재 회의 기준으로 검색합니다.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sourceStatus(_ title: String, connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.35))
                .frame(width: 7, height: 7)
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.secondary.opacity(0.08))
        .clipShape(Capsule())
    }

    private func relatedDocRow(_ doc: RelatedDoc) -> some View {
        Button {
            if let url = URL(string: doc.url) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Text(doc.source == .notion ? "N" : "C")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .frame(width: 22, height: 22)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                VStack(alignment: .leading, spacing: 3) {
                    Text(doc.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if !doc.snippet.isEmpty {
                        Text(doc.snippet)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(doc.url)
    }

    private func runRelatedSearch(_ query: String) {
        lastRelatedQuery = query
        Task { await relatedInfo.search(query: query) }
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: detailHeadingFontSize, weight: .bold))
        }
    }

    // MARK: - Search

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearch.isEmpty
    }

    private var hasLiveMeeting: Bool {
        viewModel.isRecording || viewModel.isFinalizingMeeting
    }

    private var liveSegments: [Segment] {
        var segments = viewModel.committedSegments
        if let pending = viewModel.pendingSegment,
           !pending.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           segments.last?.text != pending.text {
            segments.append(pending)
        }
        return segments
    }

    private var liveTitle: String {
        let topic = MeetingContext.shared.topic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !topic.isEmpty { return topic }
        return viewModel.isFinalizingMeeting ? "정리 중인 회의" : "진행 중인 회의"
    }

    private var liveSubtitle: String {
        let state = viewModel.isFinalizingMeeting ? "요약 생성 중" : "녹음 중"
        return "\(state) · \(MeetingRecord.durationText(viewModel.recordingDuration)) · 구간 \(liveSegments.count)개"
    }

    private var liveRunningSummary: String {
        MeetingContext.shared.runningSummary.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var livePrimaryText: String {
        if !liveRunningSummary.isEmpty { return liveRunningSummary }
        if let text = liveSegments.last?.text, !text.isEmpty { return text }
        return "전사를 기다리는 중입니다"
    }

    private var liveRelatedSearchQuery: String {
        compactRelatedQuery(liveSegments.suffix(4).map(\.text).joined(separator: " "))
    }

    private var displayedMeetings: [MeetingRecord] {
        guard isSearching else { return store.meetings }
        return store.meetings.filter { recordMatches($0) }
    }

    private var selectedRecord: MeetingRecord? {
        if let selectedID, let record = displayedMeetings.first(where: { $0.id == selectedID }) {
            return record
        }
        return displayedMeetings.first
    }

    private func recordMatches(_ record: MeetingRecord) -> Bool {
        let query = trimmedSearch
        guard !query.isEmpty else { return true }
        return displayTitle(for: record).localizedCaseInsensitiveContains(query)
            || record.topic.localizedCaseInsensitiveContains(query)
            || outcomeSearchText(record.summary).localizedCaseInsensitiveContains(query)
            || record.summary.markdown().localizedCaseInsensitiveContains(query)
            || record.transcript.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private func primaryMatch(for record: MeetingRecord) -> MeetingSearchMatch {
        let query = trimmedSearch
        if !query.isEmpty {
            if displayTitle(for: record).localizedCaseInsensitiveContains(query) {
                return MeetingSearchMatch(badge: "제목", text: displayTitle(for: record))
            }
            if record.topic.localizedCaseInsensitiveContains(query) {
                return MeetingSearchMatch(badge: "주제", text: record.topic)
            }
            if let decision = visibleDecisions(record.summary.decisions).first(where: { $0.text.localizedCaseInsensitiveContains(query) }) {
                return MeetingSearchMatch(badge: decision.time.isEmpty ? "결정" : decision.time, text: "결정: \(decision.text)")
            }
            if let item = visibleActionItems(record.summary.actionItems).first(where: { actionItemMatches($0, query: query) }) {
                return MeetingSearchMatch(badge: item.time.isEmpty ? "할 일" : item.time, text: "할 일: \(item.task)")
            }
            if let question = visibleOpenQuestions(record.summary.openQuestions).first(where: { $0.text.localizedCaseInsensitiveContains(query) }) {
                return MeetingSearchMatch(badge: question.time.isEmpty ? "질문" : question.time, text: "질문: \(question.text)")
            }
            if let section = record.summary.sections.first(where: { section in
                section.title.localizedCaseInsensitiveContains(query)
                    || section.points.contains { point in
                        point.text.localizedCaseInsensitiveContains(query)
                            || point.subPoints.contains { $0.localizedCaseInsensitiveContains(query) }
                    }
            }) {
                let text = section.points.first?.text ?? section.title
                return MeetingSearchMatch(badge: section.time.isEmpty ? "요약" : section.time, text: text)
            }
            if record.summary.markdown().localizedCaseInsensitiveContains(query) {
                return MeetingSearchMatch(badge: "요약", text: record.summary.leadAnswer)
            }
            if let segment = record.transcript.first(where: { $0.text.localizedCaseInsensitiveContains(query) }) {
                return MeetingSearchMatch(badge: relativeTimestamp(segment, in: record), text: segment.text)
            }
        }

        if !record.summary.leadAnswer.isEmpty {
            return MeetingSearchMatch(badge: "요약", text: record.summary.leadAnswer)
        }
        if let segment = record.transcript.first {
            return MeetingSearchMatch(badge: relativeTimestamp(segment, in: record), text: segment.text)
        }
        return MeetingSearchMatch(badge: "회의", text: record.subtitle)
    }

    private func relatedSearchQuery(for record: MeetingRecord) -> String {
        let keywordText = record.summary.keywords.prefix(5).joined(separator: " ")
        if !keywordText.isEmpty { return compactRelatedQuery(keywordText) }

        let outcomeText = outcomeSearchText(record.summary)
        if !outcomeText.isEmpty { return compactRelatedQuery(outcomeText) }

        let summaryText = record.summary.leadAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !summaryText.isEmpty { return compactRelatedQuery(summaryText) }

        return compactRelatedQuery(record.transcript.suffix(4).map(\.text).joined(separator: " "))
    }

    private func compactRelatedQuery(_ text: String) -> String {
        let normalized = text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        if normalized.count <= 120 { return normalized }
        return String(normalized.prefix(120))
    }

    private func summaryPreviewText(_ summary: MeetingSummary) -> String {
        let lead = summary.leadAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !lead.isEmpty { return lead }
        if let decision = visibleDecisions(summary.decisions).first {
            return "결정: \(decision.text)"
        }
        if let action = visibleActionItems(summary.actionItems).first {
            return "할 일: \(action.task)"
        }
        if let question = visibleOpenQuestions(summary.openQuestions).first {
            return "질문: \(question.text)"
        }
        return ""
    }

    private func outcomeSearchText(_ summary: MeetingSummary) -> String {
        var parts: [String] = []
        parts.append(contentsOf: visibleDecisions(summary.decisions).map(\.text))
        parts.append(contentsOf: visibleActionItems(summary.actionItems).flatMap { item in
            [item.task, item.owner, item.due].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        })
        parts.append(contentsOf: visibleOpenQuestions(summary.openQuestions).map(\.text))
        return parts.joined(separator: " ")
    }

    private func visibleDecisions(_ decisions: [MeetingSummary.Decision]) -> [MeetingSummary.Decision] {
        decisions.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func visibleActionItems(_ items: [MeetingSummary.ActionItem]) -> [MeetingSummary.ActionItem] {
        items.filter { !$0.task.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func visibleOpenQuestions(_ questions: [MeetingSummary.OpenQuestion]) -> [MeetingSummary.OpenQuestion] {
        questions.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func actionItemMatches(_ item: MeetingSummary.ActionItem, query: String) -> Bool {
        item.task.localizedCaseInsensitiveContains(query)
            || item.owner.localizedCaseInsensitiveContains(query)
            || item.due.localizedCaseInsensitiveContains(query)
    }

    private func actionMetadata(_ item: MeetingSummary.ActionItem) -> String {
        let owner = item.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = item.due.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !owner.isEmpty { parts.append("담당: \(owner)") }
        if !due.isEmpty { parts.append("기한: \(due)") }
        return parts.joined(separator: " · ")
    }

    private func meetingTableOfContentsEntries(
        _ sections: [MeetingSummary.Section]
    ) -> [(sectionIndex: Int, number: Int, title: String, time: String, preview: String, pointCount: Int)] {
        sections.enumerated().compactMap { index, section in
            let title = cleanedSectionTitle(section.title, fallbackIndex: index)
            let time = section.time.trimmingCharacters(in: .whitespacesAndNewlines)
            let pointCount = section.points.filter {
                !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !$0.subPoints.isEmpty
            }.count
            guard !title.isEmpty || pointCount > 0 else { return nil }
            return (
                sectionIndex: index,
                number: index + 1,
                title: title,
                time: time,
                preview: meetingTableOfContentsPreview(section),
                pointCount: pointCount
            )
        }
    }

    private func meetingTableOfContentsPreview(_ section: MeetingSummary.Section) -> String {
        section.points
            .map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? ""
    }

    private func meetingNoteSections(_ sections: [MeetingSummary.Section]) -> [MeetingNoteSection] {
        sections.enumerated().compactMap { index, section in
            let title = cleanedSectionTitle(section.title, fallbackIndex: index)
            let time = section.time.trimmingCharacters(in: .whitespacesAndNewlines)

            let points = section.points.compactMap { point -> MeetingNotePoint? in
                let pointText = point.text.trimmingCharacters(in: .whitespacesAndNewlines)
                let subPoints = point.subPoints
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                guard !pointText.isEmpty || !subPoints.isEmpty else { return nil }
                return MeetingNotePoint(text: pointText, subPoints: subPoints)
            }

            guard !title.isEmpty || !points.isEmpty else { return nil }
            return MeetingNoteSection(
                sectionIndex: index,
                number: index + 1,
                title: title,
                time: time,
                points: points
            )
        }
    }

    private func tocAnchorID(_ index: Int) -> String {
        "meeting-note-section-\(index)"
    }

    private struct MeetingNoteSection {
        let sectionIndex: Int
        let number: Int
        let title: String
        let time: String
        let points: [MeetingNotePoint]
    }

    private struct MeetingNotePoint {
        let text: String
        let subPoints: [String]
    }

    private func cleanedSectionTitle(_ title: String, fallbackIndex: Int) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "\(fallbackIndex + 1). 섹션" : trimmed
    }

    private func selectFirstAvailableIfNeeded(preferFirstResult: Bool = false) {
        if hasLiveMeeting, showingLiveMeeting, !preferFirstResult {
            showingLiveMeeting = true
            return
        }
        guard !displayedMeetings.isEmpty else {
            selectedID = nil
            showingLiveMeeting = hasLiveMeeting
            return
        }
        if preferFirstResult {
            if hasLiveMeeting {
                showingLiveMeeting = true
                selectedID = nil
                return
            }
            selectedID = displayedMeetings.first?.id
            showingLiveMeeting = false
            return
        }
        if let selectedID, displayedMeetings.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = displayedMeetings.first?.id
        showingLiveMeeting = false
    }

    private func selectLiveMeeting() {
        showingLiveMeeting = true
        selectedID = nil
    }

    // MARK: - Helpers

    private func displayTitle(for record: MeetingRecord) -> String {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없음" : title
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d"
        return formatter.string(from: date)
    }

    private func relativeTimestamp(
        _ segment: Segment,
        in record: MeetingRecord? = nil,
        fallbackSegments: [Segment] = []
    ) -> String {
        let start = record?.transcript.first?.timestamp
            ?? fallbackSegments.first?.timestamp
            ?? record?.startedAt
            ?? segment.timestamp
        let seconds = max(0, Int(segment.timestamp.timeIntervalSince(start).rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private var detailHeadingFontSize: CGFloat {
        useReadableDetailText ? 15 : 14
    }

    private var detailSectionTitleFontSize: CGFloat {
        useReadableDetailText ? 16 : 14
    }

    private var detailBodyFontSize: CGFloat {
        useReadableDetailText ? 15 : 13
    }

    private var detailSubBodyFontSize: CGFloat {
        useReadableDetailText ? 14 : 12
    }

    private var detailTimestampFontSize: CGFloat {
        useReadableDetailText ? 12 : 11
    }

    private var detailLineSpacing: CGFloat {
        useReadableDetailText ? 5 : 4
    }

    private var detailCardSpacing: CGFloat {
        useReadableDetailText ? 18 : 12
    }

    private var detailItemSpacing: CGFloat {
        useReadableDetailText ? 10 : 8
    }

    private var detailSubItemSpacing: CGFloat {
        useReadableDetailText ? 6 : 4
    }

    private var detailSubTextColor: Color {
        useReadableDetailText ? Color.primary.opacity(0.78) : .secondary
    }

    private func markdownText(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    private func copyFullMeeting(_ record: MeetingRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(MeetingExporter.markdown(for: MeetingResult.from(record)), forType: .string)
    }

    private func copyTranscript(_ record: MeetingRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.transcript.map(\.text).joined(separator: "\n"), forType: .string)
    }

    private func copyMarkdown(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copyLiveSummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(liveRunningSummary, forType: .string)
    }

    private func copyLiveTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(liveSegments.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
