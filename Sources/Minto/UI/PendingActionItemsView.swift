import SwiftUI
import AppKit

private enum PendingActionPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let border = Color.secondary.opacity(0.18)
    static let muted = Color.secondary.opacity(0.10)
}

enum PendingActionItemsViewState: Equatable, Sendable {
    case loading
    case disabled
    case empty
    case items([PendingActionItemsGroup])
}

public struct PendingActionItemsView: View {
    private let state: PendingActionItemsViewState

    public init(meetings: [MeetingRecord], useCase: PendingActionItemsUseCase = PendingActionItemsUseCase()) {
        let groups = useCase.pendingActionItems(from: meetings)
        if !groups.isEmpty {
            state = .items(groups)
        } else if !meetings.isEmpty && !meetings.contains(where: { !$0.summary.isEmpty }) {
            state = .disabled
        } else {
            state = .empty
        }
    }

    init(state: PendingActionItemsViewState) {
        self.state = state
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .background(PendingActionPalette.background)
        .frame(minWidth: 520, minHeight: 420)
        .textSelection(.enabled)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Label("미완료 할일", systemImage: "checklist")
                    .font(.system(size: 20, weight: .bold))
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            if pendingCount > 0 {
                Text("\(pendingCount)개 남음")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            loadingContent
        case .disabled:
            centeredState(
                systemImage: "info.circle",
                title: "요약이 없는 회의에서는 할일을 가져올 수 없어요",
                subtitle: "회의 요약이 만들어지면 할일이 여기에 표시돼요",
                tint: .secondary
            )
        case .empty:
            centeredState(
                systemImage: "checkmark",
                title: "미완료 할일이 없어요",
                subtitle: "새로운 회의에서 할일이 추가되거나 남은 할일이 생기면 여기에 표시돼요",
                tint: .green
            )
        case .items(let groups):
            itemsContent(groups)
        }
    }

    private var loadingContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            skeleton(width: 160)
            ForEach(0..<4, id: \.self) { index in
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(PendingActionPalette.muted)
                        .frame(width: 14, height: 14)
                    skeleton(width: index.isMultiple(of: 2) ? 280 : 220)
                }
            }
            Spacer()
        }
        .padding(24)
    }

    private func itemsContent(_ groups: [PendingActionItemsGroup]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(groups) { group in
                    groupSection(group)
                }
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func groupSection(_ group: PendingActionItemsGroup) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.meetingTitle)
                        .font(.system(size: 14, weight: .bold))
                        .lineLimit(1)
                    Text(group.meetingSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text("\(group.items.count)개")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(group.items) { item in
                    pendingRow(item)
                }
            }
        }
        .padding(16)
        .background(PendingActionPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(PendingActionPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func pendingRow(_ item: PendingActionItem) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Text("미완료")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(PendingActionPalette.muted)
                .clipShape(Capsule())
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 5) {
                if !item.actionItem.time.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(item.actionItem.time.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                Text(item.actionItem.task.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)

                let meta = actionMetadata(item.actionItem)
                if !meta.isEmpty {
                    Text(meta)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func centeredState(systemImage: String, title: String, subtitle: String, tint: Color) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 44, height: 44)
                .background(PendingActionPalette.muted)
                .clipShape(Circle())
            Text(title)
                .font(.system(size: 14, weight: .bold))
                .multilineTextAlignment(.center)
            Text(subtitle)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func skeleton(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(PendingActionPalette.muted)
            .frame(width: width, height: 12)
    }

    private var pendingCount: Int {
        if case .items(let groups) = state {
            return groups.reduce(0) { $0 + $1.items.count }
        }
        return 0
    }

    private var headerSubtitle: String {
        switch state {
        case .loading:
            return "회의별 할일을 불러오는 중이에요"
        case .disabled:
            return "요약이 있는 회의가 필요해요"
        case .empty:
            return "회의별 미완료 항목이 없어요"
        case .items(let groups):
            return "\(groups.count)개 회의에서 모았어요"
        }
    }

    private func actionMetadata(_ item: MeetingSummary.ActionItem) -> String {
        let owner = item.owner.trimmingCharacters(in: .whitespacesAndNewlines)
        let due = item.due.trimmingCharacters(in: .whitespacesAndNewlines)
        var parts: [String] = []
        if !owner.isEmpty { parts.append("담당: \(owner)") }
        if !due.isEmpty { parts.append("기한: \(due)") }
        return parts.joined(separator: " · ")
    }
}
