import Foundation
import UniformTypeIdentifiers
import CryptoKit

/// 로컬 파일을 평문 `AttachedDocument`로 추출하는 Infra 어댑터.
///
/// Phase 0: md/txt(Foundation 텍스트 읽기). Phase 1에서 PDF 텍스트(PDFKit, 백그라운드),
/// Phase 2에서 이미지·스캔 PDF(Vision OCR) 경로를 추가한다.
/// 저수준 추출기는 로깅하지 않는다 — 시작/성공/실패 로깅은 호출하는 UseCase(Phase 3)가 담당한다.
///
/// 인스턴스화 불필요 — 상태 없는 정적 네임스페이스. (Phase 3에서 DI가 필요하면 그때 프로토콜화 결정.)
public enum FileDocumentExtractor {

    /// 첨부 파일로 허용하는 UTType 목록의 단일 출처.
    /// Phase 0: 평문 텍스트(markdown 은 `public.plain-text` 에 conform). Phase 1/2 에서 pdf·이미지 추가.
    public static let supportedContentTypes: [UTType] = [.plainText]

    /// contentType 으로 판별되지 않을 때(확장자 기반 fallback)의 허용 확장자.
    public static let supportedExtensions: Set<String> = ["txt", "md", "markdown", "text"]

    /// 파일 크기 sanity 가드(바이트). prompt budget 이 아니라 비정상 입력 방어용.
    public static let defaultMaxFileBytes = 50 * 1024 * 1024

    /// 개별 파일 글자 수 가드(비정상 입력 방어용 상한). LLM 토큰 예산 관리는
    /// `DocumentIngestionUseCase`(Phase 3)의 합산 cap이 담당한다 — 여기서 결정하지 않는다.
    public static let defaultCharacterCap = 200_000

    /// 파일 URL → 평문 `DocumentIngestionResult`.
    ///
    /// 보안 범위 자원(security-scoped resource) 접근 권한은 **호출자(Phase 3 UseCase)가** 책임진다 —
    /// `url.startAccessingSecurityScopedResource()` + `defer { stopAccessing... }`로 이 호출을 감싼다.
    /// 이 함수는 권한이 이미 확보됐다고 가정한다.
    ///
    /// - Parameters:
    ///   - url: 추출할 파일.
    ///   - maxFileBytes: 초과 시 `.tooLarge`. 테스트에서 작게 주입 가능.
    ///   - characterCap: 초과 분량은 잘라낸다. 테스트에서 작게 주입 가능.
    public static func extract(
        from url: URL,
        maxFileBytes: Int = defaultMaxFileBytes,
        characterCap: Int = defaultCharacterCap
    ) async -> DocumentIngestionResult {
        guard isSupported(url) else {
            return .failure(.unsupportedFormat)
        }

        if let size = fileByteSize(url), size > maxFileBytes {
            return .failure(.tooLarge)
        }

        guard let raw = readText(url) else {
            return .failure(.readFailed)
        }

        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure(.emptyContent)
        }

        let capped = raw.count > characterCap ? String(raw.prefix(characterCap)) : raw
        let document = AttachedDocument(
            id: stableID(for: url),
            title: url.deletingPathExtension().lastPathComponent,
            text: capped,
            sourceKind: .file,
            sourceLabel: url.lastPathComponent
        )
        return .success(document)
    }

    /// 파일 경로 기반 안정 식별자(SHA-256 hex). 같은 파일은 같은 id → 중복 첨부 감지에 쓴다.
    /// 비가역 해시라 id가 어딘가 기록돼도 절대경로가 새지 않는다(민감경로 보호).
    private static func stableID(for url: URL) -> String {
        let path = url.standardizedFileURL.path
        let digest = SHA256.hash(data: Data(path.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 지원 형식 여부. contentType 우선, 없으면 확장자 fallback.
    public static func isSupported(_ url: URL) -> Bool {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
           supportedContentTypes.contains(where: { type.conforms(to: $0) }) {
            return true
        }
        return supportedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func fileByteSize(_ url: URL) -> Int? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
    }

    /// UTF-8 우선, 실패 시 인코딩 자동감지(BOM 등) fallback.
    private static func readText(_ url: URL) -> String? {
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            return utf8
        }
        var usedEncoding = String.Encoding.utf8
        if let detected = try? String(contentsOf: url, usedEncoding: &usedEncoding) {
            return detected
        }
        return nil
    }
}
