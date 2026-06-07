import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    @AppStorage("selectedModel") private var selectedModel = "openai_whisper-large-v3-v20240930_turbo"

    // 교정 provider별 모델 선택(서비스가 같은 UserDefaults 키를 읽는다).
    @AppStorage("codexModel") private var codexModel = "auto"
    @AppStorage("geminiModel") private var geminiModel = "gemini-2.5-flash"
    @AppStorage("copilotModel") private var copilotModel = "gpt-4o"

    // LLM 교정 서비스 관찰
    @ObservedObject private var llmService = LLMCorrectionService.shared
    @ObservedObject private var copilot = CopilotOAuthService.shared
    @ObservedObject private var codex = CodexOAuthService.shared

    // Gemini는 ObservableObject가 아니므로 @State로 상태 관리
    @State private var geminiLoggedIn = GeminiOAuthService.shared.isLoggedIn
    @State private var geminiEmail = GeminiOAuthService.shared.email
    @State private var isLoginLoading = false
    @State private var loginError: String? = nil

    // 외부 연동(Notion MCP OAuth·Confluence token).
    @ObservedObject private var notionMCP = NotionMCPService.shared
    @ObservedObject private var confluence = ConfluenceService.shared
    @AppStorage(ConfluenceService.baseURLKey) private var confluenceBaseURL = ""
    @AppStorage(ConfluenceService.emailKey) private var confluenceEmail = ""
    @State private var notionConnectLoading = false
    @State private var notionConnectError: String? = nil
    @State private var confluenceTokenInput = ""
    @State private var showNotionSettings = false
    @State private var showConfluenceSettings = false
    @AppStorage("lastLLMProvider") private var lastLLMProviderRaw = "codex"

    private let availableModels: [(id: String, label: String, note: String, memory: String)] = [
        (
            "openai_whisper-large-v3-v20240930_turbo",
            "회의 정확도 우선",
            "한국어 회의 권장 · 다운로드 약 810MB",
            "실행 중 메모리 여유 2~3GB 권장"
        ),
        (
            "openai_whisper-medium",
            "균형",
            "정확도와 속도 균형 · 다운로드 약 770MB",
            "실행 중 메모리 여유 1.5~2.5GB 권장"
        ),
        (
            "openai_whisper-small",
            "빠른 기록",
            "빠른 초안용 · 다운로드 약 250MB",
            "실행 중 메모리 여유 1GB 내외 권장"
        ),
    ]
    private let deprecatedModelIDs = [
        "openai_whisper-tiny",
        "openai_whisper-base",
        "openai_whisper-large-v3-v20240930_626MB",
        "openai_whisper-large-v3-v20240930_turbo_632MB",
    ]

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            llmCorrectionSection
            searchReadinessSection
            sourceConnectionsSection

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
                if isModelFailed {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("모델 파일이 손상되었거나 권한 문제로 열리지 않습니다.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button("캐시 정리 후 모델 다시 받기") {
                            Task {
                                await viewModel.recoverModelCacheAndReload(variant: selectedModel)
                            }
                        }
                        .disabled(isModelBusy)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("오버레이") {
                Text("투명도는 메뉴바에서 실시간으로 조절할 수 있습니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("현재 상태") {
                LabeledContent("로드된 모델", value: viewModel.modelDisplayName)
                LabeledContent("모델 상태", value: modelStateDescription)
                if viewModel.isRecording {
                    LabeledContent("녹음 시간", value: formatDuration(viewModel.recordingDuration))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 520)
        .onAppear {
            normalizeSelectedModelIfNeeded()
            rememberCurrentProviderIfNeeded()
        }
        .onChange(of: llmService.selectedProvider) { _, provider in
            if provider != .none {
                lastLLMProviderRaw = provider.rawValue
            }
        }
    }

    // MARK: - Correction Section Rows

    private var llmCorrectionSection: some View {
        Section("전사 자동 교정") {
            Toggle(isOn: llmCorrectionEnabledBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("전사 자동 교정")
                            .font(.callout.weight(.semibold))
                        Text("권장")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                    Text("회의 용어와 문맥으로 띄어쓰기, 오인식, 전문용어 표기를 다듬습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .help("음성 인식 결과를 회의 맥락에 맞게 자연스럽게 다듬습니다. 회의록 품질을 위해 켜두는 것을 권장합니다.")

            if llmService.selectedProvider != .none {
                llmProviderRow
                currentProviderModelPicker
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
    }

    private var llmCorrectionEnabledBinding: Binding<Bool> {
        Binding(
            get: { llmService.selectedProvider != .none },
            set: { enabled in
                if enabled {
                    llmService.selectedProvider = restoredLLMProvider
                } else {
                    rememberCurrentProviderIfNeeded()
                    llmService.selectedProvider = .none
                }
            }
        )
    }

    private var restoredLLMProvider: LLMCorrectionService.Provider {
        LLMCorrectionService.Provider(rawValue: lastLLMProviderRaw) ?? .codex
    }

    private func rememberCurrentProviderIfNeeded() {
        if llmService.selectedProvider != .none {
            lastLLMProviderRaw = llmService.selectedProvider.rawValue
        }
    }

    // MARK: - Integration Section Rows

    private var searchReadinessSection: some View {
        Section("검색 준비도") {
            VStack(alignment: .leading, spacing: 10) {
                Label("기본 회의 검색 준비됨", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)
                Text(searchReadinessMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label(nextSearchSetupAction, systemImage: connectedSearchSourceCount == 2 ? "checkmark.circle.fill" : "arrow.down.circle")
                    .font(.caption)
                    .foregroundColor(connectedSearchSourceCount == 2 ? .green : .secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private var sourceConnectionsSection: some View {
        Section("검색 소스") {
            DisclosureGroup(isExpanded: $showNotionSettings) {
                notionSettingsBody
            } label: {
                integrationStatusRow(title: "Notion", connected: notionMCP.isConnected)
            }

            DisclosureGroup(isExpanded: $showConfluenceSettings) {
                confluenceSettingsBody
            } label: {
                integrationStatusRow(title: "Confluence", connected: confluence.isConfigured)
            }
        }
    }

    private var connectedSearchSourceCount: Int {
        (notionMCP.isConnected ? 1 : 0) + (confluence.isConfigured ? 1 : 0)
    }

    private var searchReadinessMessage: String {
        switch connectedSearchSourceCount {
        case 0:
            return "저장된 회의는 바로 검색됩니다. Notion이나 Confluence를 연결하면 관련 문서까지 함께 찾습니다."
        case 1:
            return "저장된 회의와 연결된 외부 문서 1개를 함께 검색할 수 있습니다."
        default:
            return "Notion과 Confluence가 모두 연결되어 회의 내용으로 문서를 찾을 수 있습니다."
        }
    }

    private var nextSearchSetupAction: String {
        if connectedSearchSourceCount == 2 { return "추가 설정 없이 사용할 수 있습니다" }
        if !notionMCP.isConnected { return "다음 단계: Notion 연결" }
        return "다음 단계: Confluence 연결"
    }

    @ViewBuilder
    private var notionSettingsBody: some View {
        if notionMCP.isConnected {
            Button("연결 해제") {
                notionMCP.disconnect()
                notionConnectError = nil
            }
            .foregroundColor(.red)
            Text("이 기기의 토큰만 지웁니다. 권한을 완전히 회수하려면 Notion 설정의 연결된 앱에서 해제하세요.")
                .font(.caption)
                .foregroundColor(.secondary)
        } else if notionConnectLoading {
            HStack {
                ProgressView().scaleEffect(0.8)
                Text("연결 중…")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        } else {
            Button("Notion 연결") {
                notionConnectError = nil
                notionConnectLoading = true
                Task {
                    do {
                        try await NotionMCPService.shared.connect()
                    } catch is CancellationError {
                        // 사용자 취소는 조용히 처리한다.
                    } catch {
                        let message = (error as? LocalizedError)?.errorDescription
                            ?? error.localizedDescription
                        FileHandle.standardError.write(Data("[NotionMCP] 연결 실패(type=\(String(describing: type(of: error))), message=\(message))\n".utf8))
                        notionConnectError = "연결에 실패했습니다. 다시 시도해 주세요."
                    }
                    notionConnectLoading = false
                }
            }
        }
        if let err = notionConnectError {
            Text(err).font(.caption).foregroundColor(.red)
        }
        Text("Notion을 연결하면 회의 목록의 관련 문서 탭에서 문서를 찾을 수 있습니다.")
            .font(.caption)
            .foregroundColor(.secondary)
    }

    private var confluenceSettingsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("사이트 URL (https://회사.atlassian.net)", text: $confluenceBaseURL)
                .textContentType(.URL)
            TextField("이메일", text: $confluenceEmail)
            SecureField("API token", text: $confluenceTokenInput)
            HStack {
                Button("저장") {
                    confluence.setAPIToken(confluenceTokenInput)
                    confluenceTokenInput = ""
                }
                .disabled(confluenceTokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if confluence.isConfigured {
                    Button("연동 해제") {
                        confluence.setAPIToken("")
                        confluenceEmail = ""
                        confluenceBaseURL = ""
                    }
                    .foregroundColor(.red)
                }
            }
            Text("id.atlassian.com의 API tokens에서 토큰을 발급하세요.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func integrationStatusRow(title: String, connected: Bool) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(title).font(.callout)
            Spacer()
            Text(connected ? "연동됨" : "미연동")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - LLM Section Rows

    private var llmProviderRow: some View {
        Picker("공급자", selection: $llmService.selectedProvider) {
            ForEach(LLMCorrectionService.Provider.allCases.filter { $0 != .none }, id: \.self) { provider in
                Text(provider.label).tag(provider)
            }
        }
        .help("교정에 사용할 도구를 선택합니다.")
    }

    @ViewBuilder
    private var currentProviderModelPicker: some View {
        switch llmService.selectedProvider {
        case .codex:
            Picker("교정 모델", selection: $codexModel) {
                ForEach(CodexOAuthService.availableModels, id: \.id) { Text($0.label).tag($0.id) }
            }
            Text("Codex의 ‘자동’은 계정 플랜에 맞춰 안전한 모델을 선택합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .gemini:
            Picker("교정 모델", selection: $geminiModel) {
                ForEach(GeminiOAuthService.availableModels, id: \.id) { Text($0.label).tag($0.id) }
            }
        case .copilot:
            Picker("교정 모델", selection: $copilotModel) {
                ForEach(CopilotOAuthService.availableModels, id: \.id) { Text($0.label).tag($0.id) }
            }
        case .none:
            EmptyView()
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

    private func modelRow(_ model: (id: String, label: String, note: String, memory: String)) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(model.label)
                    .font(.body.weight(.semibold))
                Text(model.note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(model.memory)
                    .font(.caption2)
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

    private var isModelFailed: Bool {
        if case .failed = viewModel.modelState { return true }
        return false
    }

    private func normalizeSelectedModelIfNeeded() {
        if deprecatedModelIDs.contains(selectedModel) {
            selectedModel = "openai_whisper-large-v3-v20240930_turbo"
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
