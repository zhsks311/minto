import Foundation
import Testing
@testable import MintoCore

@Suite("모델 캐시 복구")
struct ModelCacheRecoveryTests {

    @Test("현재 variant와 size suffix 캐시만 복구 후보로 잡는다")
    func cacheCandidateURLsAreScopedToVariant() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-model-cache-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let variant = "openai_whisper-large-v3-v20240930_turbo"
        let downloadRoot = root
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("download", isDirectory: true)

        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(variant, isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("\(variant)_632MB", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("openai_whisper-small", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: downloadRoot.appendingPathComponent(variant, isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: downloadRoot.appendingPathComponent("\(variant)_632MB", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: downloadRoot.appendingPathComponent("openai_whisper-base", isDirectory: true),
            withIntermediateDirectories: true
        )

        let paths = Set(STTService.modelCacheCandidateURLs(for: variant, repoRoot: root).map(canonicalPath))

        #expect(paths.contains(canonicalPath(root.appendingPathComponent(variant, isDirectory: true))))
        #expect(paths.contains(canonicalPath(root.appendingPathComponent("\(variant)_632MB", isDirectory: true))))
        #expect(paths.contains(canonicalPath(downloadRoot.appendingPathComponent(variant, isDirectory: true))))
        #expect(paths.contains(canonicalPath(downloadRoot.appendingPathComponent("\(variant)_632MB", isDirectory: true))))
        #expect(!paths.contains(canonicalPath(root.appendingPathComponent("openai_whisper-small", isDirectory: true))))
        #expect(!paths.contains(canonicalPath(downloadRoot.appendingPathComponent("openai_whisper-base", isDirectory: true))))
    }

    @Test("손상된 metadata 오류는 자동 복구 대상으로 본다")
    func invalidMetadataErrorIsRecoverable() {
        let error = NSError(
            domain: "Hub",
            code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Invalid metadata: Could not remove corrupted metadata file"
            ]
        )

        #expect(STTService.isRecoverableMetadataError(error))
        #expect(!STTService.isRecoverableMetadataError(CocoaError(.fileNoSuchFile)))
    }

    private func canonicalPath(_ url: URL) -> String {
        url.resolvingSymlinksInPath().path
    }
}
