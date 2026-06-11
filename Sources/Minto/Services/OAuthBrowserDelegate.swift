import AppKit
import MCP
import Network

/// OAuth authorization URL을 기본 브라우저로 열고, Notion이 돌려주는
/// loopback callback(`http://127.0.0.1:53682/callback`)을 받아 SDK에 반환한다.
///
/// Notion MCP authorization endpoint는 native custom scheme(`minto2://...`)을
/// 실제 인증 단계에서 거부하므로 loopback HTTP redirect를 사용한다.
final class OAuthBrowserDelegate: NSObject, OAuthAuthorizationDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "com.minto.notion-oauth-callback")
    private var listener: NWListener?
    private var didResume = false

    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    self.startCallbackListener(continuation: continuation)

                    Task { @MainActor in
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        } onCancel: {
            queue.async {
                self.stopListener()
            }
        }
    }

    private func startCallbackListener(continuation: CheckedContinuation<URL, Error>) {
        do {
            let listener = try NWListener(
                using: .tcp,
                on: NWEndpoint.Port(integerLiteral: 53682)
            )
            self.listener = listener
            self.didResume = false

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                if case let .failed(error) = state {
                    self.finish(continuation, result: .failure(error))
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection, continuation: continuation)
            }

            listener.start(queue: queue)
        } catch {
            finish(continuation, result: .failure(error))
        }
    }

    private func handle(_ connection: NWConnection, continuation: CheckedContinuation<URL, Error>) {
        connection.stateUpdateHandler = { state in
            if case .ready = state {
                self.receiveRequest(on: connection, continuation: continuation)
            }
        }
        connection.start(queue: queue)
    }

    private func receiveRequest(on connection: NWConnection, continuation: CheckedContinuation<URL, Error>) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, _, error in
            if let error {
                self.finish(continuation, result: .failure(error))
                return
            }

            guard let data,
                  let request = String(data: data, encoding: .utf8),
                  let callbackURL = Self.callbackURL(from: request)
            else {
                self.respond(on: connection, status: "400 Bad Request", body: "Invalid OAuth callback")
                self.finish(continuation, result: .failure(OAuthBrowserError.missingCallbackURL))
                return
            }

            self.respond(on: connection, status: "200 OK", body: "Minto Notion connection complete. You can close this tab.")
            self.finish(continuation, result: .success(callbackURL))
        }
    }

    private func respond(on connection: NWConnection, status: String, body: String) {
        let response = """
        HTTP/1.1 \(status)\r
        Content-Type: text/plain; charset=utf-8\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func finish(_ continuation: CheckedContinuation<URL, Error>, result: Result<URL, Error>) {
        guard !didResume else { return }
        didResume = true
        stopListener()

        switch result {
        case .success(let url):
            continuation.resume(returning: url)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    private func stopListener() {
        listener?.cancel()
        listener = nil
    }

    private static func callbackURL(from request: String) -> URL? {
        guard let firstLine = request.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET" else { return nil }

        let pathAndQuery = String(parts[1])
        guard pathAndQuery.hasPrefix("/callback") else { return nil }
        return URL(string: "http://127.0.0.1:53682\(pathAndQuery)")
    }
}

// MARK: - 에러 타입

enum OAuthBrowserError: Error, LocalizedError {
    case missingCallbackURL

    var errorDescription: String? {
        switch self {
        case .missingCallbackURL: return "OAuth 콜백 URL이 없어요."
        }
    }
}
