import AppKit
import SwiftUI

private enum ConfluenceContextStatusTone {
    case neutral
    case success
    case warning
    case error
}

/// "녹음 시작" 시 뜨는 회의 시작 시트.
/// 주제·용어집을 입력받아 그 회의 세션의 교정 맥락으로 쓴다. 비우고 시작해도 된다.
public struct MeetingSetupView: View {
    @ObservedObject private var confluence = ConfluenceService.shared
    @ObservedObject private var glossaryStore = GlossaryStore.shared
    @ObservedObject private var notion = NotionMCPService.shared
    @State private var topic: String = ""
    @State private var glossary: String = ""
    @State private var document: String = ""
    @State private var showGlossary = false
    @State private var showDocument = false
    @State private var audioInputMode: AudioInputMode = .microphone
    @State private var audioReadiness: AudioInputReadiness = .ready(for: .microphone)
    @State private var selectedGlossaryCategories: Set<String> = []
    @State private var confluenceDocuments: [ConfluenceService.ContextDocument] = []
    @State private var confluenceStatus: String?
    @State private var confluenceStatusTone: ConfluenceContextStatusTone = .neutral
    @State private var isSearchingConfluence = false
    @State private var attachedFiles: [AttachedDocument] = []
    @State private var isImportingFiles = false
    @State private var ingestingFileCount = 0
    @State private var documentAttachError: String?
    @State private var notionURLInput: String = ""

    private let onStart: (String, String, String, AudioInputMode) -> Void
    private let onCancel: () -> Void
    private let audioReadinessChecker: AudioInputReadinessChecker
    private let glossarySelectionDefaults: UserDefaults

    public init(
        onStart: @escaping (String, String, String, AudioInputMode) -> Void,
        onCancel: @escaping () -> Void,
        audioReadinessChecker: AudioInputReadinessChecker = .live,
        glossarySelectionDefaults: UserDefaults = .standard
    ) {
        self.onStart = onStart
        self.onCancel = onCancel
        self.audioReadinessChecker = audioReadinessChecker
        self.glossarySelectionDefaults = glossarySelectionDefaults
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("새 회의")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                Text("바로 녹음할 수 있어요")
                    .font(.title3.weight(.bold))
                Text("주제만 적어도 충분해요. 필요한 정보는 선택해서 더하세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("회의 주제")
                    .font(.subheadline.weight(.medium))
                TextField("예: 검색 고도화 설계 리뷰", text: $topic)
                    .textFieldStyle(.roundedBorder)
            }

            audioInputPicker

            glossaryContextEditor

            documentContextEditor

            if ingestingFileCount > 0 {
                Text("처리 중인 첨부 \(ingestingFileCount)개는 제외돼요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            HStack {
                Spacer()
                Button("닫기") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("녹음 시작") { onStart(topic, combinedGlossary, combinedDocument, audioInputMode) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(ProminentActionButtonStyle())
                    .disabled(!audioReadiness.canStartRecording)
            }
        }
        .padding(20)
        .frame(width: 440)
        .task(id: audioInputMode) {
            await refreshAudioReadiness(for: audioInputMode)
        }
        .onAppear {
            restoreGlossarySelection()
        }
        .onChange(of: selectedGlossaryCategories) { _, _ in
            saveGlossarySelection()
        }
        .onChange(of: glossaryStore.categorySelectionNames) { _, _ in
            pruneGlossarySelection()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await refreshAudioReadiness(for: audioInputMode) }
        }
    }

    private var audioInputPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("입력")
                .font(.subheadline.weight(.medium))
            Picker("입력", selection: $audioInputMode) {
                ForEach(AudioInputMode.selectableCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 6) {
                Image(systemName: audioInputMode.requiresScreenCapturePermission ? "rectangle.on.rectangle" : "mic")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(audioInputMode.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            audioReadinessRow
        }
    }

    private var audioReadinessRow: some View {
        HStack(alignment: .top, spacing: 8) {
            readinessIcon
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(audioReadiness.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(audioReadinessColor)
                Text(audioReadiness.detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let actionTitle = audioReadiness.actionTitle {
                    Button(actionTitle) {
                        Task { await requestAudioPermissionAndRefresh() }
                    }
                    .font(.caption2)
                    .buttonStyle(.link)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(audioReadinessColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @ViewBuilder
    private var readinessIcon: some View {
        if audioReadiness.state == .checking {
            ProgressView()
                .controlSize(.mini)
        } else {
            Image(systemName: readinessIconName)
                .font(.caption)
                .foregroundColor(audioReadinessColor)
        }
    }

    private var readinessIconName: String {
        switch audioReadiness.state {
        case .checking:
            return "hourglass"
        case .ready:
            return "checkmark.circle.fill"
        case .permissionRequired:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }

    private var audioReadinessColor: Color {
        switch audioReadiness.state {
        case .checking:
            return .secondary
        case .ready:
            return .green
        case .permissionRequired:
            return .orange
        case .unavailable:
            return .red
        }
    }

    private var glossaryContextEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showGlossary.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showGlossary ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Text("용어집")
                        .font(.subheadline.weight(.medium))
                    Text(glossaryBadgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showGlossary {
                GlossarySetSelectionSection(
                    glossaryStore: glossaryStore,
                    selectedCategories: $selectedGlossaryCategories,
                    manualGlossary: $glossary,
                    manualTitle: "이번 회의 용어"
                )
                .padding(.leading, 18)
            }
        }
    }

    private var documentContextEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                showDocument.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: showDocument ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                        .frame(width: 12)
                    Text("참고 문서")
                        .font(.subheadline.weight(.medium))
                    Text(documentBadgeText)
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDocument {
                VStack(alignment: .leading, spacing: 8) {
                    fileAttachSection

                    Divider().padding(.vertical, 2)

                    Text("직접 입력")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    TextEditor(text: $document)
                        .font(.body)
                        .frame(height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

                    Divider().padding(.vertical, 2)

                    HStack(spacing: 6) {
                        Text("Confluence")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                        Image(systemName: confluence.isConfigured ? "link.circle.fill" : "exclamationmark.circle")
                            .font(.caption2)
                            .foregroundColor(confluence.isConfigured ? .green : .secondary)
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task { await fetchConfluenceContext() }
                        } label: {
                            if isSearchingConfluence {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("조회 중")
                                }
                            } else {
                                Label("Confluence 조회", systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(!canSearchConfluence)

                        if !confluence.isConfigured {
                            Text("설정에서 Confluence를 먼저 연결하세요.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if let confluenceStatus {
                        Text(confluenceStatus)
                            .font(.caption2)
                            .foregroundColor(confluenceStatusColor)
                    }

                    if !confluenceDocuments.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(confluenceDocuments) { doc in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(doc.title)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(doc.text)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.07))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                    }

                    cloudBoundaryNote
                }
                .padding(.leading, 18)
            }
        }
        .fileImporter(
            isPresented: $isImportingFiles,
            allowedContentTypes: FileDocumentExtractor.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                Task { await ingestFiles(urls) }
            case .failure(let error):
                documentAttachError = error.localizedDescription
            }
        }
    }

    /// 파일 첨부 진입 + 첨부 목록 + 처리중/오류 상태.
    private var fileAttachSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    isImportingFiles = true
                } label: {
                    Label("파일 추가", systemImage: "doc.badge.plus")
                }
                Text("PDF · 이미지 · 텍스트(md/txt)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Notion 페이지 링크 붙여넣기", text: $notionURLInput)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!notion.isConnected)
                    .onSubmit { Task { await ingestNotionPage() } }
                Button("가져오기") { Task { await ingestNotionPage() } }
                    .disabled(!notion.isConnected || notionURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !notion.isConnected {
                Text("설정에서 Notion을 연결하면 페이지를 가져올 수 있어요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            if attachedFiles.isEmpty && ingestingFileCount == 0 {
                Text("회의 안건·자료를 추가하면 교정과 요약에 참고해요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            ForEach(attachedFiles) { attached in
                attachmentRow(attached)
            }

            if ingestingFileCount > 0 {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("문서에서 글자 읽는 중 \(ingestingFileCount)개")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            if let documentAttachError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(documentAttachError)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
    }

    private func attachmentRow(_ attached: AttachedDocument) -> some View {
        HStack(spacing: 8) {
            Image(systemName: attachmentIcon(for: attached.sourceKind))
                .font(.caption)
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(attached.sourceLabel ?? attached.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Text("완료 · \(attached.text.count)자")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                attachedFiles.removeAll { $0.id == attached.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("첨부 제거")
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func attachmentIcon(for sourceKind: SourceKind) -> String {
        switch sourceKind {
        case .notion:
            return "link"
        case .confluence:
            return "doc.richtext"
        case .manual:
            return "square.and.pencil"
        case .file:
            return "doc.text"
        }
    }

    /// 클라우드 전송 경계: 데이터 흐름을 설명하는 단일 안내 지점.
    private var cloudBoundaryNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "lock.shield")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text("파일·OCR 처리는 이 기기에서 이뤄져요. 교정·요약을 켜면 문서 내용이 클라우드 AI로 전송될 수 있어요.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.top, 4)
    }

    private var documentBadgeText: String {
        let count = attachedFiles.count + confluenceDocuments.count
        if count > 0 { return "\(count)개" }
        return "선택"
    }

    private var canSearchConfluence: Bool {
        confluence.isConfigured
            && !confluenceQuery.isEmpty
            && !isSearchingConfluence
    }

    private var confluenceStatusColor: Color {
        switch confluenceStatusTone {
        case .neutral:
            return .secondary
        case .success:
            return .accentColor
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var glossaryBadgeText: String {
        GlossarySetSelectionPersistence.badgeText(
            selectedCategories: selectedGlossaryCategories,
            manualGlossary: glossary,
            availableCategoryNames: glossarySelectionCategoryNames
        )
    }

    private var selectedGlossaryEntries: [GlossaryEntry] {
        glossaryStore.entries(inCategories: selectedGlossaryCategories)
    }

    private var combinedGlossary: String {
        GlossaryContextResolver().resolve(manualGlossary: glossary, selectedEntries: selectedGlossaryEntries)
    }

    private var glossarySelectionCategoryNames: [String] {
        glossaryStore.categorySelectionNames
    }

    private func restoreGlossarySelection() {
        selectedGlossaryCategories = GlossarySetSelectionPersistence.restore(
            from: glossarySelectionDefaults,
            availableCategoryNames: glossarySelectionCategoryNames
        )
    }

    private func saveGlossarySelection() {
        GlossarySetSelectionPersistence.saveSelection(
            selectedGlossaryCategories,
            availableCategoryNames: glossarySelectionCategoryNames,
            to: glossarySelectionDefaults
        )
    }

    private func pruneGlossarySelection() {
        let pruned = GlossarySetSelectionPersistence.prunedSelection(
            selectedGlossaryCategories,
            availableCategoryNames: glossarySelectionCategoryNames,
            defaults: glossarySelectionDefaults
        )
        guard pruned != selectedGlossaryCategories else { return }
        selectedGlossaryCategories = pruned
    }

    private var confluenceQuery: String {
        let joined = [topic, document]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard joined.count > 240 else { return joined }
        return String(joined.prefix(240))
    }

    private var combinedDocument: String {
        // 결합 순서: 직접 입력 → 첨부 파일 → Confluence. 처리 완료된 첨부만 포함한다(pending 제외).
        let manual = document.trimmingCharacters(in: .whitespacesAndNewlines)
        let fileBlocks = attachedFiles.map { $0.text }
        let confluenceBlock = ConfluenceService.contextBlock(from: confluenceDocuments)
        return ([manual] + fileBlocks + [confluenceBlock])
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    /// 파일 첨부 수집. 성공분만 목록에 추가(id 중복 제외)하고 실패는 안내로 남긴다(fail-soft).
    @MainActor
    private func ingestFiles(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        documentAttachError = nil
        ingestingFileCount += urls.count
        Log.importer.info("document attach start count=\(urls.count, privacy: .public)")
        defer { ingestingFileCount = max(0, ingestingFileCount - urls.count) }

        let result = await DocumentIngestionUseCase().ingest(urls: urls)
        for attached in result.documents where !attachedFiles.contains(where: { $0.id == attached.id }) {
            attachedFiles.append(attached)
            Log.importer.info("document attach ok sourceKind=\(String(describing: attached.sourceKind), privacy: .public) chars=\(attached.text.count, privacy: .public)")
        }
        if let failure = result.failures.first {
            documentAttachError = failure.reason.errorDescription
            Log.importer.error("document attach failed reason=\(String(describing: failure.reason), privacy: .public)")
        }
    }

    /// Notion 페이지 링크 수집. 기존 Notion 연결을 재사용하고, 성공 시 첨부 목록에 추가한다(fail-soft).
    @MainActor
    private func ingestNotionPage() async {
        let url = notionURLInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        documentAttachError = nil
        ingestingFileCount += 1
        Log.importer.info("notion attach start")
        defer { ingestingFileCount = max(0, ingestingFileCount - 1) }

        let result = await notion.fetchPageDocument(url: url)
        switch result {
        case .success(let attached):
            if !attachedFiles.contains(where: { $0.id == attached.id }) {
                attachedFiles.append(attached)
                Log.importer.info("notion attach ok chars=\(attached.text.count, privacy: .public)")
            }
            notionURLInput = ""
        case .failure(let reason):
            documentAttachError = reason.errorDescription
            Log.importer.error("notion attach failed reason=\(String(describing: reason), privacy: .public)")
        }
    }

    private func fetchConfluenceContext() async {
        let query = confluenceQuery
        guard !query.isEmpty else {
            confluenceStatus = "조회할 회의 주제나 안건을 먼저 입력하세요."
            confluenceStatusTone = .neutral
            return
        }
        guard confluence.isConfigured else {
            confluenceStatus = "설정에서 Confluence를 먼저 연결하세요."
            confluenceStatusTone = .neutral
            return
        }

        isSearchingConfluence = true
        confluenceStatus = nil
        confluenceStatusTone = .neutral
        defer { isSearchingConfluence = false }

        let result = await confluence.searchContext(query, limit: 3)
        confluenceDocuments = result.documents
        switch result.failure {
        case .unauthorized, .forbidden:
            confluenceStatus = "Confluence 연결이 거부됐어요. 설정 > 검색 소스에서 [연결 확인]을 해주세요."
            confluenceStatusTone = .warning
        case .network:
            confluenceStatus = "Confluence에 연결하지 못했어요. 네트워크를 확인해 주세요."
            confluenceStatusTone = .error
        case nil:
            confluenceStatus = result.documents.isEmpty
                ? "관련 Confluence 문서를 찾지 못했어요."
                : "Confluence 문서 \(result.documents.count)개를 참고자료로 사용해요."
            confluenceStatusTone = result.documents.isEmpty ? .neutral : .success
        }
    }

    @MainActor
    private func refreshAudioReadiness(for mode: AudioInputMode) async {
        audioReadiness = .checking(for: mode)
        let readiness = await audioReadinessChecker.readiness(for: mode)
        guard audioInputMode == mode else { return }
        audioReadiness = readiness
    }

    @MainActor
    private func requestAudioPermissionAndRefresh() async {
        let mode = audioInputMode
        audioReadiness = .checking(for: mode)
        let readiness = await audioReadinessChecker.requestPermission(for: mode)
        guard audioInputMode == mode else { return }
        audioReadiness = readiness
        if readiness.state == .permissionRequired {
            openScreenCaptureSettings()
        }
    }

    private func openScreenCaptureSettings() {
        let settingsURLs = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture",
        ]

        for urlString in settingsURLs {
            guard let url = URL(string: urlString), NSWorkspace.shared.open(url) else { continue }
            return
        }
    }
}
