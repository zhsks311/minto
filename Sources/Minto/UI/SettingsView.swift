import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    @AppStorage("selectedModel") private var selectedModel = "openai_whisper-large-v3-v20240930_turbo"

    private let availableModels: [(id: String, label: String, note: String)] = [
        ("openai_whisper-tiny",   "tiny",   "~75MB · 빠름, 정확도 낮음"),
        ("openai_whisper-base",   "base",   "~145MB · 균형"),
        ("openai_whisper-small",  "small",  "~250MB · 기본"),
        ("openai_whisper-medium", "medium", "~770MB · 높은 정확도"),
        ("openai_whisper-large-v3-v20240930_turbo", "large-turbo", "~810MB · 한국어 권장 ★"),
    ]

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            Section("음성 인식 모델") {
                ForEach(availableModels, id: \.id) { model in
                    modelRow(model)
                }
                Text("선택한 모델은 다음 실행 시 적용됩니다.\n현재 세션에 바로 적용하려면 아래 버튼을 누르세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("지금 바로 모델 교체") {
                    Task {
                        await viewModel.loadModel(variant: selectedModel)
                    }
                }
                .disabled(isModelBusy)
            }

            Section("오버레이") {
                Text("투명도는 메뉴바에서 실시간으로 조절할 수 있습니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("현재 상태") {
                LabeledContent("로드된 모델", value: viewModel.modelVariantName)
                LabeledContent("모델 상태", value: modelStateDescription)
                if viewModel.isRecording {
                    LabeledContent("녹음 시간", value: formatDuration(viewModel.recordingDuration))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 380)
    }

    private func modelRow(_ model: (id: String, label: String, note: String)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.label)
                    .font(.body)
                Text(model.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if selectedModel == model.id {
                Image(systemName: "checkmark")
                    .foregroundColor(.accentColor)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedModel = model.id
            UserDefaults.standard.set(model.id, forKey: "selectedModel")
        }
    }

    private var isModelBusy: Bool {
        switch viewModel.modelState {
        case .downloading, .loading: return true
        default: return false
        }
    }

    private var modelStateDescription: String {
        switch viewModel.modelState {
        case .unloaded:   return "미로드"
        case .downloading(let p): return "다운로드 중 \(Int(p * 100))%"
        case .loading:    return "초기화 중"
        case .loaded:     return "로드 완료"
        case .failed(let msg): return "실패: \(msg)"
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}

