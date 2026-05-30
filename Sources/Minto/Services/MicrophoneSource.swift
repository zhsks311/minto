@preconcurrency import AVFoundation

public final class MicrophoneSource: NSObject, AudioSourceProtocol, @unchecked Sendable {

    // MARK: - AudioSourceProtocol

    public var onBuffer: (@Sendable ([Float]) -> Void)?
    public var onError: (@Sendable (AudioSourceError) -> Void)?
    public var onLevel: (@Sendable (Float) -> Void)?

    public var availableDevices: [AudioDevice] {
        let deviceTypes: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            deviceTypes = [.microphone]
        } else {
            deviceTypes = [.builtInMicrophone]
        }
        return AVCaptureDevice.DiscoverySession(
            deviceTypes: deviceTypes,
            mediaType: .audio,
            position: .unspecified
        ).devices.map { AudioDevice(id: $0.uniqueID, name: $0.localizedName) }
    }

    // MARK: - Private state (mutated only on main thread)

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var configObserver: NSObjectProtocol?

    // MARK: - AudioSourceProtocol: start

    public func start() throws {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .denied, .restricted:
            onError?(.permissionDenied)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        do {
                            try self?.startEngine()
                        } catch {
                            self?.onError?(.engineStartFailed(error))
                        }
                    } else {
                        self?.onError?(.permissionDenied)
                    }
                }
            }
        case .authorized:
            try startEngine()
        @unknown default:
            onError?(.permissionDenied)
        }
    }

    // MARK: - AudioSourceProtocol: stop

    public func stop() {
        guard let engine else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        self.engine = nil
        self.converter = nil
    }

    // MARK: - AudioSourceProtocol: selectDevice

    public func selectDevice(_ device: AudioDevice) throws {
        stop()
        try startEngine()
    }

    // MARK: - Private

    private func startEngine() throws {
        let newEngine = AVAudioEngine()
        let inputNode = newEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        guard let newConverter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioSourceError.engineStartFailed(
                NSError(domain: "MicrophoneSource", code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "AVAudioConverter 생성 실패"])
            )
        }

        installTap(on: inputNode, inputFormat: inputFormat, converter: newConverter)

        do {
            try newEngine.start()
        } catch {
            throw AudioSourceError.engineStartFailed(error)
        }

        engine = newEngine
        converter = newConverter

        let observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigChange()
        }
        configObserver = observer
    }

    private func installTap(
        on inputNode: AVAudioInputNode,
        inputFormat: AVAudioFormat,
        converter: AVAudioConverter
    ) {
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16000,
            channels: 1,
            interleaved: false
        )!

        nonisolated(unsafe) let safeConverter = converter

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * (outputFormat.sampleRate / inputFormat.sampleRate)
            )
            guard let convertedBuffer = AVAudioPCMBuffer(
                pcmFormat: outputFormat,
                frameCapacity: frameCapacity + 1
            ) else { return }

            var error: NSError?
            nonisolated(unsafe) var inputConsumed = false
            safeConverter.convert(to: convertedBuffer, error: &error) { _, outStatus in
                if inputConsumed {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                inputConsumed = true
                outStatus.pointee = .haveData
                nonisolated(unsafe) let sendableBuffer = buffer
                return sendableBuffer
            }

            guard error == nil,
                  convertedBuffer.frameLength > 0,
                  let channelData = convertedBuffer.floatChannelData else { return }

            let frameCount = Int(convertedBuffer.frameLength)
            let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))

            // RMS → dB → 정규화 (0.0~1.0)
            let rms = sqrt(samples.reduce(0.0) { $0 + $1 * $1 } / Float(samples.count))
            let db = 20 * log10(max(rms, 1e-7))
            let level = Float(max(0, min(1, (db + 60) / 50)))  // -60dB→0, -10dB→1

            DispatchQueue.main.async { [weak self] in
                self?.onBuffer?(samples)
                self?.onLevel?(level)
            }
        }
    }

    @objc private func handleConfigChange() {
        do {
            try restart()
        } catch {
            onError?(.configChangeFailed(error))
        }
    }

    private func restart() throws {
        stop()
        try startEngine()
    }
}
