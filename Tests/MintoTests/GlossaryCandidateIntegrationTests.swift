import Testing
@testable import MintoCore
import Foundation
import Combine

/// 용어 후보 추출 → 사용자 승인/거절 전체 흐름 통합 테스트.
///
/// Combine 구독 경로는 `.receive(on: DispatchQueue.main)`으로 인해 비동기 hop이 발생하므로
/// 테스트에서는 `ingestCandidates(from:)` 공개 메서드를 직접 호출해 동기 검증한다.
/// (실제 앱은 Combine 구독 → addCandidates 경로를 사용하며, 이는 GlossaryStoreTests에서 커버됨)
@MainActor
@Suite("GlossaryCandidateIntegration", .serialized)
struct GlossaryCandidateIntegrationTests {

    private func tempFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-glossary-integration-\(UUID().uuidString)")
            .appendingPathExtension("json")
    }

    private func makeRecord(
        id: UUID = UUID(),
        title: String = "테스트 회의",
        keywords: [String]
    ) -> MeetingRecord {
        MeetingRecord(
            id: id,
            title: title,
            startedAt: Date(),
            durationSeconds: 600,
            summary: MeetingSummary(keywords: keywords)
        )
    }

    // MARK: - extractedFromNewMeeting

    @Test("신규 회의의 keywords에서 후보를 추출한다")
    func extractedFromNewMeeting() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(store.pendingCandidates.isEmpty)

        let meetingID = UUID()
        let record = makeRecord(id: meetingID, title: "스프린트 계획 회의",
                                keywords: ["Liquibase", "ArgoCD", "배포"])

        store.ingestCandidates(from: record)

        // 모든 3개 키워드가 후보로 추가된다
        #expect(store.pendingCandidates.count == 3)
        let terms = Set(store.pendingCandidates.map(\.term))
        #expect(terms == ["Liquibase", "ArgoCD", "배포"])
        // 출처 회의 ID 보존
        #expect(store.pendingCandidates.allSatisfy { $0.sourceMeetingID == meetingID })
    }

    // MARK: - filtersExistingEntries

    @Test("기존 등록 용어는 후보에서 제외한다")
    func filtersExistingEntries() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        // "Liquibase"는 이미 등록된 용어 (aliases에 "리퀴베이스" 포함)
        #expect(store.add(canonical: "Liquibase", aliasesText: "리퀴베이스") == true)

        let record = makeRecord(keywords: ["Liquibase", "리퀴베이스", "ArgoCD"])
        store.ingestCandidates(from: record)

        // Liquibase(canonical)와 리퀴베이스(alias) 모두 제외, ArgoCD만 후보
        #expect(store.pendingCandidates.count == 1)
        #expect(store.pendingCandidates[0].term == "ArgoCD")
    }

    // MARK: - approveCandidateAdds

    @Test("후보 승인 후 용어 추가 시 entries에 등록되고 후보에서 제거된다")
    func approveCandidateAdds() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        let record = makeRecord(title: "인프라 리뷰", keywords: ["Terraform", "Kubernetes"])
        store.ingestCandidates(from: record)

        #expect(store.pendingCandidates.count == 2)
        let candidate = store.pendingCandidates.first { $0.term == "Terraform" }!

        // UI 폼에서 저장 → add()가 같은 canonical의 pending 후보를 자동 제거한다
        let added = store.add(canonical: candidate.term, category: "인프라")
        #expect(added == true)
        #expect(!store.pendingCandidates.map(\.term).contains("Terraform"))
        #expect(store.entries.contains { $0.canonical == "Terraform" })

        // 영속 확인
        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(reloaded.entries.contains { $0.canonical == "Terraform" })
        #expect(!reloaded.pendingCandidates.map(\.term).contains("Terraform"))
    }

    // MARK: - rejectCandidateRemoves

    @Test("후보 무시 시 pendingCandidates에서 제거되고 entries에는 추가되지 않는다")
    func rejectCandidateRemoves() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        let record = makeRecord(title: "제품 회의", keywords: ["Jira", "컨플루언스"])
        store.ingestCandidates(from: record)
        #expect(store.pendingCandidates.count == 2)

        let candidate = store.pendingCandidates.first { $0.term == "Jira" }!
        store.dismissCandidate(candidate.id)

        // 무시된 후보는 제거됨
        #expect(!store.pendingCandidates.map(\.term).contains("Jira"))
        // 컨플루언스는 남아있음
        #expect(store.pendingCandidates.map(\.term).contains("컨플루언스"))
        // entries에는 추가되지 않음
        #expect(store.entries.isEmpty)

        // 영속 확인
        let reloaded = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        #expect(!reloaded.pendingCandidates.map(\.term).contains("Jira"))
        #expect(reloaded.entries.isEmpty)
    }

    // MARK: - 중복 ingest

    @Test("같은 회의를 두 번 ingest해도 후보가 중복 추가되지 않는다")
    func duplicateIngestIgnored() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        let record = makeRecord(keywords: ["Liquibase", "ArgoCD"])

        store.ingestCandidates(from: record)
        #expect(store.pendingCandidates.count == 2)

        // 같은 회의 재 ingest → extractNewCandidates가 existing pending 중복을 제외
        store.ingestCandidates(from: record)
        #expect(store.pendingCandidates.count == 2)
    }

    // MARK: - 1자 키워드 필터링

    @Test("길이가 1인 키워드는 후보에서 제외한다")
    func shortKeywordsFiltered() {
        let url = tempFile()
        defer { try? FileManager.default.removeItem(at: url) }

        let store = GlossaryStore(fileURL: url, meetingsPublisher: nil)
        let record = makeRecord(keywords: ["A", "DB", "CI"])
        store.ingestCandidates(from: record)

        // "A"(1자) 제외, "DB"·"CI"(2자 이상) 포함
        let terms = store.pendingCandidates.map(\.term)
        #expect(!terms.contains("A"))
        #expect(terms.contains("DB"))
        #expect(terms.contains("CI"))
    }
}
