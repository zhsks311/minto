import SwiftUI
import AppKit

struct ConfluenceExportSheet: View {
    let record: MeetingRecord
    @ObservedObject var confluence: ConfluenceService
    let openSettings: () -> Void
    @Environment(\.dismiss) private var dismiss
    @AppStorage("confluenceExportSpaceKey") private var savedSpaceKey = ""
    @AppStorage("confluenceExportParentID") private var savedParentID = ""
    @State private var pageTitle: String
    @State private var isPublishing = false
    @State private var publishedPage: ConfluenceService.PublishedPage?
    @State private var errorMessage: String?

    init(record: MeetingRecord, confluence: ConfluenceService, openSettings: @escaping () -> Void) {
        self.record = record
        self.confluence = confluence
        self.openSettings = openSettings
        let title = record.title.trimmingCharacters(in: .whitespacesAndNewlines)
        _pageTitle = State(initialValue: title.isEmpty ? "회의록" : title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Confluence로 내보내기")
                    .font(.system(size: 20, weight: .bold))
                Text("선택한 공간에 회의록 페이지를 새로 만듭니다.")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                labeledField("페이지 제목") {
                    TextField("페이지 제목", text: $pageTitle)
                }
                labeledField("공간 키") {
                    TextField("예: ENG", text: $savedSpaceKey)
                }
                labeledField("부모 페이지 ID") {
                    TextField("비우면 공간 최상위에 생성", text: $savedParentID)
                }

                Text("공간 키는 Confluence URL의 `/spaces/ENG`에서 `ENG`에 해당해요. 부모 페이지 ID는 내보낼 위치를 지정할 때만 입력하세요.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let publishedPage {
                VStack(alignment: .leading, spacing: 8) {
                    Label("내보내기가 완료됐어요.", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.system(size: 13, weight: .semibold))
                    Button {
                        if let url = URL(string: publishedPage.url) {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        Label("Confluence에서 열기", systemImage: "arrow.up.right.square")
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if ConfluenceExportSheetPresentation.showsSettingsHandoff(for: confluence.connectionState) {
                VStack(alignment: .leading, spacing: 8) {
                    Label(
                        ConfluenceExportSheetPresentation.settingsHandoffTitle,
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.orange)
                    Text(ConfluenceExportSheetPresentation.settingsHandoffMessage)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        openSettings()
                    } label: {
                        Label(
                            ConfluenceExportSheetPresentation.settingsHandoffButtonTitle,
                            systemImage: "gearshape.fill"
                        )
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("닫기") { dismiss() }
                Spacer()
                Button {
                    publish()
                } label: {
                    if isPublishing {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("내보내는 중")
                        }
                    } else {
                        Label("내보내기", systemImage: "square.and.arrow.up")
                    }
                }
                .buttonStyle(ProminentActionButtonStyle())
                .disabled(!canPublish)
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var canPublish: Bool {
        confluence.isConfigured
            && !isPublishing
            && !pageTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !savedSpaceKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func labeledField<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            content()
                .textFieldStyle(.roundedBorder)
        }
    }

    private func publish() {
        errorMessage = nil
        publishedPage = nil
        isPublishing = true
        let markdown = MeetingExporter.markdown(for: MeetingResult.from(record))
        let title = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let spaceKey = savedSpaceKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let parentID = savedParentID.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            do {
                publishedPage = try await confluence.publishPage(
                    title: title,
                    markdown: markdown,
                    spaceKey: spaceKey,
                    parentID: parentID.isEmpty ? nil : parentID
                )
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "Confluence 내보내기에 실패했어요."
            }
            isPublishing = false
        }
    }
}

enum ConfluenceExportSheetPresentation {
    static let settingsHandoffTitle = "Confluence 다시 연결이 필요해요."
    static let settingsHandoffMessage = "설정에서 API token을 다시 저장한 뒤 내보내기를 다시 시도하세요."
    static let settingsHandoffButtonTitle = "Confluence 설정 열기"

    static func showsSettingsHandoff(for state: ConfluenceService.ConnectionState) -> Bool {
        state == .needsReconnect
    }
}
