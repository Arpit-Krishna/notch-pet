import Foundation

/// Optional hooks that tell Pip the moment Claude Code or Codex shows a permission prompt.
/// The hook only appends the event to a file and exits; it prints nothing, so the agent
/// behaves exactly as if no hook were installed.
enum HookInstaller {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let dir = home.appendingPathComponent("Library/Application Support/NotchPet")
    static let scriptURL = dir.appendingPathComponent("pip-hook.sh")
    static let eventsURL = dir.appendingPathComponent("events.jsonl")
    static let marker = "NotchPet/pip-hook.sh"

    struct Target {
        let url: URL
        let agent: String
        let events: [(name: String, matcher: String?)]
    }

    static var targets: [Target] {
        var t = [Target(url: home.appendingPathComponent(".claude/settings.json"), agent: "claude",
                        events: [("PermissionRequest", nil), ("Notification", "permission_prompt")])]
        if FileManager.default.fileExists(atPath: home.appendingPathComponent(".codex").path) {
            t.append(Target(url: home.appendingPathComponent(".codex/hooks.json"), agent: "codex",
                            events: [("PermissionRequest", nil)]))
        }
        return t
    }

    /// True when any agent's settings route permission prompts to Pip.
    static var isInstalled: Bool { isInstalled(.claude) || isInstalled(.codex) }

    /// Whether this agent's own settings file contains Pip's hook. Claude runs it right away;
    /// Codex only after you trust it in `/hooks`, which Pip learns from the first Codex event.
    static func isInstalled(_ agent: Agent) -> Bool {
        guard let t = targets.first(where: { $0.agent == agent.rawValue }),
              let data = try? Data(contentsOf: t.url) else { return false }
        return String(decoding: data, as: UTF8.self).contains(marker)
    }

    static func install() throws {
        try writeScript()
        for t in targets {
            try modify(t.url) { hooks in
                strip(&hooks)
                for e in t.events {
                    var entry: [String: Any] = ["hooks": [["type": "command",
                                                            "command": "/bin/sh \"\(scriptURL.path)\" \(t.agent)",
                                                            "timeout": 5]]]
                    if let m = e.matcher { entry["matcher"] = m }
                    hooks[e.name] = (hooks[e.name] as? [Any] ?? []) + [entry]
                }
            }
        }
    }

    static func uninstall() throws {
        for t in targets { try modify(t.url) { strip(&$0) } }
    }

    // MARK: Claude usage via the status line

    /// Claude Code only reports plan limits (5-hour, weekly) to its status line command.
    /// Pip's status line saves that payload and then runs your previous status line, so
    /// what you see in the terminal doesn't change.
    static let statusScriptURL = dir.appendingPathComponent("pip-statusline.sh")
    static let statusURL = dir.appendingPathComponent("claude-status.jsonl")
    static let previousStatusURL = dir.appendingPathComponent("statusline-previous")
    static let statusMarker = "NotchPet/pip-statusline.sh"

    static var isStatusLineInstalled: Bool {
        guard let data = try? Data(contentsOf: targets[0].url) else { return false }
        return String(decoding: data, as: UTF8.self).contains(statusMarker)
    }

    static func installStatusLine() throws {
        try writeScript(statusScript, to: statusScriptURL)
        try modifyRoot(targets[0].url) { root in
            let current = root["statusLine"] as? [String: Any]
            if let cmd = current?["command"] as? String, !cmd.contains(statusMarker) {
                try? cmd.write(to: previousStatusURL, atomically: true, encoding: .utf8)
            }
            var line: [String: Any] = ["type": "command", "command": "/bin/sh \"\(statusScriptURL.path)\""]
            if let pad = current?["padding"] { line["padding"] = pad }
            root["statusLine"] = line
        }
    }

    static func uninstallStatusLine() throws {
        try modifyRoot(targets[0].url) { root in
            guard let cmd = (root["statusLine"] as? [String: Any])?["command"] as? String, cmd.contains(statusMarker) else { return }
            if let prev = try? String(contentsOf: previousStatusURL, encoding: .utf8), !prev.isEmpty {
                root["statusLine"] = ["type": "command", "command": prev]
            } else {
                root["statusLine"] = nil
            }
        }
    }

    private static let statusScript = #"""
    #!/bin/sh
    # Notch Pet status line: saves Claude Code's status payload (plan limits, cost) for Pip,
    # then prints your previous status line so the terminal looks the same.
    dir="$HOME/Library/Application Support/NotchPet"
    payload=$(cat)
    printf '%s\n' "$(printf '%s' "$payload" | tr -d '\n\r')" >> "$dir/claude-status.jsonl" 2>/dev/null
    if [ -s "$dir/statusline-previous" ]; then
      printf '%s' "$payload" | /bin/sh -c "$(cat "$dir/statusline-previous")"
    fi
    exit 0

    """#

    /// Removes Pip's entries, leaving every other hook untouched.
    private static func strip(_ hooks: inout [String: Any]) {
        for (event, value) in hooks {
            guard let entries = value as? [[String: Any]] else { continue }
            let kept = entries.filter { entry in
                let cmds = (entry["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String }
                return !cmds.contains { $0.contains(marker) }
            }
            if kept.isEmpty { hooks[event] = nil } else if kept.count != entries.count { hooks[event] = kept }
        }
    }

    /// Applies `change` to the file's "hooks" object.
    private static func modify(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        try modifyRoot(url) { root in
            var hooks = root["hooks"] as? [String: Any] ?? [:]
            change(&hooks)
            root["hooks"] = hooks.isEmpty ? nil : hooks
        }
    }

    /// Reads the JSON file, backs it up, applies `change` to the whole object and writes it back.
    private static func modifyRoot(_ url: URL, _ change: (inout [String: Any]) -> Void) throws {
        let fm = FileManager.default
        var root: [String: Any] = [:]
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw NSError(domain: "NotchPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(url.path) is not a JSON object"])
            }
            root = obj
            let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
            try? fm.copyItem(at: url, to: url.appendingPathExtension("notchpet-backup-\(stamp)"))
        } else {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        change(&root)
        let out = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try out.write(to: url, options: .atomic)
    }

    private static func writeScript(_ script: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private static func writeScript() throws {
        let script = #"""
        #!/bin/sh
        # Notch Pet: notes a permission prompt for Pip and exits at once.
        # Prints nothing, so Claude Code / Codex carry on exactly as without the hook.
        dir="$HOME/Library/Application Support/NotchPet"
        now=$(/usr/bin/perl -MTime::HiRes=time -e 'printf "%.3f", time' 2>/dev/null || date +%s)
        payload=$(head -c 1048576 | tr -d '\n\r')
        [ -n "$payload" ] && printf '{"agent":"%s","at":%s,"event":%s}\n' "${1:-claude}" "$now" "$payload" >> "$dir/events.jsonl" 2>/dev/null
        exit 0

        """#
        try writeScript(script, to: scriptURL)
    }
}
