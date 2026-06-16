import SwiftUI

struct SummaryGlossaryBanner: View {
    let glossary: String?
    @State private var isExpanded = false

    var body: some View {
        if !glossaryLines.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(glossaryLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)
                .textSelection(.enabled)
            } label: {
                Label("요약에 사용된 용어 \(glossaryLines.count)개", systemImage: "text.book.closed")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.16), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var glossaryLines: [String] {
        (glossary ?? "")
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
