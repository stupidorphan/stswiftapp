import Foundation
import os
import OSLog

// MARK: - API Error

enum STAPIError: Error, LocalizedError {
    case invalidURL
    case notConfigured
    case unauthorized
    case forbidden
    case notFound
    case serverError(Int)
    case decodingFailed(Error)
    case networkError(Error)
    case csrfFailed
    case loginFailed(String)
    case streamingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .notConfigured: return "Server not configured"
        case .unauthorized: return "Authentication failed"
        case .forbidden: return "Access denied"
        case .notFound: return "Resource not found"
        case .serverError(let code): return "Server error (\(code))"
        case .decodingFailed(let err): return "Data error: \(err.localizedDescription)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .csrfFailed: return "Failed to obtain CSRF token"
        case .loginFailed(let msg): return "Login failed: \(msg)"
        case .streamingError(let msg): return "Streaming error: \(msg)"
        }
    }
}

// MARK: - SSE Event

struct SSEEvent {
    let data: String
}

// MARK: - API Client

/// Primary HTTP client for SillyTavern API. Handles auth, CSRF, cookie persistence,
/// and SSE streaming. All SillyTavern endpoints use POST — this client abstracts that.
final class STAPIClient: NSObject, @unchecked Sendable {
    static let shared = STAPIClient()

    private let authHandler = STAuthHandler()
    private var serverURL: String = ""
    private var urlSession: URLSession!
    private let logger = Logger(subsystem: "com.stswiftapp", category: "APIClient")

    override private init() {
        super.init()
        buildSession()
    }

    private func buildSession() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 600
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        urlSession = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    /// Public authenticated URLSession for image loading via STAuthAsyncImage.
    var urlSessionForImages: URLSession { urlSession }

    // MARK: - Configuration

    func configure(with config: STServerConfig) {
        serverURL = config.sanitizedURL
        authHandler.configure(config)
        if config.allowSelfSignedCerts {
            buildSession() // recreate with self-signed-friendly delegate
        }
    }

    func reset() {
        serverURL = ""
        authHandler.reset()
        HTTPCookieStorage.shared.cookies?.forEach(HTTPCookieStorage.shared.deleteCookie)
    }

    // MARK: - CSRF

    @discardableResult
    func fetchCSRFToken() async throws -> String {
        guard !serverURL.isEmpty else { throw STAPIError.notConfigured }
        guard let url = URL(string: "\(serverURL)/csrf-token") else {
            throw STAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req = authHandler.applyAuth(to: req)

        let (data, response) = try await urlSession.data(for: req)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw STAPIError.csrfFailed
        }
        authHandler.storeSessionCookie(from: httpResp)

        struct CSRFResponse: Codable { let token: String }
        let csrfResp = try JSONDecoder().decode(CSRFResponse.self, from: data)
        authHandler.setCSRFToken(csrfResp.token)
        return csrfResp.token
    }

    // MARK: - User Account Login

    func login(handle: String, password: String) async throws {
        guard !serverURL.isEmpty else { throw STAPIError.notConfigured }
        guard let url = URL(string: "\(serverURL)/api/users/login") else {
            throw STAPIError.invalidURL
        }

        // Get CSRF token first
        try? await fetchCSRFToken()

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req = authHandler.applyAuth(to: req)

        let body = ["handle": handle, "password": password]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: req)
        guard let httpResp = response as? HTTPURLResponse else {
            throw STAPIError.loginFailed("No response")
        }
        authHandler.storeSessionCookie(from: httpResp)

        if httpResp.statusCode == 200 {
            logger.info("Login successful for \(handle)")
        } else if httpResp.statusCode == 403 {
            struct LoginError: Codable { let error: String }
            if let err = try? JSONDecoder().decode(LoginError.self, from: data) {
                throw STAPIError.loginFailed(err.error)
            }
            throw STAPIError.loginFailed("Incorrect credentials")
        } else {
            throw STAPIError.loginFailed("HTTP \(httpResp.statusCode)")
        }
    }

    func logout() async throws {
        let _: [String: String] = try await post("/api/users/logout", body: Optional<String>.none)
    }

    // MARK: - Generic POST

    /// Perform a POST request to the SillyTavern API. Most endpoints use POST.
    /// - Parameters:
    ///   - path: API path relative to server URL (e.g. "/api/chats/recent")
    ///   - body: Codable request body (optional)
    /// - Returns: Decoded response
    func post<T: Decodable, B: Encodable>(_ path: String, body: B?) async throws -> T {
        let data = try await postRaw(path, body: body)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw STAPIError.decodingFailed(error)
        }
    }

    /// POST with raw body, returns raw Data.
    func postRaw<B: Encodable>(_ path: String, body: B?) async throws -> Data {
        guard !serverURL.isEmpty else { throw STAPIError.notConfigured }
        guard let url = URL(string: "\(serverURL)\(path)") else {
            throw STAPIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req = authHandler.applyAuth(to: req)

        if let body = body {
            req.httpBody = try JSONEncoder().encode(body)
        }

        let (data, response) = try await urlSession.data(for: req)
        guard let httpResp = response as? HTTPURLResponse else {
            throw STAPIError.networkError(NSError(domain: "", code: -1))
        }
        logger.debug("POST \(path) -> \(httpResp.statusCode)")
        Logger(subsystem: "com.stswiftapp", category: "API").log("POST \(path) -> \(httpResp.statusCode)")

        switch httpResp.statusCode {
        case 200...299: return data
        case 401: throw STAPIError.unauthorized
        case 403:
            // Try refreshing CSRF token
            try? await fetchCSRFToken()
            throw STAPIError.forbidden
        case 404: throw STAPIError.notFound
        default: throw STAPIError.serverError(httpResp.statusCode)
        }
    }

    /// POST returning raw JSON array (SillyTavern uses top-level arrays for some endpoints)
    func postArray<T: Decodable, B: Encodable>(_ path: String, body: B?) async throws -> [T] {
        let data = try await postRaw(path, body: body)
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            throw STAPIError.decodingFailed(error)
        }
    }

    /// POST with raw JSON Data as the body (for [String: Any] dicts that aren't Codable).
    /// The server writes request.body directly, so send the raw JSON bytes.
    /// Keep auth/CSRF/status-code logic in sync with postRaw.
    func postRawData(_ path: String, rawBody: Data) async throws -> Data {
        guard !serverURL.isEmpty else { throw STAPIError.notConfigured }
        guard let url = URL(string: "\(serverURL)\(path)") else {
            throw STAPIError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req = authHandler.applyAuth(to: req)
        req.httpBody = rawBody

        let (data, response) = try await urlSession.data(for: req)
        guard let httpResp = response as? HTTPURLResponse else {
            throw STAPIError.networkError(NSError(domain: "", code: -1))
        }

        switch httpResp.statusCode {
        case 200...299: return data
        case 401: throw STAPIError.unauthorized
        case 403:
            try? await fetchCSRFToken()
            throw STAPIError.forbidden
        case 404: throw STAPIError.notFound
        default: throw STAPIError.serverError(httpResp.statusCode)
        }
    }

    // MARK: - Multipart Upload

    func uploadMultipart(
        _ path: String,
        body: (any Encodable)?,
        fileData: Data?,
        fileName: String = "avatar",
        mimeType: String = "image/png"
    ) async throws -> Data {
        guard !serverURL.isEmpty else { throw STAPIError.notConfigured }
        guard let url = URL(string: "\(serverURL)\(path)") else {
            throw STAPIError.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request = authHandler.applyAuth(to: request)

        var bodyData = Data()

        // JSON fields
        if let body = body {
            let json = try JSONEncoder().encode(body)
            if let jsonDict = try? JSONSerialization.jsonObject(with: json) as? [String: Any] {
                for (key, value) in jsonDict {
                    bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
                    bodyData.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
                    bodyData.append("\(value)\r\n".data(using: .utf8)!)
                }
            }
        }

        // File data
        if let fileData = fileData {
            bodyData.append("--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
            bodyData.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
            bodyData.append(fileData)
            bodyData.append("\r\n".data(using: .utf8)!)
        }

        bodyData.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = bodyData

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, (200...299).contains(httpResp.statusCode) else {
            throw STAPIError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        return data
    }

    // MARK: - Streaming (SSE)

    /// Stream SSE events from a POST endpoint.
    /// Returns an AsyncThrowingStream of SSEEvent objects.
    func streamSSE<B: Encodable>(_ path: String, body: B) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !self.serverURL.isEmpty else {
                        throw STAPIError.notConfigured
                    }
                    guard let url = URL(string: "\(self.serverURL)\(path)") else {
                        throw STAPIError.invalidURL
                    }

                    var req = URLRequest(url: url)
                    req.httpMethod = "POST"
                    req.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    req.timeoutInterval = 300
                    req = self.authHandler.applyAuth(to: req)
                    req.httpBody = try JSONEncoder().encode(body)

                    let (bytes, response) = try await self.urlSession.bytes(for: req)
                    guard let httpResp = response as? HTTPURLResponse,
                          (200...299).contains(httpResp.statusCode) else {
                        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw STAPIError.streamingError("Server returned \(status)")
                    }

                    var buffer = ""
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            if data == "[DONE]" {
                                continuation.finish()
                                return
                            }
                            continuation.yield(SSEEvent(data: data))
                        } else if line.isEmpty && !buffer.isEmpty {
                            // Empty line = event boundary, process buffered data
                            continuation.yield(SSEEvent(data: buffer))
                            buffer = ""
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Convenience: Image URL

    func imageURL(for path: String) -> URL? {
        guard !serverURL.isEmpty else { return nil }
        return URL(string: "\(serverURL)\(path)")
    }

    func authenticatedRequest(for path: String) -> URLRequest? {
        guard !serverURL.isEmpty, let url = URL(string: "\(serverURL)\(path)") else {
            return nil
        }
        var req = URLRequest(url: url)
        req = authHandler.applyAuth(to: req)
        return req
    }
}

// MARK: - URLSessionDelegate for self-signed certs

extension STAPIClient: URLSessionDelegate {
    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let config = STServerConfigManager.shared.load()
        if config.allowSelfSignedCerts,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let serverTrust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: serverTrust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}