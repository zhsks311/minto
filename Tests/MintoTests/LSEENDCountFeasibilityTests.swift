import Foundation
import Testing
@preconcurrency import FluidAudio
@testable import MintoCore

@Suite("LS-EEND 화자 수 측정", .serialized)
struct LSEENDCountFeasibilityTests {
    @Test(
        "FluidAudio LS-EEND가 실제 WAV에서 검출한 화자 수를 출력한다",
        .enabled(if: ProcessInfo.processInfo.environment["RUN_LSEEND_POC"] == "1")
    )
    func countsDetectedSpeakers() async throws {
        let environment = ProcessInfo.processInfo.environment
        let wavPath = try #require(
            nonEmptyEnvironmentValue("DIARIZATION_EVAL_WAV", in: environment),
            "DIARIZATION_EVAL_WAV가 필요합니다"
        )
        let wavURL = URL(fileURLWithPath: wavPath)
        try #require(FileManager.default.fileExists(atPath: wavURL.path), "WAV 파일이 존재해야 합니다")

        let variantName = (nonEmptyEnvironmentValue("LSEEND_VARIANT", in: environment) ?? "ami").lowercased()
        let variant = try lseendVariant(named: variantName)
        let samples = try AudioConverter().resampleAudioFile(wavURL)
        try #require(!samples.isEmpty, "AudioConverter가 빈 샘플을 반환했습니다 — WAV 파일이 유효한지 확인")
        let diarizer = try await LSEENDDiarizer(variant: variant)
        let audioSeconds = Double(samples.count) / 16_000.0
        let procStart = CFAbsoluteTimeGetCurrent()
        let timeline = try diarizer.processComplete(
            samples,
            // AudioConverter() 기본 타깃이 16kHz mono → sourceSampleRate도 16k로 일치
            sourceSampleRate: 16_000,
            keepingEnrolledSpeakers: nil,
            finalizeOnCompletion: true,
            progressCallback: nil
        )
        let procElapsed = CFAbsoluteTimeGetCurrent() - procStart
        let rtfx = procElapsed > 0 ? audioSeconds / procElapsed : 0

        let activeSpeakers = timeline.speakers.values.filter { !$0.finalizedSegments.isEmpty }
        let totalSegments = activeSpeakers.reduce(0) { $0 + $1.finalizedSegments.count }
        // 평가 러너는 측정값을 눈으로 봐야 하므로 stdout에도 찍는다(Log는 통합 로깅이라 캡처가 안 됨).
        // print 금지 규칙은 제품 Sources 대상이고, 이 게이트 테스트는 측정 출력이 목적이다.
        print(String(
            format: "[LSEEND-POC] variant=%@ detectedSpeakers=%d totalSegments=%d audioSec=%.1f procSec=%.2f rtfx=%.1f",
            variantName, activeSpeakers.count, totalSegments, audioSeconds, procElapsed, rtfx
        ))
        #expect(totalSegments > 0, "LS-EEND 결과 segment가 있어야 합니다")
    }

    private func nonEmptyEnvironmentValue(
        _ key: String,
        in environment: [String: String]
    ) -> String? {
        guard let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else {
            return nil
        }
        return value
    }

    private func lseendVariant(named rawValue: String) throws -> LSEENDVariant {
        switch rawValue.lowercased() {
        case "ami":
            return .ami
        case "callhome":
            return .callhome
        case "dihard2":
            return .dihard2
        case "dihard3":
            return .dihard3
        default:
            throw LSEENDCountFeasibilityError.invalidVariant(value: rawValue)
        }
    }
}

private enum LSEENDCountFeasibilityError: Error, CustomStringConvertible {
    case invalidVariant(value: String)

    var description: String {
        switch self {
        case .invalidVariant(let value):
            return "LSEEND_VARIANT는 ami, callhome, dihard2, dihard3 중 하나여야 합니다: \(value)"
        }
    }
}
