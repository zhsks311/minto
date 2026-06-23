import Foundation

/// 문서 수집(파일/Notion/Confluence) 한 건의 결과.
///
/// 성공이면 평문 `AttachedDocument`, 실패면 사유를 구분한 `DocumentIngestionFailure`.
/// 실패는 fail-soft 처리(회의 시작·전사·저장에 영향 없음)를 위해 사유별로 안내·재시도 정책을 가른다.
public enum DocumentIngestionResult: Sendable, Equatable {
    case success(AttachedDocument)
    case failure(DocumentIngestionFailure)
}

/// 문서 수집 실패 분류.
///
/// status code 한 종류로 뭉뚱그리지 않고 사유를 구분한다 — 사용자 안내 문구와
/// 재시도 가능 여부(재연결/재시도/형식 변경)가 사유마다 다르기 때문이다.
public enum DocumentIngestionFailure: Error, LocalizedError, Sendable, Equatable {
    /// 지원하지 않는 파일 형식/UTType.
    case unsupportedFormat
    /// 파일/리소스 접근 권한 거부(security-scoped 실패 등).
    case accessDenied
    /// sanity 가드(최대 바이트)를 초과.
    case tooLarge
    /// 읽기/디코딩 실패.
    case readFailed
    /// 추출 결과가 비어 있음(텍스트 없는 PDF는 이후 OCR fallback 대상).
    case emptyContent
    /// Notion 등 외부 소스가 연결되어 있지 않음.
    case notConnected
    /// 외부 소스 재인증 필요.
    case needsReconnect
    /// 외부 소스 조회 실패(네트워크·서버 오류 등).
    case fetchFailed
    /// 제한 시간 초과.
    case timeout

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return "지원하지 않는 파일 형식이에요."
        case .accessDenied:
            return "파일에 접근할 수 없어요. 권한을 확인하세요."
        case .tooLarge:
            return "파일이 너무 커요."
        case .readFailed:
            return "파일을 읽지 못했어요."
        case .emptyContent:
            return "문서에서 글자를 찾지 못했어요."
        case .notConnected:
            return "Notion이 연결되어 있지 않아요. 설정에서 연결하세요."
        case .needsReconnect:
            return "Notion 연결이 만료됐어요. 다시 연결하세요."
        case .fetchFailed:
            return "문서를 불러오지 못했어요."
        case .timeout:
            return "문서를 불러오는 데 시간이 너무 오래 걸려요."
        }
    }
}
