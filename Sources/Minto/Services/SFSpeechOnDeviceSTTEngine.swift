import os
import Foundation
@preconcurrency import Speech

@MainActor
final class SFSpeechOnDeviceSTTEngine: SpeechTranscriptionEngine {
    let engineID: SpeechEngineID = .sfSpeechOnDevice
    let modelVariant: String = SpeechEngineID.sfSpeechOnDevice.rawValue
    var supportsPreviewTranscription: Bool { false }

    func load(updateState: @escaping STTStateUpdater) async throws {
        let availability = Self.availability()
        guard availability.isSelectable else {
            if case .requiresPermission(let reason) = availability {
                throw STTError.speechAuthorizationRequired(reason)
            }
            throw STTError.engineUnavailable(availability.detailText ?? "SFSpeechRecognizer를 사용할 수 없어요.")
        }
        updateState(.loaded)
        Log.stt.info("Apple speech engine ready: \(self.engineID.rawValue, privacy: .public)")
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        let availability = Self.availability()
        guard availability.isSelectable else {
            if case .requiresPermission(let reason) = availability {
                throw STTError.speechAuthorizationRequired(reason)
            }
            throw STTError.engineUnavailable(availability.detailText ?? "SFSpeechRecognizer를 사용할 수 없어요.")
        }

        guard let recognizer = SFSpeechRecognizer(locale: STTAudioUtilities.koreanLocale) else {
            throw STTError.engineUnavailable("한국어 SFSpeechRecognizer를 만들 수 없어요.")
        }

        let samples = STTAudioUtilities.paddedSamples(pcmSamples)
        if let silent = STTAudioUtilities.silentResultIfNeeded(samples) {
            return silent
        }

        let url = try STTAudioUtilities.writeTemporaryAudioFile(samples: samples)
        defer { try? FileManager.default.removeItem(at: url) }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false
        request.addsPunctuation = true
        request.taskHint = .dictation

        let text = try await withCheckedThrowingContinuation { continuation in
            let completion = SFSpeechRecognitionCompletion(continuation: continuation)
            _ = recognizer.recognitionTask(with: request) { result, error in
                completion.handle(result: result, error: error)
            }
        }
        return STTAudioUtilities.transcriptionResult(text: text, sampleCount: samples.count)
    }

    nonisolated static func requestAuthorization() async -> SpeechEngineAvailability {
        _ = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        return availability()
    }

    nonisolated static func availability() -> SpeechEngineAvailability {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .requiresPermission("Apple 음성 인식 권한을 허용해야 사용할 수 있어요.")
        case .denied:
            return .unavailable("시스템 설정에서 Apple 음성 인식 권한이 거부되어 있어요.")
        case .restricted:
            return .unavailable("이 기기 정책상 Apple 음성 인식을 사용할 수 없어요.")
        case .authorized:
            break
        @unknown default:
            return .unavailable("Apple 음성 인식 권한 상태를 확인할 수 없어요.")
        }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ko-KR")) else {
            return .unavailable("한국어 SFSpeechRecognizer를 만들 수 없어요.")
        }

        guard recognizer.supportsOnDeviceRecognition else {
            return .unavailable("한국어 온디바이스 음성 인식 asset이 없어요.")
        }

        guard recognizer.isAvailable else {
            return .unavailable("현재 Apple 음성 인식 서비스를 사용할 수 없어요.")
        }

        return .available
    }
}

private final class SFSpeechRecognitionCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<String, Error>

    init(continuation: CheckedContinuation<String, Error>) {
        self.continuation = continuation
    }

    func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let error {
            resume(with: .failure(error))
            return
        }

        guard let result, result.isFinal else { return }
        resume(with: .success(result.bestTranscription.formattedString))
    }

    private func resume(with result: Result<String, Error>) {
        lock.lock()
        guard !didResume else {
            lock.unlock()
            return
        }
        didResume = true
        lock.unlock()

        switch result {
        case .success(let text):
            continuation.resume(returning: text)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}
