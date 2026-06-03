import SwiftUI
import AppKit

/// 회의 목록 + 상세. 좌측에서 회의를 고르면 우측에 저장된 요약/전사를 보여준다.
/// 상세 렌더는 종료 후 결과 창과 동일한 MeetingSummaryView를 재사용한다.
public struct MeetingLibraryView: View {
    @ObservedObject private var store: MeetingStore
    @StateObject private var detailModel = MeetingSummaryModel()
    @State private var selectedID: UUID?
    private let onNewMeeting: () -> Void

    public init(store: MeetingStore, onNewMeeting: @escaping () -> Void) {
        self.store = store
        self.onNewMeeting = onNewMeeting
    }

    public var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 240, ideal: 280, max: 360)
        } detail: {
            detail
        }
        .onChange(of: selectedID) { _, id in
            if let id, let rec = store.meetings.first(where: { $0.id == id }) {
                detailModel.state = .result(MeetingResult.from(rec))
            }
        }
        .frame(minWidth: 820, minHeight: 560)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            Button { onNewMeeting() } label: {
                Label("새 회의 시작", systemImage: "mic.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .padding(12)

            if store.meetings.isEmpty {
                emptyList
            } else {
                List(store.meetings, selection: $selectedID) { rec in
                    row(rec).tag(rec.id)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private func row(_ rec: MeetingRecord) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(rec.title.isEmpty ? "제목 없음" : rec.title)
                .font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Text(rec.subtitle)
                .font(.system(size: 11)).foregroundColor(.secondary).lineLimit(1)
        }
        .padding(.vertical, 3)
        .contextMenu {
            Button(role: .destructive) { store.delete(rec.id); if selectedID == rec.id { selectedID = nil } } label: {
                Label("삭제", systemImage: "trash")
            }
        }
    }

    private var emptyList: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 28)).foregroundColor(.secondary)
            Text("아직 저장된 회의가 없어요").font(.system(size: 13)).foregroundColor(.secondary)
            Text("‘새 회의 시작’으로 첫 회의를 녹음해 보세요").font(.caption2).foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        if selectedID != nil {
            MeetingSummaryView(model: detailModel, onClose: { selectedID = nil })
        } else {
            VStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass").font(.system(size: 34)).foregroundColor(.secondary)
                Text("왼쪽에서 회의를 선택하면 요약과 전사를 볼 수 있어요")
                    .font(.system(size: 13)).foregroundColor(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
