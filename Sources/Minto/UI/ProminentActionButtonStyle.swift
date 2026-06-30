import SwiftUI

/// 비활성(non-key) 윈도우에서 `.borderedProminent`가 강조 배경을 지우면서 흰 라벨만 남겨
/// 버튼이 통째로 사라져 보이는 문제를 피하기 위해, 윈도우 키 상태와 무관하게
/// 항상 같은 배경을 직접 그리는 강조 버튼 스타일.
struct ProminentActionButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var horizontalPadding: CGFloat = 12
    var verticalPadding: CGFloat = 6

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(.white)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(Capsule().fill(isEnabled ? MintoDesignTokens.brandTeal : Color.gray.opacity(0.45)))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}
