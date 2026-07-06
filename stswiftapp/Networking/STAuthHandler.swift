import Foundation

/// Authentication strategies for the SillyTavern server.
enum STAuthStrategy {
    case none
    case basicAuth(username: String, password: String)
    case cookieSession(handle: String, password: String)
}

/// Manages auth state and applies auth to URLRequests.
final class STAuthHandler {
    private var strategy: STAuthStrategy = .none
    private var csrfToken: String?
    private var sessionCookie: String?

    var authMode: STAuthMode {
        switch strategy {
        case .none: return .none
        case .basicAuth: return .basicAuth
        case .cookieSession: return .userAccount
        }
    }

    func configure(_ config: STServerConfig) {
        switch config.authMode {
        case .none:
            strategy = .none
        case .basicAuth:
            strategy = .basicAuth(username: config.basicAuthUsername, password: config.basicAuthPassword)
        case .userAccount:
            strategy = .cookieSession(handle: config.userHandle, password: config.userPassword)
        }
    }

    /// Apply auth headers to a request. Returns modified request.
    func applyAuth(to request: URLRequest) -> URLRequest {
        var req = request
        switch strategy {
        case .none:
            break
        case .basicAuth(let username, let password):
            let credentials = "\(username):\(password)"
            if let encoded = credentials.data(using: .utf8)?.base64EncodedString() {
                req.setValue("Basic \(encoded)", forHTTPHeaderField: "Authorization")
            }
        case .cookieSession:
            if let cookie = sessionCookie {
                req.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
        }
        if let token = csrfToken {
            req.setValue(token, forHTTPHeaderField: "x-csrf-token")
        }
        return req
    }

    func setCSRFToken(_ token: String) {
        csrfToken = token
    }

    func storeSessionCookie(from response: HTTPURLResponse) {
        if let setCookie = response.allHeaderFields["Set-Cookie"] as? String {
            sessionCookie = setCookie.components(separatedBy: ";").first
        }
    }

    func reset() {
        csrfToken = nil
        sessionCookie = nil
        strategy = .none
    }
}
