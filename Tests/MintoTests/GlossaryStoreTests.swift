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

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase", aliasesText: "리퀴베이스, liqui base", description: "DB 스키마 변경 관리") == true)

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.entries.count == 1)
        #expect(reloaded.entries[0].canonical == "Liquibase")
        #expect(reloaded.entries[0].aliases == ["리퀴베이스", "liqui base"])
        #expect(reloaded.entries[0].description == "DB 스키마 변경 관리")
    }

    @Test("저장 파일은 schemaVersion envelope를 사용한다")
    func savesSnapshotEnvelope() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
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

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
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
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

        #expect(store.add(canonical: "   ") == false)
        #expect(store.add(canonical: "Liquibase", description: "old") == true)
        #expect(store.add(canonical: "liquibase", description: "new") == true)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].canonical == "liquibase")
        #expect(store.entries[0].description == "new")
    }

    @Test("용어 수정은 id와 enabled를 보존하고 내용만 바꾼다")
    func updatePreservesIdentityAndEnabled() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

        #expect(store.add(canonical: "Liquibase", description: "old", category: "개발") == true)
        let entry = store.entries[0]
        store.setEnabled(entry.id, enabled: false)

        #expect(store.update(
            entry.id,
            canonical: "Liquibase",
            aliasesText: "리퀴베이스",
            description: "DB 스키마 변경 관리",
            category: "백엔드팀"
        ) == true)

        #expect(store.entries.count == 1)
        let updated = store.entries[0]
        #expect(updated.id == entry.id)
        #expect(updated.enabled == false)
        #expect(updated.aliases == ["리퀴베이스"])
        #expect(updated.description == "DB 스키마 변경 관리")
        #expect(updated.category == "백엔드팀")

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.entries[0].category == "백엔드팀")
    }

    @Test("수정한 canonical이 다른 항목과 겹치면 그 항목을 대체한다")
    func updateReplacesCollidingCanonical() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

        #expect(store.add(canonical: "Flyway") == true)
        #expect(store.add(canonical: "Liquibase") == true)
        let liquibaseID = store.entries.first { $0.canonical == "Liquibase" }!.id

        #expect(store.update(liquibaseID, canonical: "flyway", description: "병합됨") == true)

        #expect(store.entries.count == 1)
        #expect(store.entries[0].id == liquibaseID)
        #expect(store.entries[0].canonical == "flyway")
    }

    @Test("빈 canonical이나 없는 id로는 수정하지 않는다")
    func updateRejectsEmptyCanonicalAndUnknownID() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

        #expect(store.add(canonical: "Liquibase", description: "유지") == true)
        let id = store.entries[0].id

        #expect(store.update(id, canonical: "   ") == false)
        #expect(store.update(UUID(), canonical: "Flyway") == false)
        #expect(store.entries[0].description == "유지")
    }

    @Test("categories는 사용 중인 묶음을 중복 없이 가나다순으로 돌려준다")
    func categoriesListsUsedCategories() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

        #expect(store.add(canonical: "Liquibase", category: "개발") == true)
        #expect(store.add(canonical: "FBK", category: "나만의-백엔드팀") == true)
        #expect(store.add(canonical: "Flyway", category: "개발") == true)
        #expect(store.add(canonical: "KC", category: "  ") == true)

        #expect(store.categories == ["개발", "나만의-백엔드팀"])
    }

    @Test("저장 실패 시 메모리 상태를 먼저 바꾸지 않는다")
    func doesNotPublishUnsavedChanges() throws {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-glossary-directory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directoryURL) }

        let store = GlossaryStore(fileURL: directoryURL, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase") == false)
        #expect(store.entries.isEmpty)
    }

    @Test("후보는 주제와 맞는 enabled 용어를 우선한다")
    func ranksCandidatesByTopic() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

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
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

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

    // MARK: - GlossaryCandidate 테스트

    @Test("pendingCandidates 없는 기존 JSON 로드 시 빈 배열 반환")
    func loadLegacySnapshotWithoutPendingCandidates() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        // pendingCandidates 없는 기존 snapshot JSON 직접 작성
        let json = """
        {
          "schemaVersion": 1,
          "entries": []
        }
        """
        try json.data(using: .utf8)!.write(to: url, options: .atomic)

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.pendingCandidates.isEmpty)
    }

    @Test("dismissCandidate는 해당 후보를 제거하고 영속한다")
    func dismissCandidateRemovesAndPersists() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let meetingID = UUID()
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        let candidate = GlossaryCandidate(term: "Liquibase", sourceMeetingID: meetingID)
        store.addCandidates([candidate])
        #expect(store.pendingCandidates.count == 1)

        store.dismissCandidate(candidate.id)
        #expect(store.pendingCandidates.isEmpty)

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.pendingCandidates.isEmpty)
    }

    @Test("approveCandidate는 해당 후보를 제거하고 영속한다")
    func approveCandidateRemovesAndPersists() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let meetingID = UUID()
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        let candidate = GlossaryCandidate(term: "Flyway", sourceMeetingID: meetingID)
        store.addCandidates([candidate])
        #expect(store.pendingCandidates.count == 1)

        store.approveCandidate(candidate.id)
        #expect(store.pendingCandidates.isEmpty)

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.pendingCandidates.isEmpty)
    }

    @Test("addCandidates는 pendingCandidates를 영속한다")
    func addCandidatesPersists() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let meetingID = UUID()
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        store.addCandidates([
            GlossaryCandidate(term: "ArgoCD", sourceMeetingID: meetingID),
            GlossaryCandidate(term: "Terraform", sourceMeetingID: meetingID)
        ])
        #expect(store.pendingCandidates.count == 2)

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.pendingCandidates.count == 2)
        #expect(reloaded.pendingCandidates.map(\.term).sorted() == ["ArgoCD", "Terraform"])
    }

    // MARK: - 교정 별칭 제안 테스트

    @Test("ingestCorrectionAliases는 기존 용어에 alias 제안을 축적하고 중복을 제외한다")
    func ingestCorrectionAliasesAccumulatesAliasSuggestionsForExistingEntry() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase", aliasesText: "리퀴베이스") == true)

        store.ingestCorrectionAliases([
            (canonical: "Liquibase", alias: "리퀴베이스"),
            (canonical: "liquibase", alias: "리퀴 베이스"),
            (canonical: "LIQUIBASE", alias: "리퀴 베이스")
        ])

        #expect(store.entries[0].aliases == ["리퀴베이스"])
        #expect(store.pendingAliases.count == 1)
        #expect(store.pendingAliases[0].entryID == store.entries[0].id)
        #expect(store.pendingAliases[0].alias == "리퀴 베이스")
    }

    @Test("ingestCorrectionAliases는 기존 alias와 canonical을 대조해 entry를 찾는다")
    func ingestCorrectionAliasesMatchesExistingEntryAlias() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase", aliasesText: "리퀴베이스") == true)

        store.ingestCorrectionAliases([
            (canonical: "리퀴베이스", alias: "리퀴 베이스")
        ])

        #expect(store.pendingAliases.count == 1)
        #expect(store.pendingAliases[0].entryID == store.entries[0].id)
        #expect(store.pendingCandidates.isEmpty)
    }

    @Test("pendingAliases는 30개 상한을 유지한다")
    func ingestCorrectionAliasesCapsAliasSuggestions() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase") == true)

        store.ingestCorrectionAliases((1...31).map {
            (canonical: "Liquibase", alias: "alias-\($0)")
        })

        #expect(store.pendingAliases.count == 30)
    }

    @Test("기존 용어가 없으면 후보에 suggestedAliases를 함께 축적한다")
    func ingestCorrectionAliasesAccumulatesCandidateAliases() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        store.ingestCorrectionAliases([
            (canonical: "Liquibase", alias: "리퀴베이스"),
            (canonical: "liquibase", alias: "리퀴 베이스"),
            (canonical: "LIQUIBASE", alias: "리퀴 베이스")
        ])

        #expect(store.pendingCandidates.count == 1)
        #expect(store.pendingCandidates[0].term == "Liquibase")
        #expect(store.pendingCandidates[0].sourceMeetingID == nil)
        #expect(store.pendingCandidates[0].suggestedAliases == ["리퀴베이스", "리퀴 베이스"])
        #expect(store.pendingAliases.isEmpty)
    }

    @Test("pendingAliases와 candidate suggestedAliases가 없는 snapshot을 하위 호환 로드한다")
    func loadLegacySnapshotWithoutAliasSuggestionFields() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let candidateID = UUID()
        let meetingID = UUID()
        let json = """
        {
          "schemaVersion": 1,
          "entries": [],
          "pendingCandidates": [
            {
              "id": "\(candidateID.uuidString)",
              "term": "Liquibase",
              "sourceMeetingID": "\(meetingID.uuidString)",
              "suggestedAt": "2026-06-11T00:00:00Z"
            }
          ]
        }
        """
        try json.data(using: .utf8)!.write(to: url, options: .atomic)

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.pendingAliases.isEmpty)
        #expect(store.dismissedAliasKeys.isEmpty)
        #expect(store.pendingCandidates.count == 1)
        #expect(store.pendingCandidates[0].suggestedAliases.isEmpty)
        #expect(store.pendingCandidates[0].sourceMeetingID == meetingID)
    }

    @Test("approveAliasSuggestion은 entry aliases에 추가하고 영속한다")
    func approveAliasSuggestionAddsAliasAndPersists() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase") == true)
        store.ingestCorrectionAliases([(canonical: "Liquibase", alias: "리퀴베이스")])

        let suggestion = try #require(store.pendingAliases.first)
        store.approveAliasSuggestion(suggestion.id)

        #expect(store.pendingAliases.isEmpty)
        #expect(store.entries[0].aliases == ["리퀴베이스"])

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.pendingAliases.isEmpty)
        #expect(reloaded.entries[0].aliases == ["리퀴베이스"])
    }

    @Test("dismissAliasSuggestion은 제안만 제거하고 영속한다")
    func dismissAliasSuggestionRemovesSuggestionAndPersists() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase") == true)
        store.ingestCorrectionAliases([(canonical: "Liquibase", alias: "리퀴베이스")])

        let suggestion = try #require(store.pendingAliases.first)
        store.dismissAliasSuggestion(suggestion.id)

        #expect(store.pendingAliases.isEmpty)
        #expect(store.entries[0].aliases.isEmpty)

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.pendingAliases.isEmpty)
        #expect(reloaded.entries[0].aliases.isEmpty)
    }

    @Test("dismissAliasSuggestion은 같은 alias 제안 재유입을 영속 차단한다")
    func dismissAliasSuggestionBlocksReinsertionAndPersists() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase") == true)
        store.ingestCorrectionAliases([(canonical: "Liquibase", alias: "리퀴베이스")])

        let suggestion = try #require(store.pendingAliases.first)
        store.dismissAliasSuggestion(suggestion.id)
        store.ingestCorrectionAliases([(canonical: "Liquibase", alias: "리퀴베이스")])

        #expect(store.pendingAliases.isEmpty)

        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        reloaded.ingestCorrectionAliases([(canonical: "Liquibase", alias: "리퀴베이스")])

        #expect(reloaded.pendingAliases.isEmpty)
        #expect(reloaded.entries[0].aliases.isEmpty)
    }

    @Test("dismissedAliasKeys는 200개 상한을 유지한다")
    func dismissAliasSuggestionCapsDismissedKeys() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase") == true)

        for index in 1...205 {
            store.ingestCorrectionAliases([(canonical: "Liquibase", alias: "alias-\(index)")])
            let suggestion = try #require(store.pendingAliases.first)
            store.dismissAliasSuggestion(suggestion.id)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(GlossarySnapshot.self, from: data)

        #expect(snapshot.dismissedAliasKeys.count == 200)
        #expect(!snapshot.dismissedAliasKeys.contains(where: { $0.hasSuffix("|alias-1") }))
        #expect(snapshot.dismissedAliasKeys.contains(where: { $0.hasSuffix("|alias-6") }))
        #expect(snapshot.dismissedAliasKeys.contains(where: { $0.hasSuffix("|alias-205") }))
    }

    @Test("alias 제안 저장 실패 시 메모리 상태를 먼저 바꾸지 않는다")
    func ingestCorrectionAliasesDoesNotPublishOnSaveFailure() throws {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.add(canonical: "Liquibase") == true)

        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        store.ingestCorrectionAliases([(canonical: "Liquibase", alias: "리퀴베이스")])

        #expect(store.pendingAliases.isEmpty)
        #expect(store.entries[0].aliases.isEmpty)
    }

    // MARK: - extractNewCandidates 순수 함수 테스트

    @Test("extractNewCandidates: 기존 entries canonical과 일치하는 키워드 제외")
    func extractExcludesExistingCanonical() {
        let entries = [GlossaryEntry(canonical: "Liquibase")]
        let result = GlossaryStore.extractNewCandidates(
            keywords: ["Liquibase", "Flyway"],
            existingEntries: entries,
            existingPending: [],
            sourceMeetingID: UUID()
        )
        #expect(result.map(\.term) == ["Flyway"])
    }

    @Test("extractNewCandidates: 기존 entries alias와 case-insensitive 일치 제외")
    func extractExcludesExistingAlias() {
        let entries = [GlossaryEntry(canonical: "Liquibase", aliases: ["리퀴베이스", "LIQUI BASE"])]
        let result = GlossaryStore.extractNewCandidates(
            keywords: ["리퀴베이스", "ArgoCD"],
            existingEntries: entries,
            existingPending: [],
            sourceMeetingID: UUID()
        )
        #expect(result.map(\.term) == ["ArgoCD"])
    }

    @Test("extractNewCandidates: 기존 pending 중복 제외")
    func extractExcludesExistingPending() {
        let meetingID = UUID()
        let pending = [GlossaryCandidate(term: "Terraform", sourceMeetingID: meetingID)]
        let result = GlossaryStore.extractNewCandidates(
            keywords: ["Terraform", "ArgoCD"],
            existingEntries: [],
            existingPending: pending,
            sourceMeetingID: meetingID
        )
        #expect(result.map(\.term) == ["ArgoCD"])
    }

    @Test("extractNewCandidates: 2자 미만 키워드 제외")
    func extractExcludesShortKeywords() {
        let result = GlossaryStore.extractNewCandidates(
            keywords: ["A", "DB", "ArgoCD"],
            existingEntries: [],
            existingPending: [],
            sourceMeetingID: UUID()
        )
        #expect(result.map(\.term) == ["DB", "ArgoCD"])
    }

    @Test("addCandidates: 상한 20개 초과 시 오래된 것부터 교체")
    func addCandidatesEnforcesLimit() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        let meetingID = UUID()

        // 19개 먼저 추가 (suggestedAt 간격 1초)
        let existing = (1...19).map { i in
            GlossaryCandidate(
                term: "Term\(i)",
                sourceMeetingID: meetingID,
                suggestedAt: Date(timeIntervalSince1970: Double(i))
            )
        }
        store.addCandidates(existing)
        #expect(store.pendingCandidates.count == 19)

        // 3개 더 추가 → 총 22개 → 상한 20이므로 가장 오래된 2개(Term1, Term2) 제거
        let newer = (1...3).map { i in
            GlossaryCandidate(
                term: "New\(i)",
                sourceMeetingID: meetingID,
                suggestedAt: Date(timeIntervalSince1970: Double(100 + i))
            )
        }
        store.addCandidates(newer)
        #expect(store.pendingCandidates.count == 20)
        #expect(!store.pendingCandidates.map(\.term).contains("Term1"))
        #expect(!store.pendingCandidates.map(\.term).contains("Term2"))
        #expect(store.pendingCandidates.map(\.term).contains("Term3"))
    }

    // MARK: - pending 후보 자동 정리 테스트

    @Test("add() 성공 후 같은 term의 pending 후보를 case-insensitive로 제거한다")
    func addRemovesMatchingPendingCandidate() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let meetingID = UUID()
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

        // "liquibase"와 대소문자만 다른 pending 후보 추가
        store.addCandidates([
            GlossaryCandidate(term: "Liquibase", sourceMeetingID: meetingID),
            GlossaryCandidate(term: "LIQUIBASE", sourceMeetingID: meetingID),
            GlossaryCandidate(term: "Flyway", sourceMeetingID: meetingID)
        ])
        #expect(store.pendingCandidates.count == 3)

        // "liquibase" canonical로 add → 일치하는 후보 2개 제거
        #expect(store.add(canonical: "liquibase") == true)

        #expect(store.pendingCandidates.count == 1)
        #expect(store.pendingCandidates[0].term == "Flyway")
    }

    @Test("update() 성공 후 변경된 canonical과 일치하는 pending 후보를 제거한다")
    func updateRemovesMatchingPendingCandidate() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let meetingID = UUID()
        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)

        #expect(store.add(canonical: "Flyway") == true)
        let entryID = store.entries[0].id

        // update 대상 canonical과 일치하는 pending 후보 추가
        store.addCandidates([
            GlossaryCandidate(term: "ArgoCD", sourceMeetingID: meetingID),
            GlossaryCandidate(term: "flyway", sourceMeetingID: meetingID)
        ])
        #expect(store.pendingCandidates.count == 2)

        // canonical을 "flyway"로 update → "flyway" 후보 제거
        #expect(store.update(entryID, canonical: "flyway") == true)

        #expect(store.pendingCandidates.count == 1)
        #expect(store.pendingCandidates[0].term == "ArgoCD")
    }
}
