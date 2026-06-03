import SwiftUI
import AppKit

private extension Color {
    /// #RRGGBB hex → Color.
    init(hex: String) {
        let s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(.sRGB,
                  red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255,
                  opacity: 1)
    }
}

/// 결과 화면 색 토큰(Lilys식 다크 리포트).
private enum RC {
    static let bg = Color(hex: "#101312")
    static let card = Color(hex: "#171B19")
    static let cardBorder = Color(hex: "#2D342F")
    static let subtleBorder = Color(hex: "#252B28")
    static let heading = Color(hex: "#F4F1EA")
    static let kicker = Color(hex: "#7F8A83")
    static let meta = Color(hex: "#A2ADA6")
    static let cardTitle = Color(hex: "#E7EEE8")
    static let body = Color(hex: "#C7D0C9")
    static let bodyAlt = Color(hex: "#DDE5DF")
    static let time = Color(hex: "#9AD7B2")
    static let bullet = Color(hex: "#7F8A83")
    static let accent = Color(hex: "#E8F0EA")
    static let accentText = Color(hex: "#111513")
    static let tabBg = Color(hex: "#151917")
    static let tabInactiveText = Color(hex: "#8D9891")
    static let secondaryBtn = Color(hex: "#1A1F1C")
    static let secondaryBtnBorder = Color(hex: "#303832")
    static let secondaryBtnText = Color(hex: "#D6DDD7")
}

/// 결과 화면 데이터(계층형 요약 + 시점 전사 + 메타).
public struct MeetingResult: Sendable {
    public let title: String
    public let metaText: String
    public let summary: MeetingSummary
    public let transcript: [TranscriptLine]

    public struct TranscriptLine: Sendable, Identifiable {
        public let id = UUID()
        public let time: String
        public let text: String
        public init(time: String, text: String) { self.time = time; self.text = text }
    }

    public init(title: String, metaText: String, summary: MeetingSummary, transcript: [TranscriptLine]) {
        self.title = title; self.metaText = metaText; self.summary = summary; self.transcript = transcript
    }
}

@MainActor
public final class MeetingSummaryModel: ObservableObject {
    public enum State { case loading, result(MeetingResult), failed }
    @Published public var state: State = .loading
    public init() {}
}

/// 회의 종료 후 결과 화면(Lilys "자세한 리포트" 스타일: 리드 Q&A → 목차 → 번호 섹션(시점·중첩 불릿) → 키워드).
public struct MeetingSummaryView: View {
    @ObservedObject private var model: MeetingSummaryModel
    private let onClose: () -> Void
    @State private var tab: Tab = .summary

    private enum Tab { case summary, transcript }

    public init(model: MeetingSummaryModel, onClose: @escaping () -> Void) {
        self.model = model
        self.onClose = onClose
    }

    public var body: some View {
        ZStack {
            RC.bg.ignoresSafeArea()
            switch model.state {
            case .loading: loadingView
            case .failed: failedView
            case .result(let r): resultView(r)
            }
        }
        // 고정 크기 대신 컨테이너를 채운다(종료 후 창=고정 윈도우, 회의 목록 상세=가변 패널 모두 대응).
        .frame(minWidth: 420, maxWidth: .infinity, minHeight: 480, maxHeight: .infinity)
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            Text("회의 요약을 생성하는 중...").font(.system(size: 13)).foregroundColor(RC.meta)
        }
    }

    private var failedView: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle").foregroundColor(RC.meta)
            Text("요약을 생성하지 못했습니다.").font(.system(size: 14, weight: .semibold)).foregroundColor(RC.body)
            Text("교정/요약 provider가 선택·로그인되어 있는지 확인하세요.")
                .font(.system(size: 11)).foregroundColor(RC.meta).multilineTextAlignment(.center)
            Button("닫기") { onClose() }.padding(.top, 8)
        }
        .padding(24)
    }

    private func resultView(_ r: MeetingResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                header(r)
                tabs
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if tab == .summary { digest(r.summary) } else { transcriptList(r.transcript) }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }

            Divider().overlay(RC.subtleBorder)
            controls(r).padding(.horizontal, 24).padding(.vertical, 14)
        }
    }

    // MARK: - Header / tabs

    private func header(_ r: MeetingResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MEETING REPORT").font(.system(size: 12, weight: .bold)).foregroundColor(RC.kicker)
            Text(r.title).font(.system(size: 25, weight: .bold)).foregroundColor(RC.heading)
                .fixedSize(horizontal: false, vertical: true)
            Text(r.metaText).font(.system(size: 13)).foregroundColor(RC.meta)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tabs: some View {
        HStack(spacing: 6) {
            tabButton("요약", .summary)
            tabButton("전사", .transcript)
        }
        .padding(4).background(RC.tabBg)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(RC.subtleBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func tabButton(_ title: String, _ t: Tab) -> some View {
        let active = tab == t
        // Button으로 구현(VoiceOver 버튼 트레이트 + Space/Return 활성화). onTapGesture는 접근성 미지원.
        return Button { tab = t } label: {
            Text(title)
                .font(.system(size: 13, weight: active ? .heavy : .bold))
                .foregroundColor(active ? RC.accentText : RC.tabInactiveText)
                .frame(maxWidth: .infinity).frame(height: 30)
                .background(active ? RC.accent : RC.tabBg)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }

    // MARK: - Digest (계층형 요약)

    @ViewBuilder
    private func digest(_ s: MeetingSummary) -> some View {
        leadCard(s)
        if s.sections.count > 1 { tableOfContents(s.sections) }
        ForEach(Array(s.sections.enumerated()), id: \.offset) { _, section in
            sectionView(section)
        }
        if !s.keywords.isEmpty { keywordsRow(s.keywords) }
    }

    private func leadCard(_ s: MeetingSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !s.leadQuestion.trimmingCharacters(in: .whitespaces).isEmpty {
                Text(s.leadQuestion).font(.system(size: 14, weight: .semibold)).foregroundColor(RC.meta)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !s.leadAnswer.trimmingCharacters(in: .whitespaces).isEmpty {
                md(s.leadAnswer).font(.system(size: 16, weight: .medium)).foregroundColor(RC.bodyAlt)
                    .lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RC.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(RC.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func tableOfContents(_ sections: [MeetingSummary.Section]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("목차").font(.system(size: 13, weight: .heavy)).foregroundColor(RC.cardTitle)
            ForEach(Array(sections.enumerated()), id: \.offset) { _, s in
                Text(s.title).font(.system(size: 13)).foregroundColor(RC.meta)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
    }

    private func sectionView(_ section: MeetingSummary.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(section.title).font(.system(size: 16, weight: .bold)).foregroundColor(RC.heading)
                    .fixedSize(horizontal: false, vertical: true)
                if !section.time.isEmpty {
                    Text(section.time).font(.system(size: 11, weight: .bold)).foregroundColor(RC.time)
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(RC.tabBg).clipShape(Capsule())
                }
                Spacer(minLength: 0)
            }
            ForEach(Array(section.points.enumerated()), id: \.offset) { _, point in
                VStack(alignment: .leading, spacing: 5) {
                    if !point.text.trimmingCharacters(in: .whitespaces).isEmpty {
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").font(.system(size: 13, weight: .bold)).foregroundColor(RC.bullet)
                            md(point.text).font(.system(size: 14)).foregroundColor(RC.bodyAlt)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ForEach(Array(point.subPoints.enumerated()), id: \.offset) { _, sub in
                        HStack(alignment: .top, spacing: 8) {
                            Text("–").font(.system(size: 13)).foregroundColor(RC.bullet)
                            md(sub).font(.system(size: 13)).foregroundColor(RC.body)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.leading, 16)
                    }
                }
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(RC.card)
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(RC.cardBorder, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func keywordsRow(_ keywords: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Array(keywords.enumerated()), id: \.offset) { _, kw in
                    Text("#\(kw)").font(.system(size: 11, weight: .medium)).foregroundColor(RC.meta)
                        .lineLimit(1).fixedSize()
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(RC.card).clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Transcript

    @ViewBuilder
    private func transcriptList(_ lines: [MeetingResult.TranscriptLine]) -> some View {
        if lines.isEmpty {
            Text("전사 내용이 없습니다.").font(.system(size: 13)).foregroundColor(RC.meta)
        } else {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(lines) { line in
                    HStack(alignment: .top, spacing: 12) {
                        Text(line.time).font(.system(size: 12, weight: .bold)).foregroundColor(RC.time)
                            .frame(width: 44, alignment: .leading)
                        Text(line.text).font(.system(size: 13)).foregroundColor(RC.bodyAlt)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(RC.card)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(RC.cardBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Controls

    private func controls(_ r: MeetingResult) -> some View {
        HStack(spacing: 10) {
            // 주: Markdown 내보내기(Notion/Confluence 친화)
            Button { MeetingExporter.save(r) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up").font(.system(size: 13))
                    Text("내보내기 (.md)").font(.system(size: 14, weight: .heavy))
                }
                .foregroundColor(RC.accentText)
                .frame(maxWidth: .infinity).frame(height: 44)
                .background(RC.accent).clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)

            secondaryButton(icon: "doc.on.doc", label: "복사") { copy(r) }
            secondaryButton(label: "닫기") { onClose() }
        }
    }

    private func secondaryButton(icon: String? = nil, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 12)) }
                Text(label).font(.system(size: 13, weight: .bold))
            }
            .foregroundColor(RC.secondaryBtnText)
            .padding(.horizontal, 14).frame(height: 44)
            .background(RC.secondaryBtn)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(RC.secondaryBtnBorder, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    /// **굵게** 등 인라인 마크다운을 렌더한다.
    private func md(_ s: String) -> Text {
        if let attr = try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return Text(attr)
        }
        return Text(s)
    }

    private func copy(_ r: MeetingResult) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(r.summary.markdown(), forType: .string)
    }
}

extension MeetingResult {
    /// 저장된 회의 기록 → 결과 화면 데이터. 종료 직후와 목록 상세가 같은 렌더를 쓰도록 통일.
    public static func from(_ record: MeetingRecord) -> MeetingResult {
        let start = record.transcript.first?.timestamp ?? record.startedAt
        let lines = record.transcript.map { seg in
            let s = max(0, Int(seg.timestamp.timeIntervalSince(start).rounded()))
            return TranscriptLine(time: String(format: "%02d:%02d", s / 60, s % 60), text: seg.text)
        }
        return MeetingResult(title: record.title, metaText: record.subtitle, summary: record.summary, transcript: lines)
    }
}
