import SwiftUI

/// 파일 임포트 시 주제·용어집·예상 참석 인원 맥락을 입력하는 경량 시트.
/// MeetingSetupView의 glossaryContextEditor 패턴을 따르되,
/// 오디오 입력/Confluence 연동 부분은 포함하지 않는다.
struct FileImportSetupSheet: View {
    let fileURL: URL
    let onImport: (String, String, Int?) -> Void  // (topic, glossary, expectedSpeakerCount)
    let onSkip: () -> Void

    @ObservedObject private var glossaryStore = GlossaryStore.shared
    @State private var topic: String = ""
    @State private var expectedSpeakerCountText: String = ""
    @State private var manualGlossary: String = ""
    @State private var selectedGlossaryCategories: Set<String> = []
    @State private var showGlossary = false
    @Environment(\.dismiss) private var dismiss
    private let glossarySelectionDefaults: UserDefaults

    init(
        fileURL: URL,
        onImport: @escaping (String, String, Int?) -> Void,
        onSkip: @escaping () -> Void,
        glossarySelectionDefaults: UserDefaults = .standard
    ) {
        self.fileURL = fileURL
        self.onImport = onImport
        self.onSkip = onSkip
        self.glossarySelectionDefaults = glossarySelectionDefaults
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            topicField
            expectedSpeakerCountField
            glossaryContextEditor
            Spacer(minLength: 0)
            actionButtons
        }
        .padding(22)
        .frame(width: 460)
        .onAppear {
            restoreGlossarySelection()
        }
        .onChange(of: selectedGlossaryCategories) { _, _ in
            saveGlossarySelection()
        }
        .onChange(of: glossaryStore.categorySelectionNames) { _, _ in
            pruneGlossarySelection()
        }
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

    // MARK: - Expected speakers

    private var expectedSpeakerCountField: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("예상 참석 인원")
                .font(.system(size: 13, weight: .semibold))
            TextField("예: 4", text: $expectedSpeakerCountText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: expectedSpeakerCountText) { _, newValue in
                    normalizeExpectedSpeakerCountInput(newValue)
                }
            Text("비우면 화자 수를 자동으로 추정해요. 인원을 알면 입력하는 게 더 정확합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
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
                GlossarySetSelectionSection(
                    glossaryStore: glossaryStore,
                    selectedCategories: $selectedGlossaryCategories,
                    manualGlossary: $manualGlossary,
                    manualTitle: "이번 파일 용어",
                    manualEditorHeight: 72
                )
                .padding(.leading, 18)
            }
        }
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
                onImport(
                    topic.trimmingCharacters(in: .whitespacesAndNewlines),
                    combinedGlossary,
                    expectedSpeakerCount
                )
            } label: {
                Label("임포트", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(ProminentActionButtonStyle())
        }
    }

    // MARK: - Computed helpers

    private var selectedGlossaryEntries: [GlossaryEntry] {
        glossaryStore.entries(inCategories: selectedGlossaryCategories)
    }

    private var combinedGlossary: String {
        GlossaryContextResolver().resolve(manualGlossary: manualGlossary, selectedEntries: selectedGlossaryEntries)
    }

    private var expectedSpeakerCount: Int? {
        let trimmedText = expectedSpeakerCountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else { return nil }
        guard let count = Int(trimmedText), count > 0 else { return nil }
        return count
    }

    private var glossaryBadgeText: String {
        GlossarySetSelectionPersistence.badgeText(
            selectedCategories: selectedGlossaryCategories,
            manualGlossary: manualGlossary,
            availableCategoryNames: glossarySelectionCategoryNames
        )
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

    private func normalizeExpectedSpeakerCountInput(_ value: String) {
        let filteredValue = value.filter { $0.isASCII && $0.isNumber }
        guard filteredValue != value else { return }
        expectedSpeakerCountText = filteredValue
    }
}
