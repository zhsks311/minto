import SwiftUI

private enum TranscriptEditPalette {
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let elevated = Color(nsColor: .textBackgroundColor)
    static let border = Color.secondary.opacity(0.18)
}

struct TranscriptEditView<Header: View>: View {
    @Binding private var draft: TranscriptEditDraft
    private let isSaving: Bool
    private let errorMessage: String?
    private let timestampText: (Segment) -> String
    private let onCancel: () -> Void
    private let onSave: () -> Void
    private let header: Header

    init(
        draft: Binding<TranscriptEditDraft>,
        isSaving: Bool,
        errorMessage: String?,
        timestampText: @escaping (Segment) -> String,
        onCancel: @escaping () -> Void,
        onSave: @escaping () -> Void,
        @ViewBuilder header: () -> Header
    ) {
        self._draft = draft
        self.isSaving = isSaving
        self.errorMessage = errorMessage
        self.timestampText = timestampText
        self.onCancel = onCancel
        self.onSave = onSave
        self.header = header()
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    header
                    transcriptEditor
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(TranscriptEditPalette.background)

            bottomBar
        }
        .background(TranscriptEditPalette.background)
    }

    private var transcriptEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("전사 편집", systemImage: "square.and.pencil")
                    .font(.system(size: 16, weight: .bold))
                Spacer()
                Text("\(draft.originalSegments.count)개 구간")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }

            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(draft.originalSegments, id: \.id) { segment in
                    transcriptRow(segment)
                }
            }
        }
        .padding(18)
        .background(TranscriptEditPalette.elevated)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(TranscriptEditPalette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func transcriptRow(_ segment: Segment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(timestampText(segment))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 46, alignment: .leading)
                .padding(.top, 8)

            TextEditor(text: textBinding(for: segment))
                .font(.system(size: 13))
                .lineSpacing(4)
                .frame(minHeight: 68)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(TranscriptEditPalette.surface.opacity(0.55))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(TranscriptEditPalette.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(isSaving)
        }
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(role: .cancel) {
                onCancel()
            } label: {
                Label("취소", systemImage: "xmark")
            }
            .buttonStyle(.bordered)
            .keyboardShortcut(.cancelAction)
            .disabled(isSaving)

            Button {
                saveOrExit()
            } label: {
                if isSaving {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("저장")
                    }
                } else {
                    Label("저장", systemImage: "checkmark")
                }
            }
            .buttonStyle(ProminentActionButtonStyle())
            .keyboardShortcut("s", modifiers: .command)
            .disabled(isSaving || !draft.hasChanges)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(TranscriptEditPalette.elevated)
        .overlay(Rectangle().fill(TranscriptEditPalette.border).frame(height: 1), alignment: .top)
    }

    private func textBinding(for segment: Segment) -> Binding<String> {
        Binding(
            get: { draft.text(for: segment) },
            set: { draft.setText($0, for: segment.id) }
        )
    }

    private func saveOrExit() {
        guard draft.hasChanges else {
            onCancel()
            return
        }
        onSave()
    }
}
