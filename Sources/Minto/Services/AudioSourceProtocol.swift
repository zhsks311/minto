import Foundation

/// onBuffer는 AVAudioEngine 오디오 스레드에서 호출됨.
/// 구현체는 반드시 main queue로 디스패치 후 콜백을 호출해야 함.
public protocol AudioSourceProtocol: AnyObject {
    var onBuffer: (@Sendable ([Float]) -> Void)? { get set }
    var onError: (@Sendable (AudioSourceError) -> Void)? { get set }
    /// 정규화된 오디오 레벨 (0.0 ~ 1.0). main thread에서 호출됨.
    var onLevel: (@Sendable (Float) -> Void)? { get set }
    var availableDevices: [AudioDevice] { get }
    func start() throws
    func stop()
    func selectDevice(_ device: AudioDevice) throws
}
