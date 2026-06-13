import Foundation
import os

// MARK: - 앱 진단 로거
//
// subsystem: 번들 ID (com.minto.app)
// category: 서브시스템별 static Logger — 배포 바이너리에서도 Console.app / log stream 으로 조회 가능.
// 동적 문자열은 기본 private 마스킹되므로 비민감 값(상태·개수·파일명·에러 설명)만 .public 으로 명시한다.
// 전사/프롬프트 원문은 어떤 privacy 수준으로도 남기지 않는다.

private let subsystem = Bundle.main.bundleIdentifier ?? "com.minto.app"

enum Log {
    static let app      = Logger(subsystem: subsystem, category: "app")
    static let stt      = Logger(subsystem: subsystem, category: "stt")
    static let vad      = Logger(subsystem: subsystem, category: "vad")
    static let audio    = Logger(subsystem: subsystem, category: "audio")
    static let correction = Logger(subsystem: subsystem, category: "correction")
    static let summary  = Logger(subsystem: subsystem, category: "summary")
    static let store    = Logger(subsystem: subsystem, category: "store")
    static let search   = Logger(subsystem: subsystem, category: "search")
    static let importer = Logger(subsystem: subsystem, category: "importer")
    static let oauth    = Logger(subsystem: subsystem, category: "oauth")
    static let report   = Logger(subsystem: subsystem, category: "report")
    static let diarization = Logger(subsystem: subsystem, category: "diarization")
}
