import AVFoundation
import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public final class SystemAudioSource: NSObject, AudioSourceProtocol, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public var onBuffer: (@Sendable ([Float]) -> Void)?
    public var onError: (@Sendable (AudioSourceError) -> Void)?
    public var onLevel: (@Sendable (Float) -> Void)?

    public var availableDevices: [AudioDevice] {
        [AudioDevice(id: "system-audio", name: AudioInputMode.systemAudio.title)]
    }

    private let outputQueue = DispatchQueue(label: "minto.system-audio.capture")
    private let stateLock = NSLock()
    private var stream: SCStream?
    private var startTask: Task<Void, Never>?
    private var isCapturing = false

    public func start() throws {
        guard stream == nil else { return }

        startTask?.cancel()
        startTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.startCapture()
            } catch is CancellationError {
                return
            } catch {
                self.stop()
                self.report(Self.audioSourceError(from: error))
            }
        }
    }

    public func stop() {
        startTask?.cancel()
        startTask = nil
        setCapturing(false)

        guard let stream else { return }
        self.stream = nil
        Task {
            try? await stream.stopCapture()
        }
    }

    public func selectDevice(_ device: AudioDevice) throws {
        guard device.id == "system-audio" else {
            throw AudioSourceError.deviceNotFound(device)
        }
    }

    private func startCapture() async throws {
        let content = try await SCShareableContent.current
        try Task.checkCancellation()
        guard let display = content.displays.first else {
            throw AudioSourceError.systemAudioUnavailable("캡처 가능한 디스플레이가 없습니다.")
        }

        let configuration = SCStreamConfiguration()
        configuration.width = max(2, display.width)
        configuration.height = max(2, display.height)
        configuration.queueDepth = 1
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = Int(STTAudioUtilities.sampleRate)
        configuration.channelCount = 1

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
        try Task.checkCancellation()
        self.stream = stream
        setCapturing(true)
        try await withTaskCancellationHandler {
            try await stream.startCapture()
        } onCancel: {
            Task {
                try? await stream.stopCapture()
            }
        }
    }

    public func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        guard isCapturingSnapshot(),
              type == .audio,
              CMSampleBufferDataIsReady(sampleBuffer)
        else { return }
        do {
            let samples = try Self.floatSamples(from: sampleBuffer)
            guard !samples.isEmpty else { return }
            let level = STTAudioUtilities.normalizedLevel(samples)
            onBuffer?(samples)
            onLevel?(level)
        } catch {
            report(.engineStartFailed(error))
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        guard isCapturingSnapshot() else { return }
        setCapturing(false)
        report(Self.audioSourceError(from: error))
    }

    private func report(_ error: AudioSourceError) {
        DispatchQueue.main.async { [weak self] in
            self?.onError?(error)
        }
    }

    private func setCapturing(_ value: Bool) {
        stateLock.lock()
        isCapturing = value
        stateLock.unlock()
    }

    private func isCapturingSnapshot() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isCapturing
    }

    private static func audioSourceError(from error: Error) -> AudioSourceError {
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

    private static func floatSamples(from sampleBuffer: CMSampleBuffer) throws -> [Float] {
        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else {
            return []
        }

        let asbd = streamDescription.pointee
        let channelCount = max(1, Int(asbd.mChannelsPerFrame))
        let bufferCount = channelCount
        let audioBufferList = AudioBufferList.allocate(maximumBuffers: bufferCount)
        defer { audioBufferList.unsafeMutablePointer.deallocate() }

        var blockBuffer: CMBlockBuffer?
        let bufferListSize = MemoryLayout<AudioBufferList>.size
            + MemoryLayout<AudioBuffer>.size * (bufferCount - 1)
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList.unsafeMutablePointer,
            bufferListSize: bufferListSize,
            blockBufferAllocator: kCFAllocatorDefault,
            blockBufferMemoryAllocator: kCFAllocatorDefault,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return [] }

        let channelSamples = audioBufferList.compactMap { buffer -> [Float]? in
            guard let data = buffer.mData else { return nil }
            return convertBuffer(data: data, byteCount: Int(buffer.mDataByteSize), asbd: asbd)
        }
        guard let first = channelSamples.first, !first.isEmpty else { return [] }
        guard channelSamples.count > 1 else {
            return monoSamples(fromInterleaved: first, channelCount: channelCount)
        }

        let frameCount = channelSamples.map(\.count).min() ?? 0
        guard frameCount > 0 else { return [] }
        var mono = [Float]()
        mono.reserveCapacity(frameCount)
        for frameIndex in 0..<frameCount {
            let sum = channelSamples.reduce(Float(0)) { partial, channel in
                partial + channel[frameIndex]
            }
            mono.append(sum / Float(channelSamples.count))
        }
        return mono
    }

    private static func convertBuffer(
        data: UnsafeMutableRawPointer,
        byteCount: Int,
        asbd: AudioStreamBasicDescription
    ) -> [Float]? {
        let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0
        let isSignedInteger = (asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger) != 0

        if isFloat, asbd.mBitsPerChannel == 32 {
            let count = byteCount / MemoryLayout<Float>.size
            let pointer = data.bindMemory(to: Float.self, capacity: count)
            return Array(UnsafeBufferPointer(start: pointer, count: count))
        }

        if isSignedInteger, asbd.mBitsPerChannel == 16 {
            let count = byteCount / MemoryLayout<Int16>.size
            let pointer = data.bindMemory(to: Int16.self, capacity: count)
            return UnsafeBufferPointer(start: pointer, count: count).map {
                Float($0) / Float(Int16.max)
            }
        }

        if isSignedInteger, asbd.mBitsPerChannel == 32 {
            let count = byteCount / MemoryLayout<Int32>.size
            let pointer = data.bindMemory(to: Int32.self, capacity: count)
            return UnsafeBufferPointer(start: pointer, count: count).map {
                Float($0) / Float(Int32.max)
            }
        }

        return nil
    }

    private static func monoSamples(fromInterleaved samples: [Float], channelCount: Int) -> [Float] {
        guard channelCount > 1 else { return samples }
        let frameCount = samples.count / channelCount
        var mono = [Float]()
        mono.reserveCapacity(frameCount)
        for frameIndex in 0..<frameCount {
            let offset = frameIndex * channelCount
            var sum: Float = 0
            for channelIndex in 0..<channelCount {
                sum += samples[offset + channelIndex]
            }
            mono.append(sum / Float(channelCount))
        }
        return mono
    }
}
