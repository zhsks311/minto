import CoreGraphics
import Foundation
@preconcurrency import ScreenCaptureKit

public enum SystemAudioAvailability: Sendable, Equatable {
    case available
    case permissionRequired
    case unavailable(String)
}

public struct AudioInputReadinessChecker: Sendable {
    public static let live = AudioInputReadinessChecker(
        hasScreenCapturePermission: {
            CGPreflightScreenCaptureAccess()
        },
        requestScreenCapturePermission: {
            CGRequestScreenCaptureAccess()
        },
        systemAudioAvailability: {
            await Self.defaultSystemAudioAvailability()
        }
    )

    private let hasScreenCapturePermission: @Sendable () -> Bool
    private let requestScreenCapturePermission: @Sendable () -> Bool
    private let systemAudioAvailability: @Sendable () async -> SystemAudioAvailability

    public init(
        hasScreenCapturePermission: @escaping @Sendable () -> Bool,
        requestScreenCapturePermission: @escaping @Sendable () -> Bool,
        systemAudioAvailability: @escaping @Sendable () async -> SystemAudioAvailability
    ) {
        self.hasScreenCapturePermission = hasScreenCapturePermission
        self.requestScreenCapturePermission = requestScreenCapturePermission
        self.systemAudioAvailability = systemAudioAvailability
    }

    public func readiness(for mode: AudioInputMode) async -> AudioInputReadiness {
        switch mode {
        case .microphone:
            return .ready(for: .microphone)
        case .mixed:
            return await systemAudioReadiness(for: .mixed)
        case .systemAudio:
            return await systemAudioReadiness(for: .systemAudio)
        }
    }

    @discardableResult
    public func requestPermission(for mode: AudioInputMode) async -> AudioInputReadiness {
        guard mode.requiresScreenCapturePermission else {
            return await readiness(for: mode)
        }
        _ = requestScreenCapturePermission()
        return await readiness(for: mode)
    }

    private func systemAudioReadiness(for mode: AudioInputMode) async -> AudioInputReadiness {
        guard hasScreenCapturePermission() else {
            return Self.systemAudioPermissionRequiredReadiness()
        }

        switch await systemAudioAvailability() {
        case .available:
            return Self.systemAudioReadyReadiness(for: mode)
        case .permissionRequired:
            return Self.systemAudioPermissionRequiredReadiness()
        case .unavailable(let reason):
            return AudioInputReadiness(
                state: .unavailable,
                title: "시스템 입력 사용 불가",
                detail: reason
            )
        }
    }

    private static func systemAudioReadyReadiness(for mode: AudioInputMode) -> AudioInputReadiness {
        switch mode {
        case .mixed:
            return AudioInputReadiness(
                state: .ready,
                title: "마이크+시스템 입력 가능",
                detail: "마이크와 시스템 사운드를 함께 입력합니다. Echo cancellation은 적용하지 않습니다."
            )
        case .systemAudio:
            return AudioInputReadiness(
                state: .ready,
                title: "시스템 입력 가능",
                detail: "화상회의 상대방 소리를 입력으로 받을 준비가 됐습니다."
            )
        case .microphone:
            return .ready(for: .microphone)
        }
    }

    private static func systemAudioPermissionRequiredReadiness() -> AudioInputReadiness {
        AudioInputReadiness(
            state: .permissionRequired,
            title: "시스템 입력 권한 필요",
            detail: "macOS 화면 및 시스템 오디오 녹음 권한을 허용한 뒤 앱으로 돌아와 다시 확인하세요.",
            actionTitle: "시스템 설정 열기"
        )
    }

    private static func defaultSystemAudioAvailability() async -> SystemAudioAvailability {
        do {
            let content = try await SCShareableContent.current
            guard !content.displays.isEmpty else {
                return .unavailable("캡처 가능한 디스플레이가 없습니다.")
            }
            return .available
        } catch {
            let sourceError = systemAudioError(from: error)
            switch sourceError {
            case .screenCapturePermissionDenied:
                return .permissionRequired
            case .systemAudioUnavailable(let reason):
                return .unavailable(reason)
            default:
                return .unavailable(error.localizedDescription)
            }
        }
    }

    private static func systemAudioError(from error: Error) -> AudioSourceError {
        if let sourceError = error as? AudioSourceError {
            return sourceError
        }

        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain {
            switch nsError.code {
            case SCStreamError.userDeclined.rawValue:
                return .screenCapturePermissionDenied
            case SCStreamError.missingEntitlements.rawValue:
                return .systemAudioUnavailable("ScreenCaptureKit 권한 설정이 필요합니다.")
            default:
                break
            }
        }
        return .engineStartFailed(error)
    }
}
