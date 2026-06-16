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
}
