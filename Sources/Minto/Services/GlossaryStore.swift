import os
import Foundation
import Combine

@MainActor
public final class GlossaryStore: ObservableObject {
    public static let shared = GlossaryStore()
    public static let schemaVersion = 1
    nonisolated public static let uncategorizedCategoryName = "기타"
    nonisolated public static let defaultCategoryPresets = ["개발", "인프라", "제품", "조직", "기타"]

    @Published public private(set) var entries: [GlossaryEntry] = []
    @Published public private(set) var pendingCandidates: [GlossaryCandidate] = []
    @Published public private(set) var pendingAliases: [GlossaryAliasSuggestion] = []
    public private(set) var dismissedAliasKeys: [String] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var meetingObservationCancellable: AnyCancellable?

    /// - Parameters:
    ///   - fileURL: 저장 경로. nil이면 ~/Library/Application Support/Minto/glossary.json.
    ///   - meetingsPublisher: 회의 목록 publisher. nil이면 후보 추출 구독을 생략한다(테스트 격리용).
    public init(
        fileURL: URL? = nil,
        meetingsPublisher: AnyPublisher<[MeetingRecord], Never>? = MeetingStore.shared.$meetings.eraseToAnyPublisher()
    ) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)
                .first ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
            self.fileURL = base.appendingPathComponent("Minto/glossary.json")
        }

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        decoder = dec

        reload()
        // meetingsPublisher가 nil이면 구독 생략(테스트 격리).
        // 동기로 배선해야 한다 — 앱 시작 시 복구 복원(restorePendingRecords)이 동기로 실행되므로,
        // 구독이 한 틱이라도 늦으면 복원된 회의를 "기존 회의"로 삼켜 후보 추출을 놓친다.
        // (MeetingStore.init은 GlossaryStore를 참조하지 않으므로 순환 초기화 없음)
        if let publisher = meetingsPublisher {
            startObservingMeetings(publisher: publisher)
        }
    }

    public func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            pendingCandidates = []
            pendingAliases = []
            dismissedAliasKeys = []
            return
        }
        if let snapshot = try? decoder.decode(GlossarySnapshot.self, from: data),
           snapshot.schemaVersion == Self.schemaVersion {
            entries = Self.cleaned(snapshot.entries)
            pendingCandidates = snapshot.pendingCandidates
            pendingAliases = snapshot.pendingAliases
            dismissedAliasKeys = Self.cappedDismissedAliasKeys(snapshot.dismissedAliasKeys)
        } else if let legacy = try? decoder.decode([GlossaryEntry].self, from: data) {
            entries = Self.cleaned(legacy)
            pendingCandidates = []
            pendingAliases = []
            dismissedAliasKeys = []
            _ = save()
        } else {
            entries = []
            pendingCandidates = []
            pendingAliases = []
            dismissedAliasKeys = []
        }
    }

    /// 신규 회의의 keywords에서 후보를 추출해 pendingCandidates에 추가한다.
    /// init에서 동기로 호출되며, 재호출 시에는 이미 구독 중이면 무시한다.
    private func startObservingMeetings(publisher: AnyPublisher<[MeetingRecord], Never>) {
        guard meetingObservationCancellable == nil else { return }
        var knownIDs = Set(MeetingStore.shared.meetings.map(\.id))
        meetingObservationCancellable = publisher
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] meetings in
                guard let self else { return }
                let newMeetings = meetings.filter { !knownIDs.contains($0.id) }
                knownIDs = Set(meetings.map(\.id))
                guard !newMeetings.isEmpty else { return }
                let newCandidates = newMeetings.flatMap { meeting in
                    Self.extractNewCandidates(
                        keywords: meeting.summary.keywords,
                        existingEntries: self.entries,
                        existingPending: self.pendingCandidates,
                        sourceMeetingID: meeting.id
                    )
                }
                guard !newCandidates.isEmpty else { return }
                self.addCandidates(newCandidates)
            }
    }

    /// 회의 record의 keywords에서 후보를 추출해 pendingCandidates에 추가한다.
    /// 재요약 성공 후 명시 호출 경로에서 사용한다 — id-diff 구독은 같은 id 업데이트를 감지하지 못한다.
    public func ingestCandidates(from record: MeetingRecord) {
        let newCandidates = Self.extractNewCandidates(
            keywords: record.summary.keywords,
            existingEntries: entries,
            existingPending: pendingCandidates,
            sourceMeetingID: record.id
        )
        guard !newCandidates.isEmpty else { return }
        addCandidates(newCandidates)
    }

    /// 후보를 pendingCandidates에 병합하고 상한 20개를 유지한다 (초과 시 오래된 것 교체).
    public func addCandidates(_ newCandidates: [GlossaryCandidate]) {
        var next = pendingCandidates + newCandidates
        if next.count > 20 {
            next.sort { $0.suggestedAt < $1.suggestedAt }
            next = Array(next.suffix(20))
        }
        guard save(entries, pendingCandidates: next) else { return }
        pendingCandidates = next
        let count = newCandidates.count
        Log.store.info("glossary candidates added count=\(count, privacy: .public)")
    }

    /// 교정 전후 diff에서 얻은 별칭 후보를 축적한다. 자동 등록은 하지 않는다.
    public func ingestCorrectionAliases(_ pairs: [(canonical: String, alias: String)]) {
        guard !pairs.isEmpty else { return }

        let merge = Self.mergeCorrectionAliases(
            pairs,
            entries: entries,
            pendingCandidates: pendingCandidates,
            pendingAliases: pendingAliases,
            dismissedAliasKeys: dismissedAliasKeys
        )
        guard merge.changed else { return }
        guard save(entries, pendingCandidates: merge.pendingCandidates, pendingAliases: merge.pendingAliases) else { return }
        pendingCandidates = merge.pendingCandidates
        pendingAliases = merge.pendingAliases
    }

    /// 후보를 승인 처리(폼 프리필용) — 실제 등록은 UI 폼에서 사용자가 직접 한다. 후보 목록에서만 제거.
    public func approveCandidate(_ id: UUID) {
        let next = pendingCandidates.filter { $0.id != id }
        guard save(entries, pendingCandidates: next) else { return }
        pendingCandidates = next
    }

    /// 후보를 무시(제거)한다.
    public func dismissCandidate(_ id: UUID) {
        let next = pendingCandidates.filter { $0.id != id }
        guard save(entries, pendingCandidates: next) else { return }
        pendingCandidates = next
    }

    /// 기존 용어에 대한 별칭 제안을 승인한다. 사용자 클릭 경로에서만 호출한다.
    public func approveAliasSuggestion(_ id: UUID) {
        guard let suggestion = pendingAliases.first(where: { $0.id == id }) else { return }

        var nextEntries = entries
        let nextAliases = pendingAliases.filter { $0.id != id }
        guard let entryIndex = nextEntries.firstIndex(where: { $0.id == suggestion.entryID }) else {
            guard save(entries, pendingCandidates: pendingCandidates, pendingAliases: nextAliases) else { return }
            pendingAliases = nextAliases
            return
        }

        let existingKeys = Set(([nextEntries[entryIndex].canonical] + nextEntries[entryIndex].aliases).map(Self.foldedKey))
        let aliasKey = Self.foldedKey(suggestion.alias)
        if !existingKeys.contains(aliasKey) {
            nextEntries[entryIndex].aliases = Self.uniqueLines(nextEntries[entryIndex].aliases + [suggestion.alias])
            nextEntries[entryIndex].updatedAt = Date()
            nextEntries = Self.cleaned(nextEntries)
        }

        guard save(nextEntries, pendingCandidates: pendingCandidates, pendingAliases: nextAliases) else { return }
        entries = nextEntries
        pendingAliases = nextAliases
    }

    /// 기존 용어에 대한 별칭 제안을 무시한다.
    public func dismissAliasSuggestion(_ id: UUID) {
        guard let suggestion = pendingAliases.first(where: { $0.id == id }) else { return }
        let nextAliases = pendingAliases.filter { $0.id != id }
        let nextDismissedKeys = Self.appendingDismissedAliasKey(
            Self.aliasDismissKey(entryID: suggestion.entryID, alias: suggestion.alias),
            to: dismissedAliasKeys
        )
        guard save(
            entries,
            pendingCandidates: pendingCandidates,
            pendingAliases: nextAliases,
            dismissedAliasKeys: nextDismissedKeys
        ) else { return }
        pendingAliases = nextAliases
        dismissedAliasKeys = nextDismissedKeys
    }

    /// 새 회의의 keywords에서 추가할 후보를 추출하는 순수 함수.
    /// - Parameters:
    ///   - keywords: 신규 회의의 summary.keywords
    ///   - existingEntries: 현재 등록된 용어집 entries
    ///   - existingPending: 현재 pendingCandidates
    ///   - sourceMeetingID: 출처 회의 ID
    /// - Returns: 추가해야 할 신규 후보 목록
    nonisolated public static func extractNewCandidates(
        keywords: [String],
        existingEntries: [GlossaryEntry],
        existingPending: [GlossaryCandidate],
        sourceMeetingID: UUID
    ) -> [GlossaryCandidate] {
        // en_US_POSIX: 순수 함수 테스트 재현성 확보 (locale 의존 없이 동일 결과 보장).
        let foldLocale = Locale(identifier: "en_US_POSIX")
        let blockedByEntries = Set(
            existingEntries.flatMap { [$0.canonical] + $0.aliases }
                .map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldLocale) }
        )
        let blockedByPending = Set(
            existingPending.map { $0.term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldLocale) }
        )

        return keywords
            .filter { $0.count >= 2 }
            .filter { keyword in
                let key = keyword.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldLocale)
                return !blockedByEntries.contains(key) && !blockedByPending.contains(key)
            }
            .map { GlossaryCandidate(term: $0, sourceMeetingID: sourceMeetingID) }
    }

    private struct AliasMergeResult {
        let pendingCandidates: [GlossaryCandidate]
        let pendingAliases: [GlossaryAliasSuggestion]
        let changed: Bool
    }

    nonisolated private static func mergeCorrectionAliases(
        _ pairs: [(canonical: String, alias: String)],
        entries: [GlossaryEntry],
        pendingCandidates: [GlossaryCandidate],
        pendingAliases: [GlossaryAliasSuggestion],
        dismissedAliasKeys: [String]
    ) -> AliasMergeResult {
        var nextCandidates = pendingCandidates
        var nextAliases = pendingAliases
        let dismissedAliasKeySet = Set(dismissedAliasKeys)
        var changed = false

        for pair in pairs {
            let canonical = pair.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            let alias = pair.alias.trimmingCharacters(in: .whitespacesAndNewlines)
            let canonicalKey = foldedKey(canonical)
            let aliasKey = foldedKey(alias)
            guard !canonicalKey.isEmpty, !aliasKey.isEmpty, canonicalKey != aliasKey else { continue }

            if let entry = matchingEntry(for: canonical, in: entries) {
                let existingKeys = Set(([entry.canonical] + entry.aliases).map(foldedKey))
                guard !existingKeys.contains(aliasKey) else { continue }
                guard !dismissedAliasKeySet.contains(aliasDismissKey(entryID: entry.id, aliasKey: aliasKey)) else { continue }
                guard !nextAliases.contains(where: { $0.entryID == entry.id && foldedKey($0.alias) == aliasKey }) else { continue }
                nextAliases.append(GlossaryAliasSuggestion(entryID: entry.id, alias: alias))
                changed = true
            } else if let candidateIndex = nextCandidates.firstIndex(where: { foldedKey($0.term) == canonicalKey }) {
                let existingKeys = Set(([nextCandidates[candidateIndex].term] + nextCandidates[candidateIndex].suggestedAliases).map(foldedKey))
                guard !existingKeys.contains(aliasKey) else { continue }
                nextCandidates[candidateIndex].suggestedAliases = uniqueLines(nextCandidates[candidateIndex].suggestedAliases + [alias])
                changed = true
            } else {
                nextCandidates.append(GlossaryCandidate(term: canonical, suggestedAliases: uniqueLines([alias])))
                changed = true
            }
        }

        if nextAliases.count > 30 {
            nextAliases.sort { $0.suggestedAt < $1.suggestedAt }
            nextAliases = Array(nextAliases.suffix(30))
        }
        if nextCandidates.count > 20 {
            nextCandidates.sort { $0.suggestedAt < $1.suggestedAt }
            nextCandidates = Array(nextCandidates.suffix(20))
        }

        return AliasMergeResult(
            pendingCandidates: nextCandidates,
            pendingAliases: nextAliases,
            changed: changed
        )
    }

    @discardableResult
    public func add(
        canonical: String,
        aliasesText: String = "",
        description: String = "",
        category: String = "",
        tagsText: String = ""
    ) -> Bool {
        let entry = GlossaryEntry(
            canonical: canonical.trimmingCharacters(in: .whitespacesAndNewlines),
            aliases: Self.parseList(aliasesText),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: Self.parseList(tagsText),
            enabled: true,
            updatedAt: Date()
        )
        guard !entry.normalizedCanonical.isEmpty else { return false }

        var nextEntries = entries
        nextEntries.removeAll {
            $0.normalizedCanonical.compare(entry.normalizedCanonical, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        nextEntries.insert(entry, at: 0)
        nextEntries = Self.cleaned(nextEntries)
        // 등록된 canonical과 일치하는 pending 후보를 함께 제거해 목록에 잔존하지 않게 한다.
        let nextPending = candidatesExcluding(canonical: entry.normalizedCanonical)
        guard save(nextEntries, pendingCandidates: nextPending) else { return false }
        entries = nextEntries
        pendingCandidates = nextPending
        return true
    }

    /// 기존 용어를 제자리에서 수정한다. id·enabled는 보존하고 updatedAt만 갱신.
    /// 바뀐 canonical이 다른 항목과 겹치면 add와 같은 의미로 그 항목을 대체한다.
    @discardableResult
    public func update(
        _ id: UUID,
        canonical: String,
        aliasesText: String = "",
        description: String = "",
        category: String = "",
        tagsText: String = ""
    ) -> Bool {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return false }
        let trimmedCanonical = canonical.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCanonical.isEmpty else { return false }

        var nextEntries = entries
        nextEntries.removeAll {
            $0.id != id
                && $0.normalizedCanonical.compare(trimmedCanonical, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
        guard let nextIndex = nextEntries.firstIndex(where: { $0.id == id }) else { return false }
        nextEntries[nextIndex].canonical = trimmedCanonical
        nextEntries[nextIndex].aliases = Self.parseList(aliasesText)
        nextEntries[nextIndex].description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        nextEntries[nextIndex].category = category.trimmingCharacters(in: .whitespacesAndNewlines)
        nextEntries[nextIndex].tags = Self.parseList(tagsText)
        nextEntries[nextIndex].updatedAt = Date()
        nextEntries = Self.cleaned(nextEntries)
        // 등록된 canonical과 일치하는 pending 후보를 함께 제거해 목록에 잔존하지 않게 한다.
        let nextPending = candidatesExcluding(canonical: trimmedCanonical)
        guard save(nextEntries, pendingCandidates: nextPending) else { return false }
        entries = nextEntries
        pendingCandidates = nextPending
        return true
    }

    /// 등록된 용어들이 실제로 쓰는 묶음 이름 목록 (가나다순).
    public var categories: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            let category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !category.isEmpty else { continue }
            let key = category.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(category)
        }
        return result.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    /// 설정 화면의 관리용 분류별 묶음 목록. 비활성 용어도 포함한다.
    public var groupedEntriesByCategory: [(category: String, entries: [GlossaryEntry])] {
        Self.groupedEntriesByCategory(entries)
    }

    /// 회의 시작/파일 임포트 선택 UI에서 쓸 usable 전용 분류별 묶음 목록.
    public var usableGroupedEntriesByCategory: [(category: String, entries: [GlossaryEntry])] {
        Self.groupedEntriesByCategory(entries.filter(\.isUsable))
    }

    public var categorySelectionNames: [String] {
        usableGroupedEntriesByCategory.map(\.category)
    }

    /// 선택된 분류에 포함되는 usable 용어만 반환한다. "기타"는 빈 분류 항목을 뜻한다.
    public func entries(inCategories selectedCategories: Set<String>) -> [GlossaryEntry] {
        let selected = Set(selectedCategories.map(Self.displayCategoryName(for:)))
        guard !selected.isEmpty else { return [] }
        return entries.filter { entry in
            entry.isUsable && selected.contains(Self.displayCategoryName(for: entry.category))
        }
    }

    public func setEnabled(_ id: UUID, enabled: Bool) {
        var nextEntries = entries
        guard let index = nextEntries.firstIndex(where: { $0.id == id }) else { return }
        nextEntries[index].enabled = enabled
        nextEntries[index].updatedAt = Date()
        nextEntries = Self.cleaned(nextEntries)
        guard save(nextEntries) else { return }
        entries = nextEntries
    }

    public func delete(_ id: UUID) {
        let nextEntries = entries.filter { $0.id != id }
        let nextAliases = pendingAliases.filter { $0.entryID != id }
        guard save(nextEntries, pendingAliases: nextAliases) else { return }
        entries = nextEntries
        pendingAliases = nextAliases
    }

    public func candidates(for topic: String, limit: Int = 8) -> [GlossaryEntry] {
        let usable = entries.filter(\.isUsable)
        let scored = usable.map { entry in
            (entry: entry, score: Self.relevanceScore(entry, query: topic))
        }
        return scored
            .filter { $0.score > 0 }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.entry.updatedAt > $1.entry.updatedAt
            }
            .prefix(limit)
            .map(\.entry)
    }

    /// 프롬프트 한 줄에 포함하는 설명 최대 길이. 길게 저장해도 AI에는 이만큼만 전달된다.
    nonisolated public static let promptDescriptionMaxLength = 80

    nonisolated public static func promptLines(for entries: [GlossaryEntry]) -> [String] {
        cleaned(entries, sortByUpdatedAt: false).filter(\.isUsable).map { entry in
            var line = entry.normalizedCanonical
            let aliases = entry.aliases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            if !aliases.isEmpty {
                line += " = \(aliases.joined(separator: ", "))"
            }
            let description = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !description.isEmpty {
                line += " — \(String(description.prefix(promptDescriptionMaxLength)))"
            }
            return line
        }
    }

    /// 등록된 canonical과 folding-equal한 pending 후보를 제외한 목록을 반환한다.
    private func candidatesExcluding(canonical: String) -> [GlossaryCandidate] {
        let foldLocale = Locale(identifier: "en_US_POSIX")
        let key = canonical.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldLocale)
        return pendingCandidates.filter { candidate in
            candidate.term.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: foldLocale) != key
        }
    }

    /// - Parameters:
    ///   - entriesToSave: nil이면 현재 메모리의 entries를 그대로 저장한다.
    ///   - pendingToSave: nil이면 현재 메모리의 pendingCandidates를 그대로 저장한다.
    @discardableResult
    private func save(
        _ entriesToSave: [GlossaryEntry]? = nil,
        pendingCandidates pendingToSave: [GlossaryCandidate]? = nil,
        pendingAliases aliasesToSave: [GlossaryAliasSuggestion]? = nil,
        dismissedAliasKeys dismissedKeysToSave: [String]? = nil
    ) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let snapshot = GlossarySnapshot(
                schemaVersion: Self.schemaVersion,
                entries: entriesToSave ?? entries,
                pendingCandidates: pendingToSave ?? pendingCandidates,
                pendingAliases: aliasesToSave ?? pendingAliases,
                dismissedAliasKeys: dismissedKeysToSave ?? dismissedAliasKeys
            )
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            Log.store.error("GlossaryStore 저장 실패: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated private static func cleaned(_ raw: [GlossaryEntry], sortByUpdatedAt: Bool = true) -> [GlossaryEntry] {
        var seen = Set<String>()
        var cleanedEntries: [GlossaryEntry] = []
        for var entry in raw {
            entry.canonical = entry.canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.aliases = uniqueLines(entry.aliases)
            entry.description = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.category = entry.category.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.tags = uniqueLines(entry.tags)
            guard !entry.canonical.isEmpty else { continue }
            let key = entry.canonical.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            cleanedEntries.append(entry)
        }
        guard sortByUpdatedAt else { return cleanedEntries }
        return cleanedEntries.sorted { $0.updatedAt > $1.updatedAt }
    }

    nonisolated private static func parseList(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",\n")
        return uniqueLines(
            text.components(separatedBy: separators)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        )
    }

    nonisolated private static func uniqueLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    nonisolated public static func displayCategoryName(for category: String) -> String {
        let trimmed = category.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? uncategorizedCategoryName : trimmed
    }

    nonisolated public static func groupedEntriesByCategory(
        _ entries: [GlossaryEntry]
    ) -> [(category: String, entries: [GlossaryEntry])] {
        let grouped = Dictionary(grouping: entries) { entry in
            displayCategoryName(for: entry.category)
        }
        return grouped.keys.sorted { lhs, rhs in
            let lhsIndex = defaultCategoryPresets.firstIndex(of: lhs) ?? Int.max
            let rhsIndex = defaultCategoryPresets.firstIndex(of: rhs) ?? Int.max
            if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
            return lhs.localizedStandardCompare(rhs) == .orderedAscending
        }
        .map { category in
            let entries = grouped[category] ?? []
            return (category: category, entries: entries)
        }
    }

    nonisolated private static func matchingEntry(for canonical: String, in entries: [GlossaryEntry]) -> GlossaryEntry? {
        let key = foldedKey(canonical)
        return entries.first { entry in
            foldedKey(entry.canonical) == key || entry.aliases.contains { foldedKey($0) == key }
        }
    }

    nonisolated private static func aliasDismissKey(entryID: UUID, alias: String) -> String {
        aliasDismissKey(entryID: entryID, aliasKey: foldedKey(alias))
    }

    nonisolated private static func aliasDismissKey(entryID: UUID, aliasKey: String) -> String {
        "\(entryID.uuidString)|\(aliasKey)"
    }

    nonisolated private static func appendingDismissedAliasKey(_ key: String, to keys: [String]) -> [String] {
        guard !key.isEmpty else { return cappedDismissedAliasKeys(keys) }
        var next = keys.filter { $0 != key }
        next.append(key)
        return cappedDismissedAliasKeys(next)
    }

    nonisolated private static func cappedDismissedAliasKeys(_ keys: [String]) -> [String] {
        let unique = keys.reduce(into: [String]()) { result, key in
            guard !key.isEmpty, !result.contains(key) else { return }
            result.append(key)
        }
        guard unique.count > 200 else { return unique }
        return Array(unique.suffix(200))
    }

    nonisolated private static func foldedKey(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    nonisolated private static func relevanceScore(_ entry: GlossaryEntry, query: String) -> Int {
        let foldedQuery = query.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
        guard !foldedQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return 0 }
        let fields = [entry.canonical, entry.description, entry.category] + entry.aliases + entry.tags
        return fields.reduce(0) { score, field in
            let folded = field.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            return foldedQuery.contains(folded) || folded.contains(foldedQuery) ? score + 1 : score
        }
    }
}

public struct GlossarySnapshot: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let entries: [GlossaryEntry]
    public let pendingCandidates: [GlossaryCandidate]
    public let pendingAliases: [GlossaryAliasSuggestion]
    public let dismissedAliasKeys: [String]

    public init(
        schemaVersion: Int,
        entries: [GlossaryEntry],
        pendingCandidates: [GlossaryCandidate] = [],
        pendingAliases: [GlossaryAliasSuggestion] = [],
        dismissedAliasKeys: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.entries = entries
        self.pendingCandidates = pendingCandidates
        self.pendingAliases = pendingAliases
        self.dismissedAliasKeys = dismissedAliasKeys
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, entries, pendingCandidates, pendingAliases, dismissedAliasKeys
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        entries = try c.decode([GlossaryEntry].self, forKey: .entries)
        // 기존 schemaVersion 1 파일에는 새 pending 필드가 없으므로 tolerant 디코딩.
        pendingCandidates = (try? c.decode([GlossaryCandidate].self, forKey: .pendingCandidates)) ?? []
        pendingAliases = (try? c.decode([GlossaryAliasSuggestion].self, forKey: .pendingAliases)) ?? []
        dismissedAliasKeys = (try? c.decode([String].self, forKey: .dismissedAliasKeys)) ?? []
    }
}

public struct GlossaryContextResolver: Sendable {
    public static let defaultMaxCharacters = 1_200

    public let maxCharacters: Int

    public init(maxCharacters: Int = Self.defaultMaxCharacters) {
        self.maxCharacters = maxCharacters
    }

    public func resolve(
        manualGlossary: String,
        selectedEntries: [GlossaryEntry]
    ) -> String {
        let selectedLines = GlossaryStore.promptLines(for: selectedEntries)
        let manualLines = manualGlossary
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return fitLines(uniqueLines(selectedLines + manualLines), maxCharacters: maxCharacters)
    }

    private func uniqueLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let key = canonicalKey(for: trimmed)
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(trimmed)
        }
        return result
    }

    private func fitLines(_ lines: [String], maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }
        var result: [String] = []
        var currentCount = 0

        for line in lines {
            let additionalCount = line.count + (result.isEmpty ? 0 : 1)
            if currentCount + additionalCount <= maxCharacters {
                result.append(line)
                currentCount += additionalCount
            } else if result.isEmpty {
                return String(line.prefix(maxCharacters)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return result.joined(separator: "\n")
    }

    private func canonicalKey(for line: String) -> String {
        let separators = ["=", "—"]
        let canonical = separators
            .compactMap { separator -> String? in
                guard let range = line.range(of: separator) else { return nil }
                return String(line[..<range.lowerBound])
            }
            .min { $0.count < $1.count } ?? line
        return canonical.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
    }
}
