import Foundation

@MainActor
public final class MeetingSearchAnswerController: ObservableObject {
    @Published public private(set) var answer: MeetingSearchAnswer?
    @Published public private(set) var answerQuery = ""
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var isGenerating = false
    @Published public private(set) var isProviderReady = false
    @Published public private(set) var isCheckingProvider = false

    private let settings: MeetingSearchAnswerSettingsService
    private let useCase: MeetingSearchAnswerUseCase
    private let providerResolver: @MainActor () -> (any LLMTextGenerationProvider)?
    private let notificationCenter: NotificationCenter
    private var generationTask: Task<Void, Never>?
    private var readinessTask: Task<Void, Never>?
    private var apiKeyObserver: NotificationObserverToken?
    private var generationToken = UUID()

    public init(
        settings: MeetingSearchAnswerSettingsService = .shared,
        useCase: MeetingSearchAnswerUseCase = MeetingSearchAnswerUseCase(),
        providerResolver: (@MainActor () -> (any LLMTextGenerationProvider)?)? = nil,
        notificationCenter: NotificationCenter = .default
    ) {
        self.settings = settings
        self.useCase = useCase
        self.providerResolver = providerResolver ?? { settings.selectedTextProvider() }
        self.notificationCenter = notificationCenter
        self.apiKeyObserver = NotificationObserverToken(notificationCenter.addObserver(
            forName: .llmAPIKeyStoreDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshReadiness()
            }
        })
    }

    deinit {
        generationTask?.cancel()
        readinessTask?.cancel()
        if let apiKeyObserver {
            notificationCenter.removeObserver(apiKeyObserver.value)
        }
    }

    public func reset(clearReadiness: Bool = false) {
        generationTask?.cancel()
        generationToken = UUID()
        answer = nil
        answerQuery = ""
        errorMessage = nil
        isGenerating = false
        if clearReadiness {
            readinessTask?.cancel()
            isProviderReady = false
            isCheckingProvider = false
        }
    }

    public func canGenerate(query: String, resultCount: Int) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && resultCount > 0
            && !isGenerating
            && isProviderReady
    }

    public func hintText(query: String, resultCount: Int) -> String {
        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "검색어를 입력하면 저장된 회의 근거로 답변할 수 있습니다."
        }
        if resultCount == 0 {
            return "검색 결과가 있으면 AI가 회의 근거만 사용해 답변할 수 있습니다."
        }
        if !settings.isEnabled {
            return "설정에서 검색 답변을 켜면 상위 회의 근거를 AI가 종합합니다."
        }
        guard let providerID = settings.selectedProvider.providerID,
              let descriptor = LLMProviderRegistry.shared.descriptor(for: providerID)
        else {
            return "검색 답변에 사용할 AI 서비스를 선택하세요."
        }
        guard descriptor.supportedCapabilities.contains(.answer) else {
            return "현재 선택한 AI 서비스는 검색 답변을 지원하지 않습니다. AI 연결에서 다른 서비스를 선택하세요."
        }
        guard isProviderReady else {
            return "검색 답변 AI 설정을 완료하세요. 로컬 런타임, 로그인, API 키 중 선택한 연결 방식이 준비되어야 합니다."
        }
        return descriptor.id.isCloudProvider
            ? "상위 검색 근거가 선택한 AI 서비스로 전송됩니다."
            : "검색 결과 \(resultCount)개를 근거로 답변을 만들 수 있습니다."
    }

    public func refreshReadiness() {
        readinessTask?.cancel()
        isProviderReady = false
        guard let provider = providerResolver() else {
            isCheckingProvider = false
            return
        }
        isCheckingProvider = true
        readinessTask = Task {
            let ready = await provider.isConfigured()
            await MainActor.run {
                guard !Task.isCancelled else { return }
                isProviderReady = ready
                isCheckingProvider = false
            }
        }
    }

    public func generate(query: String, index: MeetingSearchIndex) {
        generate(query: query, results: index.search(query, limit: Int.max))
    }

    public func generate(query: String, results: [MeetingSearchResult]) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let provider = providerResolver() else {
            errorMessage = hintText(query: trimmed, resultCount: results.count)
            return
        }
        guard isProviderReady else {
            errorMessage = "검색 답변 AI 설정을 완료하세요. 로컬 런타임, 로그인, API 키 중 선택한 연결 방식이 준비되어야 합니다."
            return
        }

        generationTask?.cancel()
        answer = nil
        answerQuery = trimmed
        errorMessage = nil
        isGenerating = true
        let token = UUID()
        generationToken = token

        generationTask = Task {
            do {
                let generated = try await useCase.answer(query: trimmed, results: results, provider: provider)
                await MainActor.run {
                    guard generationToken == token else { return }
                    answer = generated
                    errorMessage = nil
                    isGenerating = false
                }
            } catch is CancellationError {
                await MainActor.run {
                    guard generationToken == token else { return }
                    isGenerating = false
                }
            } catch {
                let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                await MainActor.run {
                    guard generationToken == token else { return }
                    answer = nil
                    errorMessage = message
                    isGenerating = false
                }
            }
        }
    }
}

private final class NotificationObserverToken: @unchecked Sendable {
    let value: NSObjectProtocol

    init(_ value: NSObjectProtocol) {
        self.value = value
    }
}
