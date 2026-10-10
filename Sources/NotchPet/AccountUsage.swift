import Foundation
import Security

/// Claude plan usage straight from Anthropic, the way Claude Code's `/usage` gets it.
///
/// Uses the Claude Code login already in your Keychain ("Claude Code-credentials"; macOS asks
/// once). The token is only sent to api.anthropic.com, read-only, and never stored by Pip.
/// Expired tokens are left alone: Pip never refreshes them, so it can't log Claude Code out.
/// The endpoint isn't documented, so if it changes Pip falls back to the status line.
enum AccountUsage {
    enum Failure: Error { case noLogin, needsAccess, expired, http(Int), badResponse }

    /// `interactive: false` never shows the Keychain dialog. Background refreshes use that, so a
    /// dialog only appears when you click: macOS asks again whenever Claude Code rewrites its
    /// login or Pip is rebuilt, and a dialog popping up on a timer is just noise.
    private static func accessToken(interactive: Bool) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        // The login keychain uses per-app access lists; switching user interaction off makes a
        // missing grant fail with errSecInteractionNotAllowed instead of opening the dialog.
        if !interactive { SecKeychainSetUserInteractionAllowed(false) }
        defer { if !interactive { SecKeychainSetUserInteractionAllowed(true) } }
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed { throw Failure.needsAccess }
        guard status == errSecSuccess, let data = item as? Data,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let oauth = root["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String else { throw Failure.noLogin }
        if let exp = oauth["expiresAt"] as? Double, Date(timeIntervalSince1970: exp / 1000) < Date() { throw Failure.expired }
        return token
    }

    static func fetch(interactive: Bool) async throws -> AgentUsage {
        let token = try accessToken(interactive: interactive)
        var req = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 10)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, resp) = try await URLSession.shared.data(for: req)
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw Failure.http(code) }
        guard let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let usage = UsageParser.claude(["rate_limits": obj.filter { $0.value is [String: Any] }], now: Date()) else {
            throw Failure.badResponse
        }
        return usage
    }
}
