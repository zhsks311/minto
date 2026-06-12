import Foundation
import FluidAudio

/// Silero VAD 모델(~1MB)의 준비 상태를 관리한다.
///
/// FluidAudio `VadManager`는 모델이 없으면 다운로드까지 수행하므로, 여기서는
/// init 한 번으로 모델 파일을 영속 디렉터리에 채우고 상태만 UI에 노출한다.
/// 녹음 경로는 다운로드를 기다리지 않는다 — factory가 모델 부재 시 Energy로
/// fail-soft 하고, 준비가 끝나면 다음 녹음부터 Silero가 적용된다.
@MainActor
public final class SileroVADModelStore: ObservableObject {
    public static let shared = SileroVADModelStore()

    @Published public private(set) var state: ModelState = .unloaded

    private var prepareTask: Task<Void, Never>?
    private let environment: [String: String]

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
        if isModelReady {
            state = .loaded
        }
    }

    public var isModelReady: Bool {
        configuration.hasLocalModelBundle
    }

    private var configuration: SileroVADProcessor.Configuration {
        SileroVADProcessor.Configuration(environment: environment) ?? .defaultCandidate
    }

    /// 모델이 없으면 다운로드를 시작한다. 이미 준비됐거나 진행 중이면 아무것도 하지 않는다.
    public func prepareIfNeeded() {
        if isModelReady {
            state = .loaded
            return
        }
        prepare()
    }

    public func prepare() {
        guard prepareTask == nil else { return }
        let modelDirectory = configuration.modelDirectory
        state = .downloading(0)
        Log.vad.info("silero vad model prepare start dir=\(modelDirectory.lastPathComponent, privacy: .public)")
        // @MainActor 클래스는 Sendable이라 강한 캡처가 안전하고, 다운로드 동안만 수명이 연장된다.
        prepareTask = Task {
            defer { self.prepareTask = nil }
            do {
                // VadManager init이 모델 다운로드(필요 시)와 로드를 함께 수행한다.
                // 인스턴스는 파일 준비가 목적이라 버린다 — 녹음 경로가 자체 생성한다.
                _ = try await VadManager(
                    config: .default,
                    modelDirectory: modelDirectory,
                    progressHandler: { progress in
                        // 백그라운드 스레드 콜백 — 상태 접근은 MainActor Task 안에서만 한다.
                        let fraction = progress.fractionCompleted
                        Task { @MainActor [weak self] in
                            guard let self, case .downloading = self.state else { return }
                            self.state = .downloading(fraction)
                        }
                    }
                )
                self.state = .loaded
                Log.vad.info("silero vad model ready dir=\(modelDirectory.lastPathComponent, privacy: .public)")
            } catch {
                self.state = .failed(error.localizedDescription)
                Log.vad.error("silero vad model prepare failed error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
