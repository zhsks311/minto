import Foundation
import Testing
@testable import MintoCore

@Suite("System Audio Live Capture (Manual Only)", .serialized)
struct SystemAudioLiveTests {
    @Test("SystemAudioSource는 별도 프로세스의 시스템 오디오를 buffer로 받는다")
    func systemAudioSourceCapturesSeparateProcessOutput() async throws {
        guard ProcessInfo.processInfo.environment["RUN_SYSTEM_AUDIO_LIVE_TEST"] == "1" else { return }

        let afplayPath = "/usr/bin/afplay"
        guard FileManager.default.isExecutableFile(atPath: afplayPath) else {
            Issue.record("afplay 실행 파일이 없습니다: \(afplayPath)")
            return
        }

        let readiness = await AudioInputReadinessChecker.live.readiness(for: .systemAudio)
        guard readiness.canStartRecording else {
            Issue.record("시스템 오디오 입력을 시작할 수 없습니다: \(readiness.title) / \(readiness.detail)")
            return
        }

        let toneURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto-system-audio-live-test-\(UUID().uuidString).wav")
        try Self.writeSineWave(to: toneURL)
        defer {
            try? FileManager.default.removeItem(at: toneURL)
        }

        let probe = SystemAudioLiveProbe()
        let source = SystemAudioSource()
        source.onBuffer = { samples in
            Task { await probe.record(samples: samples) }
        }
        source.onLevel = { level in
            Task { await probe.record(level: level) }
        }
        source.onError = { error in
            Task { await probe.record(error: error) }
        }

        try source.start()
        defer { source.stop() }
        try await Task.sleep(nanoseconds: 800_000_000)

        try Self.playAudio(at: toneURL, afplayPath: afplayPath)

        let captured = await probe.waitForSamples(minSamples: 1_600, timeoutNanoseconds: 4_000_000_000)
        let snapshot = await probe.snapshot()
        if !snapshot.errors.isEmpty {
            Issue.record("SystemAudioSource error callbacks: \(snapshot.errors.joined(separator: ", "))")
        }
        #expect(captured, "SystemAudioSource가 외부 afplay 출력에서 충분한 sample을 받지 못했습니다. samples=\(snapshot.sampleCount)")
        #expect(snapshot.maxLevel > 0.001, "SystemAudioSource level이 갱신되지 않았습니다. maxLevel=\(snapshot.maxLevel)")
    }

    private static func playAudio(at url: URL, afplayPath: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: afplayPath)
        process.arguments = [url.path]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0, "afplay 종료 코드가 0이 아닙니다: \(process.terminationStatus)")
    }

    private static func writeSineWave(
        to url: URL,
        durationSeconds: Double = 1.2,
        sampleRate: Int = 44_100,
        frequency: Double = 880,
        amplitude: Double = 0.35
    ) throws {
        let frameCount = Int(durationSeconds * Double(sampleRate))
        let bitsPerSample = 16
        let channelCount = 1
        let byteRate = sampleRate * channelCount * bitsPerSample / 8
        let blockAlign = channelCount * bitsPerSample / 8
        let dataByteCount = frameCount * blockAlign

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendUInt32LE(UInt32(36 + dataByteCount))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendUInt32LE(16)
        data.appendUInt16LE(1)
        data.appendUInt16LE(UInt16(channelCount))
        data.appendUInt32LE(UInt32(sampleRate))
        data.appendUInt32LE(UInt32(byteRate))
        data.appendUInt16LE(UInt16(blockAlign))
        data.appendUInt16LE(UInt16(bitsPerSample))
        data.append(contentsOf: "data".utf8)
        data.appendUInt32LE(UInt32(dataByteCount))

        for frame in 0..<frameCount {
            let phase = 2.0 * Double.pi * frequency * Double(frame) / Double(sampleRate)
            let sample = Int16(max(-1.0, min(1.0, sin(phase) * amplitude)) * Double(Int16.max))
            data.appendInt16LE(sample)
        }

        try data.write(to: url, options: .atomic)
    }
}

private actor SystemAudioLiveProbe {
    private var sampleCount = 0
    private var maxLevel: Float = 0
    private var errors: [String] = []

    func record(samples: [Float]) {
        sampleCount += samples.count
    }

    func record(level: Float) {
        maxLevel = max(maxLevel, level)
    }

    func record(error: AudioSourceError) {
        errors.append(String(describing: error))
    }

    func waitForSamples(minSamples: Int, timeoutNanoseconds: UInt64) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if sampleCount >= minSamples || !errors.isEmpty {
                return sampleCount >= minSamples
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return sampleCount >= minSamples
    }

    func snapshot() -> (sampleCount: Int, maxLevel: Float, errors: [String]) {
        (sampleCount, maxLevel, errors)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        append(bytesOf: &littleEndian)
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        append(bytesOf: &littleEndian)
    }

    mutating func appendInt16LE(_ value: Int16) {
        var littleEndian = value.littleEndian
        append(bytesOf: &littleEndian)
    }

    private mutating func append<T>(bytesOf value: inout T) {
        Swift.withUnsafeBytes(of: &value) { bytes in
            append(contentsOf: bytes)
        }
    }
}
