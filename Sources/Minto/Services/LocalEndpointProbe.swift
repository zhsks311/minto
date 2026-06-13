import Foundation

protocol EndpointProbeTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionEndpointProbeTransport: EndpointProbeTransport {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        return (data, httpResponse)
    }
}

struct LocalEndpointProbe: Sendable {
    private let transport: any EndpointProbeTransport

    init(transport: any EndpointProbeTransport = URLSessionEndpointProbeTransport()) {
        self.transport = transport
    }

    func responds(to url: URL) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (_, response) = try await transport.data(for: request)
            return (200..<300).contains(response.statusCode)
        } catch {
            return false
        }
    }
}
