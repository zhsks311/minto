import SwiftUI

struct GlossarySettingsSection: View {
    @ObservedObject private var glossaryStore = GlossaryStore.shared

    @State private var glossaryCanonicalInput = ""
    @State private var glossaryAliasesInput = ""
    @State private var glossaryDescriptionInput = ""
    @State private var glossaryTagsInput = ""
    @State private var glossaryCategoryInput = "개발"
    @State private var glossaryNewCategoryInput = ""
    @State private var showGlossaryAddForm = false
    /// nil이 아니면 폼이 해당 용어의 수정 모드로 동작한다.
    @State private var editingGlossaryEntryID: UUID? = nil
    @State private var collapsedGlossaryCategories: Set<String> = []
    @State private var expandedAliasSuggestionEntryIDs: Set<UUID> = []
    /// 후보 [추가]로 폼을 열었을 때의 출처 후보 id.
    /// 저장 성공 시 approveCandidate를 호출해 목록에서 제거한다.
    /// 폼 취소 시에는 nil만 초기화하고 후보는 유지한다.
    @State private var pendingCandidateIDForForm: UUID? = nil
    @State private var aliasPrefillTask: Task<Void, Never>? = nil

    private static let glossaryNewCategoryTag = "__new-glossary-category__"

    var body: some View {
        Section("용어집") {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("묶음별 용어집에서 회의 주제에 맞는 용어만 추천합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("활성 용어 \(glossaryStore.entries.filter(\.enabled).count)개 · AI 전달량 \(glossaryPromptPreviewCount) / \(GlossaryContextResolver.defaultMaxCharacters)자")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Button(glossaryEditorVisible ? "접기" : "용어 추가") {
                    if glossaryEditorVisible {
                        cancelGlossaryEditing()
                    } else {
                        showGlossaryAddForm = true
                    }
                }
            }

            if glossaryEditorVisible {
                glossaryEditorForm
            }

            if !glossaryStore.pendingCandidates.isEmpty {
                candidateSuggestionsArea
            }

            if glossaryStore.entries.isEmpty {
                Text("개발, 인프라, 제품, 조직처럼 묶음별 용어를 추가하면 새 회의 시작 때 관련 용어만 선택할 수 있습니다. 묶음 이름은 직접 만들 수도 있습니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(glossaryGroupedEntries, id: \.category) { group in
                    glossaryCategoryCard(group)
                }
            }

            Text("저장 개수에는 제한이 없습니다. AI에는 회의 주제와 선택한 용어만 최대 \(GlossaryContextResolver.defaultMaxCharacters)자까지 전달됩니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - 제안된 용어 영역

    private var candidateSuggestionsArea: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("제안된 용어")
                .font(.caption.weight(.bold))
                .foregroundColor(.accentColor)
            Text("회의에서 발견한 용어입니다. 추가하면 등록 폼이 열립니다.")
                .font(.caption2)
                .foregroundColor(.secondary)
            ForEach(glossaryStore.pendingCandidates) { candidate in
                candidateRow(candidate)
            }
        }
        .padding(.vertical, 4)
    }

    private func candidateRow(_ candidate: GlossaryCandidate) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.term)
                    .font(.callout.weight(.semibold))
                if !candidate.suggestedAliases.isEmpty {
                    Text("오인식: \(candidate.suggestedAliases.joined(separator: ", "))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                if let title = sourceMeetingTitle(for: candidate) {
                    Text(title)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Button("추가") {
                prefillFormForCandidate(candidate)
            }
            .buttonStyle(.bordered)
            .font(.caption)
            Button("무시") {
                glossaryStore.dismissCandidate(candidate.id)
            }
            .buttonStyle(.borderless)
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    /// 후보의 출처 회의 제목 (회의가 없으면 nil).
    private func sourceMeetingTitle(for candidate: GlossaryCandidate) -> String? {
        guard let sourceMeetingID = candidate.sourceMeetingID else { return nil }
        return MeetingStore.shared.meetings.first { $0.id == sourceMeetingID }?.title
    }

    /// [추가] 버튼 동작: 폼을 열고 canonical을 프리필한다. 자동 등록하지 않는다.
    /// 후보 제거는 저장 성공 시에만 수행한다 — 취소 시 후보가 소실되지 않도록.
    private func prefillFormForCandidate(_ candidate: GlossaryCandidate) {
        editingGlossaryEntryID = nil
        glossaryCanonicalInput = candidate.term
        if glossaryAliasesInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            glossaryAliasesInput = candidate.suggestedAliases.joined(separator: ", ")
        }
        glossaryDescriptionInput = ""
        glossaryTagsInput = ""
        glossaryNewCategoryInput = ""
        if glossaryCategoryInput == Self.glossaryNewCategoryTag {
            glossaryCategoryInput = glossaryCategoryOptions.first ?? "개발"
        }
        pendingCandidateIDForForm = candidate.id
        showGlossaryAddForm = true
        startAliasPrefillIfNeeded(for: candidate)
    }

    /// 묶음 하나를 헤더 + 용어 행들로 묶은 카드. 헤더 클릭으로 접고 펼친다.
    private func glossaryCategoryCard(_ group: (category: String, entries: [GlossaryEntry])) -> some View {
        let collapsed = collapsedGlossaryCategories.contains(group.category)
        let activeCount = group.entries.filter(\.enabled).count

        return VStack(alignment: .leading, spacing: 0) {
            Button {
                if collapsed {
                    collapsedGlossaryCategories.remove(group.category)
                } else {
                    collapsedGlossaryCategories.insert(group.category)
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                    Text(group.category)
                        .font(.callout.weight(.semibold))
                    Text("\(group.entries.count)개")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.12))
                        .clipShape(Capsule())
                    if activeCount < group.entries.count {
                        Text("추천 포함 \(activeCount)개")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color.secondary.opacity(0.07))

            if !collapsed {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { position, entry in
                    if position > 0 {
                        Divider()
                            .padding(.leading, 10)
                    }
                    glossaryEntryRow(entry)
                }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    /// 압축 행: 표기 + 설명/별칭은 한 줄로 잘라 길어져도 행 높이를 유지한다.
    private func glossaryEntryRow(_ entry: GlossaryEntry) -> some View {
        let aliasSuggestions = aliasSuggestions(for: entry)
        let isExpanded = expandedAliasSuggestionEntryIDs.contains(entry.id)

        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { entry.enabled },
                    set: { glossaryStore.setEnabled(entry.id, enabled: $0) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .help("회의 시작 때 추천에 포함")

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.normalizedCanonical)
                        .font(.callout.weight(.semibold))
                        .foregroundColor(entry.enabled ? .primary : .secondary)
                    if !entry.description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(entry.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    let meta = glossaryEntryMeta(entry)
                    if !meta.isEmpty {
                        Text(meta)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                if !aliasSuggestions.isEmpty {
                    Button {
                        toggleAliasSuggestions(for: entry.id)
                    } label: {
                        HStack(spacing: 4) {
                            Text("별칭 제안 \(aliasSuggestions.count)")
                                .font(.caption2.weight(.semibold))
                            Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.10))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("별칭 제안 보기")
                }

                Button {
                    beginEditingGlossaryEntry(entry)
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help("편집")

                Button(role: .destructive) {
                    if editingGlossaryEntryID == entry.id {
                        cancelGlossaryEditing()
                    }
                    glossaryStore.delete(entry.id)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("삭제")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)

            if isExpanded, !aliasSuggestions.isEmpty {
                aliasSuggestionList(aliasSuggestions, entryID: entry.id)
            }
        }
    }

    private func aliasSuggestionList(_ suggestions: [GlossaryAliasSuggestion], entryID: UUID) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(suggestions) { suggestion in
                HStack(spacing: 8) {
                    Text("오인식: \(suggestion.alias)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("추가") {
                        glossaryStore.approveAliasSuggestion(suggestion.id)
                        // approve가 제안을 동기 제거한 뒤 비었는지 확인해야 접힘 상태가 정확하다.
                        collapseAliasSuggestionsIfEmpty(entryID)
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    Button("무시") {
                        glossaryStore.dismissAliasSuggestion(suggestion.id)
                        collapseAliasSuggestionsIfEmpty(entryID)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color.secondary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.leading, 34)
        .padding(.trailing, 10)
        .padding(.bottom, 8)
    }

    private func aliasSuggestions(for entry: GlossaryEntry) -> [GlossaryAliasSuggestion] {
        glossaryStore.pendingAliases
            .filter { $0.entryID == entry.id }
            .sorted { $0.suggestedAt < $1.suggestedAt }
    }

    private func toggleAliasSuggestions(for entryID: UUID) {
        if expandedAliasSuggestionEntryIDs.contains(entryID) {
            expandedAliasSuggestionEntryIDs.remove(entryID)
        } else {
            expandedAliasSuggestionEntryIDs.insert(entryID)
        }
    }

    private func collapseAliasSuggestionsIfEmpty(_ entryID: UUID) {
        if !glossaryStore.pendingAliases.contains(where: { $0.entryID == entryID }) {
            expandedAliasSuggestionEntryIDs.remove(entryID)
        }
    }

    private func glossaryEntryMeta(_ entry: GlossaryEntry) -> String {
        var parts: [String] = []
        if !entry.aliases.isEmpty {
            parts.append("오인식: \(entry.aliases.joined(separator: ", "))")
        }
        if !entry.tags.isEmpty {
            parts.append("태그: \(entry.tags.joined(separator: ", "))")
        }
        return parts.joined(separator: " · ")
    }

    private var glossaryEditorForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(editingGlossaryEntryID == nil ? "새 용어" : "용어 수정")
                .font(.caption.weight(.bold))
                .foregroundColor(.accentColor)

            VStack(alignment: .leading, spacing: 4) {
                Text("묶음")
                    .font(.caption.weight(.semibold))
                Picker("", selection: $glossaryCategoryInput) {
                    ForEach(glossaryCategoryOptions, id: \.self) { category in
                        Text(category).tag(category)
                    }
                    Text("새 묶음 만들기…").tag(Self.glossaryNewCategoryTag)
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: 220, alignment: .leading)

                if glossaryCategoryInput == Self.glossaryNewCategoryTag {
                    glossaryInputField(
                        title: "새 묶음 이름",
                        placeholder: "예: 백엔드팀, 프로젝트-X",
                        help: "팀이나 프로젝트 이름으로 나만의 용어집을 만들 수 있습니다.",
                        text: $glossaryNewCategoryInput
                    )
                }
            }

            glossaryInputField(
                title: "정확한 표기",
                placeholder: "Liquibase",
                help: "회의록에 남기고 싶은 최종 표기입니다.",
                text: $glossaryCanonicalInput
            )
            glossaryInputField(
                title: "잘못 인식되기 쉬운 표현",
                placeholder: "리퀴베이스, liqui base",
                help: "쉼표나 줄바꿈으로 여러 표현을 입력하세요.",
                text: $glossaryAliasesInput
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("짧은 설명")
                    .font(.caption.weight(.semibold))
                TextEditor(text: $glossaryDescriptionInput)
                    .font(.callout)
                    .frame(height: 52)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                HStack {
                    Text("회의 주제와 맞는 용어만 추천할 때 사용합니다.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(glossaryDescriptionInput.count)자 · AI에는 앞 \(GlossaryStore.promptDescriptionMaxLength)자만 전달")
                        .font(.caption2)
                        .foregroundColor(glossaryDescriptionInput.count > GlossaryStore.promptDescriptionMaxLength ? .orange : .secondary)
                }
            }

            glossaryInputField(
                title: "태그",
                placeholder: "db, 마이그레이션",
                help: "검색과 추천 힌트입니다. 쉼표로 구분하세요.",
                text: $glossaryTagsInput
            )

            if let promptLine = glossaryPromptPreviewLine {
                VStack(alignment: .leading, spacing: 3) {
                    Text("AI 전달 형식")
                        .font(.caption.weight(.semibold))
                    Text(promptLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                    Text("이 용어는 전달 예산 \(GlossaryContextResolver.defaultMaxCharacters)자 중 약 \(promptLine.count)자를 차지합니다.")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            HStack(spacing: 8) {
                Button(editingGlossaryEntryID == nil ? "저장" : "수정 저장") {
                    saveGlossaryEntry()
                }
                .disabled(!canSaveGlossaryEntry)

                Button("취소") {
                    cancelGlossaryEditing()
                }
                .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func glossaryInputField(
        title: String,
        placeholder: String,
        help: String,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )

                if text.wrappedValue.isEmpty {
                    Text(placeholder)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .allowsHitTesting(false)
                }

                TextField("", text: text)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
            }
            .frame(maxWidth: .infinity)
            Text(help)
                .font(.caption2)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var glossaryEditorVisible: Bool {
        showGlossaryAddForm || editingGlossaryEntryID != nil
    }

    /// 사용 중인 묶음 + 프리셋을 합친 선택지. 사용자가 만든 묶음이 먼저 보인다.
    private var glossaryCategoryOptions: [String] {
        var seen = Set<String>()
        var options: [String] = []
        for category in glossaryStore.categories + glossaryCategoryPresets {
            let key = category.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            options.append(category)
        }
        return options
    }

    private var effectiveGlossaryCategory: String {
        if glossaryCategoryInput == Self.glossaryNewCategoryTag {
            return glossaryNewCategoryInput.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return glossaryCategoryInput
    }

    private var canSaveGlossaryEntry: Bool {
        !glossaryCanonicalInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !effectiveGlossaryCategory.isEmpty
    }

    /// 현재 입력으로 AI 프롬프트에 들어갈 한 줄 미리보기.
    private var glossaryPromptPreviewLine: String? {
        let draft = GlossaryEntry(
            canonical: glossaryCanonicalInput,
            aliases: glossaryAliasesInput
                .components(separatedBy: CharacterSet(charactersIn: ",\n"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty },
            description: glossaryDescriptionInput
        )
        guard draft.isUsable else { return nil }
        return GlossaryStore.promptLines(for: [draft]).first
    }

    private func saveGlossaryEntry() {
        let saved: Bool
        if let editingID = editingGlossaryEntryID {
            saved = glossaryStore.update(
                editingID,
                canonical: glossaryCanonicalInput,
                aliasesText: glossaryAliasesInput,
                description: glossaryDescriptionInput,
                category: effectiveGlossaryCategory,
                tagsText: glossaryTagsInput
            )
        } else {
            saved = glossaryStore.add(
                canonical: glossaryCanonicalInput,
                aliasesText: glossaryAliasesInput,
                description: glossaryDescriptionInput,
                category: effectiveGlossaryCategory,
                tagsText: glossaryTagsInput
            )
        }
        if saved {
            // 후보 [추가]로 열린 폼이면 저장 성공 후 후보를 제거한다.
            // (취소 시에는 cancelGlossaryEditing에서 nil만 초기화 — 후보 유지)
            if let candidateID = pendingCandidateIDForForm {
                glossaryStore.approveCandidate(candidateID)
            }
            // 새 묶음에 저장했으면 그 묶음이 펼쳐진 상태로 보이게 한다.
            collapsedGlossaryCategories.remove(effectiveGlossaryCategory)
            cancelGlossaryEditing()
        }
    }

    private func beginEditingGlossaryEntry(_ entry: GlossaryEntry) {
        editingGlossaryEntryID = entry.id
        showGlossaryAddForm = false
        glossaryCanonicalInput = entry.canonical
        glossaryAliasesInput = entry.aliases.joined(separator: ", ")
        glossaryDescriptionInput = entry.description
        glossaryTagsInput = entry.tags.joined(separator: ", ")
        glossaryNewCategoryInput = ""
        let category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
        glossaryCategoryInput = category.isEmpty ? "기타" : category
    }

    private func cancelGlossaryEditing() {
        aliasPrefillTask?.cancel()
        aliasPrefillTask = nil
        editingGlossaryEntryID = nil
        showGlossaryAddForm = false
        pendingCandidateIDForForm = nil  // 후보는 유지, id 참조만 해제
        glossaryCanonicalInput = ""
        glossaryAliasesInput = ""
        glossaryDescriptionInput = ""
        glossaryTagsInput = ""
        glossaryNewCategoryInput = ""
        if glossaryCategoryInput == Self.glossaryNewCategoryTag {
            glossaryCategoryInput = glossaryCategoryOptions.first ?? "개발"
        }
    }

    private func startAliasPrefillIfNeeded(for candidate: GlossaryCandidate) {
        guard glossaryAliasesInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        aliasPrefillTask?.cancel()
        let candidateID = candidate.id
        let term = candidate.term

        aliasPrefillTask = Task {
            let aliases = await GlossaryAliasPrefillService.shared.suggestAliases(for: term)
            guard !Task.isCancelled, !aliases.isEmpty else { return }

            await MainActor.run {
                guard pendingCandidateIDForForm == candidateID else { return }
                guard editingGlossaryEntryID == nil, showGlossaryAddForm else { return }
                guard glossaryAliasesInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                glossaryAliasesInput = aliases.joined(separator: ", ")
            }
        }
    }

    private var glossaryCategoryPresets: [String] {
        ["개발", "인프라", "제품", "조직", "기타"]
    }

    private var glossaryGroupedEntries: [(category: String, entries: [GlossaryEntry])] {
        let grouped = Dictionary(grouping: glossaryStore.entries) { entry in
            let category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
            return category.isEmpty ? "기타" : category
        }
        return grouped.keys.sorted { lhs, rhs in
            let lhsIndex = glossaryCategoryPresets.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = glossaryCategoryPresets.firstIndex(of: rhs) ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        .map { category in
            let entries = grouped[category] ?? []
            return (category: category, entries: entries)
        }
    }

    private var glossaryPromptPreviewCount: Int {
        GlossaryContextResolver()
            .resolve(manualGlossary: "", selectedEntries: glossaryStore.entries.filter(\.isUsable))
            .count
    }
}
