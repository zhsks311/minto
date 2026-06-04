import SwiftUI

/// "녹음 시작" 시 뜨는 회의 시작 시트.
/// 주제·용어집을 입력받아 그 회의 세션의 교정 맥락으로 쓴다. 비우고 시작해도 된다.
public struct MeetingSetupView: View {
    @State private var topic: String = ""
    @State private var glossary: String = ""
    @State private var document: String = ""
    @State private var showGlossary = false
    @State private var showDocument = false

    private let onStart: (String, String, String) -> Void
    private let onCancel: () -> Void

    public init(
        onStart: @escaping (String, String, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onStart = onStart
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("회의 시작")
                    .font(.title3.weight(.bold))
                Text("주제만 적어도 충분합니다. 필요한 정보는 선택해서 더하세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("회의 주제")
                    .font(.subheadline.weight(.medium))
                TextField("예: 2분기 제품 리뷰", text: $topic)
                    .textFieldStyle(.roundedBorder)
            }

            optionalEditor(
                title: "용어집",
                subtitle: "고유명사·전문용어를 한 줄에 하나씩 입력하세요",
                text: $glossary,
                isExpanded: $showGlossary,
                height: 130
            )

            optionalEditor(
                title: "회의 자료·안건",
                subtitle: "안건·문서를 붙여넣으면 전사와 요약에 참고합니다",
                text: $document,
                isExpanded: $showDocument,
                height: 110
            )

            HStack {
                Spacer()
                Button("취소") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("녹음 시작") { onStart(topic, glossary, document) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func optionalEditor(
        title: String,
        subtitle: String,
        text: Binding<String>,
        isExpanded: Binding<Bool>,
        height: CGFloat
    ) -> some View {
        DisclosureGroup(isExpanded: isExpanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                TextEditor(text: text)
                    .font(.body)
                    .frame(height: height)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }
            .padding(.top, 6)
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text("선택")
                    .font(.caption2.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
            }
        }
    }
}
