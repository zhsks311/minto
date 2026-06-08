import Foundation
import Testing
@testable import MintoCore

@MainActor
@Suite("Nemotron sidecar transcriber")
struct NemotronSidecarTranscriberTests {

    @Test("load는 sidecar readiness를 확인하고 loaded 상태로 전환한다")
    func loadChecksReadiness() async throws {
        let client = StubNemotronTranscribingClient(
            health: NemotronSidecarHealth(
                status: "ready",
                modelID: "nemotron-8bit",
                quantization: "8bit",
                device: "mps",
                detail: nil
            )
        )
        let transcriber = NemotronSidecarTranscriber(client: client)
        var states: [ModelState] = []

        try await transcriber.load { states.append($0) }

        #expect(states == [.loading, .loaded])
        #expect(await client.healthCallCount == 1)
    }

    @Test("load는 sidecar가 준비되지 않았으면 failed 상태와 engineUnavailable 오류를 반환한다")
    func loadFailsWhenSidecarIsNotReady() async throws {
        let client = StubNemotronTranscribingClient(
            health: NemotronSidecarHealth(
                status: "warming",
                modelID: "nemotron-8bit",
                quantization: "8bit",
                device: "mps",
                detail: "model loading"
            )
        )
        let transcriber = NemotronSidecarTranscriber(client: client)
        var states: [ModelState] = []

        do {
            try await transcriber.load { states.append($0) }
            Issue.record("ready가 아닌 sidecar는 load에 실패해야 한다")
        } catch let error as STTError {
            #expect(error.localizedDescription.contains("model loading"))
        }

        #expect(states == [.loading, .failed("model loading")])
        #expect(await client.healthCallCount == 1)
    }

    @Test("transcribe는 짧은 입력을 padding해서 sidecar로 보내고 final 결과를 만든다")
    func transcribePadsSamplesAndReturnsFinalResult() async throws {
        let client = StubNemotronTranscribingClient(
            transcription: NemotronSidecarTranscription(
                text: "  안녕하세요  ",
                modelID: "nemotron-8bit",
                audioSeconds: 0.25,
                elapsedSeconds: 0.05,
                rtf: 0.2,
                peakMemoryMB: 512
            )
        )
        let transcriber = NemotronSidecarTranscriber(
            client: client,
            makeRequestID: { "req-fixed" }
        )

        let result = try await transcriber.transcribe(
            pcmSamples: [Float](repeating: 0.2, count: 4_000)
        )

        #expect(result.isFinal)
        #expect(result.segment.text == "안녕하세요")
        #expect(result.segment.duration == 0.5)
        #expect(await client.transcribedSampleCounts == [8_000])
        #expect(await client.requestIDs == ["req-fixed"])
    }

    @Test("무음 입력은 sidecar를 호출하지 않고 빈 final 결과를 반환한다")
    func silentInputSkipsSidecar() async throws {
        let client = StubNemotronTranscribingClient()
        let transcriber = NemotronSidecarTranscriber(client: client)

        let result = try await transcriber.transcribe(
            pcmSamples: [Float](repeating: 0, count: 4_000)
        )

        #expect(result.isFinal)
        #expect(result.segment.text.isEmpty)
        #expect(result.segment.duration == 0.5)
        #expect(await client.transcribedSampleCounts.isEmpty)
    }
}

private actor StubNemotronTranscribingClient: NemotronSidecarTranscribing {
    private let healthResponse: NemotronSidecarHealth
    private let transcriptionResponse: NemotronSidecarTranscription
    private var capturedHealthCallCount = 0
    private var capturedTranscribedSampleCounts: [Int] = []
    private var capturedRequestIDs: [String?] = []

    var healthCallCount: Int {
        capturedHealthCallCount
    }

    var transcribedSampleCounts: [Int] {
        capturedTranscribedSampleCounts
    }

    var requestIDs: [String?] {
        capturedRequestIDs
    }

    init(
        health: NemotronSidecarHealth = NemotronSidecarHealth(
            status: "ready",
            modelID: "nemotron-8bit",
            quantization: "8bit",
            device: "mps",
            detail: nil
        ),
        transcription: NemotronSidecarTranscription = NemotronSidecarTranscription(
            text: "",
            modelID: "nemotron-8bit",
            audioSeconds: 0,
            elapsedSeconds: 0,
            rtf: 0,
            peakMemoryMB: nil
        )
    ) {
        self.healthResponse = health
        self.transcriptionResponse = transcription
    }

    func health() async throws -> NemotronSidecarHealth {
        capturedHealthCallCount += 1
        return healthResponse
    }

    func transcribe(
        pcmSamples: [Float],
        requestID: String?
    ) async throws -> NemotronSidecarTranscription {
        capturedTranscribedSampleCounts.append(pcmSamples.count)
        capturedRequestIDs.append(requestID)
        return transcriptionResponse
    }
}
