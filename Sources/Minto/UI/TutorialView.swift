import SwiftUI

/// 튜토리얼이 가리키는 실제 UI 요소. 버튼에 `.tutorialTarget(_:)`로 표시하면
/// 오버레이가 그 위치에 링·구멍을 그린다.
enum TutorialTarget: Hashable {
    case newMeeting
    case search
    case glossary
    case fileImport
    case help
    case exportDetail
}

/// 각 타깃 버튼이 자기 bounds를 오버레이로 올려보내는 PreferenceKey.
struct TutorialAnchorKey: PreferenceKey {
    static let defaultValue: [TutorialTarget: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [TutorialTarget: Anchor<CGRect>],
        nextValue: () -> [TutorialTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// 이 뷰를 튜토리얼 타깃으로 등록한다(위치를 오버레이가 추적).
    func tutorialTarget(_ id: TutorialTarget) -> some View {
        anchorPreference(key: TutorialAnchorKey.self, value: .bounds) { [id: $0] }
    }

    /// 주어진 모양만큼 구멍을 뚫는다(딤 배경에 스포트라이트 구멍).
    fileprivate func punchOut<M: View>(@ViewBuilder _ shape: () -> M) -> some View {
        mask {
            Rectangle()
                .overlay { shape().blendMode(.destinationOut) }
                .compositingGroup()
        }
    }
}

/// 라이브러리 화면 위에 그리는 코치마크 오버레이.
/// 윈도우 내 버튼은 실제 위치에 링을, 메뉴바 녹음 버튼은 캡처 이미지에 동그라미를 보여준다.
struct TutorialCoachView: View {
    /// MeetingLibraryView가 anchor를 좌표로 풀어 넘긴 실제 버튼 사각형.
    let targets: [TutorialTarget: CGRect]
    var onClose: () -> Void

    @State private var step = 0

    /// 메뉴 팝오버 재현에서 동그라미 칠 행. 메뉴바·설정은 별도 윈도우라 라이브 링이 안 되므로 재현으로 보여준다.
    private enum MenuHighlight {
        case record
        case settings
    }

    private struct Step {
        let title: String
        let body: String
        /// 가리킬 윈도우 내 버튼. nil이면 가운데 카드로 표시.
        let target: TutorialTarget?
        /// 메뉴 팝오버를 재현해 보여줄 때 강조할 행. nil이면 재현 안 함.
        let menuHighlight: MenuHighlight?

        init(title: String, body: String, target: TutorialTarget? = nil, menuHighlight: MenuHighlight? = nil) {
            self.title = title
            self.body = body
            self.target = target
            self.menuHighlight = menuHighlight
        }
    }

    private let steps: [Step] = [
        Step(
            title: "새 회의 시작",
            body: "여기서 새 회의를 시작해요. 회의 주제와 용어집을 먼저 정해 두면 전사와 교정이 더 정확해져요.",
            target: .newMeeting
        ),
        Step(
            title: "녹음은 메뉴 막대에서",
            body: "화면 맨 위 메뉴 막대의 Minto 아이콘(􀙫)을 누르면 이런 메뉴가 열려요. 여기서 녹음을 시작·종료해요.",
            menuHighlight: .record
        ),
        Step(
            title: "회의 검색",
            body: "저장한 회의를 키워드로 찾아요. 결과 위의 ‘AI 답변’으로 질문하면 근거가 된 회의·구간도 함께 보여줘요.",
            target: .search
        ),
        Step(
            title: "요약 확인과 내보내기",
            body: "회의를 열면 이 자리에서 다시 요약하거나 Markdown·Confluence로 내보낼 수 있어요.",
            target: .exportDetail
        ),
        Step(
            title: "용어집과 파일 가져오기",
            body: "용어집으로 고유명사를 일관되게 맞춰요. 바로 옆 ‘파일 가져오기’로 기존 녹음을 회의록으로 만들 수 있어요.",
            target: .glossary
        ),
        Step(
            title: "설정에서 켜고 골라요",
            body: "메뉴의 ‘설정…’(또는 ⌘,)에서 교정·요약·검색 답변을 켜고, AI 연결(로컬 모델 또는 클라우드 provider·API 키)과 음성 엔진을 골라요. 클라우드로 보낼지 기기 안에서 처리할지도 여기서 정해요.",
            menuHighlight: .settings
        ),
        Step(
            title: "언제든 다시 보기",
            body: "사용법이 헷갈리면 여기 ‘사용법’ 버튼으로 이 안내를 다시 열 수 있어요.",
            target: .help
        )
    ]

    private var isLastStep: Bool { step == steps.count - 1 }

    /// 현재 단계가 가리키는 실제 버튼 사각형(있을 때만).
    private var currentRect: CGRect? {
        guard let target = steps[step].target else { return nil }
        return targets[target]
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .topLeading) {
                dimmedBackground
                if let rect = currentRect {
                    ring(around: rect)
                    callout
                        .frame(width: cardWidth, alignment: .leading)
                        .offset(
                            x: clampedX(for: rect, in: proxy.size),
                            y: rect.maxY + 14
                        )
                } else {
                    callout
                        .frame(width: cardWidth, alignment: .leading)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
        }
        .ignoresSafeArea()
    }

    private let cardWidth: CGFloat = 330

    private func clampedX(for rect: CGRect, in size: CGSize) -> CGFloat {
        let ideal = rect.midX - cardWidth / 2
        return min(max(ideal, 16), size.width - cardWidth - 16)
    }

    private var dimmedBackground: some View {
        Rectangle()
            .fill(Color.black.opacity(0.55))
            .ignoresSafeArea()
            // 밑 화면 조작을 막되, 바깥 탭으로 실수로 닫히지 않게 빈 제스처로 흡수.
            .contentShape(Rectangle())
            .onTapGesture {}
            .punchOut {
                if let rect = currentRect {
                    RoundedRectangle(cornerRadius: 9)
                        .frame(width: rect.width + 12, height: rect.height + 12)
                        .position(x: rect.midX, y: rect.midY)
                }
            }
    }

    private func ring(around rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: 9)
            .stroke(Color.accentColor, lineWidth: 2.5)
            .frame(width: rect.width + 12, height: rect.height + 12)
            .position(x: rect.midX, y: rect.midY)
    }

    private var callout: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(steps[step].title)
                .font(.system(size: 16, weight: .bold))
            Text(steps[step].body)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineSpacing(2)

            if let highlight = steps[step].menuHighlight {
                menuBarMock(highlight: highlight)
            }

            HStack(spacing: 10) {
                stepIndicator
                Spacer()
                Button(isLastStep ? "닫기" : "건너뛰기") { onClose() }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                if step > 0 {
                    Button("이전") { step -= 1 }
                }
                Button(isLastStep ? "시작하기" : "다음") {
                    if isLastStep { onClose() } else { step += 1 }
                }
                .buttonStyle(ProminentActionButtonStyle(horizontalPadding: 16, verticalPadding: 6))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 6)
        )
    }

    /// 실제 메뉴 막대 팝오버를 재현하고 강조 행에 동그라미를 친다.
    /// (MenuBarExtra 팝오버·설정 창은 transient/별도 윈도우라 실제 캡처를 번들하기 어려워 인앱 렌더링으로 보여준다.)
    private func menuBarMock(highlight: MenuHighlight) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            menuRow(icon: "checkmark.circle.fill", iconColor: .green, label: "모델 준비됨", muted: true)
            Divider().padding(.vertical, 3)
            menuRow(icon: "record.circle", iconColor: .accentColor, label: "녹음 시작", highlighted: highlight == .record)
            menuRow(icon: "list.bullet.rectangle", iconColor: .secondary, label: "회의 목록 열기")
            Divider().padding(.vertical, 3)
            menuRow(icon: "gearshape", iconColor: .secondary, label: "설정…", highlighted: highlight == .settings)
        }
        .padding(8)
        .frame(width: 230)
        .background(
            RoundedRectangle(cornerRadius: 9)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color.secondary.opacity(0.22)))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        )
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 2)
    }

    private func menuRow(
        icon: String,
        iconColor: Color,
        label: String,
        highlighted: Bool = false,
        muted: Bool = false
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(iconColor)
                .frame(width: 16)
            Text(label)
                .font(.system(size: 12, weight: highlighted ? .semibold : .regular))
                .foregroundColor(muted ? .secondary : .primary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            highlighted
                ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.12))
                : nil
        )
        .overlay(
            highlighted
                ? RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor, lineWidth: 2)
                : nil
        )
    }

    private var stepIndicator: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { index in
                Circle()
                    .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }
}
