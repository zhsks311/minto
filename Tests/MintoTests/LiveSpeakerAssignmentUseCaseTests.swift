import Testing
@testable import MintoCore

@Suite("LiveSpeakerAssignmentUseCase")
struct LiveSpeakerAssignmentUseCaseTests {
    @Test("start, ingest, finish는 provider 스냅샷을 교체하고 시간순으로 정렬한다")
    func replacesAndSortsSnapshots() async throws {
        let provider = MockStreamingSpeakerDiarizationProvider(
            processResponses: [
                [
                    segment("speaker-a", start: 0, end: 10),
                ],
                [
                    segment("speaker-b", start: 2, end: 4),
                    segment("speaker-a", start: 0, end: 2),
                ],
            ],
            finishResponse: [
                segment("speaker-c", start: 4, end: 5),
                segment("speaker-b", start: 2, end: 4),
                segment("speaker-a", start: 0, end: 2),
            ]
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)

        try await useCase.start(preEnrolled: [voiceprint("Alice")])
        let firstSnapshot = try await useCase.ingest(
            samples: [0.1, 0.2],
            sourceSampleRate: 48_000
        )
        let secondSnapshot = try await useCase.ingest(
            samples: [0.3],
            sourceSampleRate: 16_000
        )
        let finalSnapshot = try await useCase.finish()

        #expect(firstSnapshot == [
            segment("speaker-a", start: 0, end: 10),
        ])
        #expect(secondSnapshot == [
            segment("speaker-a", start: 0, end: 2),
            segment("speaker-b", start: 2, end: 4),
        ])
        #expect(finalSnapshot == [
            segment("speaker-a", start: 0, end: 2),
            segment("speaker-b", start: 2, end: 4),
            segment("speaker-c", start: 4, end: 5),
        ])
        #expect(await useCase.currentSegments == finalSnapshot)

        let providerSnapshot = await provider.snapshot()
        #expect(providerSnapshot.startPreEnrolledCounts == [1])
        #expect(providerSnapshot.processCalls == [
            MockProcessCall(sampleCount: 2, sourceSampleRate: 48_000),
            MockProcessCall(sampleCount: 1, sourceSampleRate: 16_000),
        ])
        #expect(providerSnapshot.finishCallCount == 1)
    }

    @Test("새 스냅샷은 이전 tentative 세그먼트를 누적하지 않는다")
    func replacementDropsStaleTentativeSegments() async throws {
        let provider = MockStreamingSpeakerDiarizationProvider(
            processResponses: [
                [
                    segment("speaker-a", start: 0, end: 10),
                ],
                [
                    segment("speaker-a", start: 2, end: 3),
                    segment("speaker-b", start: 3, end: 4),
                ],
            ]
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)

        try await useCase.start(preEnrolled: [])
        _ = try await useCase.ingest(samples: [0.1], sourceSampleRate: 16_000)
        let secondSnapshot = try await useCase.ingest(
            samples: [0.2],
            sourceSampleRate: 16_000
        )

        #expect(secondSnapshot == [
            segment("speaker-a", start: 2, end: 3),
            segment("speaker-b", start: 3, end: 4),
        ])
    }

    @Test("빈 입력과 빈 provider 반환은 빈 스냅샷으로 처리한다")
    func handlesEmptyInputAndEmptyProviderResponses() async throws {
        let provider = MockStreamingSpeakerDiarizationProvider(
            processResponses: [[], []],
            finishResponse: []
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)

        try await useCase.start(preEnrolled: [])
        let emptyInputSnapshot = try await useCase.ingest(
            samples: [],
            sourceSampleRate: 16_000
        )
        let emptyResponseSnapshot = try await useCase.ingest(
            samples: [0.1],
            sourceSampleRate: 16_000
        )
        let finalSnapshot = try await useCase.finish()

        #expect(emptyInputSnapshot.isEmpty)
        #expect(emptyResponseSnapshot.isEmpty)
        #expect(finalSnapshot.isEmpty)
        #expect(await useCase.currentSegments.isEmpty)

        let providerSnapshot = await provider.snapshot()
        #expect(providerSnapshot.processCalls == [
            MockProcessCall(sampleCount: 0, sourceSampleRate: 16_000),
            MockProcessCall(sampleCount: 1, sourceSampleRate: 16_000),
        ])
    }

    @Test("start는 기존 누적 세그먼트를 초기화한다")
    func startClearsAccumulatedSegments() async throws {
        let provider = MockStreamingSpeakerDiarizationProvider(
            processResponses: [
                [segment("speaker-a", start: 1, end: 2)],
            ]
        )
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)

        try await useCase.start(preEnrolled: [])
        let snapshot = try await useCase.ingest(
            samples: [0.1],
            sourceSampleRate: 16_000
        )
        #expect(!snapshot.isEmpty)

        try await useCase.start(preEnrolled: [])

        #expect(await useCase.currentSegments.isEmpty)
        let providerSnapshot = await provider.snapshot()
        #expect(providerSnapshot.startPreEnrolledCounts == [0, 0])
    }

    @Test("provider start 실패는 그대로 전파한다")
    func propagatesStartFailure() async {
        let provider = MockStreamingSpeakerDiarizationProvider(failure: .start)
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)

        await #expect(throws: MockProviderError.failed) {
            try await useCase.start(preEnrolled: [])
        }
    }

    @Test("provider process 실패는 그대로 전파한다")
    func propagatesProcessFailure() async throws {
        let provider = MockStreamingSpeakerDiarizationProvider(failure: .process)
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)

        try await useCase.start(preEnrolled: [])
        await #expect(throws: MockProviderError.failed) {
            try await useCase.ingest(samples: [0.1], sourceSampleRate: 16_000)
        }
    }

    @Test("provider finish 실패는 그대로 전파한다")
    func propagatesFinishFailure() async throws {
        let provider = MockStreamingSpeakerDiarizationProvider(failure: .finish)
        let useCase = LiveSpeakerAssignmentUseCase(provider: provider)

        try await useCase.start(preEnrolled: [])
        await #expect(throws: MockProviderError.failed) {
            try await useCase.finish()
        }
    }
}

private actor MockStreamingSpeakerDiarizationProvider: StreamingSpeakerDiarizationProvider {
    private var processResponses: [[DiarizedSpeakerSegment]]
    private let finishResponse: [DiarizedSpeakerSegment]
    private let failure: MockProviderFailure?
    private var startPreEnrolledCounts: [Int] = []
    private var processCalls: [MockProcessCall] = []
    private var finishCallCount = 0

    init(
        processResponses: [[DiarizedSpeakerSegment]] = [],
        finishResponse: [DiarizedSpeakerSegment] = [],
        failure: MockProviderFailure? = nil
    ) {
        self.processResponses = processResponses
        self.finishResponse = finishResponse
        self.failure = failure
    }

    func start(preEnrolled: [Voiceprint]) async throws {
        startPreEnrolledCounts.append(preEnrolled.count)
        if failure == .start {
            throw MockProviderError.failed
        }
    }

    func process(
        samples: [Float],
        sourceSampleRate: Double
    ) async throws -> [DiarizedSpeakerSegment] {
        processCalls.append(MockProcessCall(
            sampleCount: samples.count,
            sourceSampleRate: sourceSampleRate
        ))
        if failure == .process {
            throw MockProviderError.failed
        }
        guard !processResponses.isEmpty else {
            return []
        }
        return processResponses.removeFirst()
    }

    func finish() async throws -> [DiarizedSpeakerSegment] {
        finishCallCount += 1
        if failure == .finish {
            throw MockProviderError.failed
        }
        return finishResponse
    }

    func snapshot() -> MockProviderSnapshot {
        MockProviderSnapshot(
            startPreEnrolledCounts: startPreEnrolledCounts,
            processCalls: processCalls,
            finishCallCount: finishCallCount
        )
    }
}

private struct MockProviderSnapshot: Equatable, Sendable {
    let startPreEnrolledCounts: [Int]
    let processCalls: [MockProcessCall]
    let finishCallCount: Int
}

private struct MockProcessCall: Equatable, Sendable {
    let sampleCount: Int
    let sourceSampleRate: Double
}

private enum MockProviderFailure: Equatable, Sendable {
    case start
    case process
    case finish
}

private enum MockProviderError: Error, Equatable, Sendable {
    case failed
}

private func segment(
    _ speakerId: String,
    start: Double,
    end: Double
) -> DiarizedSpeakerSegment {
    DiarizedSpeakerSegment(
        speakerId: speakerId,
        startSeconds: start,
        endSeconds: end
    )
}

private func voiceprint(_ displayName: String) -> Voiceprint {
    Voiceprint(
        displayName: displayName,
        embedding: [1, 0],
        embeddingModelID: "test-speaker-embedding"
    )
}
