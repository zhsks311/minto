import Foundation
import Combine

@MainActor
public final class GlossaryStore: ObservableObject {
    public static let shared = GlossaryStore()
    public static let schemaVersion = 1

    @Published public private(set) var entries: [GlossaryEntry] = []

    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL? = nil) {
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
    }

    public func reload() {
        guard let data = try? Data(contentsOf: fileURL) else {
            entries = []
            return
        }
        if let snapshot = try? decoder.decode(GlossarySnapshot.self, from: data),
           snapshot.schemaVersion == Self.schemaVersion {
            entries = Self.cleaned(snapshot.entries)
        } else if let legacy = try? decoder.decode([GlossaryEntry].self, from: data) {
            entries = Self.cleaned(legacy)
            _ = save()
        } else {
            entries = []
        }
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
        guard save(nextEntries) else { return false }
        entries = nextEntries
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
        guard save(nextEntries) else { return false }
        entries = nextEntries
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
        guard save(nextEntries) else { return }
        entries = nextEntries
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

    private func save(_ entriesToSave: [GlossaryEntry]? = nil) -> Bool {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let snapshot = GlossarySnapshot(schemaVersion: Self.schemaVersion, entries: entriesToSave ?? entries)
            let data = try encoder.encode(snapshot)
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            fputs("[GlossaryStore] 저장 실패: \(error.localizedDescription)\n", stderr)
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

    public init(schemaVersion: Int, entries: [GlossaryEntry]) {
        self.schemaVersion = schemaVersion
        self.entries = entries
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
