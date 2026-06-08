import Foundation
import Testing
@testable import MintoCore

@Suite("Nemotron sidecar client")
struct NemotronSidecarClientTests {

    @Test("health 응답을 readiness 정보로 변환한다")
    func parsesHealthResponse() async throws {
        let transport = StubNemotronTransport { request in
            let body = """
            {
              "status": "ready",
              "model_id": "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit",
              "quantization": "8bit",
              "device": "mps",
              "detail": "warm"
            }
            """
            return (Data(body.utf8), Self.httpResponse(for: request, statusCode: 200))
        }
        let client = NemotronSidecarClient(transport: transport)

        let health = try await client.health()

        #expect(health.isReady)
        #expect(health.modelID == "mlx-community/nemotron-3.5-asr-streaming-0.6b-8bit")
        let requests = await transport.requests
        #expect(requests.map { $0.url?.path } == ["/health"])
    }

    @Test("transcribe 요청은 16kHz f32le base64 오디오 계약을 사용한다")
    func transcribeUsesFloat32Base64Contract() async throws {
        let transport = StubNemotronTransport { request in
            let body = """
            {
              "text": "안녕하세요",
              "model_id": "nemotron-8bit",
              "audio_seconds": 0.000125,
              "elapsed_seconds": 0.002,
              "rtf": 0.5,
              "peak_memory_mb": 712.5
            }
            """
            return (Data(body.utf8), Self.httpResponse(for: request, statusCode: 200))
        }
        let client = NemotronSidecarClient(
            configuration: NemotronSidecarConfiguration(
                baseURL: URL(string: "http://127.0.0.1:8765/v1")!,
                timeoutSeconds: 3,
                language: "ko"
            ),
            transport: transport
        )

        let result = try await client.transcribe(pcmSamples: [1.0, -0.5], requestID: "req-1")

        #expect(result.text == "안녕하세요")
        #expect(result.modelID == "nemotron-8bit")
        #expect(result.elapsedSeconds == 0.002)
        #expect(result.rtf == 0.5)
        #expect(result.peakMemoryMB == 712.5)

        let request = try #require(await transport.requests.first)
        #expect(request.url?.path == "/v1/transcribe")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 3)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let object = try Self.jsonObject(from: try #require(request.httpBody))
        #expect(object["schema_version"] as? Int == 1)
        #expect(object["request_id"] as? String == "req-1")
        #expect(object["language"] as? String == "ko")
        #expect(object["sample_rate"] as? Int == 16_000)
        #expect(object["audio_format"] as? String == "f32le")
        #expect(object["audio_seconds"] as? Double == 0.000125)

        let audioBase64 = try #require(object["audio_base64"] as? String)
        let audioData = try #require(Data(base64Encoded: audioBase64))
        #expect(Self.float32Values(fromLittleEndianData: audioData) == [1.0, -0.5])
    }

    @Test("HTTP 오류는 status와 body를 보존한다")
    func httpErrorKeepsStatusAndBody() async throws {
        let transport = StubNemotronTransport { request in
            (Data("model warming".utf8), Self.httpResponse(for: request, statusCode: 503))
        }
        let client = NemotronSidecarClient(transport: transport)

        do {
            _ = try await client.health()
            Issue.record("HTTP 503은 실패해야 한다")
        } catch let error as NemotronSidecarClientError {
            #expect(error == .httpStatus(503, "model warming"))
        }
    }

    private static func httpResponse(
        for request: URLRequest,
        statusCode: Int
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: request.url ?? URL(string: "http://127.0.0.1")!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private static func float32Values(fromLittleEndianData data: Data) -> [Float] {
        stride(from: 0, to: data.count, by: 4).map { offset in
            let bitPattern = UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
            return Float(bitPattern: bitPattern)
        }
    }
}

private actor StubNemotronTransport: NemotronSidecarTransport {
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
