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
            at: downloadRoot.appendingPathComponent("openai_whisper-base", isDirectory: true),
            withIntermediateDirectories: true
        )

        let names = Set(STTService.modelCacheCandidateURLs(for: variant, repoRoot: root).map(\.lastPathComponent))

        #expect(names == [variant, "\(variant)_632MB"])
        #expect(!names.contains("openai_whisper-small"))
        #expect(!names.contains("openai_whisper-base"))
    }
}
