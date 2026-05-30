import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    @AppStorage("selectedModel") private var selectedModel = "openai_whisper-large-v3-v20240930_turbo"

    // LLM 교정 서비스 관찰
    @ObservedObject private var llmService = LLMCorrectionService.shared
    @ObservedObject private var copilot = CopilotOAuthService.shared
    @ObservedObject private var codex = CodexOAuthService.shared

    // Gemini는 ObservableObject가 아니므로 @State로 상태 관리
    @State private var geminiLoggedIn = GeminiOAuthService.shared.isLoggedIn
    @State private var geminiEmail = GeminiOAuthService.shared.email
    @State private var isLoginLoading = false
    @State private var loginError: String? = nil

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

            Section("LLM 교정") {
                llmProviderRow
                if llmService.selectedProvider != .none {
                    if llmService.selectedProvider.requiresWarning {
                        tosWarningRow
                    }
                    llmStatusRow
                    llmActionRow
                    if deviceCodeInProgress {
                        deviceCodeRow
                    }
                    if let err = loginError {
                        Text(err)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
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
        .frame(width: 440, height: 520)
    }

    // MARK: - LLM Section Rows

    private var llmProviderRow: some View {
        Picker("공급자", selection: $llmService.selectedProvider) {
            ForEach(LLMCorrectionService.Provider.allCases, id: \.self) { provider in
                Text(provider.label).tag(provider)
            }
        }
    }

    private var tosWarningRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            Text("비공식 방식으로 서비스 ToS 회색 지대입니다. 개인 사용 목적으로만 사용하세요.")
                .font(.caption)
                .foregroundColor(.orange)
        }
        .padding(.vertical, 2)
    }

    private var llmStatusRow: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(currentProviderLoggedIn ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(currentProviderLoggedIn ? "로그인됨" : "미연결")
                .font(.callout)
                .foregroundColor(currentProviderLoggedIn ? .primary : .secondary)
            if currentProviderLoggedIn, !currentEmail.isEmpty {
                Text(currentEmail)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var llmActionRow: some View {
        if currentProviderLoggedIn {
            Button("로그아웃") {
                llmService.logout()
                refreshGeminiState()
                loginError = nil
            }
            .foregroundColor(.red)
        } else if !isLoginLoading {
            Button("로그인") {
                loginError = nil
                startLogin()
            }
        } else {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("로그인 중...").font(.callout).foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var deviceCodeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("브라우저에서 코드를 입력하세요:")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 8) {
                Text(currentDeviceCode)
                    .font(.system(size: 18, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.1))
                    .cornerRadius(8)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(currentDeviceCode, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("코드 복사")
            }
            Button("취소") {
                cancelLogin()
            }
            .foregroundColor(.secondary)
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Computed helpers

    private var currentProviderLoggedIn: Bool {
        switch llmService.selectedProvider {
        case .none:    return false
        case .gemini:  return geminiLoggedIn
        case .copilot: return copilot.isLoggedIn
        case .codex:   return codex.isLoggedIn
        }
    }

    private var currentEmail: String {
        switch llmService.selectedProvider {
        case .none:    return ""
        case .gemini:  return geminiEmail
        case .copilot: return copilot.email
        case .codex:   return ""
        }
    }

    private var deviceCodeInProgress: Bool {
        switch llmService.selectedProvider {
        case .copilot: return copilot.isPolling
        case .codex:   return codex.isPolling
        default:       return false
        }
    }

    private var currentDeviceCode: String {
        switch llmService.selectedProvider {
        case .copilot: return copilot.deviceCode
        case .codex:   return codex.deviceCode
        default:       return ""
        }
    }

    // MARK: - Login flows

    private func startLogin() {
        isLoginLoading = true
        switch llmService.selectedProvider {
        case .none:
            isLoginLoading = false
        case .gemini:
            Task {
                do {
                    try await GeminiOAuthService.shared.login()
                    refreshGeminiState()
                } catch {
                    loginError = error.localizedDescription
                }
                isLoginLoading = false
            }
        case .copilot:
            isLoginLoading = false
            copilot.startLogin { result in
                if case .failure(let err) = result {
                    self.loginError = err.localizedDescription
                }
            }
        case .codex:
            isLoginLoading = false
            codex.startLogin { result in
                if case .failure(let err) = result {
                    self.loginError = err.localizedDescription
                }
            }
        }
    }

    private func cancelLogin() {
        copilot.cancelLogin()
        codex.cancelLogin()
        isLoginLoading = false
    }

    private func refreshGeminiState() {
        geminiLoggedIn = GeminiOAuthService.shared.isLoggedIn
        geminiEmail = GeminiOAuthService.shared.email
    }

    // MARK: - Model section helpers

    private func modelRow(_ model: (id: String, label: String, note: String)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.label).font(.body)
                Text(model.note).font(.caption).foregroundColor(.secondary)
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
        case .unloaded:              return "미로드"
        case .downloading(let p):    return "다운로드 중 \(Int(p * 100))%"
        case .loading:               return "초기화 중"
        case .loaded:                return "로드 완료"
        case .failed(let msg):       return "실패: \(msg)"
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        String(format: "%02d:%02d", Int(t) / 60, Int(t) % 60)
    }
}
