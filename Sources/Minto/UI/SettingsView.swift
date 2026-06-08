import SwiftUI

public struct SettingsView: View {
    @ObservedObject public var viewModel: TranscriptionViewModel
    @AppStorage(SpeechEnginePreferences.selectedEngineKey) private var selectedSpeechEngineRaw = SpeechEngineID.defaultEngine.rawValue
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
    @State private var speechEngineAvailability: [SpeechEngineID: SpeechEngineAvailability] = [:]
    @State private var isRequestingSpeechAuthorization = false

    public init(viewModel: TranscriptionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
            llmCorrectionSection
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
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
        .onAppear {
            normalizeSpeechEngineSelection()
            rememberCurrentProviderIfNeeded()
            Task { await refreshSpeechEngineAvailability() }
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
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: confluence.isConfigured ? "link.circle.fill" : "link.circle")
                    .font(.caption)
                    .foregroundColor(confluence.isConfigured ? .green : .secondary)
                Text(confluence.isConfigured
                     ? "회의 목록 관련 문서 검색과 회의 시작의 Confluence 문맥 조회에 함께 사용됩니다."
                     : "연결하면 회의 목록 관련 문서 검색과 회의 시작의 Confluence 문맥 조회에서 함께 사용됩니다.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

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
                            engineChip(chip, tint: engineTint(for: family))
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
            .background(selectionBackground(for: family))
            .overlay(selectionBorder(for: family))
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
                .fill(engineTint(for: SpeechEngineFamily.localAI).opacity(0.32))
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
                .fill(engineTint(for: SpeechEngineFamily.localAI).opacity(0.06))
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
                            engineChip(chip, tint: engineTint(for: model))
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
            .background(selectionBackground(for: model))
            .overlay(selectionBorder(for: model))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(model.technicalName) · \(model.requirementNote)")
    }

    private func engineIcon(for family: SpeechEngineFamily) -> some View {
        Image(systemName: engineIconName(for: family))
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(engineTint(for: family))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(engineTint(for: family).opacity(0.12))
            )
    }

    private func engineIcon(for model: SpeechEngineID) -> some View {
        Image(systemName: engineIconName(for: model))
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(engineTint(for: model))
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(engineTint(for: model).opacity(0.12))
            )
    }

    private func choiceBadge(for family: SpeechEngineFamily) -> some View {
        Text(family.choiceBadge)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(engineTint(for: family))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(engineTint(for: family).opacity(0.12))
            )
    }

    private func choiceBadge(for model: SpeechEngineID) -> some View {
        Text(model.choiceBadge)
            .font(.system(size: 12, weight: .bold))
            .foregroundColor(engineTint(for: model))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule()
                    .fill(engineTint(for: model).opacity(0.12))
            )
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

    private func selectionBackground(for family: SpeechEngineFamily) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedSpeechEngineFamily == family ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private func selectionBorder(for family: SpeechEngineFamily) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(selectedSpeechEngineFamily == family ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 1)
    }

    private func selectionBackground(for model: SpeechEngineID) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(selectedSpeechEngineID == model ? Color.accentColor.opacity(0.08) : Color.clear)
    }

    private func selectionBorder(for model: SpeechEngineID) -> some View {
        RoundedRectangle(cornerRadius: 8)
            .stroke(selectedSpeechEngineID == model ? Color.accentColor.opacity(0.32) : Color.clear, lineWidth: 1)
    }

    private func engineIconName(for family: SpeechEngineFamily) -> String {
        switch family {
        case .localAI:
            return "checkmark.seal.fill"
        case .speechAnalyzer:
            return "sparkles"
        case .sfSpeechOnDevice:
            return "lock.shield.fill"
        }
    }

    private func engineIconName(for model: SpeechEngineID) -> String {
        switch model {
        case .whisperAccurate:
            return "checkmark.seal.fill"
        case .whisperBalanced:
            return "slider.horizontal.3"
        case .whisperFast:
            return "bolt.fill"
        case .speechAnalyzer:
            return "sparkles"
        case .sfSpeechOnDevice:
            return "lock.shield.fill"
        }
    }

    private func engineTint(for family: SpeechEngineFamily) -> Color {
        switch family {
        case .localAI:
            return .green
        case .speechAnalyzer:
            return .indigo
        case .sfSpeechOnDevice:
            return .teal
        }
    }

    private func engineTint(for model: SpeechEngineID) -> Color {
        switch model {
        case .whisperAccurate:
            return .green
        case .whisperBalanced:
            return .blue
        case .whisperFast:
            return .orange
        case .speechAnalyzer:
            return .indigo
        case .sfSpeechOnDevice:
            return .teal
        }
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
        UserDefaults.standard.set(engine.rawValue, forKey: SpeechEnginePreferences.selectedEngineKey)
        if let variant = engine.whisperVariant {
            selectedModel = variant
            UserDefaults.standard.set(variant, forKey: SpeechEnginePreferences.selectedModelKey)
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
            UserDefaults.standard.set(variant, forKey: SpeechEnginePreferences.selectedModelKey)
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
}
