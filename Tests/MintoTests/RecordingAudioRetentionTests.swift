import Foundation
import Testing
@testable import MintoCore

@Suite("RecordingAudioArchiver")
struct RecordingAudioArchiverTests {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("minto2-audio-archive-\(UUID().uuidString)", isDirectory: true)
    }

    @Test("샘플을 기록하면 WAV 파일명이 반환되고 파일이 존재한다")
    func archivesSamplesToWAV() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiver = RecordingAudioArchiver(directory: directory)

        archiver.start()
        archiver.append(samples: [Float](repeating: 0.25, count: 16_000))
        archiver.append(samples: [Float](repeating: -0.25, count: 8_000))
        let fileName = await archiver.finish()

        let name = try #require(fileName)
        #expect(name.hasSuffix(".wav"))
        let url = directory.appendingPathComponent(name)
        let size = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        // 24,000프레임 × 16bit ≈ 48KB + WAV 헤더
        #expect(size > 40_000)
    }

    @Test("기록된 프레임이 없으면 nil을 반환하고 빈 파일을 남기지 않는다")
    func finishWithoutFramesReturnsNil() async throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let archiver = RecordingAudioArchiver(directory: directory)

        archiver.start()
        let fileName = await archiver.finish()

        #expect(fileName == nil)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        #expect(leftovers.filter { $0.hasSuffix(".wav") }.isEmpty)
    }

    @Test("보관 기간이 지난 WAV만 정리한다")
    func cleanupRemovesOnlyExpiredFiles() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let now = Date()
        let oldURL = directory.appendingPathComponent("old.wav")
        let recentURL = directory.appendingPathComponent("recent.wav")
        let unrelatedURL = directory.appendingPathComponent("note.txt")
        try Data([0x52]).write(to: oldURL)
        try Data([0x52]).write(to: recentURL)
        try Data([0x6E]).write(to: unrelatedURL)
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-40 * 24 * 60 * 60)],
            ofItemAtPath: oldURL.path
        )

        let removedCount = RecordingAudioArchiver.cleanupExpired(retentionDays: 30, now: now, in: directory)

        #expect(removedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: oldURL.path))
        #expect(FileManager.default.fileExists(atPath: recentURL.path))
        #expect(FileManager.default.fileExists(atPath: unrelatedURL.path))
    }

    @Test("removeArchivedFile은 파일명만 받아 디렉터리 안에서 지운다")
    func removeArchivedFileDeletesByName() throws {
        let directory = makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("keepsafe.wav")
        try Data([0x52]).write(to: url)

        // 경로 조작이 섞여도 lastPathComponent로 한정된다.
        RecordingAudioArchiver.removeArchivedFile(named: "../keepsafe.wav", in: directory)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("보관 설정 기본값은 켬, 기간 기본값은 30일")
    func preferenceDefaults() {
        let defaults = InMemoryUserDefaults()
        #expect(RecordingAudioArchiver.isEnabled(in: defaults))
        #expect(RecordingAudioArchiver.retentionDays(in: defaults) == 30)

        defaults.set(false, forKey: RecordingAudioArchiver.preferenceKey)
        defaults.set(7, forKey: RecordingAudioArchiver.retentionDaysKey)
        #expect(!RecordingAudioArchiver.isEnabled(in: defaults))
        #expect(RecordingAudioArchiver.retentionDays(in: defaults) == 7)
    }
}

@Suite("MeetingRecord 오디오 파일명 스키마")
struct MeetingRecordAudioFileNameTests {
    @Test("audioFileName 없는 기존 JSON도 로드된다(하위 호환)")
    func decodesLegacyJSONWithoutAudioFileName() throws {
        let legacyJSON = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "기존 회의",
          "startedAt": "2026-06-01T09:00:00Z",
          "durationSeconds": 60,
          "topic": "",
          "summary": {},
          "transcript": []
        }
        """
        let decoder = MeetingRecordCoding.makeDecoder()

        let record = try decoder.decode(MeetingRecord.self, from: Data(legacyJSON.utf8))

        #expect(record.title == "기존 회의")
        #expect(record.audioFileName == nil)
    }

    @Test("audioFileName은 저장/로드 왕복에서 보존된다")
    func roundTripsAudioFileName() throws {
        let record = MeetingRecord(
            title: "오디오 보존 회의",
            startedAt: Date(timeIntervalSince1970: 1_000),
            durationSeconds: 30,
            audioFileName: "abc.wav"
        )
        let encoder = MeetingRecordCoding.makeEncoder()
        let decoder = MeetingRecordCoding.makeDecoder()

        let decoded = try decoder.decode(MeetingRecord.self, from: encoder.encode(record))

        #expect(decoded.audioFileName == "abc.wav")
    }
}

@Suite("MeetingRecord 화자 임베딩 스키마")
struct MeetingRecordSpeakerEmbeddingTests {
    @Test("speakerEmbeddings 없는 기존 JSON도 로드된다(하위 호환)")
    func decodesLegacyJSONWithoutSpeakerEmbeddings() throws {
        let legacyJSON = """
        {
          "id": "11111111-2222-3333-4444-555555555555",
          "title": "기존 회의",
          "startedAt": "2026-06-01T09:00:00Z",
          "durationSeconds": 60,
          "topic": "",
          "summary": {},
          "transcript": []
        }
        """
        let decoder = MeetingRecordCoding.makeDecoder()

        let record = try decoder.decode(MeetingRecord.self, from: Data(legacyJSON.utf8))

        #expect(record.title == "기존 회의")
        #expect(record.speakerEmbeddings == nil)
    }

    @Test("speakerEmbeddings는 저장/로드 왕복에서 보존된다")
    func roundTripsSpeakerEmbeddings() throws {
        let speakerEmbedding = MeetingRecord.MeetingSpeakerEmbedding(
            speakerLabel: "화자 1",
            embedding: [1, 0],
            embeddingModelID: "speaker-v1"
        )
        let record = MeetingRecord(
            title: "화자 임베딩 회의",
            startedAt: Date(timeIntervalSince1970: 1_000),
            durationSeconds: 30,
            speakerEmbeddings: [speakerEmbedding]
        )
        let encoder = MeetingRecordCoding.makeEncoder()
        let decoder = MeetingRecordCoding.makeDecoder()

        let decoded = try decoder.decode(MeetingRecord.self, from: encoder.encode(record))

        #expect(decoded.speakerEmbeddings == [speakerEmbedding])
    }
}

@MainActor
@Suite("녹음 오디오 보존 통합", .serialized)
struct RecordingAudioRetentionIntegrationTests {
    @Test("녹음 시작→샘플→종료 후 보존 파일명이 노출된다")
    func recordingArchivesAudioAndExposesFileName() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("minto2-audio-vm-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let audioSource = ArchiveStubAudioSource()
        let viewModel = TranscriptionViewModel(
            sttService: ArchiveStubSTTService(),
            audioSource: audioSource,
            vadProcessor: ArchiveStubVAD(),
            audioArchiverFactory: { RecordingAudioArchiver(directory: directory) }
        )

        viewModel.startRecording()
        audioSource.emit(samples: [Float](repeating: 0.2, count: 16_000))
        // onBuffer는 MainActor Task로 전달된다 — 큐에 올라간 buffer가 처리될 시간을 준다.
        await Task.yield()
        await Task.yield()
        await viewModel.stopRecordingAndDrain()

        let fileName = try #require(viewModel.lastArchivedAudioFileName)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(fileName).path))
    }
}

private final class ArchiveStubAudioSource: AudioSourceProtocol {
    var onBuffer: (@Sendable ([Float]) -> Void)?
    var onError: (@Sendable (AudioSourceError) -> Void)?
    var onLevel: (@Sendable (Float) -> Void)?
    var availableDevices: [AudioDevice] = []

    func start() throws {}
    func stop() {}
    func selectDevice(_ device: AudioDevice) throws {}

    func emit(samples: [Float]) {
        onBuffer?(samples)
    }
}

@MainActor
private final class ArchiveStubSTTService: TranscriptionSTTServicing {
    var modelState: ModelState = .loaded
    var modelVariant: String = "stub"
    var speechEngineID: SpeechEngineID = .whisperAccurate
    var supportsPreviewTranscription: Bool = false
    var onModelStateChange: ((ModelState) -> Void)?

    func loadEngine(_ engineID: SpeechEngineID) async {
        speechEngineID = engineID
    }

    func loadModel(variant: String) async {
        modelVariant = variant
    }

    func recoverModelCacheAndReload(variant: String) async {
        modelVariant = variant
    }

    func transcribe(pcmSamples: [Float]) async throws -> TranscriptionResult {
        TranscriptionResult(
            segment: Segment(text: "", timestamp: Date(), duration: 0),
            isFinal: true
        )
    }
}

private final class ArchiveStubVAD: VoiceActivityDetector, @unchecked Sendable {
    var onChunk: (@Sendable (AudioChunk) -> Void)?
    var onPreviewChunk: (@Sendable (AudioChunk) -> Void)?

    func process(samples: [Float]) {}
    func flushPending() async -> AudioChunk? { nil }
    func reset() {}
}
