import SwiftUI

/// "녹음 시작" 시 뜨는 회의 시작 시트.
/// 주제·용어집을 입력받아 그 회의 세션의 교정 맥락으로 쓴다. 비우고 시작해도 된다.
public struct MeetingSetupView: View {
    @ObservedObject private var confluence = ConfluenceService.shared
    @ObservedObject private var glossaryStore = GlossaryStore.shared
    @State private var topic: String = ""
    @State private var glossary: String = ""
    @State private var document: String = ""
    @State private var showGlossary = false
    @State private var showDocument = false
    @State private var audioInputMode: AudioInputMode = .microphone
    @State private var selectedGlossaryEntryIDs: Set<UUID> = []
    @State private var confluenceDocuments: [ConfluenceService.ContextDocument] = []
    @State private var confluenceStatus: String?
    @State private var isSearchingConfluence = false

    private let onStart: (String, String, String, AudioInputMode) -> Void
    private let onCancel: () -> Void

    public init(
        onStart: @escaping (String, String, String, AudioInputMode) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onStart = onStart
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("새 회의")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.accentColor)
                Text("바로 녹음할 수 있어요")
                    .font(.title3.weight(.bold))
                Text("주제만 적어도 충분합니다. 필요한 정보는 선택해서 더하세요.")
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

            HStack {
                Spacer()
                Button("닫기") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("녹음 시작") { onStart(topic, combinedGlossary, combinedDocument, audioInputMode) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
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
                VStack(alignment: .leading, spacing: 10) {
                    if !glossaryCandidates.isEmpty {
                        HStack(spacing: 8) {
                            Text("주제와 관련된 용어")
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("추천 선택") {
                                selectedGlossaryEntryIDs.formUnion(glossaryCandidates.map(\.id))
                            }
                            .font(.caption)
                            .buttonStyle(.borderless)
                        }

                        VStack(spacing: 6) {
                            ForEach(glossaryCandidates) { entry in
                                glossaryCandidateRow(entry)
                            }
                        }
                    } else {
                        Text(glossaryStore.entries.isEmpty
                             ? "설정에서 기본 용어를 추가하면 회의마다 다시 입력하지 않아도 됩니다."
                             : "회의 주제를 입력하면 관련 기본 용어를 추천합니다.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    if !selectedGlossaryEntriesOutsideCandidates.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("선택된 용어")
                                .font(.caption.weight(.semibold))
                            Text("현재 추천 목록에는 없지만 이번 회의 문맥에 포함됩니다.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            ForEach(selectedGlossaryEntriesOutsideCandidates) { entry in
                                glossaryCandidateRow(entry)
                            }
                        }
                    }

                    Text("이번 회의 용어")
                        .font(.caption.weight(.semibold))
                    TextEditor(text: $glossary)
                        .font(.body)
                        .frame(height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }
                .padding(.leading, 18)
            }
        }
    }

    private func glossaryCandidateRow(_ entry: GlossaryEntry) -> some View {
        Toggle(isOn: Binding(
            get: { selectedGlossaryEntryIDs.contains(entry.id) },
            set: { selected in
                if selected {
                    selectedGlossaryEntryIDs.insert(entry.id)
                } else {
                    selectedGlossaryEntryIDs.remove(entry.id)
                }
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.normalizedCanonical)
                    .font(.caption.weight(.semibold))
                if !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(entry.description)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .toggleStyle(.checkbox)
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
                    Text("Confluence 문맥 조회")
                        .font(.subheadline.weight(.medium))
                    Text(confluenceBadgeText)
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
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: confluence.isConfigured ? "link.circle.fill" : "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(confluence.isConfigured ? .green : .secondary)
                        Text(confluence.isConfigured
                             ? "설정 > 검색 소스의 Confluence 연결을 사용합니다."
                             : "설정 > 검색 소스에서 Confluence를 연결하면 사용할 수 있습니다.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Text("회의 주제나 안건으로 Confluence를 조회해 전사 교정과 요약에 참고합니다.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    TextEditor(text: $document)
                        .font(.body)
                        .frame(height: 92)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )

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
                            .foregroundColor(confluenceDocuments.isEmpty ? .secondary : .accentColor)
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
                }
                .padding(.leading, 18)
            }
        }
    }

    private var canSearchConfluence: Bool {
        confluence.isConfigured
            && !confluenceQuery.isEmpty
            && !isSearchingConfluence
    }

    private var confluenceBadgeText: String {
        if !confluenceDocuments.isEmpty { return "\(confluenceDocuments.count)개 선택" }
        return confluence.isConfigured ? "연결됨" : "설정 필요"
    }

    private var glossaryBadgeText: String {
        let count = selectedGlossaryEntries.count
            + glossary.split(whereSeparator: { $0.isNewline }).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return count > 0 ? "\(count)개 선택" : "선택"
    }

    private var glossaryCandidates: [GlossaryEntry] {
        glossaryStore.candidates(for: topic, limit: 8)
    }

    private var selectedGlossaryEntries: [GlossaryEntry] {
        let ids = selectedGlossaryEntryIDs
        return glossaryStore.entries.filter { ids.contains($0.id) && $0.isUsable }
    }

    private var selectedGlossaryEntriesOutsideCandidates: [GlossaryEntry] {
        let candidateIDs = Set(glossaryCandidates.map(\.id))
        return selectedGlossaryEntries.filter { !candidateIDs.contains($0.id) }
    }

    private var combinedGlossary: String {
        GlossaryContextResolver().resolve(manualGlossary: glossary, selectedEntries: selectedGlossaryEntries)
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
        let manual = document.trimmingCharacters(in: .whitespacesAndNewlines)
        let confluenceBlock = ConfluenceService.contextBlock(from: confluenceDocuments)
        return [manual, confluenceBlock]
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    private func fetchConfluenceContext() async {
        let query = confluenceQuery
        guard !query.isEmpty else {
            confluenceStatus = "조회할 회의 주제나 안건을 먼저 입력하세요."
            return
        }
        guard confluence.isConfigured else {
            confluenceStatus = "설정에서 Confluence를 먼저 연결하세요."
            return
        }

        isSearchingConfluence = true
        confluenceStatus = nil
        defer { isSearchingConfluence = false }

        let documents = await confluence.searchContext(query, limit: 3)
        confluenceDocuments = documents
        confluenceStatus = documents.isEmpty
            ? "관련 Confluence 문서를 찾지 못했습니다."
            : "Confluence 문서 \(documents.count)개를 참고자료로 사용합니다."
    }
}
