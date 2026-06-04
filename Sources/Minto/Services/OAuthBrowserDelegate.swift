import AuthenticationServices
import AppKit
import MCP

/// ASWebAuthenticationSession을 사용해 OAuth authorization URL을 브라우저로 띄우고
/// 콜백 URL을 OAuthAuthorizer로 돌려주는 위임 구현.
///
/// - 세션을 nonisolated(unsafe)로 강한 참조 유지 → 콜백 전 해제 방지.
/// - Swift 6 strict concurrency: presentAuthorizationURL은 nonisolated(Sendable 요구사항),
///   세션 생성·시작은 @MainActor Task 안에서 수행.
final class OAuthBrowserDelegate: NSObject, OAuthAuthorizationDelegate,
    ASWebAuthenticationPresentationContextProviding, @unchecked Sendable
{
    // 세션을 강한 참조로 유지하지 않으면 콜백 전에 해제돼 silently 실패한다.
    // @unchecked Sendable로 선언했으므로 nonisolated(unsafe) 없이 프로퍼티 접근 허용.
    private var session: ASWebAuthenticationSession?

    /// Authorization URL을 브라우저로 열고, 사용자 인증 후 redirect URL을 반환한다.
    /// 취소(.canceledLogin)는 조용히 CancellationError로 변환한다.
    func presentAuthorizationURL(_ url: URL) async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                Task { @MainActor in
                let webSession = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: "minto2"
                ) { callbackURL, error in
                    if let error = error as? ASWebAuthenticationSessionError,
                       error.code == .canceledLogin
                    {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: OAuthBrowserError.missingCallbackURL)
                        return
                    }
                    continuation.resume(returning: callbackURL)
                }
                webSession.presentationContextProvider = self
                webSession.prefersEphemeralWebBrowserSession = false

                self.session = webSession

                guard webSession.start() else {
                    self.session = nil
                    continuation.resume(throwing: OAuthBrowserError.sessionStartFailed)
                    return
                }
                }
            }
        } onCancel: {
            // 바깥 Task 취소 시 세션을 정리해 continuation leak·세션 잔존을 방지.
            Task { @MainActor in
                self.session?.cancel()
                self.session = nil
            }
        }
    }

    // MARK: - ASWebAuthenticationPresentationContextProviding

    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            NSApplication.shared.keyWindow
                ?? NSApplication.shared.windows.first
                ?? ASPresentationAnchor()
        }
    }
}

// MARK: - 에러 타입

enum OAuthBrowserError: Error, LocalizedError {
    case missingCallbackURL
    case sessionStartFailed

    var errorDescription: String? {
        switch self {
        case .missingCallbackURL: return "OAuth 콜백 URL이 없습니다."
        case .sessionStartFailed: return "인증 세션을 시작할 수 없습니다."
        }
    }
}
