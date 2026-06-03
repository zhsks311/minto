import SwiftUI
import AppKit

/// 종료 후 요약 창의 상태. 윈도우 매니저가 보유·변경하고 뷰가 관찰한다(로딩→결과 비동기 전환).
@MainActor
public final class MeetingSummaryModel: ObservableObject {
    public enum State {
        case loading
        case result(String)
        case failed
    }
    @Published public var state: State = .loading
    public init() {}
}

/// 회의 종료 후 최종 요약을 보여주는 뷰. `MeetingSetupView`와 동일한 톤(여백·타이틀·버튼 스타일).
public struct MeetingSummaryView: View {
    @ObservedObject private var model: MeetingSummaryModel
    private let onClose: () -> Void

    public init(model: MeetingSummaryModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("회의 요약")
                .font(.title3.weight(.bold))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                if case .result(let text) = model.state {
                    Button("복사") { copyToPasteboard(text) }
                }
                Spacer()
                Button("닫기") { onClose() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 480, height: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack(spacing: 10) {
                ProgressView()
                Text("회의 요약을 생성하는 중...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        case .result(let text):
            ScrollView {
                Text(text)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
            )
        case .failed:
            VStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundColor(.secondary)
                Text("요약을 생성하지 못했습니다.")
                    .font(.subheadline)
                Text("교정/요약 provider가 선택·로그인되어 있는지 확인하거나 잠시 후 다시 시도하세요.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
