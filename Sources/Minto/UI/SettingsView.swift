import os
import OSLog
import SwiftUI

private enum LocalLLMContextWindowPreset: String, CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { rawValue }

    var tokenCount: Int {
        switch self {
        case .small:
            return 2_048
        case .medium:
            return 4_608
        case .large:
            return 8_192
        }
    }

    var label: String {
        switch self {
        case .small:
            return "소"
        case .medium:
            return "중"
        case .large:
            return "대"
        }
    }

    var helpText: String {
        switch self {
        case .small:
            return "짧은 회의와 작은 모델에 적합합니다."
        case .medium:
            return "권장값입니다. 대부분의 로컬 모델에서 안정적입니다."
        case .large:
            return "긴 회의에 유리하지만 느리거나 메모리를 더 쓸 수 있습니다."
        }
    }

    static func nearest(to tokenCount: Int) -> Self {
        allCases.min {
            abs($0.tokenCount - tokenCount) < abs($1.tokenCount - tokenCount)
        } ?? .medium
    }
}

public struct SettingsView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    @AppStorage(SpeechEnginePreferences.selectedEngineKey) private var selectedSpeechEngineRaw = SpeechEngineID.defaultEngine.rawValue
    @AppStorage("selectedModel") private var selectedModel = "openai_whisper-large-v3-v20240930_turbo"

    // 교정 provider별 모델 선택(서비스가 같은 UserDefaults 키를 읽는다).
    @AppStorage("codexModel") private var codexModel = CodexOAuthService.defaultModelID
    @AppStorage("geminiModel") private var geminiModel = GeminiOAuthService.defaultModelID
    @AppStorage("copilotModel") private var copilotModel = CopilotOAuthService.defaultModelID
    @AppStorage("gptAPIModel") private var gptAPIModel = LLMAPIKeyTextProvider.defaultModelID(for: .gpt)
    @AppStorage("geminiAPIModel") private var geminiAPIModel = LLMAPIKeyTextProvider.defaultModelID(for: .gemini)
    @AppStorage("claudeAPIModel") private var claudeAPIModel = LLMAPIKeyTextProvider.defaultModelID(for: .claude)
    @AppStorage("openRouterAPIModel") private var openRouterAPIModel = LLMAPIKeyTextProvider.defaultModelID(for: .openRouter)
    @AppStorage(LocalLLMProviderConfiguration.baseURLKey) private var localLLMBaseURL = LocalLLMProviderConfiguration.defaultBaseURL.absoluteString
    @AppStorage(LocalLLMProviderConfiguration.modelIDKey) private var localLLMModelID = ""
    @AppStorage(LocalLLMProviderConfiguration.compatibilityKey) private var localLLMCompatibilityRaw = LocalLLMEndpointCompatibility.ollamaGenerate.rawValue
    @AppStorage(LocalLLMProviderConfiguration.timeoutSecondsKey) private var localLLMTimeoutSeconds = LocalLLMProviderConfiguration.defaultTimeoutSeconds
    @AppStorage(LocalLLMProviderConfiguration.contextWindowKey) private var localLLMContextWindow = LocalLLMProviderConfiguration.defaultContextWindow

    // LLM 교정 서비스 관찰
    @ObservedObject private var llmService = LLMCorrectionService.shared
    @ObservedObject private var summarySettings = LLMSummarySettingsService.shared
    @ObservedObject private var answerSettings = MeetingSearchAnswerSettingsService.shared
    @ObservedObject private var copilot = CopilotOAuthService.shared
    @ObservedObject private var codex = CodexOAuthService.shared

    // Gemini는 ObservableObject가 아니므로 @State로 상태 관리
    @State private var geminiLoggedIn = GeminiOAuthService.shared.isLoggedIn
    @State private var geminiEmail = GeminiOAuthService.shared.email
    @State private var isLoginLoading = false
    @State private var loginError: String? = nil
    @State private var apiKeyInputs: [LLMProviderID: String] = [:]
    @State private var apiModelCatalogs: [LLMProviderID: LLMModelCatalog] = [:]
    @State private var loadingAPIModelProviderIDs: Set<LLMProviderID> = []
    @State private var localLLMModelCatalog: LLMModelCatalog? = nil
    @State private var localLLMModelCatalogKey: String? = nil
    @State private var isLoadingLocalLLMModels = false
    @State private var showLocalLLMAdvancedSettings = false
    @State private var isDetectingLocalLLMCompatibility = false

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
    @State private var speechEngineAvailability: [SpeechEngineID: SpeechEngineAvailability] = [:]
    @State private var isRequestingSpeechAuthorization = false
    @State private var isExportingLogs = false
    @State private var logExportError: String? = nil

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            aiProcessingSection
            if aiConnectionNeeded {
                aiConnectionSection
            }
            GlossarySettingsSection()
            searchReadinessSection
            sourceConnectionsSection

            speechEngineSection

            Section("오버레이") {
                Text("투명도는 메뉴바에서 실시간으로 조절할 수 있습니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("현재 상태") {
                LabeledContent("실행 중인 엔진", value: viewModel.speechEngineID.family.title)
                if viewModel.speechEngineID.family == .localAI {
                    LabeledContent("실행 중인 모델", value: viewModel.speechEngineID.title)
                }
                LabeledContent("엔진 상태", value: modelStateDescription)
                if viewModel.isRecording {
                    LabeledContent("녹음 시간", value: formatDuration(viewModel.recordingDuration))
                }
                VStack(alignment: .leading, spacing: 6) {
                    Button(isExportingLogs ? "로그 내보내는 중…" : "진단 로그 내보내기") {
                        exportDiagnosticLogs()
                    }
                    .buttonStyle(.bordered)
                    .disabled(isExportingLogs)
                    Text("이번 실행 동안 기록된 로그를 내보냅니다. 내보낸 파일에는 앱 동작 기록(이벤트·에러·파일명)이 포함됩니다. 회의 내용(전사·요약·주제)은 포함되지 않습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let error = logExportError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear {
            summarySettings.migrateIfNeeded(from: llmService.selectedProvider)
            normalizeSpeechEngineSelection()
            normalizeAccountModelSelectionIfNeeded()
            normalizeSearchAnswerProviderIfNeeded()
            rememberCurrentProviderIfNeeded()
            Task { await refreshSpeechEngineAvailability() }
        }
        .onChange(of: llmService.selectedProvider) { _, provider in
            if provider != .none {
                lastLLMProviderRaw = provider.rawValue
            }
            syncSearchAnswerProviderWithActiveAIIfNeeded()
            apiKeyInputs = [:]
            loginError = nil
        }
        .onChange(of: summarySettings.selectedProvider) { _, provider in
            if provider != .none {
                lastLLMProviderRaw = provider.rawValue
            }
            syncSearchAnswerProviderWithActiveAIIfNeeded()
            apiKeyInputs = [:]
            loginError = nil
        }
        .onChange(of: answerSettings.selectedProvider) { _, provider in
            if provider != .none {
                lastLLMProviderRaw = provider.rawValue
            }
            apiKeyInputs = [:]
            loginError = nil
        }
    }

    // MARK: - AI Section Rows

    private var aiProcessingSection: some View {
        Section("AI 처리") {
            Toggle(isOn: transcriptionCleanupEnabledBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("전사 다듬기")
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

            Toggle(isOn: meetingSummaryEnabledBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("회의록 정리")
                        .font(.callout.weight(.semibold))
                    Text("요약, 목차, 결정사항, 할 일을 만듭니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .help("회의 종료 후 구조화된 회의록을 생성합니다. 전사 다듬기를 꺼도 사용할 수 있습니다.")

            Toggle(isOn: searchAnswerEnabledBinding) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("검색 답변")
                        .font(.callout.weight(.semibold))
                    Text("저장된 회의 검색 결과를 근거로 질문에 답합니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .help("검색 결과 상위 근거를 선택한 AI 서비스로 보내 종합 답변을 생성합니다.")

            if answerSettings.isEnabled {
                searchAnswerDetailRows
            }

            Text(aiProcessingStateMessage)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var aiConnectionSection: some View {
        Section("AI 연결") {
            aiProviderRow
            currentProviderModelPicker
            if activeAIProvider.requiresWarning {
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

    private var transcriptionCleanupEnabledBinding: Binding<Bool> {
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

    private var meetingSummaryEnabledBinding: Binding<Bool> {
        Binding(
            get: { summarySettings.isEnabled },
            set: { enabled in
                summarySettings.isEnabled = enabled
                if enabled, summarySettings.selectedProvider == .none {
                    summarySettings.selectedProvider = activeAIProvider
                }
            }
        )
    }

    private var searchAnswerEnabledBinding: Binding<Bool> {
        Binding(
            get: { answerSettings.isEnabled },
            set: { enabled in
                answerSettings.isEnabled = enabled
                if enabled {
                    answerSettings.selectedProvider = activeAIProvider
                }
            }
        )
    }

    private var generalAIEnabled: Bool {
        llmService.selectedProvider != .none || summarySettings.isEnabled
    }

    private var aiConnectionNeeded: Bool {
        generalAIEnabled || answerSettings.isEnabled
    }

    private var aiProcessingStateMessage: String {
        switch (llmService.selectedProvider != .none, summarySettings.isEnabled, answerSettings.isEnabled) {
        case (true, true, true):
            return "전사를 다듬고, 회의록을 정리하며, 검색 결과를 AI로 종합합니다."
        case (true, true, false):
            return "전사를 다듬고, 회의록도 자동으로 정리합니다."
        case (true, false, true):
            return "전사를 다듬고, 검색 결과를 AI로 종합합니다."
        case (true, false, false):
            return "전사는 다듬지만, 요약과 구조화는 생성하지 않습니다."
        case (false, true, true):
            return "전사는 원문 그대로 저장하고, 회의록 정리와 검색 답변만 AI로 사용합니다."
        case (false, true, false):
            return "전사는 원문 그대로 저장하고, 회의록 정리만 AI로 생성합니다."
        case (false, false, true):
            return "저장된 회의 검색 결과만 AI로 종합합니다."
        case (false, false, false):
            return "전사만 저장됩니다. 요약과 구조화는 생성되지 않습니다."
        }
    }

    private var restoredLLMProvider: LLMProviderSelection {
        LLMProviderSelection(rawValue: lastLLMProviderRaw) ?? .codex
    }

    private func rememberCurrentProviderIfNeeded() {
        if llmService.selectedProvider != .none {
            lastLLMProviderRaw = llmService.selectedProvider.rawValue
        } else if summarySettings.selectedProvider != .none {
            lastLLMProviderRaw = summarySettings.selectedProvider.rawValue
        } else if answerSettings.selectedProvider != .none {
            lastLLMProviderRaw = answerSettings.selectedProvider.rawValue
        }
    }

    private func normalizeSearchAnswerProviderIfNeeded() {
        guard answerSettings.isEnabled else { return }
        syncSearchAnswerProviderWithActiveAIIfNeeded()
    }

    private func normalizeAccountModelSelectionIfNeeded() {
        if !CodexOAuthService.availableModels.contains(where: { $0.id == codexModel }) {
            codexModel = CodexOAuthService.defaultModelID
        }
        if !GeminiOAuthService.availableModels.contains(where: { $0.id == geminiModel }) {
            geminiModel = GeminiOAuthService.defaultModelID
        }
        if !CopilotOAuthService.availableModels.contains(where: { $0.id == copilotModel }) {
            copilotModel = CopilotOAuthService.defaultModelID
        }
    }

    private func syncSearchAnswerProviderWithActiveAIIfNeeded() {
        guard answerSettings.isEnabled else { return }
        let provider = activeAIProvider
        if provider != .none, provider != answerSettings.selectedProvider {
            answerSettings.selectedProvider = provider
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
                integrationStatusRow(title: "Notion", state: notionIntegrationState)
            }

            DisclosureGroup(isExpanded: $showConfluenceSettings) {
                confluenceSettingsBody
            } label: {
                integrationStatusRow(title: "Confluence", state: confluenceIntegrationState)
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
        if notionIntegrationState == .needsReconnect { return "다음 단계: Notion 다시 연결" }
        if confluenceIntegrationState == .needsReconnect { return "다음 단계: Confluence 다시 연결" }
        if !notionMCP.isConnected { return "다음 단계: Notion 연결" }
        return "다음 단계: Confluence 연결"
    }

    private enum IntegrationConnectionState {
        case disconnected
        case connected
        case needsReconnect
    }

    private var notionIntegrationState: IntegrationConnectionState {
        switch notionMCP.connectionState {
        case .disconnected:
            return .disconnected
        case .connected:
            return .connected
        case .needsReconnect:
            return .needsReconnect
        }
    }

    private var confluenceIntegrationState: IntegrationConnectionState {
        switch confluence.connectionState {
        case .disconnected:
            return .disconnected
        case .connected:
            return .connected
        case .needsReconnect:
            return .needsReconnect
        }
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
            if notionIntegrationState == .needsReconnect {
                Text("저장된 Notion 토큰을 사용할 수 없습니다. 다시 연결해 주세요.")
                    .font(.caption)
                    .foregroundColor(.orange)
                Button("연결 정보 지우기") {
                    notionMCP.disconnect()
                    notionConnectError = nil
                }
                .foregroundColor(.red)
            }
            Button(notionIntegrationState == .needsReconnect ? "Notion 다시 연결" : "Notion 연결") {
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
                        Log.oauth.error("NotionMCP 연결 실패 type=\(String(describing: type(of: error)), privacy: .public) message=\(message, privacy: .public)")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: confluenceStatusIcon)
                    .font(.caption)
                    .foregroundColor(confluenceStatusColor)
                Text(confluenceStatusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                Label("연결 준비", systemImage: "key.fill")
                    .font(.caption.weight(.semibold))
                Text("Atlassian 계정에서 API token을 만든 뒤 사이트 URL, 이메일, token을 입력하세요. Confluence에 내보내려면 페이지 작성 권한이 필요합니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Link(destination: URL(string: "https://id.atlassian.com/manage-profile/security/api-tokens")!) {
                    Label("API token 만들기", systemImage: "arrow.up.right.square")
                }
                .font(.caption.weight(.semibold))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            TextField("사이트 URL (https://회사.atlassian.net)", text: $confluenceBaseURL)
                .textContentType(.URL)
            TextField("이메일", text: $confluenceEmail)
            SecureField(confluence.isConfigured ? "새 API token 입력" : "API token", text: $confluenceTokenInput)
            HStack {
                Button("저장") {
                    confluence.setAPIToken(confluenceTokenInput)
                    confluenceTokenInput = ""
                }
                .disabled(confluenceTokenInput.trimmingCharacters(in: .whitespaces).isEmpty)
                if confluence.canDisconnect {
                    Button("연동 해제") {
                        confluence.disconnect()
                        confluenceEmail = ""
                        confluenceBaseURL = ""
                        confluenceTokenInput = ""
                    }
                    .foregroundColor(.red)
                }
            }
            Text("토큰은 이 Mac의 비밀 저장소에만 저장됩니다. 기본 저장소는 Keychain입니다. 사이트 URL과 이메일은 연결 상태 표시와 API 호출에만 사용됩니다.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var confluenceStatusIcon: String {
        confluenceIntegrationState == .needsReconnect
            ? "exclamationmark.circle.fill"
            : (confluence.isConfigured ? "link.circle.fill" : "link.circle")
    }

    private var confluenceStatusColor: Color {
        switch confluenceIntegrationState {
        case .connected:
            return .green
        case .needsReconnect:
            return .orange
        case .disconnected:
            return .secondary
        }
    }

    private var confluenceStatusMessage: String {
        switch confluenceIntegrationState {
        case .connected:
            return "관련 문서 검색, 회의 시작 문맥 조회, Confluence 내보내기에 사용됩니다."
        case .needsReconnect:
            return "저장된 Confluence token을 사용할 수 없습니다. API token을 다시 저장해 주세요."
        case .disconnected:
            return "연결하면 관련 문서 검색, 회의 시작 문맥 조회, Confluence 내보내기를 사용할 수 있습니다."
        }
    }

    private func integrationStatusRow(title: String, state: IntegrationConnectionState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(integrationStatusColor(for: state))
                .frame(width: 7, height: 7)
            Text(title).font(.callout)
            Spacer()
            Text(integrationStatusText(for: state))
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func integrationStatusColor(for state: IntegrationConnectionState) -> Color {
        switch state {
        case .connected:
            return .green
        case .needsReconnect:
            return .orange
        case .disconnected:
            return Color.secondary.opacity(0.4)
        }
    }

    private func integrationStatusText(for state: IntegrationConnectionState) -> String {
        switch state {
        case .connected:
            return "연동됨"
        case .needsReconnect:
            return "다시 연결 필요"
        case .disconnected:
            return "미연동"
        }
    }

    // MARK: - LLM Section Rows

    private var aiProviderRow: some View {
        Picker("AI 서비스", selection: activeAIProviderBinding) {
            ForEach(LLMProviderSelection.allCases.filter { $0 != .none }, id: \.self) { provider in
                Text(provider.label).tag(provider)
            }
        }
        .help("AI 처리에 사용할 서비스를 선택합니다.")
    }

    private var searchAnswerProviderRow: some View {
        Picker("검색 답변 AI", selection: searchAnswerProviderBinding) {
            ForEach(answerCapableProviderSelections, id: \.self) { provider in
                Text(provider.label).tag(provider)
            }
        }
        .help("저장된 회의 검색 근거를 종합할 AI 서비스를 별도로 선택합니다.")
    }

    @ViewBuilder
    private var searchAnswerDetailRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("검색 답변도 AI 연결의 \(activeAIProvider.label)을 함께 사용합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Text("검색 답변은 상위 회의 근거를 선택한 AI 서비스로 전송합니다. 민감한 회의는 선택한 AI 연결을 확인하세요.")
                .font(.caption)
                .foregroundColor(.orange)
                .fixedSize(horizontal: false, vertical: true)

            if activeAIProviderAuthKind == .accountLogin {
                Text("공식 API 키 방식이 아니며 검색 근거가 해당 계정 서비스로 전송됩니다. 데이터 사용과 학습 여부는 각 앱의 프라이버시 설정에서 제어하세요.")
                    .font(.caption)
                    .foregroundColor(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var currentProviderModelPicker: some View {
        providerModelPicker(activeAIProvider, title: "사용할 모델")
    }

    @ViewBuilder
    private func providerModelPicker(_ provider: LLMProviderSelection, title: String) -> some View {
        switch provider {
        case .local:
            localLLMSettingsRows(title: title)
        case .gptAPI:
            apiModelPicker(title: title, providerID: .gpt, selection: $gptAPIModel)
        case .geminiAPI:
            apiModelPicker(title: title, providerID: .gemini, selection: $geminiAPIModel)
        case .claudeAPI:
            apiModelPicker(title: title, providerID: .claude, selection: $claudeAPIModel)
        case .openRouterAPI:
            apiModelPicker(title: title, providerID: .openRouter, selection: $openRouterAPIModel)
        case .codex:
            Picker(title, selection: $codexModel) {
                ForEach(CodexOAuthService.availableModels, id: \.id) { Text($0.label).tag($0.id) }
            }
            Text("보통은 자동을 그대로 두면 됩니다. 계정 플랜에서 최신 모델을 쓸 수 없으면 안정 모델로 다시 시도합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .gemini:
            Picker(title, selection: $geminiModel) {
                ForEach(GeminiOAuthService.availableModels, id: \.id) { Text($0.label).tag($0.id) }
            }
            Text("Gemini 계정과 Code Assist 권한에 따라 일부 모델은 막힐 수 있습니다. 실패하면 이전 호환 모델로 다시 시도합니다.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .copilot:
            Picker(title, selection: $copilotModel) {
                ForEach(CopilotOAuthService.availableModels, id: \.id) { Text($0.label).tag($0.id) }
            }
            Text("Copilot 계정과 조직 정책에서 허용된 모델만 실제 호출됩니다. 막히면 다른 모델을 선택하세요.")
                .font(.caption)
                .foregroundColor(.secondary)
        case .none:
            EmptyView()
        }
    }

    private var activeAIProvider: LLMProviderSelection {
        if llmService.selectedProvider != .none {
            return llmService.selectedProvider
        }
        if summarySettings.selectedProvider != .none {
            return summarySettings.selectedProvider
        }
        if answerSettings.isEnabled, answerSettings.selectedProvider != .none {
            return answerSettings.selectedProvider
        }
        return restoredLLMProvider
    }

    private var activeAIProviderBinding: Binding<LLMProviderSelection> {
        Binding(
            get: { activeAIProvider },
            set: { provider in
                guard provider != .none else { return }
                lastLLMProviderRaw = provider.rawValue
                if llmService.selectedProvider != .none {
                    llmService.selectedProvider = provider
                }
                if summarySettings.isEnabled {
                    summarySettings.selectedProvider = provider
                }
                if answerSettings.isEnabled {
                    answerSettings.selectedProvider = provider
                }
            }
        )
    }

    private var searchAnswerProviderBinding: Binding<LLMProviderSelection> {
        Binding(
            get: { answerCapableProvider(from: answerSettings.selectedProvider) },
            set: {
                let provider = answerCapableProvider(from: $0)
                answerSettings.selectedProvider = provider
                lastLLMProviderRaw = provider.rawValue
            }
        )
    }

    private var answerCapableProviderSelections: [LLMProviderSelection] {
        LLMProviderSelection.allCases.filter { provider in
            guard provider != .none,
                  let providerID = provider.providerID,
                  let descriptor = LLMProviderRegistry.shared.descriptor(for: providerID)
            else { return false }
            return descriptor.supportedCapabilities.contains(.answer)
        }
    }

    private func answerCapableProvider(from provider: LLMProviderSelection) -> LLMProviderSelection {
        guard provider != .none,
              let providerID = provider.providerID,
              LLMProviderRegistry.shared.descriptor(for: providerID)?.supportedCapabilities.contains(.answer) == true
        else {
            return localLLMConfigurationIsValid ? .local : .gptAPI
        }
        return provider
    }

    @ViewBuilder
    private var searchAnswerConnectionRows: some View {
        let provider = answerCapableProvider(from: answerSettings.selectedProvider)
        if let providerID = provider.providerID {
            VStack(alignment: .leading, spacing: 8) {
                Text("검색 답변 연결")
                    .font(.callout.weight(.semibold))
                Text("\(providerID.displayName)로 상위 회의 근거를 보내 답변을 만듭니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            providerModelPicker(provider, title: "검색 답변 모델")
            if providerID != .local {
                apiKeyStatusRow(providerID)
                apiKeySettingsRow(providerID)
            }
        }
    }

    private func localLLMSettingsRows(title: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            localLLMModelSelectionRows(title: title)

            Picker("문맥 창", selection: localLLMContextPresetBinding) {
                ForEach(LocalLLMContextWindowPreset.allCases) { preset in
                    Text(preset.label).tag(preset)
                }
            }
            .pickerStyle(.segmented)

            Text("\(localLLMContextPreset.label) · \(formattedInteger(localLLMContextWindow)) tokens · \(localLLMContextPreset.helpText)")
                .font(.caption)
                .foregroundColor(.secondary)

            localLLMAdvancedSettingsToggle

            if showLocalLLMAdvancedSettings {
                localLLMAdvancedSettingsRows
            }

            Text("API 키는 필요하지 않습니다. 다만 endpoint가 외부 주소이면 회의 원문이 그 서버로 전송됩니다.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .task(id: localLLMModelCatalogRefreshKey) {
            await refreshLocalLLMModelCatalog(force: false)
        }
    }

    @ViewBuilder
    private func localLLMModelSelectionRows(title: String) -> some View {
        if localLLMCompatibilityValue == .ollamaGenerate,
           let catalog = localLLMModelCatalog,
           catalog.source == .live,
           !catalog.models.isEmpty {
            Picker(title, selection: $localLLMModelID) {
                ForEach(catalog.models, id: \.id) { model in
                    Text(model.displayName).tag(model.id)
                }
            }
            Text("Ollama에서 설치된 모델을 확인했습니다. 모델명은 직접 입력하지 않아도 됩니다.")
                .font(.caption)
                .foregroundColor(.secondary)
            localLLMModelCatalogActionRows
        } else {
            VStack(alignment: .leading, spacing: 6) {
                TextField("모델 ID", text: $localLLMModelID)
                    .textFieldStyle(.roundedBorder)
                Text(localLLMManualModelHelpText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if localLLMCompatibilityValue == .ollamaGenerate {
                    localLLMModelCatalogActionRows
                }
            }
        }
    }

    @ViewBuilder
    private var localLLMModelCatalogActionRows: some View {
        if localLLMCompatibilityValue == .ollamaGenerate {
            HStack(spacing: 8) {
                Text(localLLMModelCatalogStatusText)
                    .font(.caption)
                    .foregroundColor(localLLMRuntimeIsConfirmed ? .secondary : .orange)
                if isLoadingLocalLLMModels {
                    ProgressView()
                        .scaleEffect(0.65)
                }
                Button(localLLMModelCatalog?.source == .live ? "새로고침" : "설치 모델 조회") {
                    Task { await refreshLocalLLMModelCatalog(force: true) }
                }
                .font(.caption)
                .disabled(localLLMBaseURLValue == nil || isLoadingLocalLLMModels)
            }

            if let warning = localLLMModelCatalogWarningText {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
    }

    private var localLLMAdvancedSettingsToggle: some View {
        Button {
            showLocalLLMAdvancedSettings.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: showLocalLLMAdvancedSettings ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Text("고급 설정")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("endpoint, 런타임")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .help("Endpoint URL과 로컬 런타임 형식을 설정합니다.")
    }

    private var localLLMAdvancedSettingsRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("로컬 런타임", selection: $localLLMCompatibilityRaw) {
                ForEach(LocalLLMEndpointCompatibility.allCases) { compatibility in
                    Text(compatibility.displayName).tag(compatibility.rawValue)
                }
            }
            TextField("Endpoint URL", text: $localLLMBaseURL)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button("Endpoint 확인") {
                    Task { await detectLocalLLMCompatibility() }
                }
                .font(.caption)
                .disabled(localLLMBaseURLValue == nil || isDetectingLocalLLMCompatibility)
                if isDetectingLocalLLMCompatibility {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }
            Stepper(value: $localLLMTimeoutSeconds, in: 5...600, step: 5) {
                Text("응답 대기 \(Int(localLLMTimeoutSeconds))초")
                    .font(.caption)
            }
            if localLLMCompatibilityValue != .ollamaGenerate {
                Text(localLLMStatusMessage)
                    .font(.caption)
                    .foregroundColor(localLLMConfigurationIsValid ? .secondary : .orange)
            }
            Text("OpenAI 호환 서버는 LM Studio, llama.cpp server, vLLM처럼 /v1/chat/completions 형식을 제공하는 로컬 또는 사설 서버입니다.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func apiKeyStatusRow(_ providerID: LLMProviderID) -> some View {
        let hasKey = LLMAPIKeyStore.shared.hasAPIKey(for: providerID)
        return HStack(spacing: 6) {
            Circle()
                .fill(hasKey ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(providerID.displayName)
                .font(.callout)
            Spacer()
            Text(hasKey ? "API 키 저장됨" : "API 키 필요")
                .font(.caption)
                .foregroundColor(hasKey ? .primary : .secondary)
        }
    }

    private func apiModelPicker(
        title: String,
        providerID: LLMProviderID,
        selection: Binding<String>
    ) -> some View {
        let catalog = apiModelCatalogs[providerID]
            ?? LLMAPIKeyTextProvider.bundledModelCatalog(for: providerID)
        return VStack(alignment: .leading, spacing: 6) {
            if catalog.models.isEmpty {
                TextField("모델 ID", text: selection)
                    .textFieldStyle(.roundedBorder)
                Text(apiManualModelHelpText(providerID))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker(title, selection: selection) {
                    ForEach(catalog.models, id: \.id) { model in
                        Text(model.displayName).tag(model.id)
                    }
                }
                Text(apiModelSelectionHelpText(catalog, providerID: providerID))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("모델 ID", text: selection)
                            .textFieldStyle(.roundedBorder)
                        Text(apiManualModelHelpText(providerID))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } label: {
                    Text("목록에 없는 모델 ID 직접 입력")
                        .font(.caption)
                }
            }
            HStack(spacing: 6) {
                Text(modelCatalogStatusText(catalog, providerID: providerID))
                    .font(.caption)
                    .foregroundColor(.secondary)
                if loadingAPIModelProviderIDs.contains(providerID) {
                    ProgressView()
                        .scaleEffect(0.65)
                }
                if let url = LLMAPIKeyTextProvider.modelHelpURL(for: providerID) {
                    Link("모델 확인", destination: url)
                        .font(.caption)
                }
                if LLMAPIKeyStore.shared.hasAPIKey(for: providerID) {
                    Button("새로고침") {
                        Task { await refreshAPIModelCatalog(for: providerID, force: true) }
                    }
                    .font(.caption)
                }
            }
            if let warning = catalog.warning {
                Text(warning)
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        }
        .task(id: providerID) {
            await refreshAPIModelCatalog(for: providerID, force: false)
        }
    }

    private func modelCatalogStatusText(_ catalog: LLMModelCatalog, providerID: LLMProviderID) -> String {
        switch catalog.source {
        case .live:
            return "API 키로 확인한 모델 목록입니다."
        case .bundledFallback:
            if LLMAPIKeyStore.shared.hasAPIKey(for: providerID) {
                return "모델 목록을 확인하지 못해 기본 추천 모델을 표시합니다."
            }
            return "API 키를 저장하면 모델 목록을 확인합니다. 지금은 기본 추천 모델을 표시합니다."
        case .manualOnly:
            return "모델 ID를 직접 입력하세요."
        }
    }

    private func apiModelSelectionHelpText(_ catalog: LLMModelCatalog, providerID: LLMProviderID) -> String {
        switch catalog.source {
        case .live:
            return "목록에서 사용할 모델을 선택하면 됩니다. 특별한 이유가 없으면 추천 모델을 유지하세요."
        case .bundledFallback:
            return "\(providerID.displayName)의 기본 추천 모델입니다. API 키를 저장하거나 새로고침하면 실제 사용 가능 모델을 확인합니다."
        case .manualOnly:
            return apiManualModelHelpText(providerID)
        }
    }

    private func apiManualModelHelpText(_ providerID: LLMProviderID) -> String {
        switch providerID {
        case .gpt:
            return "OpenAI Platform의 모델 ID를 입력하세요. 예: gpt-5.5, gpt-5.4-mini"
        case .gemini:
            return "Gemini API 문서의 모델 ID를 입력하세요. 예: gemini-3.5-flash, gemini-3.1-flash-lite"
        case .claude:
            return "Anthropic API의 모델 ID를 입력하세요. 예: claude-sonnet-4-6, claude-haiku-4-5-20251001"
        case .openRouter:
            return "OpenRouter 모델 ID를 입력하세요. 예: openai/gpt-5.5, anthropic/claude-sonnet-4.6"
        case .local, .copilot, .chatGPTAccount, .geminiAccount:
            return "선택한 서비스에서 요구하는 모델 ID를 입력하세요."
        }
    }

    @MainActor
    private func refreshAPIModelCatalog(for providerID: LLMProviderID, force: Bool) async {
        guard force || apiModelCatalogs[providerID] == nil else { return }
        guard let provider = LLMAPIKeyTextProvider(providerID: providerID) else { return }

        loadingAPIModelProviderIDs.insert(providerID)
        let catalog = await provider.modelCatalog()
        apiModelCatalogs[providerID] = catalog
        loadingAPIModelProviderIDs.remove(providerID)
    }

    @MainActor
    private func refreshLocalLLMModelCatalog(force: Bool) async {
        guard localLLMCompatibilityValue == .ollamaGenerate else {
            localLLMModelCatalog = nil
            localLLMModelCatalogKey = nil
            return
        }
        guard localLLMBaseURLValue != nil else {
            localLLMModelCatalog = nil
            localLLMModelCatalogKey = nil
            return
        }
        let refreshKey = localLLMModelCatalogRefreshKey
        guard force || localLLMModelCatalog == nil || localLLMModelCatalogKey != refreshKey else {
            return
        }

        isLoadingLocalLLMModels = true
        let provider = LocalLLMProvider(configuration: localLLMProviderConfiguration)
        let catalog = await provider.modelCatalog()
        localLLMModelCatalog = catalog
        localLLMModelCatalogKey = refreshKey
        isLoadingLocalLLMModels = false
    }

    @MainActor
    private func detectLocalLLMCompatibility() async {
        guard let baseURL = localLLMBaseURLValue else { return }
        isDetectingLocalLLMCompatibility = true
        defer { isDetectingLocalLLMCompatibility = false }

        if await endpointResponds(baseURL.appendingPathComponent("api").appendingPathComponent("tags")) {
            localLLMCompatibilityRaw = LocalLLMEndpointCompatibility.ollamaGenerate.rawValue
            await refreshLocalLLMModelCatalog(force: true)
            return
        }

        if await endpointResponds(baseURL.appendingPathComponent("v1").appendingPathComponent("models")) {
            localLLMCompatibilityRaw = LocalLLMEndpointCompatibility.openAIChatCompletions.rawValue
            localLLMModelCatalog = nil
            localLLMModelCatalogKey = nil
            return
        }

        localLLMModelCatalog = LLMModelCatalog(
            models: [],
            source: .manualOnly,
            warning: "Endpoint에서 Ollama 또는 OpenAI 호환 서버를 확인하지 못했습니다."
        )
        localLLMModelCatalogKey = localLLMModelCatalogRefreshKey
    }

    private func endpointResponds(_ url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(httpResponse.statusCode)
        } catch {
            return false
        }
    }

    private var tosWarningRow: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
                .font(.caption)
            Text("공식 API 키 방식이 아닙니다. 데이터 사용과 학습 여부는 각 앱의 프라이버시 설정에서 제어하세요.")
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
            Text(currentProviderStatusText)
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
        if activeAIProvider == .local {
            EmptyView()
        } else if let providerID = currentAPIKeyProviderID {
            apiKeySettingsRow(providerID)
        } else if currentProviderLoggedIn {
            Button("로그아웃") {
                disconnectCurrentAIProvider()
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

    private func apiKeySettingsRow(_ providerID: LLMProviderID) -> some View {
        let input = apiKeyInputs[providerID] ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            SecureField("\(providerID.displayName) API 키", text: apiKeyInputBinding(for: providerID))
            HStack {
                Button("API 키 저장") {
                    let saved = LLMAPIKeyStore.shared.saveAPIKey(input, for: providerID)
                    if saved {
                        apiKeyInputs[providerID] = ""
                        loginError = nil
                        Task { await refreshAPIModelCatalog(for: providerID, force: true) }
                    } else {
                        loginError = "API 키를 비밀 저장소에 저장하지 못했습니다. macOS 권한 상태를 확인하세요."
                    }
                }
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                if LLMAPIKeyStore.shared.hasAPIKey(for: providerID) {
                    Button("API 키 삭제") {
                        let deleted = LLMAPIKeyStore.shared.deleteAPIKey(for: providerID)
                        if deleted {
                            apiKeyInputs[providerID] = ""
                            apiModelCatalogs[providerID] = nil
                            loginError = nil
                        } else {
                            loginError = "API 키를 비밀 저장소에서 삭제하지 못했습니다. macOS 권한 상태를 확인하세요."
                        }
                    }
                    .foregroundColor(.red)
                }
            }
            Text("API 키는 이 Mac의 비밀 저장소에만 저장됩니다. 기본 저장소는 Keychain입니다. 회의 원문은 선택한 공급자의 API로 전송됩니다.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func apiKeyInputBinding(for providerID: LLMProviderID) -> Binding<String> {
        Binding(
            get: { apiKeyInputs[providerID] ?? "" },
            set: { apiKeyInputs[providerID] = $0 }
        )
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

    private var localLLMBaseURLValue: URL? {
        guard let url = URL(string: localLLMBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host != nil
        else {
            return nil
        }
        return url
    }

    private var localLLMModelIDValue: String {
        localLLMModelID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var localLLMCompatibilityValue: LocalLLMEndpointCompatibility {
        LocalLLMProviderConfiguration.compatibility(from: localLLMCompatibilityRaw)
    }

    private var localLLMContextPreset: LocalLLMContextWindowPreset {
        LocalLLMContextWindowPreset.nearest(to: localLLMContextWindow)
    }

    private var localLLMContextPresetBinding: Binding<LocalLLMContextWindowPreset> {
        Binding(
            get: { localLLMContextPreset },
            set: { localLLMContextWindow = $0.tokenCount }
        )
    }

    private var localLLMProviderConfiguration: LocalLLMProviderConfiguration {
        LocalLLMProviderConfiguration(
            baseURL: localLLMBaseURLValue ?? LocalLLMProviderConfiguration.defaultBaseURL,
            modelID: localLLMModelIDValue,
            compatibility: localLLMCompatibilityValue,
            timeoutSeconds: localLLMTimeoutSeconds,
            contextWindow: localLLMContextWindow
        )
    }

    private var localLLMModelCatalogRefreshKey: String {
        [
            localLLMBaseURL.trimmingCharacters(in: .whitespacesAndNewlines),
            localLLMCompatibilityValue.rawValue
        ].joined(separator: "|")
    }

    private var localLLMConfigurationIsValid: Bool {
        localLLMBaseURLValue != nil && !localLLMModelIDValue.isEmpty
    }

    private var localLLMRuntimeIsConfirmed: Bool {
        guard localLLMConfigurationIsValid else { return false }
        guard localLLMCompatibilityValue == .ollamaGenerate else { return true }
        guard let catalog = localLLMModelCatalog,
              catalog.source == .live
        else {
            return false
        }
        return catalog.models.contains { $0.id == localLLMModelIDValue }
    }

    private var localLLMMissingStatusText: String {
        if localLLMBaseURLValue == nil {
            return "Endpoint URL 확인 필요"
        }
        return "모델 ID 필요"
    }

    private var localLLMStatusMessage: String {
        if localLLMBaseURLValue == nil {
            return "Endpoint URL 형식을 확인하세요."
        }
        if localLLMModelIDValue.isEmpty {
            return "Ollama 또는 llama.cpp 서버에서 사용할 모델 ID를 입력하세요."
        }
        if localLLMCompatibilityValue == .ollamaGenerate {
            return localLLMModelCatalogStatusText
        }
        return "OpenAI 호환 런타임은 표준 모델 목록 조회가 없어 입력한 모델 ID를 그대로 사용합니다."
    }

    private var localLLMManualModelHelpText: String {
        switch localLLMCompatibilityValue {
        case .ollamaGenerate:
            return "설치 모델을 조회할 수 없을 때만 직접 입력하세요. Ollama에서는 `ollama list`의 NAME 값을 사용합니다. 예: llama3.1:8b"
        case .openAIChatCompletions:
            return "LM Studio, llama.cpp server, vLLM 같은 서버가 요구하는 모델 ID를 입력하세요. 서버의 모델 목록이나 실행 로그에 표시된 이름을 그대로 쓰면 됩니다."
        }
    }

    private var localLLMModelCatalogStatusText: String {
        if localLLMBaseURLValue == nil {
            return "Endpoint URL을 입력하면 설치 모델을 조회할 수 있습니다."
        }
        if isLoadingLocalLLMModels {
            return "Ollama 설치 모델을 확인하는 중입니다."
        }
        guard let catalog = localLLMModelCatalog else {
            return "설치 모델 조회로 실제 모델 존재 여부를 확인하세요."
        }
        if catalog.source != .live {
            return "Ollama 모델 목록을 확인하지 못했습니다."
        }
        if catalog.models.isEmpty {
            return "Ollama에 설치된 모델이 없습니다."
        }
        if localLLMModelIDValue.isEmpty {
            return "설치된 모델 \(catalog.models.count)개 중 하나를 선택하세요."
        }
        if catalog.models.contains(where: { $0.id == localLLMModelIDValue }) {
            return "설치된 모델 확인됨: \(localLLMModelIDValue)"
        }
        return "입력한 모델이 설치 목록에 없습니다."
    }

    private var localLLMModelCatalogWarningText: String? {
        guard let catalog = localLLMModelCatalog else { return nil }
        if catalog.source != .live || catalog.models.isEmpty {
            return catalog.warning
        }
        return nil
    }

    private var currentProviderLoggedIn: Bool {
        switch activeAIProvider {
        case .none:
            return false
        case .local:
            return localLLMRuntimeIsConfirmed
        case .gptAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .gpt)
        case .geminiAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .gemini)
        case .claudeAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .claude)
        case .openRouterAPI:
            return LLMAPIKeyStore.shared.hasAPIKey(for: .openRouter)
        case .gemini:
            return geminiLoggedIn
        case .copilot:
            return copilot.isLoggedIn
        case .codex:
            return codex.isLoggedIn
        }
    }

    private var currentProviderStatusText: String {
        if activeAIProvider == .local {
            if !localLLMConfigurationIsValid {
                return localLLMMissingStatusText
            }
            if localLLMRuntimeIsConfirmed {
                return localLLMCompatibilityValue == .ollamaGenerate ? "설치 모델 확인됨" : "로컬 런타임 설정됨"
            }
            return localLLMCompatibilityValue == .ollamaGenerate ? "모델 확인 필요" : "로컬 런타임 설정됨"
        }
        if currentAPIKeyProviderID != nil {
            return currentProviderLoggedIn ? "API 키 저장됨" : "API 키 필요"
        }
        return currentProviderLoggedIn ? "로그인됨" : "미연결"
    }

    private var currentEmail: String {
        switch activeAIProvider {
        case .none, .local, .gptAPI, .geminiAPI, .claudeAPI, .openRouterAPI, .codex:
            return ""
        case .gemini:
            return geminiEmail
        case .copilot:
            return copilot.email
        }
    }

    private var deviceCodeInProgress: Bool {
        switch activeAIProvider {
        case .copilot: return copilot.isPolling
        case .codex:   return codex.isPolling
        default:       return false
        }
    }

    private var currentAPIKeyProviderID: LLMProviderID? {
        switch activeAIProvider {
        case .gptAPI:
            return .gpt
        case .geminiAPI:
            return .gemini
        case .claudeAPI:
            return .claude
        case .openRouterAPI:
            return .openRouter
        case .none, .local, .gemini, .copilot, .codex:
            return nil
        }
    }

    private var activeAIProviderAuthKind: LLMProviderAuthKind? {
        guard let providerID = activeAIProvider.providerID else { return nil }
        return LLMProviderRegistry.shared.descriptor(for: providerID)?.authKind
    }

    private var currentDeviceCode: String {
        switch activeAIProvider {
        case .copilot: return copilot.deviceCode
        case .codex:   return codex.deviceCode
        default:       return ""
        }
    }

    // MARK: - Login flows

    private func startLogin() {
        isLoginLoading = true
        switch activeAIProvider {
        case .none, .local, .gptAPI, .geminiAPI, .claudeAPI, .openRouterAPI:
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

    private func disconnectCurrentAIProvider() {
        switch activeAIProvider {
        case .none, .local:
            break
        case .gptAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .gpt)
        case .geminiAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .gemini)
        case .claudeAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .claude)
        case .openRouterAPI:
            LLMAPIKeyStore.shared.deleteAPIKey(for: .openRouter)
        case .gemini:
            GeminiOAuthService.shared.logout()
        case .copilot:
            CopilotOAuthService.shared.logout()
        case .codex:
            CodexOAuthService.shared.logout()
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

    // MARK: - Speech engine section helpers

    private var speechEngineSection: some View {
        Section("음성 인식 엔진") {
            speechEngineGuide
            activeSpeechEngineStatus

            ForEach(SpeechEngineFamily.allCases) { family in
                speechEngineFamilyRow(family)

                if family == .localAI, selectedSpeechEngineFamily == .localAI {
                    localModelPicker
                }

                if family == .sfSpeechOnDevice, sfSpeechNeedsPermission {
                    Button {
                        Task { await requestSpeechAuthorization() }
                    } label: {
                        if isRequestingSpeechAuthorization {
                            HStack {
                                ProgressView().scaleEffect(0.8)
                                Text("권한 요청 중...")
                            }
                        } else {
                            Text("Apple 음성 인식 권한 허용하기")
                        }
                    }
                    .disabled(isRequestingSpeechAuthorization)
                }
            }

            Text("사용할 수 없는 엔진은 현재 기기, macOS 버전, 권한, 한국어 언어 파일 상태를 기준으로 비활성화됩니다.")
                .font(.caption)
                .foregroundColor(.secondary)

            Button("지금 바로 엔진 전환") {
                Task { await applySelectedSpeechEngine() }
            }
            .disabled(isModelBusy || !selectedSpeechEngineAvailability.isSelectable)

            if selectedSpeechEngineID == .sfSpeechOnDevice {
                Label("Apple 기본 받아쓰기는 온디바이스 전용 요청으로 실행합니다.", systemImage: "shield.checkered")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
            }

            if selectedSpeechEngineID.supportsCacheRecovery, isModelFailed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("모델 파일이 손상되었거나 권한 문제로 열리지 않습니다.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("캐시 정리 후 모델 다시 받기") {
                        Task {
                            await viewModel.recoverModelCacheAndReload(
                                variant: selectedSpeechEngineID.whisperVariant ?? selectedModel
                            )
                        }
                    }
                    .disabled(isModelBusy)
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var speechEngineGuide: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("대부분은 로컬 AI 엔진을 선택하고, 모델은 정확도 우선을 쓰면 됩니다.", systemImage: "checkmark.seal.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            Text("Apple 기본 받아쓰기는 온디바이스 전용 요청으로 실행합니다.")
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.accentColor.opacity(0.08))
        )
    }

    private var activeSpeechEngineStatus: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent("현재 실행 중", value: activeSpeechEngineText)
                .font(.system(size: 13))
            if isPendingSpeechEngineSelection {
                LabeledContent("선택 예정", value: pendingSpeechEngineText)
                    .font(.system(size: 13))
                    .foregroundColor(.orange)
            }
            LabeledContent("작동 상태", value: modelStateDescription)
                .font(.system(size: 13))
            Text("전환 버튼을 누른 뒤 현재 실행 중 값이 원하는 엔진으로 바뀌고 작동 상태가 로드됨이면 실제로 적용된 상태입니다.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func speechEngineFamilyRow(_ family: SpeechEngineFamily) -> some View {
        let availability = availability(for: family)
        return Button {
            selectSpeechEngineFamily(family)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                engineIcon(for: family)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(family.title)
                            .font(.system(size: 15, weight: .semibold))
                        choiceBadge(for: family)
                    }

                    Text(family.bestFor)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)

                    Text(family.caution)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        ForEach(family.choiceChips, id: \.self) { chip in
                            engineChip(chip, tint: family.tint)
                        }
                        Text(family.requirementNote)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }

                    if let detail = availability.detailText {
                        Text(detail)
                            .font(.system(size: 12))
                            .foregroundColor(.orange)
                    }
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    statusBadge(for: availability)
                    if viewModel.speechEngineID.family == family {
                        Text("실행 중")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.accentColor)
                    }
                    if selectedSpeechEngineFamily == family {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.accentColor)
                            .fontWeight(.semibold)
                            .accessibilityLabel("선택됨")
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 8)
            .background(selectionBackground(isSelected: selectedSpeechEngineFamily == family))
            .overlay(selectionBorder(isSelected: selectedSpeechEngineFamily == family))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(family.technicalName) · \(family.requirementNote)")
        .disabled(!availability.isSelectable)
        .opacity(availability.isSelectable ? 1 : 0.58)
    }

    private var localModelPicker: some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle()
                .fill(SpeechEngineFamily.localAI.tint.opacity(0.32))
                .frame(width: 3)
                .clipShape(Capsule())
                .padding(.vertical, 8)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("로컬 AI 안에서 모델 선택")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    Text("위 로컬 AI 엔진을 선택했을 때 사용할 실제 전사 모델입니다.")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                ForEach(SpeechEngineID.localModelOptions) { model in
                    localModelRow(model)
                }
            }
        }
        .padding(.leading, 38)
        .padding(.trailing, 8)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(SpeechEngineFamily.localAI.tint.opacity(0.06))
        )
    }

    private func localModelRow(_ model: SpeechEngineID) -> some View {
        Button {
            selectLocalModel(model)
        } label: {
            HStack(alignment: .top, spacing: 10) {
                engineIcon(for: model)
                    .scaleEffect(0.9)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(model.title)
                            .font(.system(size: 13, weight: .semibold))
                        choiceBadge(for: model)
                    }
                    Text(model.bestFor)
                        .font(.system(size: 12))
                        .foregroundColor(.primary)
                    Text(model.caution)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        ForEach(model.choiceChips, id: \.self) { chip in
                            engineChip(chip, tint: model.tint)
                        }
                    }
                }

                Spacer(minLength: 8)

                if viewModel.speechEngineID == model {
                    Text("실행 중")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.accentColor)
                }
                if selectedSpeechEngineID == model {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                        .fontWeight(.semibold)
                        .accessibilityLabel("선택됨")
                }
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(selectionBackground(isSelected: selectedSpeechEngineID == model))
            .overlay(selectionBorder(isSelected: selectedSpeechEngineID == model))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(model.technicalName) · \(model.requirementNote)")
    }

    private func engineChip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(tint.opacity(0.08))
            )
    }

    private func statusBadge(for availability: SpeechEngineAvailability) -> some View {
        Text(availability.statusText)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(statusColor(for: availability))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(statusColor(for: availability).opacity(0.12))
            .clipShape(Capsule())
    }

    private func statusColor(for availability: SpeechEngineAvailability) -> Color {
        switch availability {
        case .checking:
            return .blue
        case .available:
            return .green
        case .requiresPermission:
            return .orange
        case .unavailable:
            return .secondary
        }
    }

    private var selectedSpeechEngineID: SpeechEngineID {
        SpeechEngineID(rawValue: selectedSpeechEngineRaw) ?? .defaultEngine
    }

    private var selectedSpeechEngineFamily: SpeechEngineFamily {
        selectedSpeechEngineID.family
    }

    private var selectedLocalModelID: SpeechEngineID {
        if selectedSpeechEngineID.family == .localAI {
            return selectedSpeechEngineID
        }
        return SpeechEngineID.fromWhisperVariant(selectedModel)
    }

    private var selectedSpeechEngineAvailability: SpeechEngineAvailability {
        availability(for: selectedSpeechEngineID)
    }

    private var activeSpeechEngineText: String {
        let active = viewModel.speechEngineID
        if active.family == .localAI {
            return "\(active.family.title) · \(active.title)"
        }
        return active.family.title
    }

    private var pendingSpeechEngineText: String {
        if selectedSpeechEngineID.family == .localAI {
            return "\(selectedSpeechEngineID.family.title) · \(selectedSpeechEngineID.title)"
        }
        return selectedSpeechEngineID.family.title
    }

    private var isPendingSpeechEngineSelection: Bool {
        selectedSpeechEngineID != viewModel.speechEngineID
    }

    private var sfSpeechNeedsPermission: Bool {
        if case .requiresPermission = availability(for: SpeechEngineID.sfSpeechOnDevice) {
            return true
        }
        return false
    }

    private func availability(for family: SpeechEngineFamily) -> SpeechEngineAvailability {
        switch family {
        case .localAI:
            return availability(for: selectedLocalModelID)
        case .speechAnalyzer, .sfSpeechOnDevice:
            return availability(for: family.representativeEngine)
        }
    }

    private func availability(for engine: SpeechEngineID) -> SpeechEngineAvailability {
        if let availability = speechEngineAvailability[engine] {
            return availability
        }
        return engine.whisperVariant == nil ? .checking("가용성을 확인하고 있습니다.") : .available
    }

    private func selectSpeechEngineFamily(_ family: SpeechEngineFamily) {
        switch family {
        case .localAI:
            selectSpeechEngine(selectedLocalModelID)
        case .speechAnalyzer:
            selectSpeechEngine(.speechAnalyzer)
        case .sfSpeechOnDevice:
            selectSpeechEngine(.sfSpeechOnDevice)
        }
    }

    private func selectLocalModel(_ model: SpeechEngineID) {
        guard model.family == .localAI else { return }
        selectSpeechEngine(model)
    }

    private func selectSpeechEngine(_ engine: SpeechEngineID) {
        selectedSpeechEngineRaw = engine.rawValue
        if let variant = engine.whisperVariant {
            selectedModel = variant
        }
    }

    private func normalizeSpeechEngineSelection() {
        SpeechEnginePreferences.normalizeLegacyValues()
        selectedSpeechEngineRaw = SpeechEnginePreferences.selectedEngine().rawValue
        if let variant = selectedSpeechEngineID.whisperVariant {
            selectedModel = variant
        }
    }

    private func refreshSpeechEngineAvailability() async {
        var refreshed: [SpeechEngineID: SpeechEngineAvailability] = [:]
        for engine in SpeechEngineID.allCases {
            refreshed[engine] = await STTService.engineAvailability(for: engine)
        }
        speechEngineAvailability = refreshed
    }

    private func requestSpeechAuthorization() async {
        isRequestingSpeechAuthorization = true
        speechEngineAvailability[.sfSpeechOnDevice] = await STTService.requestSFSpeechAuthorization()
        isRequestingSpeechAuthorization = false
    }

    private func applySelectedSpeechEngine() async {
        if let variant = selectedSpeechEngineID.whisperVariant {
            selectedModel = variant
        }
        await viewModel.loadSpeechEngine(selectedSpeechEngineID)
        await refreshSpeechEngineAvailability()
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

    private func formattedInteger(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func exportDiagnosticLogs() {
        isExportingLogs = true
        logExportError = nil
        Task { @MainActor in
            defer { isExportingLogs = false }
            do {
                // scope: .currentProcessIdentifier — 현재 프로세스 세션 로그만 수집
                let store = try OSLogStore(scope: .currentProcessIdentifier)
                let subsystem = Bundle.main.bundleIdentifier ?? "com.minto.app"
                let predicate = NSPredicate(format: "subsystem == %@", subsystem)
                // position(date:) 대신 프로세스 첫 항목부터 수집 (현재 실행 분만 해당)
                let entries = try store.getEntries(
                    with: [],
                    at: store.position(timeIntervalSinceLatestBoot: 0),
                    matching: predicate
                )
                var lines: [String] = []
                for entry in entries {
                    if let logEntry = entry as? OSLogEntryLog {
                        // 주의: 같은 프로세스에서 읽는 composedMessage는 privacy 마스킹이
                        // 적용되지 않은 원문이다. 내보내기 안전의 전제는 마스킹이 아니라
                        // "Logger에 전사·주제·검색어·절대경로 같은 민감/식별 값을 넣지 않기"다.
                        lines.append("[\(logEntry.date)] [\(logEntry.category)] \(logEntry.composedMessage)")
                    }
                }

                guard !lines.isEmpty else {
                    logExportError = "내보낼 로그가 없습니다."
                    Log.app.info("log export: no entries found")
                    return
                }

                let content = lines.joined(separator: "\n")
                guard let data = content.data(using: .utf8) else { return }

                // beginSheetModal(for:) 대신 begin { } — keyWindow nil 시 무음 실패 방지
                let panel = NSSavePanel()
                panel.nameFieldStringValue = "minto-diagnostic-logs.txt"
                panel.allowedContentTypes = [.plainText]
                let result = await withCheckedContinuation { continuation in
                    panel.begin { response in
                        continuation.resume(returning: response)
                    }
                }
                guard result == .OK, let url = panel.url else { return }
                try data.write(to: url, options: .atomic)
                Log.app.info("log export success lines=\(lines.count, privacy: .public)")
            } catch {
                Log.app.error("log export failed: \(error.localizedDescription, privacy: .public)")
                logExportError = "로그 내보내기 실패: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - SpeechEngine 표시 헬퍼 (SpeechEngineDisplay.swift의 SpeechEngineDisplayable 사용)

    private func engineIcon(for item: some SpeechEngineDisplayable) -> some View {
        Image(systemName: item.iconName)
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(item.tint)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(item.tint.opacity(0.12))
            )
    }

    private func choiceBadge(for item: some SpeechEngineDisplayable) -> some View {
        Text(item.badgeLabel)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(item.tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(item.tint.opacity(0.12))
            )
    }

    private func selectionBackground(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(isSelected ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private func selectionBorder(isSelected: Bool) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(isSelected ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 1)
    }
}
