import SwiftUI

/// 비활성(non-key) 윈도우에서도 배경이 사라지지 않도록 직접 그리는 강조 버튼 스타일.
/// MeetingLibraryView의 ProminentActionButtonStyle과 동일하나 파일 범위 접근 문제로 복제한다.
private struct FileImportProminentButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Capsule().fill(isEnabled ? Color.accentColor : Color.gray.opacity(0.45)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

/// 파일 임포트 시 주제·용어집 맥락을 입력하는 경량 시트.
/// MeetingSetupView의 glossaryContextEditor 패턴을 따르되,
/// 오디오 입력/Confluence 연동 부분은 포함하지 않는다.
struct FileImportSetupSheet: View {
    let fileURL: URL
    let onImport: (String, String) -> Void  // (topic, glossary)
    let onSkip: () -> Void

    @ObservedObject private var glossaryStore = GlossaryStore.shared
    @State private var topic: String = ""
    @State private var manualGlossary: String = ""
    @State private var selectedGlossaryEntryIDs: Set<UUID> = []
    @State private var showGlossary = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            topicField
            glossaryContextEditor
            Spacer(minLength: 0)
            actionButtons
        }
        .padding(22)
        .frame(width: 460)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("파일로 회의록 만들기")
                .font(.system(size: 20, weight: .bold))
            Text(fileURL.deletingPathExtension().lastPathComponent)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Topic

    private var topicField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("회의 주제")
                .font(.system(size: 13, weight: .semibold))
            TextField("예: Q2 스프린트 회고, 신규 기능 기획", text: $topic)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: - Glossary

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
                    Text("AI에는 선택한 용어와 직접 입력한 용어만 최대 \(GlossaryContextResolver.defaultMaxCharacters)자까지 전달됩니다. 현재 \(combinedGlossary.count) / \(GlossaryContextResolver.defaultMaxCharacters)자")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

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
                            ForEach(selectedGlossaryEntriesOutsideCandidates) { entry in
                                glossaryCandidateRow(entry)
                            }
                        }
                    }

                    Text("이번 파일 용어")
                        .font(.caption.weight(.semibold))
                    TextEditor(text: $manualGlossary)
                        .font(.body)
                        .frame(height: 72)
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
                if !entry.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(entry.category)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
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

    // MARK: - Actions

    private var actionButtons: some View {
        HStack {
            Button("건너뛰고 바로 임포트") {
                dismiss()
                onSkip()
            }
            .foregroundColor(.secondary)
            Spacer()
            Button {
                dismiss()
                onImport(topic.trimmingCharacters(in: .whitespacesAndNewlines), combinedGlossary)
            } label: {
                Label("임포트", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(FileImportProminentButtonStyle())
        }
    }

    // MARK: - Computed helpers

    private var glossaryCandidates: [GlossaryEntry] {
        glossaryStore.candidates(for: topic, limit: 24)
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
        GlossaryContextResolver().resolve(manualGlossary: manualGlossary, selectedEntries: selectedGlossaryEntries)
    }

    private var glossaryBadgeText: String {
        let count = selectedGlossaryEntries.count
            + manualGlossary.split(whereSeparator: { $0.isNewline })
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
        return count > 0 ? "\(count)개 선택" : "선택"
    }
}
