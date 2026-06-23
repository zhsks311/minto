import Foundation
import Testing
import AppKit
import CoreText
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import MintoCore

@Suite("FileDocumentExtractor")
struct FileDocumentExtractorTests {

    private func writeTempFile(ext: String, data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("file-extract-\(UUID().uuidString).\(ext)")
        try data.write(to: url)
        return url
    }

    private func writeTempText(
        ext: String,
        _ content: String,
        encoding: String.Encoding = .utf8
    ) throws -> URL {
        try writeTempFile(ext: ext, data: content.data(using: encoding)!)
    }

    /// 합성 텍스트 PDF 를 만든다. `text == nil` 이면 텍스트 없는 빈 페이지(스캔본 모사).
    private func makePDF(text: String?) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-extract-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            fatalError("PDF context 생성 실패")
        }
        ctx.beginPDFPage(nil)
        if let text {
            let attr = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 12),
                .foregroundColor: NSColor.black
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
            let textRect = mediaBox.insetBy(dx: 40, dy: 40)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            CTFrameDraw(frame, ctx)
        }
        ctx.endPDFPage()
        ctx.closePDF()
        return url
    }

    /// 흰 배경에 검은 텍스트를 렌더한 비트맵 CGImage(스캔/촬영 문서의 깨끗한 버전 모사).
    private func renderTextToCGImage(_ text: String, fontSize: CGFloat = 32) -> CGImage {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor.black
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let lineCount = text.split(whereSeparator: { $0.isNewline }).count
        let width = 1100
        let height = max(300, lineCount * Int(fontSize * 1.9) + 100)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            fatalError("bitmap context 생성 실패")
        }
        ctx.setFillColor(NSColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let framesetter = CTFramesetterCreateWithAttributedString(attributed as CFAttributedString)
        let textRect = CGRect(x: 50, y: 50, width: width - 100, height: height - 100)
        let path = CGPath(rect: textRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
        CTFrameDraw(frame, ctx)
        guard let image = ctx.makeImage() else {
            fatalError("CGImage 생성 실패")
        }
        return image
    }

    /// 텍스트를 그린 이미지 파일(PNG)을 만든다 — OCR 경로 검증용.
    private func writeTextImage(_ text: String) -> URL {
        let image = renderTextToCGImage(text)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-extract-\(UUID().uuidString).png")
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            fatalError("image destination 생성 실패")
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            fatalError("PNG 쓰기 실패")
        }
        return url
    }

    /// 텍스트를 "이미지로 그린" PDF(선택 가능한 텍스트 없음 = 스캔본 모사). OCR fallback 경로 검증용.
    private func makeImageOnlyPDF(_ text: String, pages: Int = 1) -> URL {
        let image = renderTextToCGImage(text)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("doc-extract-scan-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: CGFloat(image.width), height: CGFloat(image.height))
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            fatalError("PDF context 생성 실패")
        }
        for _ in 0..<pages {
            ctx.beginPDFPage(nil)
            ctx.draw(image, in: mediaBox)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    @Test("UTF-8 마크다운 파일을 평문으로 추출한다")
    func extractsMarkdown() async throws {
        let content = "# 회의 안건\n- 일정 확정\n- 예산 검토"
        let url = try writeTempText(ext: "md", content)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        guard case let .success(document) = result else {
            Issue.record("기대: success, 실제: \(result)")
            return
        }
        #expect(document.text == content)
        #expect(document.sourceKind == .file)
        #expect(document.sourceLabel == url.lastPathComponent)
        #expect(document.title == url.deletingPathExtension().lastPathComponent)
    }

    @Test("txt 파일을 추출한다")
    func extractsPlainText() async throws {
        let content = "회의 참고 자료\n다음 분기 목표"
        let url = try writeTempText(ext: "txt", content)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        guard case let .success(document) = result else {
            Issue.record("기대: success, 실제: \(result)")
            return
        }
        #expect(document.text == content)
        #expect(document.sourceKind == .file)
        #expect(document.title == url.deletingPathExtension().lastPathComponent)
        #expect(document.sourceLabel == url.lastPathComponent)
        #expect(!document.id.isEmpty)
    }

    @Test("같은 경로는 같은 안정 id 를 만든다")
    func stableIDIsDeterministic() async throws {
        let url = try writeTempText(ext: "txt", "안정 식별 테스트")
        defer { try? FileManager.default.removeItem(at: url) }

        let first = await FileDocumentExtractor.extract(from: url)
        let second = await FileDocumentExtractor.extract(from: url)

        guard case let .success(a) = first, case let .success(b) = second else {
            Issue.record("기대: 두 번 모두 success")
            return
        }
        #expect(a.id == b.id)
    }

    @Test("확장자 없는 파일은 unsupportedFormat 으로 분류한다")
    func extensionlessFileFails() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("README-\(UUID().uuidString)")
        try "내용".data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        #expect(result == .failure(.unsupportedFormat))
    }

    @Test("내용이 공백뿐이면 emptyContent 로 분류한다")
    func emptyFileFails() async throws {
        let url = try writeTempText(ext: "txt", "   \n\t  ")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        #expect(result == .failure(.emptyContent))
    }

    @Test("지원하지 않는 형식은 unsupportedFormat 으로 분류한다")
    func unsupportedFormatFails() async throws {
        let url = try writeTempFile(ext: "bin", data: Data([0x00, 0x01, 0x02, 0x03]))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        #expect(result == .failure(.unsupportedFormat))
    }

    @Test("글자 수 cap 을 초과하면 잘라낸다")
    func appliesCharacterCap() async throws {
        let content = String(repeating: "가", count: 100)
        let url = try writeTempText(ext: "txt", content)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url, characterCap: 10)

        guard case let .success(document) = result else {
            Issue.record("기대: success, 실제: \(result)")
            return
        }
        #expect(document.text.count == 10)
    }

    @Test("최대 바이트를 초과하면 tooLarge 로 분류한다")
    func tooLargeFails() async throws {
        let url = try writeTempText(ext: "txt", "내용이 있는 파일")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url, maxFileBytes: 1)

        #expect(result == .failure(.tooLarge))
    }

    @Test("UTF-8 이 아니어도 인코딩을 감지해 읽는다")
    func fallsBackToDetectedEncoding() async throws {
        let content = "테스트 본문입니다"
        let url = try writeTempText(ext: "txt", content, encoding: .utf16)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        guard case let .success(document) = result else {
            Issue.record("기대: success, 실제: \(result)")
            return
        }
        #expect(document.text == content)
    }

    @Test("텍스트 PDF 를 평문으로 추출한다")
    func extractsTextFromPDF() async throws {
        let url = makePDF(text: "Minto 회의 안건 추출 테스트 본문")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        guard case let .success(document) = result else {
            Issue.record("기대: success, 실제: \(result)")
            return
        }
        #expect(document.text.contains("Minto"))
        #expect(document.text.contains("추출"))
        #expect(document.sourceKind == .file)
        #expect(document.sourceLabel == url.lastPathComponent)
    }

    @Test("텍스트 없는 PDF(스캔본)는 emptyContent 로 분류한다 — Phase 2 OCR fallback 대상")
    func scannedPDFFailsAsEmptyContent() async throws {
        let url = makePDF(text: nil)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        #expect(result == .failure(.emptyContent))
    }

    @Test("손상된 PDF 는 readFailed 로 분류한다")
    func corruptPDFFailsAsReadFailed() async throws {
        let url = try writeTempFile(ext: "pdf", data: Data("not a real pdf".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        #expect(result == .failure(.readFailed))
    }

    @Test("이미지 파일을 OCR 로 추출한다")
    func extractsTextFromImage() async throws {
        let url = writeTextImage("Minto 회의 안건 검토")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        guard case let .success(document) = result else {
            Issue.record("기대: success, 실제: \(result)")
            return
        }
        #expect(document.text.contains("Minto"))
        #expect(document.text.contains("회의"))
        #expect(document.sourceKind == .file)
    }

    @Test("텍스트 없는 스캔 PDF 는 OCR fallback 으로 추출한다")
    func scannedPDFRecoveredByOCR() async throws {
        let url = makeImageOnlyPDF("Minto 스캔 문서 추출")
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        guard case let .success(document) = result else {
            Issue.record("기대: success(OCR fallback), 실제: \(result)")
            return
        }
        #expect(document.text.contains("Minto"))
        #expect(document.text.contains("스캔"))
    }

    @Test("OCR 페이지 상한을 넘는 스캔 PDF 는 상한까지만 처리한다")
    func ocrPageCapLimitsPages() async throws {
        let url = makeImageOnlyPDF("Minto 페이지 상한 테스트", pages: 3)
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url, ocrPageCap: 1)

        guard case let .success(document) = result else {
            Issue.record("기대: success, 실제: \(result)")
            return
        }
        // 같은 텍스트가 3장 → 상한 1장만 처리하면 "Minto" 가 정확히 1회.
        let occurrences = document.text.components(separatedBy: "Minto").count - 1
        #expect(occurrences == 1)
    }

    @Test("손상된 이미지는 readFailed 로 분류한다")
    func corruptImageFailsAsReadFailed() async throws {
        let url = try writeTempFile(ext: "png", data: Data("not a real png".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        let result = await FileDocumentExtractor.extract(from: url)

        #expect(result == .failure(.readFailed))
    }
}
