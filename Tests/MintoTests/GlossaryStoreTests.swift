import Testing
@testable import MintoCore
import Foundation

@MainActor
@Suite("GlossaryStore", .serialized)
struct GlossaryStoreTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-glossary-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    @Test("용어 추가 후 새 store에서 다시 읽는다")
    func addAndReload() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url)
        #expect(store.add(canonical: "Liquibase", aliasesText: "리퀴베이스, liqui base", description: "DB 스키마 변경 관리") == true)

        let reloaded = GlossaryStore(fileURL: url)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries[0].canonical == "Liquibase")
        #expect(reloaded.entries[0].aliases == ["리퀴베이스", "liqui base"])
        #expect(reloaded.entries[0].description == "DB 스키마 변경 관리")
    }

    @Test("저장 파일은 schemaVersion envelope를 사용한다")
    func savesSnapshotEnvelope() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url)
        #expect(store.add(canonical: "Liquibase") == true)

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GlossarySnapshot.self, from: data)

        #expect(snapshot.schemaVersion == GlossaryStore.schemaVersion)
        #expect(snapshot.entries.map(\.canonical) == ["Liquibase"])
    }

    @Test("legacy 배열 파일은 snapshot envelope로 마이그레이션한다")
    func migratesLegacyArrayFile() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let legacyEntries = [
            GlossaryEntry(canonical: "LegacyTerm", aliases: ["레거시"], description: "이전 형식")
        ]
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacyEntries).write(to: url, options: .atomic)

        let store = GlossaryStore(fileURL: url)
        #expect(store.entries.map(\.canonical) == ["LegacyTerm"])

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GlossarySnapshot.self, from: data)
        #expect(snapshot.schemaVersion == GlossaryStore.schemaVersion)
        #expect(snapshot.entries.map(\.canonical) == ["LegacyTerm"])
    }

    @Test("빈 용어는 저장하지 않고 같은 canonical은 최신 항목으로 교체한다")
    func rejectsEmptyAndDeduplicatesCanonical() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url)

        #expect(store.add(canonical: "   ") == false)
        #expect(store.add(canonical: "Liquibase", description: "old") == true)
        #expect(store.add(canonical: "liquibase", description: "new") == true)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].canonical == "liquibase")
        #expect(store.entries[0].description == "new")
    }

    @Test("저장 실패 시 메모리 상태를 먼저 바꾸지 않는다")
    func doesNotPublishUnsavedChanges() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-glossary-directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = GlossaryStore(fileURL: directoryURL)
        #expect(store.add(canonical: "Liquibase") == false)
        #expect(store.entries.isEmpty)
    }

    @Test("후보는 주제와 맞는 enabled 용어를 우선한다")
    func ranksCandidatesByTopic() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url)

        #expect(store.add(canonical: "Notion", tagsText: "문서") == true)
        #expect(store.add(canonical: "Liquibase", aliasesText: "리퀴베이스", description: "DB 스키마 변경 관리", tagsText: "db") == true)
        let disabledID = store.entries.first { $0.canonical == "Notion" }!.id
        store.setEnabled(disabledID, enabled: false)

        let candidates = store.candidates(for: "db 스키마 형상 관리", limit: 4)

        #expect(candidates.map(\.canonical) == ["Liquibase"])
    }

    @Test("주제와 맞지 않는 0점 용어는 추천하지 않는다")
    func excludesZeroScoreCandidates() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url)

        #expect(store.add(canonical: "Notion", tagsText: "문서") == true)

        #expect(store.candidates(for: "", limit: 4).isEmpty)
        #expect(store.candidates(for: "결제 정산", limit: 4).isEmpty)
    }

    @Test("resolver는 선택 항목과 회의별 입력을 중복 없이 병합한다")
    func resolverMergesSelectedEntriesWithManualGlossary() {
        let selected = [
            GlossaryEntry(
                canonical: "Liquibase",
                aliases: ["리퀴베이스"],
                description: "DB 스키마 변경 관리",
                updatedAt: Date(timeIntervalSince1970: 2)
            )
        ]

        let merged = GlossaryContextResolver().resolve(
            manualGlossary: "Liquibase\nFlyway",
            selectedEntries: selected
        )

        #expect(merged == "Liquibase = 리퀴베이스 — DB 스키마 변경 관리\nFlyway")
    }

    @Test("resolver는 항목 수 대신 문자 예산 안에서 가능한 용어를 포함한다")
    func resolverUsesCharacterBudgetInsteadOfEntryCount() {
        let selected = [
            GlossaryEntry(canonical: "Liquibase"),
            GlossaryEntry(canonical: "Flyway"),
            GlossaryEntry(canonical: "ArgoCD"),
            GlossaryEntry(canonical: "Terraform"),
            GlossaryEntry(canonical: "Kubernetes")
        ]

        let merged = GlossaryContextResolver(maxCharacters: 1_000).resolve(
            manualGlossary: "Confluence\nNotion\nJira",
            selectedEntries: selected
        )

        #expect(merged.split(whereSeparator: { $0.isNewline }).count == 8)
        #expect(merged.contains("Liquibase"))
        #expect(merged.contains("Kubernetes"))
        #expect(merged.contains("Jira"))
    }

    @Test("resolver는 프롬프트 용어 수와 길이를 제한한다")
    func resolverCapsPromptSize() {
        let entries = (1...5).map {
            GlossaryEntry(canonical: "Term\($0)", description: String(repeating: "가", count: 120))
        }

        let merged = GlossaryContextResolver(maxCharacters: 40).resolve(
            manualGlossary: "ManualTerm",
            selectedEntries: entries
        )

        #expect(merged.count <= 40)
        #expect(merged.contains("Term1"))
    }
}
