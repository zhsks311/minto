import Foundation

public enum VoiceprintMatching {
    /// Returns 0 for dimension mismatch, empty vectors, zero vectors, or non-finite values.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dot = 0.0
        var aNorm = 0.0
        var bNorm = 0.0
        for index in a.indices {
            let lhs = Double(a[index])
            let rhs = Double(b[index])
            guard lhs.isFinite, rhs.isFinite else { return 0 }
            dot += lhs * rhs
            aNorm += lhs * lhs
            bNorm += rhs * rhs
        }

        guard aNorm > 0, bNorm > 0 else { return 0 }
        return dot / (sqrt(aNorm) * sqrt(bNorm))
    }

    public static func centroids(
        from pairs: [(speakerId: String, embedding: [Float])]
    ) -> [(speakerId: String, centroid: [Float])] {
        let grouped = Dictionary(grouping: pairs) { $0.speakerId }

        return grouped.keys.sorted().compactMap { speakerId in
            guard let speakerPairs = grouped[speakerId] else { return nil }
            let embeddings = speakerPairs.map { $0.embedding }.filter { !$0.isEmpty }
            guard !embeddings.isEmpty else { return nil }

            let dimensions = embeddings[0].count
            guard embeddings.allSatisfy({ $0.count == dimensions }) else { return nil }

            var sums = Array(repeating: 0.0, count: dimensions)
            for embedding in embeddings {
                for index in embedding.indices {
                    let value = Double(embedding[index])
                    guard value.isFinite else { return nil }
                    sums[index] += value
                }
            }

            let count = Double(embeddings.count)
            let averaged = sums.map { $0 / count }
            let norm = sqrt(averaged.reduce(0.0) { $0 + ($1 * $1) })
            guard norm.isFinite, norm > 0 else { return nil }

            return (
                speakerId: speakerId,
                centroid: averaged.map { Float($0 / norm) }
            )
        }
    }

    public static func bestMatch(
        for embedding: [Float],
        among prints: [Voiceprint],
        embeddingModelID: String,
        threshold: Double
    ) -> Voiceprint? {
        var bestPrint: Voiceprint?
        var bestScore = -Double.infinity

        for print in prints {
            guard print.embeddingModelID == embeddingModelID,
                  print.dimensions == embedding.count,
                  print.embedding.count == embedding.count else {
                continue
            }

            let score = cosineSimilarity(embedding, print.embedding)
            if score > bestScore {
                bestScore = score
                bestPrint = print
            }
        }

        guard bestScore >= threshold else { return nil }
        return bestPrint
    }

    public static func identifySpeakers(
        labeledCentroids: [(speakerLabel: String, centroid: [Float])],
        among prints: [Voiceprint],
        embeddingModelID: String,
        threshold: Double
    ) -> [String: Voiceprint] {
        var candidates: [(speakerLabel: String, voiceprint: Voiceprint, score: Double)] = []

        for labeledCentroid in labeledCentroids {
            for voiceprint in prints {
                guard voiceprint.embeddingModelID == embeddingModelID,
                      voiceprint.dimensions == labeledCentroid.centroid.count,
                      voiceprint.embedding.count == labeledCentroid.centroid.count else {
                    continue
                }

                let score = cosineSimilarity(labeledCentroid.centroid, voiceprint.embedding)
                guard score >= threshold else {
                    continue
                }

                candidates.append((
                    speakerLabel: labeledCentroid.speakerLabel,
                    voiceprint: voiceprint,
                    score: score
                ))
            }
        }

        candidates.sort { lhs, rhs in
            if lhs.score != rhs.score {
                return lhs.score > rhs.score
            }
            if lhs.speakerLabel != rhs.speakerLabel {
                return lhs.speakerLabel < rhs.speakerLabel
            }
            return lhs.voiceprint.id.uuidString < rhs.voiceprint.id.uuidString
        }

        var result: [String: Voiceprint] = [:]
        var assignedLabels = Set<String>()
        var assignedPrintIDs = Set<UUID>()

        for candidate in candidates {
            guard !assignedLabels.contains(candidate.speakerLabel),
                  !assignedPrintIDs.contains(candidate.voiceprint.id) else {
                continue
            }

            result[candidate.speakerLabel] = candidate.voiceprint
            assignedLabels.insert(candidate.speakerLabel)
            assignedPrintIDs.insert(candidate.voiceprint.id)
        }

        return result
    }
}
