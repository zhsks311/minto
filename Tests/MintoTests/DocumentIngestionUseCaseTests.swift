import Foundation
import Testing
@testable import MintoCore

@Suite("DocumentIngestionUseCase")
struct DocumentIngestionUseCaseTests {

    private func writeTempText(ext: String, _ content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingest-\(UUID().uuidString).\(ext)")
        try content.data(using: .utf8)!.write(to: url)
        return url
    }

    private func writeTempBinary(ext: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ingest-\(UUID().uuidString).\(ext)")
        try Data([0x00, 0x01, 0x02]).write(to: url)
        return url
    }

    @Test("여러 파일을 입력 순서대로 평문 문서로 모은다")
    func ingestsMultipleFilesInOrder() async throws {
        let first = try writeTempText(ext: "txt", "첫 번째 안건")
        let second = try writeTempText(ext: "md", "# 두 번째 안건")
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }

        let useCase = DocumentIngestionUseCase()
        let result = await useCase.ingest(urls: [first, second])

        #expect(result.documents.count == 2)
        #expect(result.failures.isEmpty)
        #expect(result.documents[0].text == "첫 번째 안건")
        #expect(result.documents[1].text == "# 두 번째 안건")
        #expect(result.documents.allSatisfy { $0.sourceKind == .file })
    }

    @Test("성공과 실패를 분리해 분류한다 — fail-soft")
    func separatesSuccessAndFailure() async throws {
        let good = try writeTempText(ext: "txt", "유효한 문서")
        let bad = try writeTempBinary(ext: "bin")
        defer {
            try? FileManager.default.removeItem(at: good)
            try? FileManager.default.removeItem(at: bad)
        }

        let useCase = DocumentIngestionUseCase()
        let result = await useCase.ingest(urls: [good, bad])

        #expect(result.documents.count == 1)
        #expect(result.documents[0].text == "유효한 문서")
        #expect(result.failures.count == 1)
        #expect(result.failures[0].reason == .unsupportedFormat)
        #expect(result.failures[0].sourceLabel == bad.lastPathComponent)
    }

    @Test("빈 입력은 빈 결과를 돌려준다")
    func emptyInputYieldsEmptyResult() async throws {
        let useCase = DocumentIngestionUseCase()
        let result = await useCase.ingest(urls: [])

        #expect(result.documents.isEmpty)
        #expect(result.failures.isEmpty)
    }

    @Test("operation 이 제한 시간을 넘으면 timeout 으로 분류한다")
    func slowOperationTimesOut() async throws {
        // operation 은 1초, timeout 은 20ms → 결정론적으로 timeout 이 이긴다.
        let result = await DocumentIngestionUseCase.resultWithinTimeout(.milliseconds(20)) {
            try? await Task.sleep(for: .seconds(1))
            return .success(AttachedDocument(id: "x", title: "t", text: "느림", sourceKind: .file, sourceLabel: nil))
        }

        #expect(result == .failure(.timeout))
    }

    @Test("operation 이 제한 시간 안에 끝나면 그 결과를 돌려준다")
    func fastOperationReturnsResult() async throws {
        // operation 즉시 반환, timeout 10초 → 결정론적으로 operation 이 이긴다.
        let document = AttachedDocument(id: "x", title: "t", text: "빠름", sourceKind: .file, sourceLabel: nil)
        let result = await DocumentIngestionUseCase.resultWithinTimeout(.seconds(10)) {
            .success(document)
        }

        #expect(result == .success(document))
    }
}
