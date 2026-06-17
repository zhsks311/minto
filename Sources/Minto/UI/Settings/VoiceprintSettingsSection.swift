import SwiftUI

struct VoiceprintSettingsSection: View {
    @ObservedObject private var voiceprintStore = VoiceprintStore.shared

    var body: some View {
        Section("화자 보이스프린트") {
            VStack(alignment: .leading, spacing: 3) {
                Text("등록한 화자의 목소리 특징(임베딩)만 이 Mac에 저장해요. 음성 원본은 저장하지 않아요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("다음 파일 임포트에서 같은 사람을 자동으로 찾아 이름을 붙여요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("등록된 보이스프린트 \(voiceprintStore.voiceprints.count)개")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if voiceprintStore.voiceprints.isEmpty {
                Text("전사 화면에서 화자 이름을 입력하고 ‘등록’을 누르면 여기에 보여요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(voiceprintStore.voiceprints) { voiceprint in
                    voiceprintRow(voiceprint)
                }
            }
        }
    }

    private func voiceprintRow(_ voiceprint: Voiceprint) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(voiceprint.displayName)
                    .font(.callout.weight(.semibold))
                Text("\(enrollmentDateText(voiceprint.enrolledAt)) · \(voiceprint.dimensions)차원")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if voiceprint.embeddingModelID != FluidAudioOfflineDiarizationProvider.embeddingModelID {
                    Text("현재 모델과 호환되지 않음 · 재등록 필요")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            Spacer()
            Button(role: .destructive) {
                deleteVoiceprint(voiceprint)
            } label: {
                Label("삭제", systemImage: "trash")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private func deleteVoiceprint(_ voiceprint: Voiceprint) {
        let beforeCount = voiceprintStore.voiceprints.count
        Log.store.info("voiceprint delete start count=\(beforeCount, privacy: .public)")

        let ok = voiceprintStore.delete(id: voiceprint.id)
        if ok {
            let afterCount = voiceprintStore.voiceprints.count
            Log.store.info("voiceprint delete success count=\(afterCount, privacy: .public)")
        } else {
            Log.store.error("voiceprint delete failed count=\(beforeCount, privacy: .public)")
        }
    }

    private func enrollmentDateText(_ date: Date) -> String {
        Self.enrollmentDateFormatter.string(from: date)
    }

    private static let enrollmentDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy. M. d."
        return formatter
    }()
}
