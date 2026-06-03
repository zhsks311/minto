import SwiftUI

/// "녹음 시작" 시 뜨는 회의 시작 시트.
/// 주제·용어집을 입력받아 그 회의 세션의 교정 맥락으로 쓴다. 비우고 시작해도 된다.
public struct MeetingSetupView: View {
    @State private var topic: String = ""
    @State private var glossary: String = ""

    private let onStart: (String, String) -> Void
    private let onCancel: () -> Void

    public init(
        onStart: @escaping (String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onStart = onStart
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("회의 시작")
                .font(.title3.weight(.bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("회의 주제")
                    .font(.subheadline.weight(.medium))
                TextField("예: 탕수육 부먹 vs 찍먹 끝장 토론회", text: $topic)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("용어집")
                    .font(.subheadline.weight(.medium))
                Text("고유명사·전문용어를 한 줄에 하나씩 입력하세요")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextEditor(text: $glossary)
                    .font(.body)
                    .frame(height: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack {
                Spacer()
                Button("취소") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("시작") { onStart(topic, glossary) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}
