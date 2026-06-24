import Foundation
import Testing
@testable import MintoCore

@Suite("ClaudeCodeCLIProvider", .serialized)
struct ClaudeCodeCLIProviderTests {

    @Test("stdout JSON result를 LLMTextResponse로 반환한다")
    func generateTextParsesResultJSON() async throws {
        let fixture = try ProviderFixture(
            result: .success(ProcessResult(
                exitCode: 0,
                stdout: Data(#"{"result":"정리된 회의록"}"#.utf8),
                stderr: Data()
            ))
        )
        defer { fixture.cleanup() }

        let response = try await fixture.provider.generateText(LLMTextRequest(
            useCase: .finalSummary,
            instructions: "회의를 요약하세요.",
            userContent: "회의 전사",
            modelID: "opus",
            maxOutputTokens: 1_024
        ))

        #expect(response.text == "정리된 회의록")
        #expect(response.providerID == .claudeCodeCLI)
        #expect(response.modelID == "opus")
        #expect(response.finishReason == .stop)
        #expect(response.warnings.isEmpty)

        let call = try #require(fixture.launcher.calls.first)
        #expect(call.executableURL == fixture.cliURL)
        #expect(call.currentDirectory.path.hasSuffix("/Minto/claude-cli-cwd"))
        #expect(call.arguments.contains("--output-format"))
        #expect(call.arguments.contains("json"))
    }

    @Test("비정상 종료와 인증 stderr는 unauthorized로 매핑한다")
    func generateTextMapsAuthenticationFailure() async throws {
        let fixture = try ProviderFixture(
            result: .success(ProcessResult(
                exitCode: 1,
                stdout: Data(),
                stderr: Data("Please login to Claude Code first".utf8)
            ))
        )
        defer { fixture.cleanup() }

        await #expect(throws: LLMProviderError.unauthorized) {
            _ = try await fixture.provider.generateText(Self.request())
        }
    }

    @Test("빈 stdout은 badResponse로 매핑한다")
    func generateTextMapsEmptyStdoutToBadResponse() async throws {
        let fixture = try ProviderFixture(
            result: .success(ProcessResult(exitCode: 0, stdout: Data(), stderr: Data()))
        )
        defer { fixture.cleanup() }

        do {
            _ = try await fixture.provider.generateText(Self.request())
            Issue.record("빈 stdout은 badResponse를 던져야 합니다.")
        } catch let error as LLMProviderError {
            guard case .badResponse(let message) = error else {
                Issue.record("예상치 못한 LLMProviderError: \(error)")
                return
            }
            #expect(message.contains("bodyLen=0"))
        } catch {
            Issue.record("LLMProviderError가 아닌 에러: \(error)")
        }
    }

    @Test("CLI 경로가 없으면 launcher를 호출하지 않고 notConfigured를 던진다")
    func generateTextRequiresExistingCLIPath() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let defaults = InMemoryUserDefaults()
        defaults.set(root.appendingPathComponent("missing-claude").path, forKey: ClaudeCodeCLIProvider.cliPathKey)
        let launcher = RecordingProcessLauncher(result: .success(ProcessResult(
            exitCode: 0,
            stdout: Data(#"{"result":"unused"}"#.utf8),
            stderr: Data()
        )))
        let provider = try #require(ClaudeCodeCLIProvider(
            defaults: defaults,
            launcher: launcher,
            environment: ["PATH": "/usr/bin"],
            appSupportDirectory: root,
            timeout: .seconds(5),
            maxStdinBytes: 10 * 1024 * 1024
        ))

        await #expect(throws: LLMProviderError.notConfigured) {
            _ = try await provider.generateText(Self.request())
        }
        #expect(launcher.calls.isEmpty)
    }

    @Test("Task 취소는 launcher 취소 경로까지 전달된다")
    func cancellationReachesLauncher() async throws {
        let root = try Self.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let cliURL = try Self.createCLIFile(in: root)

        let defaults = InMemoryUserDefaults()
        defaults.set(cliURL.path, forKey: ClaudeCodeCLIProvider.cliPathKey)
        let launcher = CancellableProcessLauncher()
        let provider = try #require(ClaudeCodeCLIProvider(
            defaults: defaults,
            launcher: launcher,
            environment: ["PATH": "/usr/bin"],
            appSupportDirectory: root,
            timeout: .seconds(30),
            maxStdinBytes: 10 * 1024 * 1024
        ))

        let task = Task {
            try await provider.generateText(Self.request())
        }
        await launcher.waitUntilStarted()
        task.cancel()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
        #expect(await launcher.wasCancelled)
    }

    @Test("전사는 stdin에만 전달하고 argv와 environment에는 싣지 않는다")
    func userContentIsOnlyPassedThroughStdin() async throws {
        let transcript = "민감한 회의 전사 원문"
        let fixture = try ProviderFixture(
            result: .success(ProcessResult(
                exitCode: 0,
                stdout: Data(#"{"result":"답변"}"#.utf8),
                stderr: Data()
            )),
            environment: [
                "PATH": "/opt/homebrew/bin:/usr/bin",
                "ANTHROPIC_API_KEY": "should-not-leak"
            ]
        )
        defer { fixture.cleanup() }

        _ = try await fixture.provider.generateText(LLMTextRequest(
            useCase: .answer,
            instructions: "질문에 답하세요.",
            userContent: transcript,
            modelID: nil
        ))

        let call = try #require(fixture.launcher.calls.first)
        #expect(call.stdin == Data(transcript.utf8))
        #expect(!call.arguments.contains { $0.contains(transcript) })
        #expect(call.arguments.contains("--system-prompt"))
        #expect(call.arguments.contains("질문에 답하세요."))
        #expect(call.environment["PATH"] == "/opt/homebrew/bin:/usr/bin")
        #expect(call.environment["ANTHROPIC_API_KEY"] == nil)
    }

    @Test("연결 확인은 version 조회가 아니라 trivial prompt 왕복으로 검증한다")
    func checkConnectionRunsTrivialPrompt() async throws {
        let fixture = try ProviderFixture(
            result: .success(ProcessResult(
                exitCode: 0,
                stdout: Data(#"{"result":"pong"}"#.utf8),
                stderr: Data()
            ))
        )
        defer { fixture.cleanup() }

        let executableURL = try await fixture.provider.checkConnection()

        #expect(executableURL == fixture.cliURL)
        let call = try #require(fixture.launcher.calls.first)
        #expect(call.stdin == Data("ping".utf8))
        #expect(call.arguments.contains("-p"))
        #expect(call.arguments.contains("--output-format"))
        #expect(call.arguments.contains("json"))
        #expect(!call.arguments.contains("--version"))
    }

    @Test("CLI 경로 발견은 설정값을 기본 설치 경로보다 우선한다")
    func cliDiscoveryPrefersConfiguredPath() {
        let configuredPath = "\(NSHomeDirectory())/custom/bin/claude"
        var checkedPaths: [String] = []

        let resolvedPath = ClaudeCodeCLIProvider.resolvedCLIPath(
            configuredPath: configuredPath,
            environment: ["NPM_CONFIG_PREFIX": "/custom/npm"]
        ) { path in
            checkedPaths.append(path)
            return path == configuredPath
        }

        #expect(resolvedPath == configuredPath)
        #expect(checkedPaths == [configuredPath])
    }

    @Test("CLI 경로 발견은 설정값이 비어 있으면 절대경로 fallback 순서를 따른다")
    func cliDiscoveryUsesAbsoluteFallbackOrder() {
        var checkedPaths: [String] = []

        let resolvedPath = ClaudeCodeCLIProvider.resolvedCLIPath(
            configuredPath: " ",
            environment: ["NPM_CONFIG_PREFIX": "/custom/npm"]
        ) { path in
            checkedPaths.append(path)
            return path == "/usr/local/bin/claude"
        }

        #expect(resolvedPath == "/usr/local/bin/claude")
        #expect(Array(checkedPaths.prefix(3)) == [
            "\(NSHomeDirectory())/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude"
        ])
        #expect(!checkedPaths.contains("/custom/npm/bin/claude"))
    }

    private static func request() -> LLMTextRequest {
        LLMTextRequest(
            useCase: .answer,
            instructions: "근거에 맞춰 답하세요.",
            userContent: "사용자 입력",
            modelID: "sonnet"
        )
    }

    fileprivate static func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MintoClaudeCodeCLIProviderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    fileprivate static func createCLIFile(in root: URL) throws -> URL {
        let cliURL = root.appendingPathComponent("claude")
        try Data().write(to: cliURL)
        return cliURL
    }
}

private struct ProviderFixture {
    let root: URL
    let cliURL: URL
    let launcher: RecordingProcessLauncher
    let provider: ClaudeCodeCLIProvider

    init(
        result: Result<ProcessResult, Error>,
        environment: [String: String] = ["PATH": "/usr/bin"]
    ) throws {
        root = try ClaudeCodeCLIProviderTests.temporaryDirectory()
        cliURL = try ClaudeCodeCLIProviderTests.createCLIFile(in: root)
        launcher = RecordingProcessLauncher(result: result)

        let defaults = InMemoryUserDefaults()
        defaults.set(cliURL.path, forKey: ClaudeCodeCLIProvider.cliPathKey)
        defaults.set(ClaudeCodeCLIProvider.defaultModelID, forKey: ClaudeCodeCLIProvider.modelDefaultsKey)

        provider = try #require(ClaudeCodeCLIProvider(
            defaults: defaults,
            launcher: launcher,
            environment: environment,
            appSupportDirectory: root,
            timeout: .seconds(5),
            maxStdinBytes: 10 * 1024 * 1024
        ))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: root)
    }
}

private struct ProcessCall: Sendable {
    let executableURL: URL
    let arguments: [String]
    let environment: [String: String]
    let currentDirectory: URL
    let stdin: Data
    let timeout: Duration
}

private final class RecordingProcessLauncher: ProcessLauncher, @unchecked Sendable {
    private let lock = NSLock()
    private let result: Result<ProcessResult, Error>
    private var recordedCalls: [ProcessCall] = []

    var calls: [ProcessCall] {
        lock.withLock { recordedCalls }
    }

    init(result: Result<ProcessResult, Error>) {
        self.result = result
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        stdin: Data,
        timeout: Duration
    ) async throws -> ProcessResult {
        lock.withLock {
            recordedCalls.append(ProcessCall(
                executableURL: executableURL,
                arguments: arguments,
                environment: environment,
                currentDirectory: currentDirectory,
                stdin: stdin,
                timeout: timeout
            ))
        }
        return try result.get()
    }
}

private final class CancellableProcessLauncher: ProcessLauncher, @unchecked Sendable {
    private let state = CancellableProcessLauncherState()

    var wasCancelled: Bool {
        get async { await state.wasCancelled }
    }

    func waitUntilStarted() async {
        await state.waitUntilStarted()
    }

    func run(
        executableURL: URL,
        arguments: [String],
        environment: [String: String],
        currentDirectory: URL,
        stdin: Data,
        timeout: Duration
    ) async throws -> ProcessResult {
        await state.markStarted(ProcessCall(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            currentDirectory: currentDirectory,
            stdin: stdin,
            timeout: timeout
        ))

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task {
                    await state.store(continuation)
                }
            }
        } onCancel: {
            Task {
                await self.state.cancel()
            }
        }
    }
}

private actor CancellableProcessLauncherState {
    private var started = false
    private var cancelled = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var continuation: CheckedContinuation<ProcessResult, Error>?

    var wasCancelled: Bool { cancelled }

    func markStarted(_ call: ProcessCall) {
        _ = call
        started = true
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        if started {
            return
        }

        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func store(_ continuation: CheckedContinuation<ProcessResult, Error>) {
        if cancelled {
            continuation.resume(throwing: CancellationError())
        } else {
            self.continuation = continuation
        }
    }

    func cancel() {
        cancelled = true
        continuation?.resume(throwing: CancellationError())
        continuation = nil
    }
}
