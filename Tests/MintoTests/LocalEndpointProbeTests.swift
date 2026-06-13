import Foundation
import Testing
@testable import MintoCore

@Suite("Local endpoint probe")
struct LocalEndpointProbeTests {

    @Test("2xx HTTP 응답이면 true를 반환한다")
    func returnsTrueForSuccessfulStatus() async throws {
        let transport = StubEndpointProbeTransport { request in
            (Data(), Self.httpResponse(for: request, statusCode: 204))
        }
        let probe = LocalEndpointProbe(transport: transport)

        let responds = await probe.responds(to: URL(string: "http://127.0.0.1:11434/api/tags")!)

        #expect(responds)
        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "GET")
        #expect(request.timeoutInterval == 5)
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
    }

    @Test("2xx가 아닌 HTTP 응답이면 false를 반환한다")
    func returnsFalseForFailureStatus() async {
        let transport = StubEndpointProbeTransport { request in
            (Data(), Self.httpResponse(for: request, statusCode: 503))
        }
        let probe = LocalEndpointProbe(transport: transport)

        let responds = await probe.responds(to: URL(string: "http://127.0.0.1:11434/v1/models")!)

        #expect(!responds)
    }

    @Test("transport timeout은 false를 반환한다")
    func returnsFalseForTimeout() async {
        let transport = StubEndpointProbeTransport { _ in
            throw URLError(.timedOut)
        }
        let probe = LocalEndpointProbe(transport: transport)

        let responds = await probe.responds(to: URL(string: "http://127.0.0.1:11434/api/tags")!)

        #expect(!responds)
    }

    private static func httpResponse(
        for request: URLRequest,
        statusCode: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private actor StubEndpointProbeTransport: EndpointProbeTransport {
    typealias Handler = @Sendable (URLRequest) throws -> (Data, HTTPURLResponse)

    private let handler: Handler
    private var capturedRequests: [URLRequest] = []

    var requests: [URLRequest] {
        capturedRequests
    }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        capturedRequests.append(request)
        return try handler(request)
    }
}
