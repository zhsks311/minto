import SwiftUI

struct ReSummaryGlossarySheet: View {
    let record: MeetingRecord

    @ObservedObject private var glossaryStore: GlossaryStore
    @State private var selectedCategories: Set<String> = []
    @State private var manualGlossary = ""
    @State private var isSubmitting = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private let glossarySelectionDefaults: UserDefaults
    private let onConfirm: (String) async -> String?

    init(
        record: MeetingRecord,
        glossaryStore: GlossaryStore = .shared,
        glossarySelectionDefaults: UserDefaults = .standard,
        onConfirm: @escaping (String) async -> String?
    ) {
        self.record = record
        self.glossaryStore = glossaryStore
        self.glossarySelectionDefaults = glossarySelectionDefaults
        self.onConfirm = onConfirm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    previousGlossarySection
                    GlossarySetSelectionSection(
                        glossaryStore: glossaryStore,
                        selectedCategories: $selectedCategories,
                        manualGlossary: $manualGlossary,
                        manualTitle: "이번 재요약 용어",
                        manualEditorHeight: 82
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 420)

            if let error {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            actionButtons
        }
        .padding(22)
        .frame(width: 520)
        // 재요약 진행 중에는 시트를 닫지 못하게 막는다. Escape(.cancelAction)는 disabled 버튼에서도
        // 발동할 수 있어, 백그라운드 retry Task만 남고 시트가 사라지는 상황을 방지한다.
        .interactiveDismissDisabled(isSubmitting)
        .onAppear {
            restoreGlossarySelection()
        }
        .onChange(of: glossaryStore.categorySelectionNames) { _, _ in
            pruneGlossarySelection()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("다시 요약")
                .font(.system(size: 20, weight: .bold))
            Text(record.title)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
    }

    private var previousGlossarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("이전 요약에 사용된 용어")
                .font(.system(size: 13, weight: .semibold))

            if previousGlossaryLines.isEmpty {
                Text("이전 요약에 저장된 용어가 없어요.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(previousGlossaryLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.07))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.16), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .textSelection(.enabled)
            }
        }
    }

    private var actionButtons: some View {
        HStack {
            Button("취소") {
                guard !isSubmitting else { return }
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isSubmitting)

            Spacer()

            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 6) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                    Text(isSubmitting ? "요약 중" : "다시 요약")
                }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(ProminentActionButtonStyle())
            .disabled(isSubmitting)
        }
    }

    private var selectedGlossaryEntries: [GlossaryEntry] {
        glossaryStore.entries(inCategories: selectedCategories)
    }

    private var combinedGlossary: String {
        GlossaryContextResolver().resolve(
            manualGlossary: manualGlossary,
            selectedEntries: selectedGlossaryEntries
        )
    }

    private var glossarySelectionCategoryNames: [String] {
        glossaryStore.categorySelectionNames
    }

    private var previousGlossaryLines: [String] {
        (record.summaryGlossary ?? "")
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func restoreGlossarySelection() {
        selectedCategories = GlossarySetSelectionPersistence.load(
            from: glossarySelectionDefaults,
            availableCategories: GlossarySetSelectionPersistence.availableCategories(
                from: glossarySelectionCategoryNames
            )
        )
        manualGlossary = ""
        error = nil
    }

    private func pruneGlossarySelection() {
        let pruned = GlossarySetSelectionPersistence.validSelectedCategories(
            selectedCategories,
            availableCategoryNames: glossarySelectionCategoryNames
        )
        guard pruned != selectedCategories else { return }
        selectedCategories = pruned
    }

    @MainActor
    private func submit() async {
        guard !isSubmitting else { return }
        isSubmitting = true
        error = nil

        let message = await onConfirm(combinedGlossary)
        isSubmitting = false
        if let message {
            error = message
        } else {
            dismiss()
        }
    }
}
