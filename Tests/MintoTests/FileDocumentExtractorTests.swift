import Foundation
import Testing
import AppKit
import CoreText
import CoreGraphics
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
}
