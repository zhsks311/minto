import SwiftUI

struct GlossarySetSelectionSection: View {
    @ObservedObject private var glossaryStore: GlossaryStore
    @Binding private var selectedCategories: Set<String>
    @Binding private var manualGlossary: String

    private let manualTitle: String
    private let manualEditorHeight: CGFloat

    init(
        glossaryStore: GlossaryStore = .shared,
        selectedCategories: Binding<Set<String>>,
        manualGlossary: Binding<String>,
        manualTitle: String,
        manualEditorHeight: CGFloat = 92
    ) {
        self.glossaryStore = glossaryStore
        self._selectedCategories = selectedCategories
        self._manualGlossary = manualGlossary
        self.manualTitle = manualTitle
        self.manualEditorHeight = manualEditorHeight
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("AI에는 선택한 용어집과 직접 입력한 용어만 최대 \(GlossaryContextResolver.defaultMaxCharacters)자까지 전달돼요. 현재 \(combinedGlossary.count) / \(GlossaryContextResolver.defaultMaxCharacters)자")
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if combinedGlossary.count >= GlossaryContextResolver.defaultMaxCharacters {
                Text("전달 가능한 길이를 넘는 용어는 잘려서 전달돼요.")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if categoryGroups.isEmpty {
                Text("설정에서 기본 용어를 추가하면 회의마다 다시 입력하지 않아도 돼요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("용어집 선택")
                        .font(.caption.weight(.semibold))
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(categoryGroups, id: \.category) { group in
                                categoryRow(
                                    category: group.category,
                                    usableCount: group.entries.filter(\.isUsable).count
                                )
                            }
                        }
                    }
                    .frame(maxHeight: 160)
                }
            }

            Text(manualTitle)
                .font(.caption.weight(.semibold))
            TextEditor(text: $manualGlossary)
                .font(.body)
                .frame(height: manualEditorHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
        }
    }

    private var categoryGroups: [(category: String, entries: [GlossaryEntry])] {
        glossaryStore.groupedEntriesByCategory
    }

    private var selectedEntries: [GlossaryEntry] {
        glossaryStore.entries(inCategories: selectedCategories)
    }

    private var combinedGlossary: String {
        GlossaryContextResolver().resolve(
            manualGlossary: manualGlossary,
            selectedEntries: selectedEntries
        )
    }

    private func categoryRow(category: String, usableCount: Int) -> some View {
        Toggle(isOn: categoryBinding(for: category)) {
            HStack(spacing: 6) {
                Text("\(category) (\(usableCount))")
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .toggleStyle(.checkbox)
    }

    private func categoryBinding(for category: String) -> Binding<Bool> {
        Binding(
            get: { selectedCategories.contains(category) },
            set: { selected in
                if selected {
                    selectedCategories.insert(category)
                } else {
                    selectedCategories.remove(category)
                }
            }
        )
    }
}
