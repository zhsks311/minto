import SwiftUI
import AppKit
import UniformTypeIdentifiers

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
    @ObservedObject private var answerSettings = MeetingSearchAnswerSettingsService.shared
    @ObservedObject private var relatedInfo = RelatedInfoService.shared
    @ObservedObject private var notionMCP = NotionMCPService.shared
    @ObservedObject private var confluence = ConfluenceService.shared
    @StateObject private var searchAnswerController = MeetingSearchAnswerController()
    @StateObject private var fileImportUseCase: MeetingFileImportUseCase
    @State private var selectedID: UUID?
    @State private var searchText = ""
    // 검색 인덱스·결과 캐시. 키 입력마다 전체 회의를 다시 청크하지 않도록
    // 인덱스는 회의 목록 변경 시에만, 결과는 디바운스된 쿼리 변경 시에만 갱신한다.
    @State private var searchIndex = MeetingSearchIndex(chunks: [])
    @StateObject private var embeddingViewModel = SearchEmbeddingViewModel()
    @State private var meetingSearchResults: [MeetingSearchResult] = []
    /// 필터 미적용 전체 검색 결과. AI 답변 생성에는 필터된 결과 대신 이 값을 사용해
    /// 요약/결정 등 근거가 누락되지 않게 한다.
    @State private var allMeetingSearchResults: [MeetingSearchResult] = []
    @State private var showingLiveMeeting = false
    @State private var showingExportOptions = false
    @State private var showingConfluenceExport = false
    @State private var exportRecord: MeetingRecord?
    // 오른쪽 디테일 영역에 AI 답변 전문을 표시할지 여부.
    // 라이브 회의 디테일이 항상 우선하고, 회의 행/인용 클릭 시 꺼진다.
    @State private var showingSearchAnswerDetail = false
    /// AI 답변의 인용을 클릭했을 때 회의 미리보기에서 스크롤·하이라이트할 근거 위치.
    @State private var searchAnswerCitationAnchor: SearchAnswerCitationAnchor?
    @State private var detailTab: DetailTab = .summary
    @State private var lastRelatedQuery = ""
    @State private var fileImportTask: Task<Void, Never>?
    /// 파일 선택 후 맥락 입력 시트를 띄울 URL. nil이면 시트 미표시.
    @State private var fileImportSetupURL: URL?
    /// 이전 실행에서 완료되지 못한 파일 가져오기 마커.
    @State private var unfinishedImportFileName: String?
    @State private var didReportUnfinishedImport = false
    /// 재요약 진행 중인 회의 ID. nil이면 재요약 없음.
    /// record.id에 바인딩해 다른 회의 선택 시 상태 오염을 방지한다.
    @State private var retryingRecordID: UUID?
    /// 재요약 실패 정보. id가 현재 표시 중인 record와 일치할 때만 에러를 렌더한다.
    @State private var retryError: (id: UUID, message: String)?
    /// 재요약 전에 용어집을 다시 선택할 회의.
    @State private var reSummaryGlossaryRecord: MeetingRecord?
    @State private var speakerRenameDrafts: [String: String] = [:]
    @State private var speakerMergeTargets: [String: String] = [:]
    @State private var speakerEditError: (id: UUID, message: String)?
    @State private var speakerEnrollNotice: (id: UUID, message: String, isError: Bool)?
    @State private var transcriptEditDraft: TranscriptEditDraft?
    @State private var transcriptEditSavingID: UUID?
    @State private var transcriptEditError: (id: UUID, message: String)?
    @State private var transcriptEditedHintID: UUID?
    @State private var documentRemovalRecordID: UUID?
    @State private var showingDocumentRemovalConfirmation = false
    @State private var documentRemovalSavingID: UUID?
    @State private var documentRemovalError: (id: UUID, message: String)?
    /// 검색 결과를 특정 chunk 종류로 좁히는 필터. 검색어가 비면 .all로 리셋된다.
    @State private var activeSearchFilter: SearchKindFilter = .all
    @AppStorage("meetingDetailReadableText") private var useReadableDetailText = true
    private let onNewMeeting: () -> Void
    private let onShowOverlay: () -> Void
    private let onStopRecording: () -> Void
    private let fileImportDefaults: UserDefaults

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
        onStopRecording: @escaping () -> Void,
        fileImportDefaults: UserDefaults = .standard
    ) {
        self.store = store
        self.viewModel = viewModel
        self.onNewMeeting = onNewMeeting
        self.onShowOverlay = onShowOverlay
        self.onStopRecording = onStopRecording
        self.fileImportDefaults = fileImportDefaults
        _fileImportUseCase = StateObject(wrappedValue: MeetingFileImportUseCase(defaults: fileImportDefaults))
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
            rebuildSearchIndex()
            selectFirstAvailableIfNeeded()
            searchAnswerController.refreshReadiness()
            detectUnfinishedFileImportIfNeeded()
        }
        .onChange(of: store.meetings) { _, _ in
            searchAnswerController.reset()
            dismissSearchAnswerPresentation()
            rebuildSearchIndex()
            selectFirstAvailableIfNeeded()
        }
        .onChange(of: selectedID) { _, _ in
            cancelTranscriptEditing()
            cancelDocumentRemoval()
        }
        .onChange(of: detailTab) { _, _ in
            // 탭 전환도 편집 상태를 무효화한다 — "편집" 버튼으로만 진입(상태 누수 방지).
            cancelTranscriptEditing()
        }
        .onChange(of: searchText) { _, _ in
            searchAnswerController.reset()
            dismissSearchAnswerPresentation()
            if hasLiveMeeting {
                showingLiveMeeting = true
                selectedID = nil
            }
        }
        .task(id: searchText) {
            // 한글 IME는 자모 단위로 searchText를 갱신하므로 짧게 디바운스해
            // 조합 중 매 키 입력마다 전체 검색이 실행되는 것을 막는다.
            if isSearching {
                try? await Task.sleep(for: .milliseconds(200))
                if Task.isCancelled { return }
            }
            refreshSearchResults()
            if !hasLiveMeeting {
                selectFirstAvailableIfNeeded(preferFirstResult: true)
            }
        }
        .onChange(of: viewModel.isRecording) { _, isRecording in
            showingLiveMeeting = isRecording || viewModel.isFinalizingMeeting
            if !showingLiveMeeting {
                // 회의가 저장되지 않고 끝나면 store.meetings onChange가 안 불려
                // 이전 검색의 답변 디테일이 남을 수 있어 여기서도 닫는다.
                dismissSearchAnswerPresentation()
                selectFirstAvailableIfNeeded(preferFirstResult: true)
            }
        }
        .onChange(of: viewModel.isFinalizingMeeting) { _, isFinalizing in
            if isFinalizing {
                showingLiveMeeting = true
            } else if !viewModel.isRecording {
                showingLiveMeeting = false
                dismissSearchAnswerPresentation()
                selectFirstAvailableIfNeeded(preferFirstResult: true)
            }
        }
        .onChange(of: answerSettings.isEnabled) { _, _ in
            searchAnswerController.reset(clearReadiness: true)
            dismissSearchAnswerPresentation()
            searchAnswerController.refreshReadiness()
        }
        .onChange(of: answerSettings.effectiveProvider) { _, _ in
            searchAnswerController.reset(clearReadiness: true)
            dismissSearchAnswerPresentation()
            searchAnswerController.refreshReadiness()
        }
        .onChange(of: fileImportUseCase.state) { _, state in
            if state.stage != .idle {
                unfinishedImportFileName = nil
            }
            if let record = state.record {
                selectedID = record.id
                showingLiveMeeting = false
                detailTab = .summary
            }
        }
        .onReceive(GlossaryStore.shared.$entries) { _ in
            // 용어집 변경 시 검색 결과를 즉시 재계산해 추가/삭제된 용어를 반영한다.
            if isSearching { refreshSearchResults() }
        }
        .confirmationDialog(
            "회의록 내보내기",
            isPresented: $showingExportOptions,
            titleVisibility: .visible
        ) {
            if let exportRecord {
                Button("Markdown 파일로 저장") {
                    MeetingExporter.save(MeetingResult.from(exportRecord))
                }
                Button("전체 내용 복사") {
                    copyFullMeeting(exportRecord)
                }
                if confluence.isConfigured {
                    Button("Confluence로 내보내기") {
                        showingConfluenceExport = true
                    }
                } else {
                    Button("Confluence 설정 열기") {
                        openSettingsWindow()
                    }
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text(confluence.isConfigured
                 ? "파일로 저장하거나 연결된 Confluence 공간에 새 페이지로 만들 수 있어요."
                 : "Confluence 내보내기는 설정의 검색 소스에서 Confluence를 연결한 뒤 사용할 수 있어요.")
        }
        .confirmationDialog(
            "회의 자료를 제거할까요?",
            isPresented: $showingDocumentRemovalConfirmation,
            titleVisibility: .visible
        ) {
            Button("문서 제거", role: .destructive) {
                confirmDocumentRemoval()
            }
            Button("취소", role: .cancel) {
                documentRemovalRecordID = nil
            }
        } message: {
            Text("로컬에 저장된 회의 자료만 제거돼요. 요약과 전사는 유지돼요.")
        }
        .sheet(isPresented: $showingConfluenceExport) {
            if let exportRecord {
                ConfluenceExportSheet(
                    record: exportRecord,
                    confluence: confluence,
                    openSettings: openSettingsWindow
                )
            }
        }
        .sheet(isPresented: Binding(
            get: { fileImportSetupURL != nil },
            set: { if !$0 { fileImportSetupURL = nil } }
        )) {
            if let url = fileImportSetupURL {
                FileImportSetupSheet(
                    fileURL: url,
                    onImport: { topic, glossary, expectedSpeakerCount in
                        startFileImport(
                            url: url,
                            topic: topic,
                            glossary: glossary,
                            expectedSpeakerCount: expectedSpeakerCount,
                            diarizeSpeakers: true
                        )
                    },
                    onSkip: {
                        startFileImport(
                            url: url,
                            topic: nil,
                            glossary: "",
                            expectedSpeakerCount: nil,
                            diarizeSpeakers: false
                        )
                    }
                )
            }
        }
        .sheet(item: $reSummaryGlossaryRecord) { record in
            ReSummaryGlossarySheet(record: record) { glossary in
                await retrySummary(for: record, glossary: glossary)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                headerTitle
                    .layoutPriority(1)
                Spacer(minLength: 12)
                searchField
                    .frame(minWidth: 220, idealWidth: 360, maxWidth: 360)
                    .layoutPriority(0)
                fileImportButton
                    .layoutPriority(2)
                newMeetingButton
                    .layoutPriority(4)
            }

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    headerTitle
                    Spacer(minLength: 12)
                    newMeetingButton
                }
                HStack(spacing: 10) {
                    searchField
                        .frame(minWidth: 180, maxWidth: .infinity)
                    fileImportButton
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Minto")
                .font(.system(size: 20, weight: .bold))
            Text(isSearching ? "필요한 회의와 근거를 찾고 있어요" : "회의를 찾거나 새로 시작하세요")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var fileImportButton: some View {
        Button { selectFileForImport() } label: {
            Label("파일 가져오기", systemImage: "tray.and.arrow.down")
                .font(.system(size: 13, weight: .semibold))
        }
        .controlSize(.large)
        .fixedSize()
        .disabled(hasLiveMeeting || fileImportUseCase.state.isRunning)
        .help(hasLiveMeeting ? "진행 중인 회의를 종료한 뒤 파일을 가져올 수 있어요." : "음성 또는 영상 파일로 회의록을 만들어요.")
    }

    private var newMeetingButton: some View {
        Button { onNewMeeting() } label: {
            Label("새 회의", systemImage: "mic.circle.fill")
                .font(.system(size: 13, weight: .semibold))
        }
        .buttonStyle(ProminentActionButtonStyle(horizontalPadding: 16, verticalPadding: 9))
        .fixedSize()
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
            if store.corruptedCount > 0 {
                corruptedMeetingNotice
            }
            unfinishedFileImportCard
            fileImportStatusCard

            if isSearching {
                searchSummary
                searchAnswerCard
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

    private var corruptedMeetingNotice: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(.orange)
            Text("\(store.corruptedCount)건의 회의를 불러오지 못했어요")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var detailColumn: some View {
        Group {
            switch detailContent {
            case .live:
                liveMeetingDetail
            case .searchAnswer:
                searchAnswerDetail
            case .preview(let record):
                meetingPreview(record)
            case .empty:
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

    // MARK: - Search answer detail

    /// 오른쪽 디테일 영역에 표시하는 AI 답변 전문. meetingPreview와 같은 골격(ScrollView + padding 28)을 쓴다.
    private var searchAnswerDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Label("AI 답변", systemImage: "sparkles")
                        .font(.system(size: 26, weight: .bold))
                    Text("“\(trimmedSearch)” — 저장된 회의 근거로 답변해요")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }

                if searchAnswerController.isGenerating {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                        Text("검색 결과를 종합하는 중이에요…")
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 6)
                } else if let searchAnswer = searchAnswerController.answer, searchAnswer.query == trimmedSearch {
                    markdownText(searchAnswer.text)
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if !searchAnswer.citations.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            sectionTitle("근거", systemImage: "text.quote")
                            searchAnswerDetailCitationList(searchAnswer.citations)
                        }
                    }

                    HStack(spacing: 10) {
                        Button {
                            copySearchAnswer(searchAnswer)
                        } label: {
                            Label("답변과 근거 복사", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(.bordered)
                        Button {
                            searchAnswerController.generate(query: trimmedSearch, results: allMeetingSearchResults)
                            searchAnswerCitationAnchor = nil
                        } label: {
                            Label("다시 만들기", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!searchAnswerController.canGenerate(query: trimmedSearch, resultCount: allMeetingSearchResults.count))
                    }
                } else if let errorMessage = searchAnswerController.errorMessage {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(errorMessage)
                            .font(.system(size: 13))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                        Button {
                            searchAnswerController.generate(query: trimmedSearch, results: allMeetingSearchResults)
                            searchAnswerCitationAnchor = nil
                        } label: {
                            Label("다시 시도", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .disabled(!searchAnswerController.canGenerate(query: trimmedSearch, resultCount: allMeetingSearchResults.count))
                    }
                } else {
                    Text(searchAnswerController.hintText(query: trimmedSearch, resultCount: allMeetingSearchResults.count))
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LibraryPalette.background)
    }

    /// 현재 검색어에 대한 답변이 이미 만들어져 있는지. 회의 미리보기에서 "답변으로 돌아가기" 노출 조건.
    private var hasSearchAnswerForCurrentQuery: Bool {
        searchAnswerController.isGenerating || searchAnswerController.answer?.query == trimmedSearch
    }

    private var backToSearchAnswerButton: some View {
        Button {
            showingSearchAnswerDetail = true
            searchAnswerCitationAnchor = nil
        } label: {
            Label("AI 답변으로 돌아가기", systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(.bordered)
    }

    /// 디테일 영역용 근거 목록. 같은 회의의 인용을 하나의 카드로 묶어
    /// "어느 회의의 어느 대목"인지 한눈에 보이게 한다.
    private func searchAnswerDetailCitationList(_ citations: [MeetingSearchAnswerCitation]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(searchAnswerCitationGroups(citations), id: \.meetingID) { group in
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                        Text(group.meetingTitle)
                            .font(.system(size: 12, weight: .bold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.06))

                    ForEach(Array(group.citations.enumerated()), id: \.element.id) { position, citation in
                        if position > 0 {
                            Divider()
                                .padding(.leading, 12)
                        }
                        Button {
                            selectSearchAnswerCitation(citation)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Text("[\(citation.number)]")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundColor(.accentColor)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(searchAnswerCitationMeta(citation))
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                    if !citation.preview.isEmpty {
                                        // 회의 요약 원문에 **강조** 마크다운이 저장돼 있어 평문 Text면 그대로 노출된다.
                                        markdownText(citation.preview)
                                            .font(.system(size: 12))
                                            .foregroundColor(.primary)
                                            .lineLimit(3)
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .padding(.top, 2)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("이 근거 대목으로 이동")
                    }
                }
                .background(LibraryPalette.elevated)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private struct SearchAnswerCitationGroup {
        let meetingID: UUID
        let meetingTitle: String
        var citations: [MeetingSearchAnswerCitation]
    }

    /// 인용을 등장 순서를 유지한 채 회의별로 묶는다. 번호([n])는 답변 본문 표기와 같게 유지.
    private func searchAnswerCitationGroups(_ citations: [MeetingSearchAnswerCitation]) -> [SearchAnswerCitationGroup] {
        var groups: [SearchAnswerCitationGroup] = []
        var indexByMeeting: [UUID: Int] = [:]
        for citation in citations {
            if let index = indexByMeeting[citation.meetingID] {
                groups[index].citations.append(citation)
            } else {
                indexByMeeting[citation.meetingID] = groups.count
                groups.append(SearchAnswerCitationGroup(
                    meetingID: citation.meetingID,
                    meetingTitle: citation.meetingTitle,
                    citations: [citation]
                ))
            }
        }
        return groups
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
                Text("저장된 회의 \(store.meetings.count)개에서 바로 찾아요")
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

    /// 왼쪽 컬럼의 컴팩트 AI 답변 카드. 답변 전문·근거는 오른쪽 디테일 영역(searchAnswerDetail)이 담당하고,
    /// 여기서는 진입점(CTA)과 현재 상태 요약만 보여준다.
    private var searchAnswerCard: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("AI 답변", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                if searchAnswerController.isCheckingProvider {
                    Text("확인 중")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                } else if !answerSettings.isEnabled || !searchAnswerController.isProviderReady {
                    Button("AI 설정") { openSettingsWindow() }
                        .font(.system(size: 11, weight: .semibold))
                }
            }

            if searchAnswerController.isCheckingProvider {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("AI 설정 확인 중")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else if searchAnswerController.isGenerating {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("검색 결과를 종합하는 중")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
            } else if let searchAnswer = searchAnswerController.answer, searchAnswer.query == trimmedSearch {
                // 미리보기 2줄 + 레이블 전체를 하나의 버튼으로 — 텍스트만 클릭되는 좁은 히트 영역을 피한다.
                Button {
                    showingSearchAnswerDetail = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        markdownText(searchAnswer.text)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .lineLimit(2)
                        Label("전체 답변 보기", systemImage: "arrow.right.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("전체 답변 보기")
            } else if let errorMessage = searchAnswerController.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                        .lineLimit(2)
                    generateAnswerButton(title: "다시 시도")
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(searchAnswerController.hintText(query: trimmedSearch, resultCount: allMeetingSearchResults.count))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if answerSettings.isEnabled && searchAnswerController.isProviderReady {
                        generateAnswerButton(title: "AI 답변 만들기")
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func generateAnswerButton(title: String) -> some View {
        Button {
            // 필터와 무관하게 전체 검색 결과를 근거로 넘겨 요약·결정 등 컨텍스트가 누락되지 않게 한다.
            searchAnswerController.generate(query: trimmedSearch, results: allMeetingSearchResults)
            // generate()가 가드(provider 미준비)로 조기 반환해도 디테일을 연다 —
            // 에러 메시지를 디테일 영역에서 크게 보여주는 것이 의도.
            showingSearchAnswerDetail = true
            searchAnswerCitationAnchor = nil
        } label: {
            Label(title, systemImage: "sparkles")
                .font(.system(size: 12, weight: .semibold))
        }
        .buttonStyle(ProminentActionButtonStyle())
        .disabled(!searchAnswerController.canGenerate(query: trimmedSearch, resultCount: allMeetingSearchResults.count))
    }

    private func searchAnswerCitationMeta(_ citation: MeetingSearchAnswerCitation) -> String {
        // citation.label은 time이 비면 kind.label과 같은 값이라 붙이면 "제목 · 제목"처럼 중복된다.
        var parts = [citation.kind.label]
        let time = citation.time.trimmingCharacters(in: .whitespacesAndNewlines)
        if !time.isEmpty {
            parts.append(time)
        }
        return parts.joined(separator: " · ")
    }

    private var suggestionChips: some View {
        HStack(spacing: 6) {
            Label("필터", systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(LibraryPalette.elevated)
                .clipShape(Capsule())
            // .all은 칩을 표시하지 않는다 — 전체 칩이 없어도 모두 선택 해제하면 .all로 돌아온다.
            ForEach([SearchKindFilter.summary, .transcript, .topic, .document], id: \.label) { filter in
                let active = activeSearchFilter == filter
                Button {
                    activeSearchFilter = active ? .all : filter
                    refreshSearchResults()
                    selectFirstAvailableIfNeeded(preferFirstResult: true)
                } label: {
                    Text(filter.label)
                        .font(.system(size: 11, weight: active ? .semibold : .medium))
                        .foregroundColor(active ? .white : .secondary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(active ? Color.accentColor : Color.secondary.opacity(0.10))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
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
            if activeSearchFilter != .all {
                VStack(spacing: 4) {
                    Text("'\(activeSearchFilter.label)' 필터를 해제하면 더 많은 결과를 볼 수 있어요")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("필터 해제") {
                        activeSearchFilter = .all
                        refreshSearchResults()
                        selectFirstAvailableIfNeeded(preferFirstResult: true)
                    }
                    .font(.system(size: 12))
                    .buttonStyle(.borderless)
                    .foregroundColor(.accentColor)
                }
            } else {
                Text("다른 회의명, 안건, 결정사항으로 다시 검색해 보세요")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var unfinishedFileImportCard: some View {
        if let fileName = unfinishedImportFileName {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.orange)
                        .frame(width: 20, height: 20)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("지난 가져오기가 완료되지 못했어요")
                            .font(.system(size: 12, weight: .bold))
                        Text("파일을 다시 가져와 주세요.")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(fileName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button {
                        dismissUnfinishedFileImport()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help("안내 닫기")
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    @ViewBuilder
    private var fileImportStatusCard: some View {
        let importState = fileImportUseCase.state
        if importState.stage != .idle {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 8) {
                    fileImportIcon(importState.stage)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(importState.stage.title)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.primary)
                        if !importState.fileName.isEmpty {
                            Text(importState.fileName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if importState.isRunning {
                        Button("취소") {
                            fileImportTask?.cancel()
                        }
                        .font(.system(size: 11, weight: .semibold))
                    } else {
                        Button {
                            fileImportUseCase.reset()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 20, height: 20)
                        }
                        .buttonStyle(.plain)
                        .help("상태 닫기")
                    }
                }

                if importState.isRunning {
                    ProgressView(value: importState.progress)
                        .progressViewStyle(.linear)
                }

                Text(importState.errorMessage ?? importState.detailText)
                    .font(.system(size: 11))
                    .foregroundColor(importState.stage == .failed ? .red : .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fileImportBackground(importState.stage))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(fileImportBorder(importState.stage), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var liveMeetingRow: some View {
        let selected = showingLiveMeeting
        return HStack(alignment: .top, spacing: 8) {
            Button {
                selectLiveMeeting()
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .center) {
                        Text(liveTitle)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        HStack(spacing: 6) {
                            AudioLevelMeterView(audioLevel: viewModel.audioLevel, barCount: 10)
                                .scaleEffect(x: 0.85, y: 0.72, anchor: .leading)
                                .frame(width: 28, height: 10, alignment: .leading)
                                .opacity(viewModel.isFinalizingMeeting ? 0.35 : 1)
                                .accessibilityHidden(true)
                            Text(viewModel.isFinalizingMeeting ? "정리 중" : "녹음 중")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(viewModel.isFinalizingMeeting ? .orange : .red)
                        }
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
        // 라이브 중에도 선택 행 강조를 유지한다.
        // AI 답변 디테일이 열려 있는 동안만 강조를 억제해
        // 좌우가 서로 다른 대상을 가리키는 것처럼 보이지 않게 한다. 선택 자체는 보존.
        let selected = selectedID == record.id && !(isSearching && showingSearchAnswerDetail)
        let match = primaryMatch(for: record)

        return Button {
            selectedID = record.id
            showingLiveMeeting = false
            dismissSearchAnswerPresentation()
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
                    transcriptBlock(liveSegments, emptyText: "아직 전사된 내용이 없어요.")
                } else {
                    relatedDocsSection(
                        query: liveRelatedSearchQuery,
                        emptyText: "전사가 쌓이면 현재 회의 주제로 관련 문서를 찾을 수 있어요."
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
                Text("요약은 전사가 충분히 쌓이면 자동으로 갱신돼요.")
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
                Text("녹음이 시작되면 여기에 전사가 쌓여요.")
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

    @ViewBuilder
    private func meetingPreview(_ record: MeetingRecord) -> some View {
        if detailTab == .transcript, let draftBinding = transcriptEditDraftBinding(for: record) {
            TranscriptEditView(
                draft: draftBinding,
                isSaving: transcriptEditSavingID == record.id,
                errorMessage: transcriptEditError?.id == record.id ? transcriptEditError?.message : nil,
                timestampText: { segment in
                    relativeTimestamp(segment, in: record, fallbackSegments: draftBinding.wrappedValue.originalSegments)
                },
                onCancel: {
                    cancelTranscriptEditing()
                },
                onSave: {
                    saveTranscriptEditing(for: record)
                }
            ) {
                VStack(alignment: .leading, spacing: 18) {
                    previewHeader(record)

                    if isSearching, hasSearchAnswerForCurrentQuery {
                        backToSearchAnswerButton
                    }

                    if isSearching {
                        whyThisResult(record)
                    }
                }
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        previewHeader(record)

                        if isSearching, hasSearchAnswerForCurrentQuery {
                            backToSearchAnswerButton
                        }

                        if isSearching {
                            whyThisResult(record)
                        }

                        if detailTab == .summary {
                            if record.summary.isPlainFallback {
                                plainFallbackBanner(record)
                            }
                            leadSummary(record)
                            storedDocumentSection(record)
                            meetingTableOfContents(record.summary.sections, scrollProxy: proxy)
                            meetingNotes(record.summary.sections)
                            meetingOutcomes(record.summary)
                        } else if detailTab == .transcript {
                            transcriptBlock(
                                record.transcript,
                                emptyText: "전사 내용이 없어요.",
                                record: record,
                                onEdit: { beginTranscriptEditing(record) },
                                editDisabled: hasLiveMeeting || record.transcript.isEmpty
                            )
                        } else {
                            relatedDocsSection(
                                query: relatedSearchQuery(for: record),
                                emptyText: "이 회의의 요약과 전사로 관련 문서를 찾을 수 있어요."
                            )
                        }
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(LibraryPalette.background)
                .onAppear {
                    scrollToCitationAnchor(in: record, proxy: proxy)
                }
                .onChange(of: searchAnswerCitationAnchor) { _, _ in
                    scrollToCitationAnchor(in: record, proxy: proxy)
                }
            }
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
                summaryRetryHeaderButton(record)

                Button {
                    exportRecord = record
                    showingExportOptions = true
                } label: {
                    Label("내보내기", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button { copyFullMeeting(record) } label: {
                    Label("전체 복사", systemImage: "doc.on.doc")
                }
                .buttonStyle(ProminentActionButtonStyle())
                Button { copyTranscript(record) } label: {
                    Label("전사 복사", systemImage: "text.quote")
                }
                .buttonStyle(.bordered)
                .disabled(record.transcript.isEmpty)
            }
            if !record.summary.isPlainFallback,
               let retryMessage = retryError?.id == record.id ? retryError?.message : nil {
                Text(retryMessage)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if transcriptEditedHintID == record.id {
                Label("전사를 수정했어요 — 다시 요약하면 반영돼요.", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.green)
                    .fixedSize(horizontal: false, vertical: true)
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

    @ViewBuilder
    private func summaryRetryHeaderButton(_ record: MeetingRecord) -> some View {
        if !record.summary.isPlainFallback {
            let isThisRetrying = retryingRecordID == record.id
            Button {
                presentReSummarySheet(for: record)
            } label: {
                HStack(spacing: 6) {
                    if isThisRetrying {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text("다시 요약")
                }
            }
            .buttonStyle(.bordered)
            .disabled(hasLiveMeeting || retryingRecordID != nil)
            .help(reSummaryHelpText(for: record))
        }
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
    private func plainFallbackBanner(_ record: MeetingRecord) -> some View {
        // record는 호출 시점의 값 복사본 — 버튼 클로저가 캡처해도 시점이 고정된다.
        let isThisRetrying = retryingRecordID == record.id
        let thisError = retryError?.id == record.id ? retryError?.message : nil

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                Text("구조화 요약을 만들지 못해 임시 요약만 저장됐어요. 목차·키워드 없이 표시돼요.")
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isThisRetrying {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("다시 요약하는 중…")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else {
                HStack(spacing: 8) {
                    Button("다시 요약") {
                        presentReSummarySheet(for: record)
                    }
                    .buttonStyle(.bordered)
                    .disabled(hasLiveMeeting || retryingRecordID != nil)
                    .help(reSummaryHelpText(for: record))

                    if let errorMessage = thisError {
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.07))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.orange.opacity(0.3), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func leadSummary(_ record: MeetingRecord) -> some View {
        let summary = record.summary
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("요약", systemImage: "list.bullet.rectangle")
            SummaryGlossaryBanner(glossary: record.summaryGlossary)
            if summary.isEmpty {
                Text("요약이 없어요. 전사 내용을 먼저 확인하세요.")
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
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    citationCardBorder(Self.searchAnswerLeadAnchorID),
                    lineWidth: isCitationHighlightTarget(Self.searchAnswerLeadAnchorID) ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .id(Self.searchAnswerLeadAnchorID)
    }

    @ViewBuilder
    private func storedDocumentSection(_ record: MeetingRecord) -> some View {
        // record.document는 init/decode 시점에 이미 normalizedDocument로 정규화돼 저장된다(뷰 재정규화 불필요).
        if let document = record.document {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    sectionTitle("회의 자료", systemImage: "doc.text")
                    Text("로컬 저장")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(Capsule())
                    Spacer()
                    if documentRemovalSavingID == record.id {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Button {
                        requestDocumentRemoval(for: record)
                    } label: {
                        Label("문서 제거", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(hasLiveMeeting || documentRemovalSavingID == record.id)
                    .help(hasLiveMeeting ? "진행 중인 회의를 종료한 뒤 제거할 수 있어요." : "로컬에 저장된 회의 자료를 제거해요.")
                }

                Text("로컬에 저장된 회의 자료예요.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                // 관련 문서 탭은 Notion·Confluence 실시간 검색이라, 저장된 첨부 문서는 요약 탭의 로컬 자료로 분리한다.
                DisclosureGroup {
                    Text(document)
                        .font(.system(size: detailBodyFontSize))
                        .lineSpacing(detailLineSpacing)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 6)
                } label: {
                    Text("내용 보기 · \(document.count)자")
                        .font(.system(size: 13, weight: .semibold))
                }

                if let error = documentRemovalError, error.id == record.id {
                    Text(error.message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(18)
            .background(LibraryPalette.elevated)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
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
                    .background(citationHighlightBackground(outcomeAnchorID("decisions")))
                    .id(outcomeAnchorID("decisions"))
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
                    .background(citationHighlightBackground(outcomeAnchorID("actions")))
                    .id(outcomeAnchorID("actions"))
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
                    .background(citationHighlightBackground(outcomeAnchorID("questions")))
                    .id(outcomeAnchorID("questions"))
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
                            .background(citationHighlightBackground(tocAnchorID(section.sectionIndex)))
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
        record: MeetingRecord? = nil,
        onEdit: (() -> Void)? = nil,
        editDisabled: Bool = false
    ) -> some View {
        let speakerLabels = SpeakerLabelEditing.labels(in: segments)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                sectionTitle("전사", systemImage: "quote.bubble")
                Spacer()
                if let onEdit {
                    Button {
                        onEdit()
                    } label: {
                        Label("편집", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(editDisabled)
                    .help(hasLiveMeeting ? "진행 중인 회의를 종료한 뒤 편집할 수 있어요."
                          : editDisabled ? "전사 내용이 없어요."
                          : "전사 텍스트를 편집해요.")
                }
            }
            if let record, !speakerLabels.isEmpty {
                speakerEditor(record: record, labels: speakerLabels)
            }
            if segments.isEmpty {
                Text(emptyText)
                    .font(.system(size: detailBodyFontSize))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                    HStack(alignment: .top, spacing: 10) {
                        Text(relativeTimestamp(segment, in: record, fallbackSegments: segments))
                            .font(.system(size: detailTimestampFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 46, alignment: .leading)
                        if let record, !speakerLabels.isEmpty {
                            segmentSpeakerReassignmentMenu(segment: segment, labels: speakerLabels, record: record)
                        } else if let speaker = SpeakerLabel.normalized(segment.speaker) {
                            Text(speaker)
                                .font(.system(size: detailTimestampFontSize, weight: .semibold))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .frame(maxWidth: 64, alignment: .leading)
                        }
                        Text(segment.text)
                            .font(.system(size: detailBodyFontSize))
                            .lineSpacing(detailLineSpacing)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // record가 없으면 라이브 전사라 인용 딥링크 대상이 아니다.
                    .background(record == nil ? nil : citationHighlightBackground(transcriptAnchorID(index), inset: -4))
                    .id(transcriptAnchorID(index))
                }
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func transcriptEditDraftBinding(for record: MeetingRecord) -> Binding<TranscriptEditDraft>? {
        guard transcriptEditDraft?.recordID == record.id else {
            return nil
        }
        return Binding(
            get: {
                transcriptEditDraft ?? TranscriptEditDraft(record: record)
            },
            set: {
                transcriptEditDraft = $0
            }
        )
    }

    private func beginTranscriptEditing(_ record: MeetingRecord) {
        guard !hasLiveMeeting, !record.transcript.isEmpty else {
            return
        }
        let current = store.meetings.first(where: { $0.id == record.id }) ?? record
        transcriptEditDraft = TranscriptEditDraft(record: current)
        transcriptEditError = nil
        transcriptEditSavingID = nil
    }

    private func cancelTranscriptEditing() {
        transcriptEditDraft = nil
        transcriptEditError = nil
        transcriptEditSavingID = nil
    }

    private func saveTranscriptEditing(for record: MeetingRecord) {
        guard let draft = transcriptEditDraft, draft.recordID == record.id else {
            return
        }
        guard draft.hasChanges else {
            cancelTranscriptEditing()
            return
        }

        transcriptEditSavingID = record.id
        transcriptEditError = nil

        let changedTextCount = draft.changedTextCount
        let removedSegmentCount = draft.removedSegmentCount
        let finalSegmentCount = draft.editedSegments.count
        Log.store.info("transcript edit save start segments=\(draft.originalSegments.count, privacy: .public) changedSegments=\(changedTextCount, privacy: .public) removedSegments=\(removedSegmentCount, privacy: .public)")

        switch TranscriptEditing.save(draft, in: store) {
        case .success:
            transcriptEditDraft = nil
            transcriptEditSavingID = nil
            transcriptEditError = nil
            showTranscriptEditedHint(for: record.id)
            Log.store.info("transcript edit save success segments=\(finalSegmentCount, privacy: .public) changedSegments=\(changedTextCount, privacy: .public) removedSegments=\(removedSegmentCount, privacy: .public)")
        case .skippedEmpty:
            transcriptEditSavingID = nil
            transcriptEditError = (id: record.id, message: "내용이 없어 저장할 수 없어요")
            Log.store.error("transcript edit save skipped empty changedSegments=\(changedTextCount, privacy: .public) removedSegments=\(removedSegmentCount, privacy: .public)")
        case .failed:
            transcriptEditSavingID = nil
            transcriptEditError = (id: record.id, message: "전사 수정을 저장하지 못했어요.")
            Log.store.error("transcript edit save failed changedSegments=\(changedTextCount, privacy: .public) removedSegments=\(removedSegmentCount, privacy: .public)")
        }
    }

    private func showTranscriptEditedHint(for recordID: UUID) {
        transcriptEditedHintID = recordID
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            if transcriptEditedHintID == recordID {
                transcriptEditedHintID = nil
            }
        }
    }

    private func segmentSpeakerReassignmentMenu(
        segment: Segment,
        labels: [String],
        record: MeetingRecord
    ) -> some View {
        let currentSpeaker = SpeakerLabel.normalized(segment.speaker)

        return Menu {
            ForEach(labels, id: \.self) { label in
                Button {
                    reassignSegment(segment.id, to: label, in: record)
                } label: {
                    if label == currentSpeaker {
                        Label(label, systemImage: "checkmark")
                    } else {
                        Text(label)
                    }
                }
                .disabled(label == currentSpeaker)
            }

            Divider()

            Button {
                reassignSegmentToNewSpeaker(segment.id, in: record)
            } label: {
                Label("새 화자", systemImage: "plus")
            }
        } label: {
            HStack(spacing: 3) {
                Text(currentSpeaker ?? "화자 지정")
                    .font(.system(size: detailTimestampFontSize, weight: .semibold))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: 76, alignment: .leading)
        }
        .controlSize(.small)
        .frame(width: 84, alignment: .leading)
        .help("화자 재배정")
    }

    private func speakerEditor(record: MeetingRecord, labels: [String]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                sectionTitle("화자", systemImage: "person.2")
                Spacer()
                Text("\(labels.count)명")
                    .font(.system(size: detailTimestampFontSize, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(labels, id: \.self) { label in
                    speakerEditorRow(label: label, labels: labels, record: record)
                }
            }

            if let error = speakerEditError, error.id == record.id {
                Text(error.message)
                    .font(.system(size: detailTimestampFontSize, weight: .medium))
                    .foregroundColor(.red)
            }

            if let notice = speakerEnrollNotice, notice.id == record.id {
                Text(notice.message)
                    .font(.system(size: detailTimestampFontSize, weight: .medium))
                    .foregroundColor(notice.isError ? Color.red : Color.green)
            }
        }
        .padding(12)
        .background(LibraryPalette.surface.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func speakerEditorRow(label: String, labels: [String], record: MeetingRecord) -> some View {
        let renameDraft = SpeakerLabel.normalized(speakerRenameDrafts[label] ?? label) ?? ""
        let isDuplicateRename = labels.contains { $0 != label && $0 == renameDraft }
        let canRename = !renameDraft.isEmpty && renameDraft != label && !isDuplicateRename
        let mergeTargets = labels.filter { $0 != label }
        let currentRecord = store.meetings.first(where: { $0.id == record.id }) ?? record
        let enrollmentName = (speakerRenameDrafts[label] ?? label).trimmingCharacters(in: .whitespacesAndNewlines)
        let hasSpeakerCentroid = currentRecord.speakerEmbeddings?.contains {
            SpeakerLabel.normalized($0.speakerLabel) == SpeakerLabel.normalized(label)
        } == true
        let canEnroll = hasSpeakerCentroid && !enrollmentName.isEmpty && !SpeakerLabel.isAutoGenerated(enrollmentName)

        return HStack(spacing: 8) {
            Text(label)
                .font(.system(size: detailTimestampFontSize, weight: .semibold))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 74, alignment: .leading)

            TextField("화자 이름", text: speakerRenameBinding(for: label))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: detailTimestampFontSize))
                .frame(minWidth: 120)

            Button {
                renameSpeaker(label, in: record)
            } label: {
                Label("이름변경", systemImage: "checkmark")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canRename)

            Divider()
                .frame(height: 22)

            Button {
                enrollSpeaker(label: label, name: enrollmentName, record: record)
            } label: {
                Label("등록", systemImage: "person.crop.circle.badge.plus")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!canEnroll)
            .help("이 화자의 목소리 데이터(임베딩)가 있고 실제 이름을 입력했을 때만 등록할 수 있어요.")

            if !mergeTargets.isEmpty {
                Divider()
                    .frame(height: 22)

                Picker("병합 대상", selection: speakerMergeTargetBinding(for: label, labels: labels)) {
                    ForEach(mergeTargets, id: \.self) { target in
                        Text(target).tag(target)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 110)

                Button {
                    mergeSpeaker(label, labels: labels, in: record)
                } label: {
                    Label("병합", systemImage: "arrow.triangle.merge")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func speakerRenameBinding(for label: String) -> Binding<String> {
        Binding(
            get: { speakerRenameDrafts[label] ?? label },
            set: { speakerRenameDrafts[label] = $0 }
        )
    }

    private func speakerMergeTargetBinding(for label: String, labels: [String]) -> Binding<String> {
        Binding(
            get: { speakerMergeTarget(for: label, labels: labels) },
            set: { speakerMergeTargets[label] = $0 }
        )
    }

    private func speakerMergeTarget(for label: String, labels: [String]) -> String {
        if let selected = speakerMergeTargets[label],
           selected != label,
           labels.contains(selected) {
            return selected
        }
        return labels.first { $0 != label } ?? label
    }

    private func renameSpeaker(_ label: String, in record: MeetingRecord) {
        guard let target = SpeakerLabel.normalized(speakerRenameDrafts[label] ?? label),
              target != label else {
            return
        }
        let labels = SpeakerLabelEditing.labels(in: record.transcript)
        guard !labels.contains(target) else {
            return
        }
        saveSpeakerEdit(source: label, target: target, kind: "rename", in: record)
    }

    private func mergeSpeaker(_ label: String, labels: [String], in record: MeetingRecord) {
        let target = speakerMergeTarget(for: label, labels: labels)
        guard target != label else {
            return
        }
        saveSpeakerEdit(source: label, target: target, kind: "merge", in: record)
    }

    private func enrollSpeaker(label: String, name: String, record: MeetingRecord) {
        let current = store.meetings.first(where: { $0.id == record.id }) ?? record
        guard let entry = current.speakerEmbeddings?.first(where: {
            SpeakerLabel.normalized($0.speakerLabel) == SpeakerLabel.normalized(label)
        }) else {
            speakerEditError = nil
            speakerEnrollNotice = (id: record.id, message: "등록할 화자 임베딩이 없어요.", isError: true)
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            speakerEditError = nil
            speakerEnrollNotice = (id: record.id, message: "등록할 이름을 입력해 주세요.", isError: true)
            return
        }
        guard !SpeakerLabel.isAutoGenerated(trimmedName) else {
            speakerEditError = nil
            speakerEnrollNotice = (id: record.id, message: "실제 이름을 입력해 주세요.", isError: true)
            return
        }
        // usablePrints가 현재 modelID로 필터링하므로 같은 모델 공간의 동명만 차단한다.
        if VoiceprintStore.shared.voiceprints.contains(where: { $0.displayName == trimmedName && $0.embeddingModelID == entry.embeddingModelID }) {
            speakerEditError = nil
            speakerEnrollNotice = (id: record.id, message: "'\(trimmedName)'은 이미 등록된 이름이에요.", isError: true)
            return
        }

        Log.store.info("voiceprint enroll start dimensions=\(entry.embedding.count, privacy: .public) model=\(entry.embeddingModelID, privacy: .public)")
        let ok = VoiceprintStore.shared.add(
            name: trimmedName,
            embedding: entry.embedding,
            embeddingModelID: entry.embeddingModelID
        )
        if ok {
            speakerEditError = nil
            speakerEnrollNotice = (id: record.id, message: "보이스프린트를 등록했어요.", isError: false)
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(3))
                if speakerEnrollNotice?.id == record.id {
                    speakerEnrollNotice = nil
                }
            }
            Log.store.info("voiceprint enroll success dimensions=\(entry.embedding.count, privacy: .public) model=\(entry.embeddingModelID, privacy: .public)")
        } else {
            speakerEditError = nil
            speakerEnrollNotice = (id: record.id, message: "보이스프린트 등록에 실패했어요.", isError: true)
            Log.store.error("voiceprint enroll failed dimensions=\(entry.embedding.count, privacy: .public) model=\(entry.embeddingModelID, privacy: .public)")
        }
    }

    private func reassignSegment(_ segmentID: Segment.ID, to target: String, in record: MeetingRecord) {
        saveSegmentSpeakerReassignment(segmentID: segmentID, target: target, kind: "reassign", in: record)
    }

    private func reassignSegmentToNewSpeaker(_ segmentID: Segment.ID, in record: MeetingRecord) {
        let current = store.meetings.first(where: { $0.id == record.id }) ?? record
        let target = SpeakerLabelEditing.nextNewSpeakerLabel(existing: SpeakerLabelEditing.labels(in: current.transcript))
        saveSegmentSpeakerReassignment(segmentID: segmentID, target: target, kind: "reassign-new", in: record)
    }

    private func saveSpeakerEdit(source: String, target: String, kind: String, in record: MeetingRecord) {
        let current = store.meetings.first(where: { $0.id == record.id }) ?? record
        var updated = current
        updated.transcript = SpeakerLabelEditing.replacingSpeaker(source, with: target, in: current.transcript)
        updated.speakerEmbeddings = SpeakerLabelEditing.replacingSpeakerLabel(source, with: target, in: current.speakerEmbeddings)

        let changedSegmentCount = zip(current.transcript, updated.transcript).reduce(0) { count, pair in
            count + (pair.0.speaker == pair.1.speaker ? 0 : 1)
        }
        guard changedSegmentCount > 0 else {
            return
        }

        speakerEditError = nil
        speakerEnrollNotice = nil
        Log.store.info("speaker label edit start kind=\(kind, privacy: .public) changedSegments=\(changedSegmentCount, privacy: .public)")
        switch store.save(updated) {
        case .success:
            speakerRenameDrafts.removeValue(forKey: source)
            speakerMergeTargets.removeValue(forKey: source)
            Log.store.info("speaker label edit success kind=\(kind, privacy: .public) changedSegments=\(changedSegmentCount, privacy: .public)")
        case .skippedEmpty:
            speakerEditError = (id: record.id, message: "저장할 전사 내용이 없어요.")
            Log.store.error("speaker label edit skipped kind=\(kind, privacy: .public)")
        case .failed:
            speakerEditError = (id: record.id, message: "화자 변경을 저장하지 못했어요.")
            Log.store.error("speaker label edit failed kind=\(kind, privacy: .public)")
        }
    }

    private func saveSegmentSpeakerReassignment(
        segmentID: Segment.ID,
        target: String,
        kind: String,
        in record: MeetingRecord
    ) {
        let current = store.meetings.first(where: { $0.id == record.id }) ?? record
        var updated = current
        updated.transcript = SpeakerLabelEditing.reassignSegment(id: segmentID, to: target, in: current.transcript)
        // 구간 재배정은 speakerEmbeddings를 건드리지 않는다. 기존 라벨로의 재배정은 centroid 소유를 바꾸지 않고, '새 화자'로 만든 라벨은 임베딩 없이 수동 생성된 것이라 대응 centroid가 애초에 없다(그 라벨은 등록 버튼이 비활성된다).

        let changedSegmentCount = zip(current.transcript, updated.transcript).reduce(0) { count, pair in
            count + (pair.0.speaker == pair.1.speaker ? 0 : 1)
        }
        guard changedSegmentCount > 0 else {
            return
        }

        speakerEditError = nil
        speakerEnrollNotice = nil
        Log.store.info("speaker label edit start kind=\(kind, privacy: .public) changedSegments=\(changedSegmentCount, privacy: .public)")
        switch store.save(updated) {
        case .success:
            Log.store.info("speaker label edit success kind=\(kind, privacy: .public) changedSegments=\(changedSegmentCount, privacy: .public)")
        case .skippedEmpty:
            speakerEditError = (id: record.id, message: "저장할 전사 내용이 없어요.")
            Log.store.error("speaker label edit skipped kind=\(kind, privacy: .public)")
        case .failed:
            speakerEditError = (id: record.id, message: "화자 변경을 저장하지 못했어요.")
            Log.store.error("speaker label edit failed kind=\(kind, privacy: .public)")
        }
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
                .buttonStyle(ProminentActionButtonStyle())
                .disabled(query.isEmpty || !relatedInfo.isAnyConfigured || relatedInfo.isSearching)
                .help(relatedInfo.isAnyConfigured ? "현재 회의 요약과 전사로 Notion·Confluence를 검색해요." : "설정에서 Notion 또는 Confluence를 먼저 연결하세요.")
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
                    Text("관련 문서를 찾고 있어요.")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
            } else if !relatedInfo.isAnyConfigured {
                Text("설정에서 검색 소스를 연결하면 회의 내용으로 관련 문서를 찾을 수 있어요.")
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
                Text("조회 버튼을 누르면 현재 회의 기준으로 검색해요.")
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

    // MARK: - Search kind filter

    /// 검색 결과를 chunk 종류로 좁히는 필터.
    /// 칩 라벨 ↔ Kind 집합 매핑:
    ///   요약  → summary, section, decision, actionItem, openQuestion
    ///   전사  → transcript
    ///   주제  → topic, title, keywords
    ///   회의 자료 → document
    private enum SearchKindFilter: CaseIterable {
        case all
        case summary
        case transcript
        case topic
        case document

        var label: String {
            switch self {
            case .all: return "전체"
            case .summary: return "요약"
            case .transcript: return "전사"
            case .topic: return "주제"
            case .document: return MeetingSearchChunk.Kind.document.label
            }
        }

        /// 이 필터가 허용하는 MeetingSearchChunk.Kind 집합. nil이면 전체 허용.
        var allowedKinds: Set<MeetingSearchChunk.Kind>? {
            switch self {
            case .all: return nil
            case .summary: return [.summary, .section, .decision, .actionItem, .openQuestion]
            case .transcript: return [.transcript]
            case .topic: return [.topic, .title, .keywords]
            case .document: return [.document]
            }
        }

        func matches(_ result: MeetingSearchResult) -> Bool {
            guard let kinds = allowedKinds else { return true }
            return kinds.contains(result.chunk.kind)
        }
    }

    // MARK: - Detail content state

    private enum DetailContent {
        case live
        case searchAnswer
        case preview(MeetingRecord)
        case empty
    }

    /// 오른쪽 디테일 영역에 무엇을 표시할지 결정하는 단일 분기점.
    /// 우선순위: 라이브 회의 > AI 답변 > 회의 미리보기 > 빈 상태.
    private var detailContent: DetailContent {
        if showingLiveMeeting, hasLiveMeeting {
            return .live
        }
        if isSearching, showingSearchAnswerDetail {
            return .searchAnswer
        }
        if let record = selectedRecord {
            return .preview(record)
        }
        return .empty
    }

    /// showingSearchAnswerDetail / searchAnswerCitationAnchor를 함께 닫는 헬퍼.
    /// 흩어진 리셋을 한 곳에서 관리한다.
    private func dismissSearchAnswerPresentation() {
        showingSearchAnswerDetail = false
        searchAnswerCitationAnchor = nil
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
        return "전사를 기다리는 중이에요"
    }

    private var liveRelatedSearchQuery: String {
        compactRelatedQuery(liveSegments.suffix(4).map(\.text).joined(separator: " "))
    }

    private var displayedMeetings: [MeetingRecord] {
        guard isSearching else { return store.meetings }
        let recordsByID = Dictionary(uniqueKeysWithValues: store.meetings.map { ($0.id, $0) })
        var seen = Set<UUID>()
        return meetingSearchResults.compactMap { result in
            guard !seen.contains(result.meetingID), let record = recordsByID[result.meetingID] else {
                return nil
            }
            seen.insert(result.meetingID)
            return record
        }
    }

    private var selectedRecord: MeetingRecord? {
        if let selectedID, let record = displayedMeetings.first(where: { $0.id == selectedID }) {
            return record
        }
        return displayedMeetings.first
    }

    private func rebuildSearchIndex() {
        // 디스크 인덱스가 있고 현재 meetings와 ID 집합이 일치하면 재빌드를 생략한다.
        // MeetingSearchIndexStore.load()는 schemaVersion·chunkingVersion 불일치 시 nil을 반환한다.
        let indexStore = MeetingSearchIndexStore(directory: store.storageDirectory)
        if let loaded = indexStore.load() {
            let indexedIDs = Set(loaded.chunks.map(\.meetingID))
            let currentIDs = Set(store.meetings.map(\.id))
            if indexedIDs == currentIDs {
                searchIndex = loaded
                refreshSearchResults()
                embeddingViewModel.rebuildEmbeddingIndex(from: loaded)
                return
            }
        }
        searchIndex = MeetingSearchIndex(records: store.meetings)
        refreshSearchResults()
        embeddingViewModel.rebuildEmbeddingIndex(from: searchIndex)
    }


    private func refreshSearchResults() {
        guard isSearching else {
            meetingSearchResults = []
            allMeetingSearchResults = []
            activeSearchFilter = .all
            return
        }
        let queryTokens = MeetingSearchIndex.queryTerms(trimmedSearch)
        let usableEntries = GlossaryStore.shared.entries.filter(\.isUsable)
        let expandedTokens = GlossaryQueryExpander.expand(queryTokens: queryTokens, entries: usableEntries)
        let tokenResults = searchIndex.search(trimmedSearch, limit: Int.max, expandedTokens: expandedTokens)
        let all: [MeetingSearchResult]
        if let embIdx = embeddingViewModel.embeddingIndex {
            let queryVector = LocalHashEmbeddingProvider.vector(for: trimmedSearch)
            all = MeetingSearchEmbeddingIndex.rerank(
                results: tokenResults,
                queryVector: queryVector,
                embeddings: embIdx
            )
        } else {
            all = tokenResults
        }
        allMeetingSearchResults = all
        meetingSearchResults = activeSearchFilter == .all ? all : all.filter { activeSearchFilter.matches($0) }
    }

    private func selectSearchAnswerCitation(_ citation: MeetingSearchAnswerCitation) {
        selectedID = citation.meetingID
        showingLiveMeeting = false
        showingSearchAnswerDetail = false
        detailTab = citation.kind == .transcript ? .transcript : .summary
        searchAnswerCitationAnchor = SearchAnswerCitationAnchor(
            meetingID: citation.meetingID,
            sourcePath: citation.sourcePath
        )
    }

    // MARK: - Search answer citation deep link

    private struct SearchAnswerCitationAnchor: Equatable {
        let meetingID: UUID
        let sourcePath: String
    }

    private static let searchAnswerLeadAnchorID = "meeting-lead-summary"

    private func outcomeAnchorID(_ group: String) -> String {
        "meeting-outcome-\(group)"
    }

    private func transcriptAnchorID(_ index: Int) -> String {
        "transcript-segment-\(index)"
    }

    /// sourcePath("summary.sections[2]" 등)를 미리보기의 스크롤 앵커 ID로 변환한다.
    /// 결정/할일/질문은 UI가 빈 항목을 걸러 행 인덱스가 어긋날 수 있어 그룹 단위로 이동한다.
    private func citationScrollTargetID(_ anchor: SearchAnswerCitationAnchor) -> String? {
        let path = anchor.sourcePath
        if path == "summary.lead" || path == "title" || path == "topic" || path == "summary.keywords" {
            return Self.searchAnswerLeadAnchorID
        }
        if let index = indexedSourcePath(path, prefix: "summary.sections") {
            return tocAnchorID(index)
        }
        if indexedSourcePath(path, prefix: "summary.decisions") != nil {
            return outcomeAnchorID("decisions")
        }
        if indexedSourcePath(path, prefix: "summary.actionItems") != nil {
            return outcomeAnchorID("actions")
        }
        if indexedSourcePath(path, prefix: "summary.openQuestions") != nil {
            return outcomeAnchorID("questions")
        }
        if let index = indexedSourcePath(path, prefix: "transcript") {
            return transcriptAnchorID(index)
        }
        return nil
    }

    private func indexedSourcePath(_ path: String, prefix: String) -> Int? {
        guard path.hasPrefix("\(prefix)["), path.hasSuffix("]") else { return nil }
        return Int(path.dropFirst(prefix.count + 1).dropLast())
    }

    private func isCitationHighlightTarget(_ id: String) -> Bool {
        guard let anchor = searchAnswerCitationAnchor else { return false }
        return citationScrollTargetID(anchor) == id
    }

    private func citationCardBorder(_ id: String) -> Color {
        isCitationHighlightTarget(id) ? Color.accentColor.opacity(0.55) : LibraryPalette.border
    }

    /// 행/그룹용 하이라이트. 음수 패딩으로 레이아웃을 건드리지 않고 칠만 확장한다.
    private func citationHighlightBackground(_ id: String, inset: CGFloat = -6) -> some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(isCitationHighlightTarget(id) ? LibraryPalette.accentSoft : Color.clear)
            .padding(inset)
    }

    private func scrollToCitationAnchor(in record: MeetingRecord, proxy: ScrollViewProxy) {
        guard let anchor = searchAnswerCitationAnchor,
              anchor.meetingID == record.id,
              let targetID = citationScrollTargetID(anchor) else { return }
        // 디테일 → 미리보기 전환 직후에는 앵커 뷰가 아직 레이아웃 전이라 한 틱 미룬다.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    private func primaryMatch(for record: MeetingRecord) -> MeetingSearchMatch {
        if isSearching, let result = meetingSearchResults.first(where: { $0.meetingID == record.id }) {
            return MeetingSearchMatch(badge: result.label, text: result.preview)
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

    /// 회의 선택이 바뀌면 이전 record에 묶인 제거 상태를 초기화한다(transcriptEdit*와 대칭).
    /// 현재 제거는 동기 실행이라 잔류가 드물지만, 이후 async 전환 시 savingID 고착을 막는다.
    private func cancelDocumentRemoval() {
        documentRemovalSavingID = nil
        documentRemovalError = nil
    }

    private func requestDocumentRemoval(for record: MeetingRecord) {
        guard !hasLiveMeeting else {
            return
        }
        documentRemovalError = nil
        documentRemovalRecordID = record.id
        showingDocumentRemovalConfirmation = true
    }

    private func confirmDocumentRemoval() {
        guard let recordID = documentRemovalRecordID else {
            return
        }
        documentRemovalRecordID = nil
        showingDocumentRemovalConfirmation = false
        removeStoredDocument(recordID)
    }

    private func removeStoredDocument(_ recordID: UUID) {
        guard !hasLiveMeeting else {
            documentRemovalError = (id: recordID, message: "진행 중인 회의를 종료한 뒤 제거할 수 있어요.")
            return
        }

        let documentChars = store.meetings.first(where: { $0.id == recordID })?.document?.count ?? 0
        documentRemovalSavingID = recordID
        documentRemovalError = nil
        Log.store.info("meeting document remove start documentChars=\(documentChars, privacy: .public)")

        switch MeetingDocumentRemoval.removeDocument(recordID: recordID, in: store) {
        case .success:
            documentRemovalSavingID = nil
            documentRemovalError = nil
            Log.store.info("meeting document remove success documentChars=\(documentChars, privacy: .public)")
        case .skippedEmpty, .failed:
            // skippedEmpty는 전사·요약이 모두 비어야 발생하는데, 회의 자료 섹션은 document가 있을 때만 보이고
            // 저장된 record는 이미 비어있지 않으므로 사실상 도달하지 않는다. 두 경우 모두 단일 재시도 안내로 통합한다.
            documentRemovalSavingID = nil
            documentRemovalError = (id: recordID, message: "회의 자료를 제거하지 못했어요. 다시 시도해 보세요.")
            Log.store.error("meeting document remove failed documentChars=\(documentChars, privacy: .public)")
        }
    }

    private func reSummaryHelpText(for record: MeetingRecord) -> String {
        if hasLiveMeeting {
            return "진행 중인 회의를 종료한 뒤 다시 요약할 수 있어요."
        }
        if let retryingRecordID, retryingRecordID != record.id {
            return "다른 회의를 다시 요약하는 중이에요. 끝나면 다시 시도할 수 있어요."
        }
        if retryingRecordID == record.id {
            return "요약을 다시 만드는 중이에요."
        }
        return "현재 회의 전사로 요약을 다시 만들어요."
    }

    private func presentReSummarySheet(for record: MeetingRecord) {
        guard !hasLiveMeeting, retryingRecordID == nil else { return }
        retryError = nil
        reSummaryGlossaryRecord = record
    }

    @MainActor
    private func retrySummary(for record: MeetingRecord, glossary: String) async -> String? {
        guard !hasLiveMeeting else {
            return "진행 중인 회의를 종료한 뒤 다시 요약할 수 있어요."
        }
        guard retryingRecordID == nil else {
            return "이미 다시 요약하는 중이에요."
        }

        retryError = nil
        retryingRecordID = record.id
        let useCase = MeetingSummaryRetryUseCase()
        let result = await useCase.retry(record: record, glossary: glossary)
        if retryingRecordID == record.id {
            retryingRecordID = nil
        }

        if case .failure(let reason) = result {
            let message = retryFailureMessage(for: reason)
            retryError = (id: record.id, message: message)
            return message
        }
        retryError = nil
        return nil
    }

    private func retryFailureMessage(for reason: SummaryRetryFailureReason) -> String {
        if case .saveFailed = reason {
            return "다시 요약 결과 저장에 실패했어요. 다시 시도해 보세요."
        }
        return "요약을 다시 만들지 못했어요. 다시 시도해 보세요."
    }

    private func copyMarkdown(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func copySearchAnswer(_ answer: MeetingSearchAnswer) {
        let citationText = answer.citations.map { citation in
            let meta = searchAnswerCitationMeta(citation)
            return "[\(citation.number)] \(citation.meetingTitle) · \(meta)\n\(citation.preview)"
        }
        let text = ([answer.text, "근거", citationText.joined(separator: "\n\n")]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            .joined(separator: "\n\n")
        copyMarkdown(text)
    }

    private func copyLiveSummary() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(liveRunningSummary, forType: .string)
    }

    private func copyLiveTranscript() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(liveSegments.map(\.text).joined(separator: "\n"), forType: .string)
    }

    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func detectUnfinishedFileImportIfNeeded() {
        guard !didReportUnfinishedImport else { return }
        guard let fileName = MeetingFileImportUseCase.pendingImportFileName(in: fileImportDefaults) else { return }

        unfinishedImportFileName = fileName
        didReportUnfinishedImport = true
        Log.importer.error("pending import marker found file=\(fileName, privacy: .public)")
    }

    private func dismissUnfinishedFileImport() {
        MeetingFileImportUseCase.clearPendingImportMarker(in: fileImportDefaults)
        unfinishedImportFileName = nil
    }

    private func selectFileForImport() {
        guard !hasLiveMeeting, !fileImportUseCase.state.isRunning else { return }

        let panel = NSOpenPanel()
        panel.title = "파일로 회의록 만들기"
        panel.prompt = "가져오기"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = MeetingFileImportUseCase.supportedContentTypes
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            // 파일 선택 후 주제·용어집 입력 시트를 띄운다.
            fileImportSetupURL = url
        }
    }

    private func startFileImport(
        url: URL,
        topic: String?,
        glossary: String,
        expectedSpeakerCount: Int?,
        diarizeSpeakers: Bool = false
    ) {
        fileImportSetupURL = nil
        fileImportTask?.cancel()
        fileImportTask = Task { @MainActor in
            do {
                _ = try await fileImportUseCase.importFile(
                    url,
                    topic: topic.flatMap { $0.isEmpty ? nil : $0 },
                    glossary: glossary,
                    expectedSpeakerCount: expectedSpeakerCount,
                    diarizeSpeakers: diarizeSpeakers,
                    enrolledVoiceprints: VoiceprintStore.shared.usablePrints(
                        forModelID: FluidAudioOfflineDiarizationProvider.embeddingModelID
                    )
                )
            } catch is CancellationError {
                // 취소 상태는 use-case가 이미 반영한다.
            } catch {
                // 실패 상태는 use-case가 이미 반영한다.
            }
        }
    }

    private func fileImportIcon(_ stage: MeetingFileImportStage) -> some View {
        let symbol: String
        let color: Color
        switch stage {
        case .idle:
            symbol = "tray"
            color = .secondary
        case .analyzing, .transcribing, .correcting, .summarizing, .saving:
            symbol = "arrow.triangle.2.circlepath"
            color = .accentColor
        case .completed:
            symbol = "checkmark.circle.fill"
            color = .green
        case .failed:
            symbol = "exclamationmark.triangle.fill"
            color = .red
        case .cancelled:
            symbol = "xmark.circle.fill"
            color = .secondary
        }
        return Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(color)
            .frame(width: 20, height: 20)
    }

    private func fileImportBackground(_ stage: MeetingFileImportStage) -> Color {
        switch stage {
        case .completed:
            return Color.green.opacity(0.08)
        case .failed:
            return Color.red.opacity(0.08)
        case .cancelled:
            return Color.secondary.opacity(0.08)
        case .idle, .analyzing, .transcribing, .correcting, .summarizing, .saving:
            return LibraryPalette.elevated
        }
    }

    private func fileImportBorder(_ stage: MeetingFileImportStage) -> Color {
        switch stage {
        case .completed:
            return Color.green.opacity(0.25)
        case .failed:
            return Color.red.opacity(0.25)
        case .idle, .analyzing, .transcribing, .correcting, .summarizing, .saving, .cancelled:
            return LibraryPalette.border
        }
    }
}

// ConfluenceExportSheet and ConfluenceExportSheetPresentation moved to ConfluenceExportSheet.swift
