import Foundation
import UniformTypeIdentifiers
import CryptoKit
import PDFKit
import Vision
import ImageIO

/// 로컬 파일을 평문 `AttachedDocument`로 추출하는 Infra 어댑터.
///
/// Phase 0: md/txt(Foundation 텍스트 읽기). Phase 1: PDF 텍스트(PDFKit, 백그라운드).
/// Phase 2: 이미지 파일·텍스트 없는 스캔 PDF(Vision OCR, ko-KR, 백그라운드).
/// 저수준 추출기는 로깅하지 않는다 — 시작/성공/실패 로깅은 호출하는 UseCase(Phase 3)가 담당한다.
///
/// 인스턴스화 불필요 — 상태 없는 정적 네임스페이스. (Phase 3에서 DI가 필요하면 그때 프로토콜화 결정.)
public enum FileDocumentExtractor {

    /// 첨부 파일로 허용하는 UTType 목록의 단일 출처.
    /// 평문 텍스트(markdown 은 `public.plain-text` 에 conform) + pdf + 이미지(png/jpg/heic 등은 `public.image` 에 conform).
    public static let supportedContentTypes: [UTType] = [.plainText, .pdf, .image]

    /// contentType 으로 판별되지 않을 때(확장자 기반 fallback)의 허용 확장자.
    public static let supportedExtensions: Set<String> = [
        "txt", "md", "markdown", "text", "pdf",
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp"
    ]

    /// 파일 크기 sanity 가드(바이트). prompt budget 이 아니라 비정상 입력 방어용.
    public static let defaultMaxFileBytes = 50 * 1024 * 1024

    /// 개별 파일 글자 수 가드(비정상 입력 방어용 상한). LLM 토큰 예산 관리는
    /// `DocumentIngestionUseCase`(Phase 3)의 합산 cap이 담당한다 — 여기서 결정하지 않는다.
    public static let defaultCharacterCap = 200_000

    /// 스캔 PDF OCR 시 처리할 최대 페이지 수. 페이지당 신경망 추론(~300ms)이라 지연을 bound 한다.
    /// 프로브 근거: `VisionOCRProbeTests`(장당 평균 ~319ms) → 30p ≈ 9~10초.
    public static let defaultOCRPageCap = 30

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
    ///   - ocrPageCap: 스캔 PDF OCR 시 처리할 최대 페이지 수. 테스트에서 작게 주입 가능.
    public static func extract(
        from url: URL,
        maxFileBytes: Int = defaultMaxFileBytes,
        characterCap: Int = defaultCharacterCap,
        ocrPageCap: Int = defaultOCRPageCap
    ) async -> DocumentIngestionResult {
        guard let kind = fileKind(url) else {
            return .failure(.unsupportedFormat)
        }

        if let size = fileByteSize(url), size > maxFileBytes {
            return .failure(.tooLarge)
        }

        let rawText: String?
        switch kind {
        case .text:
            rawText = readText(url)
        case .image:
            rawText = await ocrImage(at: url)
        case .pdf:
            // 못 엶 → nil(readFailed). 텍스트가 있으면 그대로, 없으면(스캔본) OCR fallback.
            guard let pdfText = await extractPDFText(url) else {
                return .failure(.readFailed)
            }
            if pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rawText = await ocrPDF(at: url, pageCap: ocrPageCap)
            } else {
                rawText = pdfText
            }
        }

        // nil = 파일 자체를 열거나 읽지 못함(손상 등). 빈 문자열은 readFailed 가 아니라 emptyContent 로 분기한다.
        guard let raw = rawText else {
            return .failure(.readFailed)
        }

        // 텍스트가 전혀 없으면(스캔본 OCR 도 실패한 경우 포함) .emptyContent.
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
        fileKind(url) != nil
    }

    /// 추출 경로 분류. 텍스트 읽기·PDF 추출·이미지 OCR 은 서로 다른 처리라 미리 가른다.
    private enum FileKind {
        case text
        case pdf
        case image
    }

    private static func fileKind(_ url: URL) -> FileKind? {
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType {
            if type.conforms(to: .pdf) {
                return .pdf
            }
            if type.conforms(to: .image) {
                return .image
            }
            if type.conforms(to: .plainText) {
                return .text
            }
        }
        switch url.pathExtension.lowercased() {
        case "pdf":
            return .pdf
        case "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp":
            return .image
        case "txt", "md", "markdown", "text":
            return .text
        default:
            return nil
        }
    }

    /// PDFKit 텍스트 추출. `PDFDocument` 은 Sendable 이 아니라 detached task 안에 가두고 `String` 만 경계를 넘긴다.
    /// 백그라운드 안전성은 `PDFKitBackgroundProbeTests` 로 확인됨(MainActor 제약·페이지 상한 불필요).
    /// 반환: 문서를 못 엶 → nil(readFailed), 열었지만 텍스트 없음(스캔본) → ""(emptyContent → Phase 2 OCR).
    private static func extractPDFText(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            // 문서를 못 엶 → nil(readFailed). 열렸으면 텍스트가 없어도 "" 를 돌려
            // emptyContent(스캔본 → OCR) 로 분기시킨다. nil 로 흘리면 readFailed 와 섞인다.
            guard let document = PDFDocument(url: url) else {
                return nil
            }
            return document.string ?? ""
        }.value
    }

    /// 이미지 파일 OCR. 못 엶 → nil(readFailed), 열렸지만 글자 없음 → ""(emptyContent).
    /// `CGImage`·`VNImageRequestHandler` 는 Sendable 이 아니라 detached task 안에서 생성·소비하고 `String` 만 반환한다.
    private static func ocrImage(at url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                return nil
            }
            return recognizeText(image)
        }.value
    }

    /// 스캔 PDF OCR fallback. 페이지를 비트맵으로 렌더 → Vision OCR. 페이지 상한으로 지연을 bound 한다.
    /// 부분 결과 fail-soft: 일부 페이지 렌더/인식 실패해도 나머지를 합쳐 반환한다.
    private static func ocrPDF(at url: URL, pageCap: Int) async -> String? {
        await Task.detached(priority: .userInitiated) {
            guard let document = PDFDocument(url: url) else {
                return nil
            }
            let pageCount = min(document.pageCount, pageCap)
            guard pageCount > 0 else {
                return ""
            }
            var collected: [String] = []
            for index in 0..<pageCount {
                guard let page = document.page(at: index),
                      let image = renderPageToCGImage(page) else {
                    continue
                }
                let text = recognizeText(image)
                if !text.isEmpty {
                    collected.append(text)
                }
            }
            return collected.joined(separator: "\n")
        }.value
    }

    /// PDF 페이지를 흰 배경 비트맵 `CGImage` 로 렌더한다. OCR 품질을 위해 2배 확대.
    private static func renderPageToCGImage(_ page: PDFPage, scale: CGFloat = 2.0) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int(bounds.width * scale)
        let height = Int(bounds.height * scale)
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return nil
        }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// Vision on-device 텍스트 인식(ko-KR + en-US). 인식 실패/없음 → "".
    private static func recognizeText(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLanguages = ["ko-KR", "en-US"]
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else {
            return ""
        }
        return (request.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }
            .joined(separator: "\n")
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
