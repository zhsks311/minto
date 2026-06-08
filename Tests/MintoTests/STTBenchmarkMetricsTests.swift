import Foundation
import Testing

@Suite("STT Benchmark Metrics")
struct STTBenchmarkMetricsTests {
    @Test("run metric encodes stable common schema keys")
    func runMetricEncodesStableCommonSchemaKeys() throws {
        let metric = STTBenchmarkRunMetric(
            benchmarkKind: "unit",
            engineID: "whisper_fast",
            engineLabel: "WhisperKit turbo",
            modelID: "openai_whisper-large-v3-v20240930_turbo",
            sampleID: "sample",
            supportsPreview: true,
            benchmarkSeconds: 10,
            totalUnitCount: 1,
            measuredUnitCount: 1,
            referenceLength: 3,
            hypothesisLength: 2,
            distance: 1,
            microCER: 1.0 / 3.0,
            macroCER: 1.0 / 3.0,
            globalDistance: nil,
            globalReferenceLength: nil,
            globalCER: nil,
            emptyFinalCount: 0,
            audioSeconds: 10,
            elapsedSeconds: 2,
            rtf: 0.2,
            segments: [
                STTBenchmarkSegmentMetric(
                    index: 0,
                    startSeconds: 0,
                    endSeconds: 10,
                    durationSeconds: 10,
                    reference: "가나다",
                    hypothesis: "가나",
                    referenceLength: 3,
                    hypothesisLength: 2,
                    distance: 1,
                    cer: 1.0 / 3.0,
                    elapsedSeconds: 2,
                    rtf: 0.2,
                    empty: false
                )
            ]
        )

        let data = try JSONEncoder().encode(metric)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["schema_version"] as? Int == 1)
        #expect(object["benchmark_kind"] as? String == "unit")
        #expect(object["engine_id"] as? String == "whisper_fast")
        #expect(object["model_id"] as? String == "openai_whisper-large-v3-v20240930_turbo")
        #expect(object["sample_id"] as? String == "sample")
        #expect(object["supports_preview"] as? Bool == true)
        #expect(object.keys.contains("micro_cer"))
        #expect(object.keys.contains("macro_cer"))
        #expect(object["global_cer"] is NSNull)
        #expect(object["peak_memory_mb"] is NSNull)
        #expect(object["streaming"] is NSNull)
        #expect((object["segments"] as? [[String: Any]])?.first?["reference_length"] as? Int == 3)
    }

    @Test("text metrics use the same normalized character contract as CER tests")
    func textMetricsUseNormalizedCharacterContract() {
        #expect(STTBenchmarkTextMetrics.normalizedLength("가 나,다.") == 3)
    }

    @Test("peak resident memory is available on macOS benchmark runs")
    func peakResidentMemoryIsAvailable() throws {
        let memoryMB = try #require(STTBenchmarkProcessMetrics.peakResidentMemoryMB())

        #expect(memoryMB > 0)
    }
}
