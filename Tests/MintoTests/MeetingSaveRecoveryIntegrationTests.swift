import Testing
@testable import MintoCore
import Foundation

/// MeetingSaveRecovery 통합 테스트.
/// 저장 실패 → 복구 파일 생성 → 복원 호출 → store 반영 → 파일 삭제 전 과정을 검증한다.
@MainActor
@Suite("MeetingSaveRecoveryIntegration", .serialized)
struct MeetingSaveRecoveryIntegrationTests {

    private func tempDir(label: String = UUID().uuidString) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-integration-\(label)", isDirectory: true)
    }

    private func sampleRecord(title: String = "통합 테스트 회의") -> MeetingRecord {
        MeetingRecord(
            title: title,
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            durationSeconds: 90,
            topic: "통합 테스트",
            summary: MeetingSummary(leadAnswer: "통합 요약"),
            transcript: [Segment(text: "통합 테스트 발화", timestamp: Date(timeIntervalSince1970: 1_700_000_000), duration: 5)]
        )
    }

    // MARK: - End-to-end: 단일 복구 파일

    @Test("복구 파일 생성 후 복원하면 store에 나타나고 파일이 삭제된다")
    func testEndToEndRecoveryAndRestore() throws {
        let recoveryDir = tempDir(label: "recovery")
        let storeDir = tempDir(label: "store")
        defer {
            try? FileManager.default.removeItem(at: recoveryDir)
            try? FileManager.default.removeItem(at: storeDir)
        }

        // 1단계: 저장 실패 시나리오 — 복구 파일 생성
        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: recoveryDir)

        // 복구 파일(.json, .md) 생성 확인
        let beforeFiles = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        #expect(beforeFiles.filter { $0.pathExtension == "json" }.count == 1)
        #expect(beforeFiles.filter { $0.pathExtension == "md" }.count == 1)

        // 2단계: 앱 재시작 시나리오 — 복원 호출
        let store = MeetingStore(directory: storeDir)
        let (restored, failed) = MeetingSaveRecovery.restorePendingRecords(into: store, recoveryDirectory: recoveryDir)

        // 3단계: store에 나타남 확인
        #expect(restored == 1)
        #expect(failed == 0)
        #expect(store.meetings.contains { $0.id == record.id })

        // 4단계: 복구 파일 삭제 확인
        let afterFiles = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        #expect(afterFiles.isEmpty)
    }

    // MARK: - End-to-end: 복수 복구 파일

    @Test("복구 파일이 여러 개일 때 모두 복원되고 모든 파일이 삭제된다")
    func testRecoveryWithMultipleFiles() throws {
        let recoveryDir = tempDir(label: "recovery-multi")
        let storeDir = tempDir(label: "store-multi")
        defer {
            try? FileManager.default.removeItem(at: recoveryDir)
            try? FileManager.default.removeItem(at: storeDir)
        }

        let records = [
            sampleRecord(title: "회의 A"),
            sampleRecord(title: "회의 B"),
            sampleRecord(title: "회의 C"),
        ]

        // 복구 파일 3개 생성
        for record in records {
            MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: recoveryDir)
        }

        let store = MeetingStore(directory: storeDir)
        let (restored, failed) = MeetingSaveRecovery.restorePendingRecords(into: store, recoveryDirectory: recoveryDir)

        #expect(restored == 3)
        #expect(failed == 0)

        // store에 3개 모두 존재
        for record in records {
            #expect(store.meetings.contains { $0.id == record.id })
        }

        // 복구 디렉터리 비어 있음
        let afterFiles = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        #expect(afterFiles.isEmpty)
    }

    // MARK: - 부분 실패: 손상 파일 + 정상 파일 혼재

    @Test("손상 파일과 정상 파일이 섞여 있으면 정상 파일만 복원되고 손상 파일은 남는다")
    func testPartialFailureWithCorruptFile() throws {
        let recoveryDir = tempDir(label: "recovery-partial")
        let storeDir = tempDir(label: "store-partial")
        defer {
            try? FileManager.default.removeItem(at: recoveryDir)
            try? FileManager.default.removeItem(at: storeDir)
        }

        // 손상 파일 삽입
        try FileManager.default.createDirectory(at: recoveryDir, withIntermediateDirectories: true)
        let corruptURL = recoveryDir.appendingPathComponent("corrupt.json")
        try Data("{ invalid json }".utf8).write(to: corruptURL)

        // 정상 복구 파일 2개
        let record1 = sampleRecord(title: "정상 회의 1")
        let record2 = sampleRecord(title: "정상 회의 2")
        MeetingSaveRecovery.writeRecoveryFile(for: record1, recoveryDirectory: recoveryDir)
        MeetingSaveRecovery.writeRecoveryFile(for: record2, recoveryDirectory: recoveryDir)

        let store = MeetingStore(directory: storeDir)
        let (restored, failed) = MeetingSaveRecovery.restorePendingRecords(into: store, recoveryDirectory: recoveryDir)

        // 정상 2건 복원, 손상 1건 실패
        #expect(restored == 2)
        #expect(failed == 1)
        #expect(store.meetings.contains { $0.id == record1.id })
        #expect(store.meetings.contains { $0.id == record2.id })

        // 손상 파일만 남음
        let remaining = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        #expect(remaining.count == 1)
        #expect(remaining[0].lastPathComponent == "corrupt.json")
    }

    // MARK: - JSON 내용 검증

    @Test("복구 JSON을 직접 디코드하면 원본 record와 동일하다")
    func testJsonContentMatchesOriginal() throws {
        let recoveryDir = tempDir(label: "recovery-json")
        defer { try? FileManager.default.removeItem(at: recoveryDir) }

        let record = sampleRecord()
        MeetingSaveRecovery.writeRecoveryFile(for: record, recoveryDirectory: recoveryDir)

        let files = try FileManager.default.contentsOfDirectory(at: recoveryDir, includingPropertiesForKeys: nil)
        let jsonURL = try #require(files.first { $0.pathExtension == "json" })
        let data = try Data(contentsOf: jsonURL)
        let decoder = MeetingRecordCoding.makeDecoder()
        let decoded = try decoder.decode(MeetingRecord.self, from: data)

        #expect(decoded.id == record.id)
        #expect(decoded.title == record.title)
        #expect(decoded.transcript.count == record.transcript.count)
        #expect(decoded.transcript.first?.text == record.transcript.first?.text)
    }

    // MARK: - 복구 디렉터리 미존재

    @Test("복구 디렉터리가 없으면 (0, 0)을 반환하고 크래시하지 않는다")
    func testNonExistentRecoveryDirectory() {
        let storeDir = tempDir(label: "store-nodir")
        let nonExistentDir = tempDir(label: "nonexistent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: storeDir) }
        // nonExistentDir는 생성하지 않음

        let store = MeetingStore(directory: storeDir)
        let (restored, failed) = MeetingSaveRecovery.restorePendingRecords(into: store, recoveryDirectory: nonExistentDir)

        #expect(restored == 0)
        #expect(failed == 0)
    }
}
