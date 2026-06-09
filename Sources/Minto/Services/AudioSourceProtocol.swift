import Foundation

/// onBuffer는 source별 capture queue에서 호출될 수 있다.
/// 소비자는 UI/MainActor 상태를 만지기 전에 직접 actor hop 해야 한다.
public protocol AudioSourceProtocol: AnyObject {
    var onBuffer: (@Sendable ([Float]) -> Void)? { get set }
    var onError: (@Sendable (AudioSourceError) -> Void)? { get set }
    /// 정규화된 오디오 레벨 (0.0 ~ 1.0). source별 capture queue에서 호출될 수 있다.
    var onLevel: (@Sendable (Float) -> Void)? { get set }
    var availableDevices: [AudioDevice] { get }
    func start() throws
    func stop()
    func selectDevice(_ device: AudioDevice) throws
}
