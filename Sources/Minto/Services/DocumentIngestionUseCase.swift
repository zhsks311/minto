import Foundation

/// 여러 파일 URL을 평문 `AttachedDocument`로 모으는 Application use-case.
///
/// 책임: 입력 순회·보안 범위 자원(security-scoped) 접근·per-file timeout·어댑터 호출·실패 분류·fail-soft.
/// UI는 선택만 하고 이 use-case를 호출한다 — 파싱·HTTP·schema 변환을 직접 하지 않는다.
/// 관측(진행률) 상태는 두지 않는다(UI 레이어가 필요 시 래핑). 합산 cap·문자열 결합은 호출자(combinedDocument 조립)가 담당한다.
public struct DocumentIngestionUseCase: Sendable {

    /// 한 번의 수집 결과. 성공 문서와 분류된 실패를 분리해 fail-soft 안내에 쓴다.
    public struct BatchResult: Sendable, Equatable {
        public let documents: [AttachedDocument]
        public let failures: [Failure]

        public struct Failure: Sendable, Equatable {
            public let sourceLabel: String
            public let reason: DocumentIngestionFailure

            public init(sourceLabel: String, reason: DocumentIngestionFailure) {
                self.sourceLabel = sourceLabel
                self.reason = reason
            }
        }

        public init(documents: [AttachedDocument], failures: [Failure]) {
            self.documents = documents
            self.failures = failures
        }
    }

    /// 파일 1건 추출 제한 시간. 스캔 PDF OCR(30p ≈ 9~10초)을 넉넉히 덮되 무한 대기는 막는다.
    private let perFileTimeout: Duration

    public init(perFileTimeout: Duration = .seconds(30)) {
        self.perFileTimeout = perFileTimeout
    }

    /// 파일 URL들을 순회하며 평문으로 추출한다. 입력 순서를 유지한다.
    public func ingest(urls: [URL]) async -> BatchResult {
        var documents: [AttachedDocument] = []
        var failures: [BatchResult.Failure] = []

        for url in urls {
            // fileImporter 가 준 URL 은 보안 범위 자원이라 접근 전후로 start/stop 해야 한다.
            let didAccess = url.startAccessingSecurityScopedResource()
            let result = await extractWithTimeout(url)
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }

            switch result {
            case .success(let document):
                documents.append(document)
            case .failure(let reason):
                failures.append(.init(sourceLabel: url.lastPathComponent, reason: reason))
            }
        }

        return BatchResult(documents: documents, failures: failures)
    }

    private func extractWithTimeout(_ url: URL) async -> DocumentIngestionResult {
        await Self.resultWithinTimeout(perFileTimeout) {
            await FileDocumentExtractor.extract(from: url)
        }
    }

    /// 추출 operation 과 timeout 을 경쟁시켜 먼저 끝나는 쪽을 채택한다. timeout 이 이기면 `.failure(.timeout)`.
    /// (operation 주입형이라 결정론적으로 테스트 가능 — internal.)
    static func resultWithinTimeout(
        _ timeout: Duration,
        operation: @escaping @Sendable () async -> DocumentIngestionResult
    ) async -> DocumentIngestionResult {
        await withTaskGroup(of: DocumentIngestionResult?.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failure(.timeout)
        }
    }
}
