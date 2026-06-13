import SwiftUI

public struct AudioLevelMeterView: View {
    private let audioLevel: Float
    private let barCount: Int

    public init(audioLevel: Float, barCount: Int = 16) {
        self.audioLevel = audioLevel
        self.barCount = barCount
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                let threshold = Float(index + 1) / Float(barCount)
                let active = audioLevel >= threshold
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(active ? levelBarColor(at: Float(index) / Float(barCount)) : Color.secondary.opacity(0.12))
                    .frame(width: 3, height: active ? 12 : 7)
                    .animation(.easeOut(duration: 0.04), value: active)
            }
        }
    }

    private func levelBarColor(at position: Float) -> Color {
        if position < 0.6 { return .green }
        if position < 0.85 { return .yellow }
        return .red
    }
}
