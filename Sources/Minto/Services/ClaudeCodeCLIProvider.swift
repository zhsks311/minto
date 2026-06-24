import Foundation

struct ProcessResult: Sendable {
    let exitCode: Int32
    let stdout: Data
    let stderr: Data
}

protocol ProcessLauncher: Sendable {
    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        stdin: Data,
        timeout: Duration
    ) async throws -> ProcessResult
}

final class FoundationProcessLauncher: ProcessLauncher, @unchecked Sendable {
    private static let activeProcesses = RunningProcessRegistry()

    @discardableResult
    static func terminateRunningProcesses() -> Int {
        activeProcesses.terminateAll()
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        stdin: Data,
        timeout: Duration
    ) async throws -> ProcessResult {
        let handle = RunningProcessHandle()
        return try await withTaskCancellationHandler {
            try await runProcess(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                currentDirectory: currentDirectory,
                stdin: stdin,
                timeout: timeout,
                handle: handle
            )
        } onCancel: {
            handle.terminate()
        }
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        stdin: Data,
        timeout: Duration,
        handle: RunningProcessHandle
    ) async throws -> ProcessResult {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        let exitObserver = ProcessExitObserver()

        process.executableURL = executableURL
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = currentDirectory
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe
        process.terminationHandler = { process in
            let exitCode = process.terminationStatus
            Task {
                await exitObserver.finish(exitCode)
            }
        }

        let stdoutTask = Task {
            (try? stdoutPipe.fileHandleForReading.readToEnd()) ?? Data()
        }
        let stderrTask = Task {
            (try? stderrPipe.fileHandleForReading.readToEnd()) ?? Data()
        }

        do {
            handle.set(process)
            try process.run()
        } catch {
            handle.clear()
            Self.stopIO(
                stdoutTask: stdoutTask,
                stderrTask: stderrTask,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdinPipe: stdinPipe
            )
            throw error
        }
        Self.activeProcesses.insert(handle)
        defer {
            Self.activeProcesses.remove(handle)
            handle.clear()
        }

        let stdinTask = Task {
            try? stdinPipe.fileHandleForWriting.write(contentsOf: stdin)
            try? stdinPipe.fileHandleForWriting.close()
        }

        let exitCode: Int32
        do {
            exitCode = try await Self.waitForExit(exitObserver, timeout: timeout)
        } catch ProcessLauncherError.timedOut {
            handle.terminate()
            Self.stopIO(
                stdoutTask: stdoutTask,
                stderrTask: stderrTask,
                stdinTask: stdinTask,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdinPipe: stdinPipe
            )
            throw ProcessLauncherError.timedOut
        } catch is CancellationError {
            handle.terminate()
            Self.stopIO(
                stdoutTask: stdoutTask,
                stderrTask: stderrTask,
                stdinTask: stdinTask,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdinPipe: stdinPipe
            )
            throw CancellationError()
        } catch {
            handle.terminate()
            Self.stopIO(
                stdoutTask: stdoutTask,
                stderrTask: stderrTask,
                stdinTask: stdinTask,
                stdoutPipe: stdoutPipe,
                stderrPipe: stderrPipe,
                stdinPipe: stdinPipe
            )
            throw error
        }

        _ = await stdinTask.result
        let stdout = await stdoutTask.value
        let stderr = await stderrTask.value
        return ProcessResult(exitCode: exitCode, stdout: stdout, stderr: stderr)
    }

    private static func waitForExit(_ observer: ProcessExitObserver, timeout: Duration) async throws -> Int32 {
        try await withThrowingTaskGroup(of: Int32.self) { group in
            group.addTask {
                await observer.wait()
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw ProcessLauncherError.timedOut
            }

            guard let exitCode = try await group.next() else {
                throw ProcessLauncherError.timedOut
            }
            group.cancelAll()
            return exitCode
        }
    }

    private static func stopIO(
        stdoutTask: Task<Data, Never>,
        stderrTask: Task<Data, Never>,
        stdinTask: Task<Void, Never>? = nil,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        stdinPipe: Pipe
    ) {
        stdinTask?.cancel()
        stdoutTask.cancel()
        stderrTask.cancel()
        try? stdinPipe.fileHandleForWriting.close()
        try? stdoutPipe.fileHandleForReading.close()
        try? stderrPipe.fileHandleForReading.close()
    }
}

private enum ClaudeCodeCLIOperation: String {
    case generate
    case connectionCheck
}

private struct ClaudeCodeCLIRunResult: Sendable {
    let text: String
    let executableURL: URL
    let warnings: [String]
}

public final class ClaudeCodeCLIProvider: LLMTextGenerationProvider, @unchecked Sendable {
    public static let cliPathKey = "claudeCodeCLIPath"
    public static let modelDefaultsKey = "claudeCodeCLIModel"
    public static let defaultModelID = "sonnet"

    private static let defaultTimeout: Duration = .seconds(60)
    private static let maxStdinBytes = 10 * 1024 * 1024
    private static let anthropicAPIKeyEnvironmentName = "ANTHROPIC_API_KEY"
    private static let workingDirectoryName = "claude-cli-cwd"
    private static let localInstallCLIPath = "~/.claude/local/claude"
    private static let homebrewCLIPath = "/opt/homebrew/bin/claude"
    private static let intelHomebrewCLIPath = "/usr/local/bin/claude"
    private static let systemCLIPath = "/usr/bin/claude"
    private static let npmPrefixEnvironmentKeys = ["NPM_CONFIG_PREFIX", "npm_config_prefix"]
    private static let connectionCheckInstructions = "pong이라고 한 단어로만 답하세요."
    private static let connectionCheckInput = "ping"
    // 빈 --tools 값은 일부 Claude Code CLI 버전에서 파싱 실패할 수 있다.
    private static let toolBlockingArguments = ["--disallowedTools", "*"]

    public let descriptor: LLMProviderDescriptor
    private let defaults: UserDefaults
    private let launcher: any ProcessLauncher
    private let processEnvironment: [String: String]
    private let appSupportDirectory: URL?
    private let timeout: Duration
    private let maxStdinBytes: Int
    private let fileManager: FileManager
    private let limiter = ClaudeCodeCLIExecutionLimiter(maxConcurrent: 1)

    public convenience init?(registry: LLMProviderRegistry = .shared, defaults: UserDefaults = .standard) {
        self.init(
            registry: registry,
            defaults: defaults,
            launcher: FoundationProcessLauncher(),
            environment: ProcessInfo.processInfo.environment,
            appSupportDirectory: nil,
            timeout: Self.defaultTimeout,
            maxStdinBytes: Self.maxStdinBytes,
            fileManager: .default
        )
    }

    init?(
        registry: LLMProviderRegistry = .shared,
        defaults: UserDefaults = .standard,
        launcher: any ProcessLauncher,
        environment: [String: String],
        appSupportDirectory: URL?,
        timeout: Duration = ClaudeCodeCLIProvider.defaultTimeout,
        maxStdinBytes: Int = ClaudeCodeCLIProvider.maxStdinBytes,
        fileManager: FileManager = .default
    ) {
        guard let descriptor = registry.descriptor(for: .claudeCodeCLI),
              descriptor.authKind == .cliPath
        else {
            return nil
        }
        self.descriptor = descriptor
        self.defaults = defaults
        self.launcher = launcher
        self.processEnvironment = environment
        self.appSupportDirectory = appSupportDirectory
        self.timeout = timeout
        self.maxStdinBytes = maxStdinBytes
        self.fileManager = fileManager
    }

    public func isConfigured() async -> Bool {
        resolvedCLIPath() != nil
    }

    public func modelCatalog() async -> LLMModelCatalog {
        Self.bundledModelCatalog()
    }

    public func generateText(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        try await limiter.withPermit {
            try await generateTextWithoutConcurrentProcessBurst(request)
        }
    }

    @discardableResult
    public func checkConnection() async throws -> URL {
        try await limiter.withPermit {
            let modelID = selectedModelID(requestModelID: nil)
            let result = try await runClaude(
                operation: .connectionCheck,
                instructions: Self.connectionCheckInstructions,
                userContent: Self.connectionCheckInput,
                modelID: modelID
            )
            return result.executableURL
        }
    }

    @discardableResult
    public static func terminateRunningProcesses() -> Int {
        let count = FoundationProcessLauncher.terminateRunningProcesses()
        if count > 0 {
            Log.llm.info("claude cli terminate requested activeProcesses=\(count, privacy: .public)")
        }
        return count
    }

    public static func bundledModelCatalog() -> LLMModelCatalog {
        LLMModelCatalog(
            models: bundledModels(),
            source: .bundledFallback,
            manualModelHelpURL: URL(string: "https://docs.anthropic.com/en/docs/about-claude/models/overview"),
            warning: "Claude Code CLI는 사용자 본인 기기와 본인 claude 로그인을 사용하지만 회의 내용은 Anthropic으로 전송돼요. 로컬 처리가 아니며 구독 약관 확인을 권장해요."
        )
    }

    public static func bundledModels() -> [LLMModelInfo] {
        let capabilities: Set<LLMModelInfo.Capability> = [.textGeneration, .summary, .answer]
        return [
            LLMModelInfo(
                id: "sonnet",
                displayName: "Claude Sonnet",
                description: "회의록 정리와 검색 답변의 기본 선택",
                capabilities: capabilities,
                isRecommended: true
            ),
            LLMModelInfo(
                id: "opus",
                displayName: "Claude Opus",
                description: "복잡한 회의 구조화 품질을 우선할 때",
                capabilities: capabilities
            ),
            LLMModelInfo(
                id: "haiku",
                displayName: "Claude Haiku",
                description: "짧은 답변과 낮은 지연 시간을 우선할 때",
                capabilities: capabilities
            )
        ]
    }

    public static func cliPathExists(_ rawPath: String, fileManager: FileManager = .default) -> Bool {
        let path = normalizedCLIPath(rawPath)
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    public static func resolvedCLIPath(
        configuredPath rawPath: String?,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> String? {
        resolvedCLIPath(
            configuredPath: rawPath,
            environment: environment,
            fileExists: { cliPathExists($0, fileManager: fileManager) }
        )
    }

    static func resolvedCLIPath(
        configuredPath rawPath: String?,
        environment: [String: String],
        fileExists: (String) -> Bool
    ) -> String? {
        candidateCLIPaths(configuredPath: rawPath, environment: environment)
            .first(where: fileExists)
    }

    public static func normalizedCLIPath(_ rawPath: String) -> String {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("~") else { return trimmed }
        return (trimmed as NSString).expandingTildeInPath
    }

    private static func candidateCLIPaths(configuredPath rawPath: String?, environment: [String: String]) -> [String] {
        let configuredPath = normalizedCLIPath(rawPath ?? "")
        if !configuredPath.isEmpty {
            return [configuredPath]
        }

        var candidates = [
            normalizedCLIPath(localInstallCLIPath),
            homebrewCLIPath,
            intelHomebrewCLIPath
        ]
        for key in npmPrefixEnvironmentKeys {
            guard let prefix = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !prefix.isEmpty
            else { continue }
            candidates.append(
                URL(fileURLWithPath: normalizedCLIPath(prefix), isDirectory: true)
                    .appendingPathComponent("bin")
                    .appendingPathComponent("claude")
                    .path
            )
        }
        candidates.append(systemCLIPath)

        var seen: Set<String> = []
        return candidates.filter { seen.insert($0).inserted }
    }

    private func resolvedCLIPath() -> String? {
        Self.resolvedCLIPath(
            configuredPath: defaults.string(forKey: Self.cliPathKey),
            environment: processEnvironment,
            fileManager: fileManager
        )
    }

    private func selectedModelID(requestModelID: String?) -> String {
        if let requestModelID, !requestModelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return requestModelID
        }
        let saved = defaults.string(forKey: Self.modelDefaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? Self.defaultModelID : saved
    }

    private func generateTextWithoutConcurrentProcessBurst(_ request: LLMTextRequest) async throws -> LLMTextResponse {
        let modelID = selectedModelID(requestModelID: request.modelID)
        let result = try await runClaude(
            operation: .generate,
            instructions: request.instructions,
            userContent: request.userContent,
            modelID: modelID
        )
        return LLMTextResponse(
            text: result.text,
            providerID: self.descriptor.id,
            modelID: modelID,
            finishReason: .stop,
            warnings: result.warnings
        )
    }

    private func runClaude(
        operation: ClaudeCodeCLIOperation,
        instructions: String,
        userContent: String,
        modelID: String
    ) async throws -> ClaudeCodeCLIRunResult {
        guard let resolvedPath = resolvedCLIPath() else {
            Log.llm.error("claude cli \(operation.rawValue, privacy: .public) failed provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public) reason=notConfigured")
            throw LLMProviderError.notConfigured
        }

        let executableURL = URL(fileURLWithPath: resolvedPath)
        let preparedInput = Self.preparedStdinData(from: userContent, maxBytes: maxStdinBytes)
        let arguments = Self.arguments(instructions: instructions, modelID: modelID)
        let environment = sanitizedEnvironment()
        let currentDirectory = try workingDirectory()
        let inputCharacterCount = userContent.count

        Log.llm.info("claude cli \(operation.rawValue, privacy: .public) start provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public) inputChars=\(inputCharacterCount, privacy: .public) truncated=\(preparedInput.wasTruncated, privacy: .public)")

        let processResult: ProcessResult
        do {
            processResult = try await launcher.run(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                currentDirectory: currentDirectory,
                stdin: preparedInput.data,
                timeout: timeout
            )
        } catch is CancellationError {
            Log.llm.error("claude cli \(operation.rawValue, privacy: .public) cancelled provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public)")
            throw CancellationError()
        } catch ProcessLauncherError.timedOut {
            Log.llm.error("claude cli \(operation.rawValue, privacy: .public) failed provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public) reason=timeout")
            throw LLMProviderError.network("timeout")
        } catch {
            let publicError = Self.publicErrorDescription(error)
            Log.llm.error("claude cli \(operation.rawValue, privacy: .public) failed provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public) reason=launchFailed error=\(publicError, privacy: .public)")
            throw LLMProviderError.network(publicError)
        }

        guard processResult.exitCode == 0 else {
            let stderrPrefix = Self.stderrPrefix(from: processResult.stderr)
            Log.llm.error("claude cli \(operation.rawValue, privacy: .public) failed provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public) exitCode=\(processResult.exitCode, privacy: .public) stderrPrefix=\(stderrPrefix, privacy: .public)")
            throw Self.providerError(exitCode: processResult.exitCode, stderrPrefix: stderrPrefix)
        }

        do {
            let text = try Self.resultText(from: processResult.stdout)
            Log.llm.info("claude cli \(operation.rawValue, privacy: .public) success provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public) exitCode=\(processResult.exitCode, privacy: .public) inputChars=\(inputCharacterCount, privacy: .public) truncated=\(preparedInput.wasTruncated, privacy: .public)")
            return ClaudeCodeCLIRunResult(
                text: text,
                executableURL: executableURL,
                warnings: preparedInput.warnings
            )
        } catch let error as LLMProviderError {
            Log.llm.error("claude cli \(operation.rawValue, privacy: .public) failed provider=\(self.descriptor.id.rawValue, privacy: .public) model=\(modelID, privacy: .public) exitCode=\(processResult.exitCode, privacy: .public) error=\(Self.publicDiagnosticDescription(error), privacy: .public)")
            throw error
        }
    }

    private static func arguments(instructions: String, modelID: String) -> [String] {
        [
            "-p",
            "--system-prompt", instructions,
            "--model", modelID,
            "--output-format", "json"
        ] + toolBlockingArguments
    }

    private func sanitizedEnvironment() -> [String: String] {
        var environment = processEnvironment
        environment.removeValue(forKey: Self.anthropicAPIKeyEnvironmentName)
        return environment
    }

    private func workingDirectory() throws -> URL {
        let supportRoot: URL
        if let appSupportDirectory {
            supportRoot = appSupportDirectory
        } else {
            supportRoot = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let mintoRoot = supportRoot.appendingPathComponent("Minto", isDirectory: true)
        let cwd = mintoRoot.appendingPathComponent(Self.workingDirectoryName, isDirectory: true)
        try fileManager.createDirectory(at: cwd, withIntermediateDirectories: true)
        return cwd
    }

    private static func preparedStdinData(from userContent: String, maxBytes: Int) -> (data: Data, wasTruncated: Bool, warnings: [String]) {
        let data = Data(userContent.utf8)
        guard data.count > maxBytes else {
            return (data, false, [])
        }

        var validByteCount = maxBytes
        while validByteCount > 0,
              String(data: data.prefix(validByteCount), encoding: .utf8) == nil {
            validByteCount -= 1
        }

        return (
            Data(data.prefix(validByteCount)),
            true,
            ["입력이 10MB를 넘어 앞부분만 Claude Code CLI에 전달했어요."]
        )
    }

    private static func resultText(from stdout: Data) throws -> String {
        guard !stdout.isEmpty else {
            throw LLMProviderError.badResponse("Claude Code CLI stdout is empty bodyLen=0")
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: stdout)
        } catch {
            throw LLMProviderError.badResponse("Claude Code CLI JSON parse failed bodyLen=\(stdout.count)")
        }

        guard let dictionary = object as? [String: Any] else {
            throw LLMProviderError.badResponse("Claude Code CLI JSON root is not object bodyLen=\(stdout.count)")
        }
        guard let result = dictionary["result"] as? String else {
            throw LLMProviderError.badResponse("Claude Code CLI JSON missing field=result bodyLen=\(stdout.count)")
        }
        guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMProviderError.badResponse("Claude Code CLI result is empty bodyLen=\(stdout.count)")
        }
        return result
    }

    private static func providerError(exitCode: Int32, stderrPrefix: String) -> LLMProviderError {
        let lowercased = stderrPrefix.lowercased()
        let isAuthenticationFailure = [
            "auth",
            "login",
            "log in",
            "unauthorized",
            "permission",
            "forbidden",
            "not authenticated",
            "not logged in"
        ].contains { lowercased.contains($0) }

        if isAuthenticationFailure {
            return .unauthorized
        }
        return .network("Claude Code CLI failed exitCode=\(exitCode) stderrPrefix=\(stderrPrefix)")
    }

    private static func stderrPrefix(from stderr: Data) -> String {
        let raw = String(decoding: stderr, as: UTF8.self)
        return sanitizeForPublicLog(String(raw.prefix(200)))
    }

    private static func publicErrorDescription(_ error: any Error) -> String {
        sanitizeForPublicLog(error.localizedDescription)
    }

    private static func publicDiagnosticDescription(_ error: LLMProviderError) -> String {
        switch error {
        case .badResponse(let message), .network(let message), .modelUnavailable(let message):
            return sanitizeForPublicLog(message)
        case .httpStatus(let statusCode, let message):
            return sanitizeForPublicLog("HTTP \(statusCode) \(message)")
        case .notConfigured, .unauthorized, .rateLimited:
            return sanitizeForPublicLog(error.localizedDescription)
        }
    }

    private static func sanitizeForPublicLog(_ value: String) -> String {
        let home = NSHomeDirectory()
        guard !home.isEmpty else { return value }
        return value.replacingOccurrences(of: home, with: "~")
    }
}

private enum ProcessLauncherError: Error {
    case timedOut
}

private final class RunningProcessHandle: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?

    func set(_ process: Process) {
        lock.withLock {
            self.process = process
        }
    }

    func clear() {
        lock.withLock {
            process = nil
        }
    }

    func terminate() {
        let process: Process? = lock.withLock { self.process }
        if process?.isRunning == true {
            process?.terminate()
        }
    }
}

private final class RunningProcessRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var handles: [RunningProcessHandle] = []

    func insert(_ handle: RunningProcessHandle) {
        lock.withLock {
            handles.append(handle)
        }
    }

    func remove(_ handle: RunningProcessHandle) {
        lock.withLock {
            handles.removeAll { $0 === handle }
        }
    }

    func terminateAll() -> Int {
        let activeHandles = lock.withLock { handles }
        for handle in activeHandles {
            handle.terminate()
        }
        return activeHandles.count
    }
}

private actor ProcessExitObserver {
    private var exitCode: Int32?
    private var waiters: [CheckedContinuation<Int32, Never>] = []

    func wait() async -> Int32 {
        if let exitCode {
            return exitCode
        }

        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func finish(_ exitCode: Int32) {
        guard self.exitCode == nil else { return }
        self.exitCode = exitCode
        let waiters = self.waiters
        self.waiters.removeAll()
        for waiter in waiters {
            waiter.resume(returning: exitCode)
        }
    }
}

private actor ClaudeCodeCLIExecutionLimiter {
    private var availablePermits: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(maxConcurrent: Int) {
        availablePermits = max(1, maxConcurrent)
    }

    func withPermit<T: Sendable>(_ operation: @Sendable () async throws -> T) async throws -> T {
        await acquire()
        do {
            try Task.checkCancellation()
            let value = try await operation()
            release()
            return value
        } catch {
            release()
            throw error
        }
    }

    private func acquire() async {
        if availablePermits > 0 {
            availablePermits -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func release() {
        if waiters.isEmpty {
            availablePermits += 1
        } else {
            let waiter = waiters.removeFirst()
            waiter.resume()
        }
    }
}
