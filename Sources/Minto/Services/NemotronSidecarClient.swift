import Foundation

struct NemotronSidecarConfiguration: Equatable, Sendable {
    let baseURL: URL
    let timeoutSeconds: TimeInterval
    let language: String

    init(
        baseURL: URL = URL(string: "http://127.0.0.1:8765")!,
        timeoutSeconds: TimeInterval = 60,
        language: String = "ko"
    ) {
        self.baseURL = baseURL
        self.timeoutSeconds = timeoutSeconds
        self.language = language
    }
}

struct NemotronSidecarHealth: Equatable, Sendable {
    let status: String
    let modelID: String?
    let quantization: String?
    let device: String?
    let detail: String?

    var isReady: Bool {
        status == "ok" || status == "ready"
    }
}

struct NemotronSidecarTranscription: Equatable, Sendable {
    let text: String
    let modelID: String?
    let audioSeconds: Double
    let elapsedSeconds: Double
    let rtf: Double
    let peakMemoryMB: Double?
}

enum NemotronSidecarClientError: Error, Equatable, LocalizedError {
    case invalidHTTPResponse
    case httpStatus(Int, String)

    var errorDescription: String? {
        switch self {
        case .invalidHTTPResponse:
            return "Nemotron sidecar가 HTTP 응답을 반환하지 않았어요."
        case .httpStatus(let statusCode, let body):
            return "Nemotron sidecar HTTP \(statusCode): \(body)"
        }
    }
}

protocol NemotronSidecarTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

protocol NemotronSidecarTranscribing: Sendable {
    func health() async throws -> NemotronSidecarHealth
    func transcribe(
        pcmSamples: [Float],
        requestID: String?
    ) async throws -> NemotronSidecarTranscription
}

struct URLSessionNemotronSidecarTransport: NemotronSidecarTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw NemotronSidecarClientError.invalidHTTPResponse
        }
        return (data, httpResponse)
    }
}

struct NemotronSidecarClient: Sendable {
    private let configuration: NemotronSidecarConfiguration
    private let transport: any NemotronSidecarTransport
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        configuration: NemotronSidecarConfiguration = NemotronSidecarConfiguration(),
        transport: any NemotronSidecarTransport = URLSessionNemotronSidecarTransport()
    ) {
        self.configuration = configuration
        self.transport = transport
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    func health() async throws -> NemotronSidecarHealth {
        let request = makeRequest(path: "health", method: "GET")
        let data = try await send(request)
        let response = try decoder.decode(HealthResponse.self, from: data)
        return NemotronSidecarHealth(
            status: response.status,
            modelID: response.modelID,
            quantization: response.quantization,
            device: response.device,
            detail: response.detail
        )
    }

    func transcribe(
        pcmSamples: [Float],
        requestID: String? = nil
    ) async throws -> NemotronSidecarTranscription {
        let audioSeconds = Double(pcmSamples.count) / STTAudioUtilities.sampleRate
        let payload = TranscriptionRequest(
            schemaVersion: 1,
            requestID: requestID,
            language: configuration.language,
            sampleRate: Int(STTAudioUtilities.sampleRate),
            audioFormat: "f32le",
            audioBase64: Self.float32LittleEndianBase64(pcmSamples),
            audioSeconds: audioSeconds
        )

        var request = makeRequest(path: "transcribe", method: "POST")
        request.httpBody = try encoder.encode(payload)

        let data = try await send(request)
        let response = try decoder.decode(TranscriptionResponse.self, from: data)
        let elapsedSeconds = response.elapsedSeconds ?? 0
        let rtf = response.rtf ?? elapsedSeconds / max(audioSeconds, 0.001)
        return NemotronSidecarTranscription(
            text: response.text.trimmingCharacters(in: .whitespacesAndNewlines),
            modelID: response.modelID,
            audioSeconds: response.audioSeconds ?? audioSeconds,
            elapsedSeconds: elapsedSeconds,
            rtf: rtf,
            peakMemoryMB: response.peakMemoryMB
        )
    }

    static func float32LittleEndianBase64(_ samples: [Float]) -> String {
        var data = Data()
        data.reserveCapacity(samples.count * MemoryLayout<UInt32>.size)
        for sample in samples {
            var bitPattern = sample.bitPattern.littleEndian
            withUnsafeBytes(of: &bitPattern) { bytes in
                data.append(bytes.bindMemory(to: UInt8.self))
            }
        }
        return data.base64EncodedString()
    }

    private func makeRequest(path: String, method: String) -> URLRequest {
        let url = configuration.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = configuration.timeoutSeconds
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if method != "GET" {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw NemotronSidecarClientError.httpStatus(
                response.statusCode,
                String(body.prefix(500))
            )
        }
        return data
    }
}

extension NemotronSidecarClient: NemotronSidecarTranscribing {}

private struct HealthResponse: Decodable {
    let status: String
    let modelID: String?
    let quantization: String?
    let device: String?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case status
        case modelID = "model_id"
        case quantization
        case device
        case detail
    }
}

private struct TranscriptionRequest: Encodable {
    let schemaVersion: Int
    let requestID: String?
    let language: String
    let sampleRate: Int
    let audioFormat: String
    let audioBase64: String
    let audioSeconds: Double
}

private struct TranscriptionResponse: Decodable {
    let text: String
    let modelID: String?
    let audioSeconds: Double?
    let elapsedSeconds: Double?
    let rtf: Double?
    let peakMemoryMB: Double?

    enum CodingKeys: String, CodingKey {
        case text
        case modelID = "model_id"
        case audioSeconds = "audio_seconds"
        case elapsedSeconds = "elapsed_seconds"
        case rtf
        case peakMemoryMB = "peak_memory_mb"
    }
}
