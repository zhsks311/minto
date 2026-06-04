import SwiftUI
import AppKit

private enum LibraryPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let border = Color.secondary.opacity(0.18)
    static let accentSoft = Color.accentColor.opacity(0.12)
}

private struct MeetingSearchMatch {
    let badge: String
    let text: String
}

/// 회의 목록 + 검색 + 선택한 회의 미리보기.
/// v2는 검색을 첫 화면의 중심 작업으로 두고, 상세 리포트 전체보다 빠른 회고/탐색에 집중한다.
public struct MeetingLibraryView: View {
    @ObservedObject private var store: MeetingStore
    @State private var selectedID: UUID?
    @State private var searchText = ""
    private let onNewMeeting: () -> Void

    public init(store: MeetingStore, onNewMeeting: @escaping () -> Void) {
        self.store = store
        self.onNewMeeting = onNewMeeting
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .background(LibraryPalette.background)
        .frame(minWidth: 900, minHeight: 600)
        .onAppear { selectFirstAvailableIfNeeded() }
        .onChange(of: store.meetings) { _, _ in selectFirstAvailableIfNeeded() }
        .onChange(of: searchText) { _, _ in selectFirstAvailableIfNeeded(preferFirstResult: true) }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Minto")
                    .font(.system(size: 20, weight: .bold))
                Text(isSearching ? "필요한 회의와 근거를 찾고 있어요" : "회의를 찾거나 새로 시작하세요")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 20)

            searchField
                .frame(width: 360)

            Button { onNewMeeting() } label: {
                Label("새 회의", systemImage: "mic.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 16)
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
            TextField("회의, 안건, 결정사항 검색", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
            if isSearching {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("검색 지우기")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 36)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Content

    private var content: some View {
        HStack(spacing: 0) {
            resultsColumn
                .frame(width: 360)
            Divider()
            detailColumn
        }
    }

    private var resultsColumn: some View {
        VStack(alignment: .leading, spacing: 14) {
            searchReadiness

            if isSearching {
                searchSummary
                suggestionChips
            }

            HStack {
                Text(isSearching ? "검색 결과" : "최근 회의")
                    .font(.system(size: 14, weight: .bold))
                Spacer()
                Text("\(displayedMeetings.count)")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            if store.meetings.isEmpty {
                emptyState
            } else if displayedMeetings.isEmpty {
                noSearchResults
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(displayedMeetings) { record in
                            meetingRow(record)
                        }
                    }
                    .padding(.bottom, 8)
                }
            }
        }
        .padding(18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(LibraryPalette.surface.opacity(0.45))
    }

    private var detailColumn: some View {
        Group {
            if let record = selectedRecord {
                meetingPreview(record)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundColor(.secondary)
                    Text("회의를 선택하면 요약과 전사 근거를 볼 수 있어요")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    // MARK: - Left column blocks

    private var searchReadiness: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 3)
                    .frame(width: 30, height: 30)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.green)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("검색 준비됨")
                    .font(.system(size: 12, weight: .semibold))
                Text("저장된 회의 \(store.meetings.count)개에서 바로 찾습니다")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var searchSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("“\(trimmedSearch)” 검색 중")
                .font(.system(size: 14, weight: .bold))
                .lineLimit(1)
            Text(displayedMeetings.isEmpty ? "일치하는 회의를 찾지 못했어요" : "가장 가까운 회의부터 보여줍니다")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestionChips: some View {
        HStack(spacing: 6) {
            Label("필터", systemImage: "slider.horizontal.3")
                .font(.system(size: 11, weight: .semibold))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(LibraryPalette.elevated)
                .clipShape(Capsule())
            ForEach(["요약", "전사", "주제"], id: \.self) { label in
                Text(label)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.10))
                    .clipShape(Capsule())
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Spacer()
            Image(systemName: "tray")
                .font(.system(size: 28))
                .foregroundColor(.secondary)
            Text("아직 저장된 회의가 없어요")
                .font(.system(size: 13, weight: .semibold))
            Text("새 회의를 녹음하면 여기에서 검색할 수 있어요")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button { onNewMeeting() } label: {
                Label("첫 회의 시작", systemImage: "mic")
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResults: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundColor(.secondary)
            Text("검색 결과가 없어요")
                .font(.system(size: 13, weight: .semibold))
            Text("다른 회의명, 안건, 결정사항으로 다시 검색해 보세요")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func meetingRow(_ record: MeetingRecord) -> some View {
        let selected = selectedID == record.id
        let match = primaryMatch(for: record)

        return Button {
            selectedID = record.id
        } label: {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayTitle(for: record))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(shortDate(record.startedAt))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                }

                Text(record.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                if isSearching {
                    HStack(spacing: 6) {
                        Text(match.badge)
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.12))
                            .clipShape(Capsule())
                        Text(match.text)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                } else if !record.summary.leadAnswer.isEmpty {
                    Text(record.summary.leadAnswer)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? LibraryPalette.accentSoft : LibraryPalette.elevated)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(selected ? Color.accentColor.opacity(0.45) : LibraryPalette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                store.delete(record.id)
                if selectedID == record.id { selectedID = nil }
            } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    // MARK: - Detail preview

    private func meetingPreview(_ record: MeetingRecord) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                previewHeader(record)

                if isSearching {
                    whyThisResult(record)
                }

                leadSummary(record)
                sectionPreview(record.summary.sections)
                transcriptPreview(record)
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(LibraryPalette.background)
    }

    private func previewHeader(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(displayTitle(for: record))
                        .font(.system(size: 26, weight: .bold))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(record.subtitle)
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    if !record.topic.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(record.topic)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer()
                Button { MeetingExporter.save(MeetingResult.from(record)) } label: {
                    Label("내보내기", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Button { copySummary(record) } label: {
                    Label("요약 복사", systemImage: "doc.on.doc")
                }
                .buttonStyle(.borderedProminent)
                Button { copyTranscript(record) } label: {
                    Label("전사 복사", systemImage: "text.quote")
                }
                .buttonStyle(.bordered)
                .disabled(record.transcript.isEmpty)
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func whyThisResult(_ record: MeetingRecord) -> some View {
        let match = primaryMatch(for: record)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundColor(.accentColor)
                Text("이 회의가 먼저 보이는 이유")
                    .font(.system(size: 13, weight: .bold))
            }
            HStack(alignment: .top, spacing: 8) {
                Text(match.badge)
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(Capsule())
                Text(match.text)
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LibraryPalette.accentSoft)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.accentColor.opacity(0.22), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func leadSummary(_ record: MeetingRecord) -> some View {
        let summary = record.summary
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("요약", systemImage: "list.bullet.rectangle")
            if summary.isEmpty {
                Text("요약이 없습니다. 전사 내용을 먼저 확인하세요.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                if !summary.leadQuestion.isEmpty {
                    Text(summary.leadQuestion)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !summary.leadAnswer.isEmpty {
                    Text(summary.leadAnswer)
                        .font(.system(size: 15))
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !summary.keywords.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(summary.keywords, id: \.self) { keyword in
                                Text("#\(keyword)")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.secondary.opacity(0.10))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func sectionPreview(_ sections: [MeetingSummary.Section]) -> some View {
        if !sections.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                sectionTitle("주요 흐름", systemImage: "point.3.connected.trianglepath.dotted")
                ForEach(Array(sections.prefix(3).enumerated()), id: \.offset) { _, section in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(section.title.isEmpty ? "섹션" : section.title)
                                .font(.system(size: 13, weight: .bold))
                            if !section.time.isEmpty {
                                Text(section.time)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let firstPoint = section.points.first?.text, !firstPoint.isEmpty {
                            Text(firstPoint)
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .background(LibraryPalette.elevated)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private func transcriptPreview(_ record: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle("전사 근거", systemImage: "quote.bubble")
            if record.transcript.isEmpty {
                Text("전사 내용이 없습니다.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            } else {
                ForEach(Array(relevantTranscriptLines(for: record).enumerated()), id: \.offset) { _, segment in
                    HStack(alignment: .top, spacing: 10) {
                        Text(relativeTimestamp(segment, in: record))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(width: 46, alignment: .leading)
                        Text(segment.text)
                            .font(.system(size: 13))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(18)
        .background(LibraryPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(LibraryPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func sectionTitle(_ title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.accentColor)
            Text(title)
                .font(.system(size: 14, weight: .bold))
        }
    }

    // MARK: - Search

    private var trimmedSearch: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearch.isEmpty
    }

    private var displayedMeetings: [MeetingRecord] {
        guard isSearching else { return store.meetings }
        return store.meetings.filter { recordMatches($0) }
    }

    private var selectedRecord: MeetingRecord? {
        if let selectedID, let record = displayedMeetings.first(where: { $0.id == selectedID }) {
            return record
        }
        return displayedMeetings.first
    }

    private func recordMatches(_ record: MeetingRecord) -> Bool {
        let query = trimmedSearch
        guard !query.isEmpty else { return true }
        return displayTitle(for: record).localizedCaseInsensitiveContains(query)
            || record.topic.localizedCaseInsensitiveContains(query)
            || record.summary.markdown().localizedCaseInsensitiveContains(query)
            || record.transcript.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private func primaryMatch(for record: MeetingRecord) -> MeetingSearchMatch {
        let query = trimmedSearch
        if !query.isEmpty {
            if displayTitle(for: record).localizedCaseInsensitiveContains(query) {
                return MeetingSearchMatch(badge: "제목", text: displayTitle(for: record))
            }
            if record.topic.localizedCaseInsensitiveContains(query) {
                return MeetingSearchMatch(badge: "주제", text: record.topic)
            }
            if let section = record.summary.sections.first(where: { section in
                section.title.localizedCaseInsensitiveContains(query)
                    || section.points.contains { point in
                        point.text.localizedCaseInsensitiveContains(query)
                            || point.subPoints.contains { $0.localizedCaseInsensitiveContains(query) }
                    }
            }) {
                let text = section.points.first?.text ?? section.title
                return MeetingSearchMatch(badge: section.time.isEmpty ? "요약" : section.time, text: text)
            }
            if record.summary.markdown().localizedCaseInsensitiveContains(query) {
                return MeetingSearchMatch(badge: "요약", text: record.summary.leadAnswer)
            }
            if let segment = record.transcript.first(where: { $0.text.localizedCaseInsensitiveContains(query) }) {
                return MeetingSearchMatch(badge: relativeTimestamp(segment, in: record), text: segment.text)
            }
        }

        if !record.summary.leadAnswer.isEmpty {
            return MeetingSearchMatch(badge: "요약", text: record.summary.leadAnswer)
        }
        if let segment = record.transcript.first {
            return MeetingSearchMatch(badge: relativeTimestamp(segment, in: record), text: segment.text)
        }
        return MeetingSearchMatch(badge: "회의", text: record.subtitle)
    }

    private func relevantTranscriptLines(for record: MeetingRecord) -> [Segment] {
        guard isSearching else { return Array(record.transcript.prefix(5)) }
        let matches = record.transcript.filter { $0.text.localizedCaseInsensitiveContains(trimmedSearch) }
        return Array((matches.isEmpty ? record.transcript : matches).prefix(5))
    }

    private func selectFirstAvailableIfNeeded(preferFirstResult: Bool = false) {
        guard !displayedMeetings.isEmpty else {
            selectedID = nil
            return
        }
        if preferFirstResult {
            selectedID = displayedMeetings.first?.id
            return
        }
        if let selectedID, displayedMeetings.contains(where: { $0.id == selectedID }) {
            return
        }
        selectedID = displayedMeetings.first?.id
    }

    // MARK: - Helpers

    private func displayTitle(for record: MeetingRecord) -> String {
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "제목 없음" : title
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M.d"
        return formatter.string(from: date)
    }

    private func relativeTimestamp(_ segment: Segment, in record: MeetingRecord) -> String {
        let start = record.transcript.first?.timestamp ?? record.startedAt
        let seconds = max(0, Int(segment.timestamp.timeIntervalSince(start).rounded()))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    private func copySummary(_ record: MeetingRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.summary.markdown(), forType: .string)
    }

    private func copyTranscript(_ record: MeetingRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.transcript.map(\.text).joined(separator: "\n"), forType: .string)
    }
}
