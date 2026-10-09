import AppKit
import ApplicationServices

/// Regular Claude chats run on Anthropic's servers and leave no local log, so this reads the
/// Claude desktop app's interface through Accessibility instead: the open chat's title and URL,
/// whether a Stop button is showing (Claude is answering) and whether an Allow button is
/// showing (a tool is waiting for your OK). Needs Accessibility permission; off by default.
enum ChatWatcher {
    struct ChatState: Equatable {
        let id: String          // chat id from the claude.ai URL
        let title: String
        let generating: Bool
        let needsApproval: Bool
    }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that sends the user to Privacy & Security → Accessibility.
    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Reads the chat shown in each Claude window. Safe to call off the main thread.
    static func poll() -> [ChatState] {
        guard AXIsProcessTrusted(),
              let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.anthropic.claudefordesktop").first else { return [] }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        // Electron apps only build their accessibility tree when asked to.
        AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var chats: [ChatState] = []
        var budget = 6000
        for area in webAreas(in: root, budget: &budget) {
            guard let url = string(area, "AXURL"), let r = url.range(of: "claude.ai/chat/") else { continue }
            let id = String(url[r.upperBound...].prefix { $0 != "?" && $0 != "#" && $0 != "/" })
            var title = string(area, "AXTitle") ?? "Claude chat"
            if title.hasSuffix(" - Claude") { title = String(title.dropLast(9)) }
            var stop = false, allow = false
            var inner = 6000
            scanButtons(area, budget: &inner) { label in
                let l = label.lowercased()
                if l.hasPrefix("stop") { stop = true }
                if l.hasPrefix("allow") { allow = true }
            }
            chats.append(ChatState(id: id, title: title.isEmpty ? "Claude chat" : title, generating: stop || allow, needsApproval: allow))
        }
        return chats
    }

    private static func string(_ e: AXUIElement, _ key: String) -> String? {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(e, key as CFString, &v)
        if let s = v as? String { return s }
        if let u = v as? URL { return u.absoluteString }
        return nil
    }

    private static func children(_ e: AXUIElement) -> [AXUIElement] {
        var v: CFTypeRef?
        AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &v)
        return (v as? [AXUIElement]) ?? []
    }

    private static func webAreas(in e: AXUIElement, budget: inout Int) -> [AXUIElement] {
        guard budget > 0 else { return [] }
        budget -= 1
        if string(e, kAXRoleAttribute) == "AXWebArea", string(e, "AXURL")?.contains("claude.ai") == true { return [e] }
        var out: [AXUIElement] = []
        for c in children(e) { out += webAreas(in: c, budget: &budget) }
        return out
    }

    private static func scanButtons(_ e: AXUIElement, budget: inout Int, _ found: (String) -> Void) {
        guard budget > 0 else { return }
        budget -= 1
        if string(e, kAXRoleAttribute) == "AXButton" {
            let label = [string(e, kAXDescriptionAttribute), string(e, kAXTitleAttribute)].compactMap { $0 }.joined(separator: " ")
            if !label.isEmpty { found(label) }
        }
        for c in children(e) { scanButtons(c, budget: &budget, found) }
    }
}
