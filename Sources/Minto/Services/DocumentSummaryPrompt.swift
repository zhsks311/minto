import Foundation

/// 첨부 문서(안건/자료)를 회의 요약용 **참고 맥락**으로 1회 압축하는 프롬프트 빌더.
///
/// 전사 요약(`SummaryPrompt`)과 목적이 다르다: 여기서는 *문서 자체*를 짧은 불릿으로 줄여,
/// 이후 회의 요약 프롬프트에 raw 발췌(excerpt) 대신 주입한다. 결과는 `MeetingContext.documentSummary`
/// 또는 `SummaryGenerationContext.documentSummary`에 캐시되어 매 요약마다 재생성하지 않는다.
///
/// 네트워크·상태에 의존하지 않는 순수 함수이므로 단위 테스트로 검증한다.
public enum DocumentSummaryPrompt {

    /// 문서 입력 상한. 매우 긴 문서(스캔 PDF·OCR 다중 페이지)에서 context limit 초과를 막는다.
    /// 한도 초과 시 뒷부분을 생략한다(요약은 1회성이라 앞부분 중심이 보통 충분하다).
    static let maxDocumentCharacters = 12_000

    /// - Parameter document: 첨부 문서 평문
    /// - Returns: (instructions, userContent). document가 비면 빈 쌍.
    public static func build(document: String) -> (instructions: String, userContent: String) {
        let trimmed = document.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("", "") }

        let instructions = """
        당신은 회의 참고 문서(안건·자료)를 요약하는 전문가입니다. 아래 문서를, 이 문서를 참고하는
        회의의 요약을 도울 **참고 맥락**으로 압축하세요.

        요약 원칙:
        - 문서에 실제로 적힌 내용만 요약한다. 추론·해석·외부 지식·추측을 더하지 않는다(없는 사실 날조 금지).
        - 회의 주제·핵심 안건, 등장하는 고유명사·전문용어, 주요 항목·수치·일정 중심으로 정리한다.
        - 한국어 불릿 5~10개, 전체 약 1000자 이내로 간결하게. 문서 문장을 그대로 길게 옮기지 말고 압축한다.
        - 불릿 텍스트만 출력한다. 설명·따옴표·접두어·제목 없이 결과만.
        """

        let body: String
        if trimmed.count > maxDocumentCharacters {
            body = String(trimmed.prefix(maxDocumentCharacters)) + "\n…(이후 문서 생략)"
        } else {
            body = trimmed
        }
        let userContent = "문서:\n\(body)"
        return (instructions, userContent)
    }
}
