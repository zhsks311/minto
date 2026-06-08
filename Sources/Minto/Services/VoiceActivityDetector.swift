import Foundation

public protocol VoiceActivityDetector: AnyObject, Sendable {
    var onChunk: (@Sendable (AudioChunk) -> Void)? { get set }
    var onPreviewChunk: (@Sendable (AudioChunk) -> Void)? { get set }

    func process(samples: [Float])
    func flushPending() async -> AudioChunk?
    func reset()
}

extension VADProcessor: VoiceActivityDetector {}
