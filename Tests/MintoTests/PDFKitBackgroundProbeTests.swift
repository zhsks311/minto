import Testing
import Foundation
import AppKit
import PDFKit
import CoreText
import CoreGraphics
import Dispatch

/// PDFKit 백그라운드 추출 안전성 프로브 (ADR 0005 PDF 동시성 결정용).
///
/// 검증 목표:
///   1. Swift 6 strict concurrency에서 `PDFDocument`를 Task.detached 클로저에 가두고
///      결과 `String`만 반환하는 패턴이 컴파일되는가 (Sendable).
///   2. 백그라운드 스레드 추출이 크래시 없이 정확한 텍스트를 반환하는가 (한글+ASCII).
///   3. 여러 PDF를 동시에 추출할 때 thread-safety가 깨지는가 (stress).
///   4. 메인 vs 백그라운드 추출 지연 비교.
///
/// 픽스처는 CoreGraphics+CoreText로 테스트 내에서 생성(외부 바이너리 의존 없음).
/// 실행: RUN_PDF_PROBE=1 swift test --filter PDFKitBackgroundProbeTests
struct PDFKitBackgroundProbeTests {

    private static let asciiMarker = "Page 1"
    private static let koreanMarker = "전략수출금융지원법안"
    private static let lineText = "회의 안건 \(koreanMarker) 검토 ABC123 dry-run Liquibase"

    /// 멀티페이지 텍스트 PDF를 임시 파일로 생성하고 URL을 반환한다.
    private static func makeTextPDF(pageCount: Int, linesPerPage: Int = 40) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pdfprobe-\(pageCount)p-\(UUID().uuidString).pdf")
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let ctx = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else {
            fatalError("PDF context 생성 실패")
        }
        let body = Array(repeating: lineText, count: linesPerPage).joined(separator: "\n")
        for page in 0..<pageCount {
            ctx.beginPDFPage(nil)
            let text = "Page \(page + 1)\n" + body
            let attr = NSAttributedString(string: text, attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: NSColor.black
            ])
            let framesetter = CTFramesetterCreateWithAttributedString(attr as CFAttributedString)
            let textRect = mediaBox.insetBy(dx: 40, dy: 40)
            let path = CGPath(rect: textRect, transform: nil)
            let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)
            CTFrameDraw(frame, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return url
    }

    private static var enabled: Bool {
        ProcessInfo.processInfo.environment["RUN_PDF_PROBE"] == "1"
    }

    private static func elapsedMs(_ block: () -> Void) -> Double {
        let start = DispatchTime.now()
        block()
        let end = DispatchTime.now()
        return Double(end.uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0
    }

    @Test
    func backgroundExtractionIsSafe() async throws {
        guard Self.enabled else { return }
        let url = Self.makeTextPDF(pageCount: 20)
        defer { try? FileManager.default.removeItem(at: url) }

        // 핵심 패턴: PDFDocument는 detached 클로저 안에서만 살고, String(Sendable)만 경계를 넘는다.
        let start = DispatchTime.now()
        let extracted = await Task.detached(priority: .userInitiated) {
            PDFDocument(url: url)?.string
        }.value
        let awaitMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000.0

        let text = try #require(extracted, "백그라운드 추출 결과가 nil")
        let hasASCII = text.contains(Self.asciiMarker)
        let hasKorean = text.contains(Self.koreanMarker)

        print("[PDF-PROBE] 20p 백그라운드 추출: \(text.count)자, ascii=\(hasASCII), korean=\(hasKorean), await=\(String(format: "%.1f", awaitMs))ms")

        #expect(hasASCII, "ASCII 텍스트(Page 1) 추출 실패 — 백그라운드 추출 자체가 안 됨")
        // 한글은 관찰값(연구가 우려한 CJK 매핑). 실패해도 스레드 결론과 무관하므로 기록만.
        if !hasKorean {
            print("[PDF-PROBE][주의] 한글 마커 미추출 — CoreText 생성 PDF의 CJK ToUnicode 이슈 가능")
        }
    }

    @Test
    func concurrentExtractionStress() async throws {
        guard Self.enabled else { return }
        let urls = (0..<8).map { _ in Self.makeTextPDF(pageCount: 10) }
        defer { urls.forEach { try? FileManager.default.removeItem(at: $0) } }

        // 서로 다른 PDFDocument 인스턴스를 동시에 추출 → thread-safety 크래시 유발 시도.
        let results = await withTaskGroup(of: Bool.self) { group -> [Bool] in
            for url in urls {
                group.addTask(priority: .userInitiated) {
                    let text = PDFDocument(url: url)?.string
                    return (text?.contains(Self.asciiMarker)) ?? false
                }
            }
            var acc: [Bool] = []
            for await ok in group { acc.append(ok) }
            return acc
        }

        print("[PDF-PROBE] 동시 추출 8건 성공=\(results.filter { $0 }.count)/8")
        #expect(results.count == 8)
        #expect(results.allSatisfy { $0 }, "동시 추출 중 일부 실패 — thread-safety 의심")
    }

    @Test
    func mainVsBackgroundLatency() async throws {
        guard Self.enabled else { return }
        let url = Self.makeTextPDF(pageCount: 50)
        defer { try? FileManager.default.removeItem(at: url) }

        let bgStart = DispatchTime.now()
        let bgText = await Task.detached(priority: .userInitiated) {
            PDFDocument(url: url)?.string
        }.value
        let bgMs = Double(DispatchTime.now().uptimeNanoseconds - bgStart.uptimeNanoseconds) / 1_000_000.0

        var mainMs = 0.0
        await MainActor.run {
            mainMs = Self.elapsedMs {
                _ = PDFDocument(url: url)?.string
            }
        }

        print("[PDF-PROBE] 50p 추출 지연: background=\(String(format: "%.1f", bgMs))ms, mainActor=\(String(format: "%.1f", mainMs))ms")
        #expect(bgText != nil)
    }
}
