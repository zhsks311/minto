import Testing
import Foundation
import AppKit
import Vision
import CoreText
import CoreGraphics
import Dispatch

/// Phase 2(OCR) 선행 게이트 프로브.
///
/// 목적: Apple Vision `VNRecognizeTextRequest` 의 **한국어(ko-KR) 인식 정확도(CER)와 지연**을
/// 실측해 Phase 2(이미지·스캔 PDF OCR) 구현 여부와 페이지 상한·진행률 정책을 정한다.
/// 통과/실패가 아니라 **수치 관찰**이 목적이므로 `RUN_OCR_PROBE=1` 일 때만 돈다(CI 기본 제외).
///
/// 실행: `RUN_OCR_PROBE=1 swift test --filter VisionOCRProbe`
@Suite("VisionOCRProbe")
struct VisionOCRProbeTests {

    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["RUN_OCR_PROBE"] == "1"
    }

    /// 회의록 성격의 한국어 본문(숫자·이름·문장부호 포함) — OCR 타깃 대표 샘플.
    private static let sample = """
    2026년 2분기 제품 회의록
    참석자 김민수 박지영 이정훈
    안건 신규 STT 엔진 도입 검토
    안건 회의록 자동 요약 품질 개선
    결정사항 다음 스프린트에 베타 배포
    """

    /// 흰 배경에 검은 텍스트를 렌더한 비트맵 CGImage. 스캔/촬영 문서의 깨끗한 버전 모사.
    private static func renderTextImage(_ text: String, fontSize: CGFloat) -> CGImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let lineCount = text.split(whereSeparator: { $0.isNewline }).count
        let width = 1100
        let height = max(300, lineCount * Int(fontSize * 1.9) + 100)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("bitmap context 생성 실패")
        }
        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let textRect = CGRect(x: 50, y: 50, width: width - 100, height: height - 100)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, context)

        guard let image = context.makeImage() else {
            fatalError("CGImage 생성 실패")
        }
        return image
    }

    /// languages == nil 이면 automaticallyDetectsLanguage 사용(명시 목록 무시).
    private static func recognize(_ image: CGImage, languages: [String]? = ["ko-KR", "en-US"]) throws -> (text: String, ms: Double) {
        let request = VNRecognizeTextRequest()
        if let languages {
            request.recognitionLanguages = languages
        } else {
            request.automaticallyDetectsLanguage = true
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let start = DispatchTime.now()
        try handler.perform([request])
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

        let recognized = (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
        return (recognized, ms)
    }

    /// 공백·줄바꿈을 무시한 문자 단위 CER(=편집거리 / 정답 길이). 줄바꿈 차이는 오류로 세지 않는다.
    private static func cer(truth: String, hypothesis: String) -> Double {
        let strip: (String) -> [Character] = { input in
            Array(input.filter { !$0.isWhitespace })
        }
        let truthChars = strip(truth)
        let hypothesisChars = strip(hypothesis)
        guard !truthChars.isEmpty else { return 0 }
        return Double(levenshtein(truthChars, hypothesisChars)) / Double(truthChars.count)
    }

    private static func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    @Test("한국어 OCR 정확도·지연 실측")
    func koreanOCRAccuracyAndLatency() throws {
        guard Self.enabled else { return }

        for fontSize in [20.0, 28.0, 40.0] as [CGFloat] {
            let image = Self.renderTextImage(Self.sample, fontSize: fontSize)
            let (recognized, ms) = try Self.recognize(image)
            let errorRate = Self.cer(truth: Self.sample, hypothesis: recognized)

            print("[OCR-PROBE] font=\(Int(fontSize))pt CER=\(String(format: "%.3f", errorRate)) "
                + "지연=\(String(format: "%.1f", ms))ms 인식글자=\(recognized.filter { !$0.isWhitespace }.count)")
            print("[OCR-PROBE]   recognized: \(recognized.replacingOccurrences(of: "\n", with: " / "))")
        }
    }

    @Test("페이지당 OCR 지연 추정(여러 장 연속)")
    func perPageLatency() throws {
        guard Self.enabled else { return }

        let image = Self.renderTextImage(Self.sample, fontSize: 28)
        let pageCount = 5
        let start = DispatchTime.now()
        for _ in 0..<pageCount {
            _ = try Self.recognize(image)
        }
        let totalMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
        print("[OCR-PROBE] \(pageCount)장 연속 총=\(String(format: "%.1f", totalMs))ms, "
            + "장당평균=\(String(format: "%.1f", totalMs / Double(pageCount)))ms")
    }

    /// 한글 회의록 + 한자·일본어 섞인 샘플 — recognitionLanguages 후보들. 정답 기준 CER 비교.
    private static let mixedSample = """
    회의 결과 確認
    김민환 金玟煥 배혜정 裵惠貞
    プロジェクト 進捗 ミント
    予算 検討 完了
    """

    @Test("recognitionLanguages 세트별 CER·지연 비교 (한글 회귀 + 한자·일어 이득)")
    func languageSetComparison() throws {
        guard Self.enabled else { return }

        // (a) 이 기기에서 Vision 이 실제 지원하는 언어
        if let supported = try? VNRecognizeTextRequest.supportedRecognitionLanguages(
            for: .accurate, revision: VNRecognizeTextRequestRevision3
        ) {
            print("[OCR-PROBE] supported(.accurate,rev3): \(supported.joined(separator: ", "))")
        }

        let configs: [(label: String, langs: [String]?)] = [
            ("ko",                 ["ko-KR"]),
            ("ko+en",              ["ko-KR", "en-US"]),
            ("ko+en+ja",           ["ko-KR", "en-US", "ja-JP"]),
            ("ko+en+ja+zhHans+zhHant", ["ko-KR", "en-US", "ja-JP", "zh-Hans", "zh-Hant"]),
            ("auto",               nil)
        ]

        for (name, sample) in [("korean", Self.sample), ("mixed", Self.mixedSample)] {
            let image = Self.renderTextImage(sample, fontSize: 30)
            print("[OCR-PROBE] === \(name) sample ===")
            for config in configs {
                guard let (text, ms) = try? Self.recognize(image, languages: config.langs) else {
                    print("[OCR-PROBE]   \(config.label): 인식 실패(미지원 언어?)")
                    continue
                }
                let errorRate = Self.cer(truth: sample, hypothesis: text)
                print("[OCR-PROBE]   \(config.label): CER=\(String(format: "%.3f", errorRate)) 지연=\(String(format: "%.0f", ms))ms")
            }
        }
    }
}
