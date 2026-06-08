import Foundation
import Darwin

struct STTBenchmarkRunMetric: Encodable {
    let schemaVersion: Int
    let benchmarkKind: String
    let engineID: String
    let engineLabel: String
    let modelID: String
    let sampleID: String
    let supportsPreview: Bool
    let benchmarkSeconds: Double
    let totalUnitCount: Int
    let measuredUnitCount: Int
    let referenceLength: Int
    let hypothesisLength: Int
    let distance: Int
    let microCER: Double
    let macroCER: Double
    let globalDistance: Int?
    let globalReferenceLength: Int?
    let globalCER: Double?
    let fullReferenceGlobalDistance: Int?
    let fullReferenceGlobalReferenceLength: Int?
    let fullReferenceGlobalCER: Double?
    let emptyFinalCount: Int
    let falsePositiveTranscriptCount: Int
    let falsePositiveTranscriptChars: Int
    let audioSeconds: Double
    let elapsedSeconds: Double
    let rtf: Double
    let aggregateRTF: Double
    let peakMemoryMB: Double?
    let metadata: [String: String]
    let streaming: STTBenchmarkStreamingSummary?
    let segments: [STTBenchmarkSegmentMetric]
    let previewSegments: [STTBenchmarkPreviewSegmentMetric]

    init(
        schemaVersion: Int = 1,
        benchmarkKind: String,
        engineID: String,
        engineLabel: String,
        modelID: String,
        sampleID: String,
        supportsPreview: Bool,
        benchmarkSeconds: Double,
        totalUnitCount: Int,
        measuredUnitCount: Int,
        referenceLength: Int,
        hypothesisLength: Int,
        distance: Int,
        microCER: Double,
        macroCER: Double,
        globalDistance: Int?,
        globalReferenceLength: Int?,
        globalCER: Double?,
        fullReferenceGlobalDistance: Int? = nil,
        fullReferenceGlobalReferenceLength: Int? = nil,
        fullReferenceGlobalCER: Double? = nil,
        emptyFinalCount: Int,
        falsePositiveTranscriptCount: Int = 0,
        falsePositiveTranscriptChars: Int = 0,
        audioSeconds: Double,
        elapsedSeconds: Double,
        rtf: Double,
        aggregateRTF: Double? = nil,
        peakMemoryMB: Double? = nil,
        metadata: [String: String] = [:],
        streaming: STTBenchmarkStreamingSummary? = nil,
        segments: [STTBenchmarkSegmentMetric],
        previewSegments: [STTBenchmarkPreviewSegmentMetric] = []
    ) {
        self.schemaVersion = schemaVersion
        self.benchmarkKind = benchmarkKind
        self.engineID = engineID
        self.engineLabel = engineLabel
        self.modelID = modelID
        self.sampleID = sampleID
        self.supportsPreview = supportsPreview
        self.benchmarkSeconds = benchmarkSeconds
        self.totalUnitCount = totalUnitCount
        self.measuredUnitCount = measuredUnitCount
        self.referenceLength = referenceLength
        self.hypothesisLength = hypothesisLength
        self.distance = distance
        self.microCER = microCER
        self.macroCER = macroCER
        self.globalDistance = globalDistance
        self.globalReferenceLength = globalReferenceLength
        self.globalCER = globalCER
        self.fullReferenceGlobalDistance = fullReferenceGlobalDistance
        self.fullReferenceGlobalReferenceLength = fullReferenceGlobalReferenceLength
        self.fullReferenceGlobalCER = fullReferenceGlobalCER
        self.emptyFinalCount = emptyFinalCount
        self.falsePositiveTranscriptCount = falsePositiveTranscriptCount
        self.falsePositiveTranscriptChars = falsePositiveTranscriptChars
        self.audioSeconds = audioSeconds
        self.elapsedSeconds = elapsedSeconds
        self.rtf = rtf
        self.aggregateRTF = aggregateRTF ?? rtf
        self.peakMemoryMB = peakMemoryMB
        self.metadata = metadata
        self.streaming = streaming
        self.segments = segments
        self.previewSegments = previewSegments
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case benchmarkKind = "benchmark_kind"
        case engineID = "engine_id"
        case engineLabel = "engine_label"
        case modelID = "model_id"
        case sampleID = "sample_id"
        case supportsPreview = "supports_preview"
        case benchmarkSeconds = "benchmark_seconds"
        case totalUnitCount = "total_unit_count"
        case measuredUnitCount = "measured_unit_count"
        case referenceLength = "reference_length"
        case hypothesisLength = "hypothesis_length"
        case distance
        case microCER = "micro_cer"
        case macroCER = "macro_cer"
        case globalDistance = "global_distance"
        case globalReferenceLength = "global_reference_length"
        case globalCER = "global_cer"
        case fullReferenceGlobalDistance = "full_reference_global_distance"
        case fullReferenceGlobalReferenceLength = "full_reference_global_reference_length"
        case fullReferenceGlobalCER = "full_reference_global_cer"
        case emptyFinalCount = "empty_final_count"
        case falsePositiveTranscriptCount = "false_positive_transcript_count"
        case falsePositiveTranscriptChars = "false_positive_transcript_chars"
        case audioSeconds = "audio_seconds"
        case elapsedSeconds = "elapsed_seconds"
        case rtf
        case aggregateRTF = "aggregate_rtf"
        case peakMemoryMB = "peak_memory_mb"
        case metadata
        case streaming
        case segments
        case previewSegments = "preview_segments"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(benchmarkKind, forKey: .benchmarkKind)
        try container.encode(engineID, forKey: .engineID)
        try container.encode(engineLabel, forKey: .engineLabel)
        try container.encode(modelID, forKey: .modelID)
        try container.encode(sampleID, forKey: .sampleID)
        try container.encode(supportsPreview, forKey: .supportsPreview)
        try container.encode(benchmarkSeconds, forKey: .benchmarkSeconds)
        try container.encode(totalUnitCount, forKey: .totalUnitCount)
        try container.encode(measuredUnitCount, forKey: .measuredUnitCount)
        try container.encode(referenceLength, forKey: .referenceLength)
        try container.encode(hypothesisLength, forKey: .hypothesisLength)
        try container.encode(distance, forKey: .distance)
        try container.encode(microCER, forKey: .microCER)
        try container.encode(macroCER, forKey: .macroCER)
        try container.encodeOptional(globalDistance, forKey: .globalDistance)
        try container.encodeOptional(globalReferenceLength, forKey: .globalReferenceLength)
        try container.encodeOptional(globalCER, forKey: .globalCER)
        try container.encodeOptional(fullReferenceGlobalDistance, forKey: .fullReferenceGlobalDistance)
        try container.encodeOptional(fullReferenceGlobalReferenceLength, forKey: .fullReferenceGlobalReferenceLength)
        try container.encodeOptional(fullReferenceGlobalCER, forKey: .fullReferenceGlobalCER)
        try container.encode(emptyFinalCount, forKey: .emptyFinalCount)
        try container.encode(falsePositiveTranscriptCount, forKey: .falsePositiveTranscriptCount)
        try container.encode(falsePositiveTranscriptChars, forKey: .falsePositiveTranscriptChars)
        try container.encode(audioSeconds, forKey: .audioSeconds)
        try container.encode(elapsedSeconds, forKey: .elapsedSeconds)
        try container.encode(rtf, forKey: .rtf)
        try container.encode(aggregateRTF, forKey: .aggregateRTF)
        try container.encodeOptional(peakMemoryMB, forKey: .peakMemoryMB)
        try container.encode(metadata, forKey: .metadata)
        try container.encodeOptional(streaming, forKey: .streaming)
        try container.encode(segments, forKey: .segments)
        try container.encode(previewSegments, forKey: .previewSegments)
    }
}

struct STTBenchmarkSegmentMetric: Encodable {
    let index: Int
    let startSeconds: Double
    let endSeconds: Double
    let durationSeconds: Double
    let reference: String
    let hypothesis: String
    let referenceLength: Int
    let hypothesisLength: Int
    let distance: Int
    let cer: Double
    let elapsedSeconds: Double
    let rtf: Double
    let empty: Bool

    enum CodingKeys: String, CodingKey {
        case index
        case startSeconds = "start_seconds"
        case endSeconds = "end_seconds"
        case durationSeconds = "duration_seconds"
        case reference
        case hypothesis
        case referenceLength = "reference_length"
        case hypothesisLength = "hypothesis_length"
        case distance
        case cer
        case elapsedSeconds = "elapsed_seconds"
        case rtf
        case empty
    }
}

struct STTBenchmarkPreviewSegmentMetric: Encodable {
    let index: Int
    let audioSeconds: Double
    let contextStartSeconds: Double
    let contextEndSeconds: Double
    let text: String
    let rtf: Double
    let revisionDistance: Int?

    enum CodingKeys: String, CodingKey {
        case index
        case audioSeconds = "audio_seconds"
        case contextStartSeconds = "context_start_seconds"
        case contextEndSeconds = "context_end_seconds"
        case text
        case rtf
        case revisionDistance = "revision_distance"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(index, forKey: .index)
        try container.encode(audioSeconds, forKey: .audioSeconds)
        try container.encode(contextStartSeconds, forKey: .contextStartSeconds)
        try container.encode(contextEndSeconds, forKey: .contextEndSeconds)
        try container.encode(text, forKey: .text)
        try container.encode(rtf, forKey: .rtf)
        try container.encodeOptional(revisionDistance, forKey: .revisionDistance)
    }
}

struct STTBenchmarkStreamingSummary: Encodable {
    let firstPartialLatencySeconds: Double?
    let partialRevisionCount: Int
    let finalLatencySeconds: Double?
    let finalCER: Double
    let unstablePartialRatio: Double
    let previewEvents: Int
    let previewNonEmpty: Int
    let finalEvents: Int

    enum CodingKeys: String, CodingKey {
        case firstPartialLatencySeconds = "first_partial_latency_seconds"
        case partialRevisionCount = "partial_revision_count"
        case finalLatencySeconds = "final_latency_seconds"
        case finalCER = "final_cer"
        case unstablePartialRatio = "unstable_partial_ratio"
        case previewEvents = "preview_events"
        case previewNonEmpty = "preview_non_empty"
        case finalEvents = "final_events"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeOptional(firstPartialLatencySeconds, forKey: .firstPartialLatencySeconds)
        try container.encode(partialRevisionCount, forKey: .partialRevisionCount)
        try container.encodeOptional(finalLatencySeconds, forKey: .finalLatencySeconds)
        try container.encode(finalCER, forKey: .finalCER)
        try container.encode(unstablePartialRatio, forKey: .unstablePartialRatio)
        try container.encode(previewEvents, forKey: .previewEvents)
        try container.encode(previewNonEmpty, forKey: .previewNonEmpty)
        try container.encode(finalEvents, forKey: .finalEvents)
    }
}

enum STTBenchmarkTextMetrics {
    static func normalizedLength(_ text: String) -> Int {
        text.filter { !$0.isWhitespace && !$0.isPunctuation }.count
    }

    static func macroCER(_ segments: [STTBenchmarkSegmentMetric]) -> Double {
        guard !segments.isEmpty else { return 0 }
        return segments.reduce(0) { $0 + $1.cer } / Double(segments.count)
    }

    static func hypothesisLength(_ segments: [STTBenchmarkSegmentMetric]) -> Int {
        segments.reduce(0) { $0 + $1.hypothesisLength }
    }
}

enum STTBenchmarkProcessMetrics {
    static func peakResidentMemoryMB() -> Double? {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return nil }

        // Darwin reports ru_maxrss in bytes. Linux reports kilobytes, but these
        // benchmark tests target the local macOS app runtime.
        return Double(usage.ru_maxrss) / 1_048_576.0
    }
}

private extension KeyedEncodingContainer {
    mutating func encodeOptional<T: Encodable>(_ value: T?, forKey key: Key) throws {
        if let value {
            try encode(value, forKey: key)
        } else {
            try encodeNil(forKey: key)
        }
    }
}
