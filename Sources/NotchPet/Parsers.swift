import Foundation

/// Reads a growing JSONL file incrementally.
final class Tail {
    let url: URL
    private(set) var offset: UInt64 = 0
    private var partial = Data()
    private(set) var hasRead = false

    init(url: URL) { self.url = url }

    func readNew(backfill: UInt64 = 512 * 1024) -> [String] {
        guard let h = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        if size < offset { offset = 0; partial.removeAll() }
        var skipFirst = false
        if !hasRead && size > backfill { offset = size - backfill; skipFirst = true }
        hasRead = true
        guard size > offset else { return [] }
        try? h.seek(toOffset: offset)
        let data = (try? h.read(upToCount: Int(size - offset))) ?? Data()
        offset += UInt64(data.count)
        let buf = partial + data
        guard let nl = buf.lastIndex(of: 0x0A) else { partial = buf; return [] }
        partial = Data(buf[buf.index(after: nl)...])
        var lines = buf[..<nl].split(separator: 0x0A).compactMap { String(data: Data($0), encoding: .utf8) }
        if skipFirst && !lines.isEmpty { lines.removeFirst() }
        return lines
    }

    /// First line of the file (Codex keeps its session metadata there).
    func firstLine(limit: Int = 4 * 1024 * 1024) -> String? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        var buf = Data()
        while buf.count < limit, let chunk = try? h.read(upToCount: 64 * 1024), !chunk.isEmpty {
            if let nl = chunk.firstIndex(of: 0x0A) {
                buf.append(chunk[..<nl])
                return String(data: buf, encoding: .utf8)
            }
            buf.append(chunk)
        }
        return nil
    }
}

private let isoFrac: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()
private let isoPlain = ISO8601DateFormatter()

func parseDate(_ v: Any?) -> Date? {
    guard let s = v as? String else { return nil }
    return isoFrac.date(from: s) ?? isoPlain.date(from: s)
}

func jsonObject(_ line: String) -> [String: Any]? {
    guard let d = line.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
}

private func base(_ v: Any?) -> String? {
    (v as? String).map { ($0 as NSString).lastPathComponent }
}

private func set(_ s: inout Session, _ p: Phase, _ activity: String, _ ts: Date) {
    s.phase = p
    s.activity = activity
    s.lastEvent = ts
    // Anything but a new tool call means a pending permission prompt was answered.
    if p != .working {
        s.permission = nil
        s.lastProgress = ts
    }
}

// MARK: - Claude Code (~/.claude/projects/<project>/<session>.jsonl)

enum ClaudeParser {
    static func apply(_ o: [String: Any], to s: inout Session) {
        let ts = parseDate(o["timestamp"]) ?? s.lastEvent
        if let cwd = o["cwd"] as? String, !cwd.isEmpty {
            s.cwd = cwd
            s.project = (cwd as NSString).lastPathComponent
        }
        if let b = o["gitBranch"] as? String, !b.isEmpty, b != "HEAD" { s.branch = b }
        let sidechain = o["isSidechain"] as? Bool ?? false
        let msg = o["message"] as? [String: Any]

        switch o["type"] as? String {
        case "user":
            if o["isMeta"] as? Bool == true { return }
            if sidechain { s.tool = "Task"; set(&s, .working, "Subagent at work", ts); return }
            if let text = msg?["content"] as? String {
                prompt(text, &s, ts)
            } else if let arr = msg?["content"] as? [[String: Any]] {
                if arr.contains(where: { $0["type"] as? String == "tool_result" }) {
                    s.tool = nil
                    set(&s, .thinking, "Thinking…", ts)
                } else if let t = arr.first(where: { $0["type"] as? String == "text" })?["text"] as? String {
                    prompt(t, &s, ts)
                }
            }
        case "assistant":
            if sidechain { s.tool = "Task"; set(&s, .working, "Subagent at work", ts); return }
            if let u = msg?["usage"] as? [String: Any] {
                let n = ["input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens"].compactMap { u[$0] as? Int }.reduce(0, +)
                if n > 0 { s.contextTokens = n }
            }
            let arr = msg?["content"] as? [[String: Any]] ?? []
            let text = arr.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
            if o["isApiErrorMessage"] as? Bool == true {
                set(&s, .error, shortText(text.isEmpty ? "API error" : text, 70), ts)
            } else if let tu = arr.last(where: { $0["type"] as? String == "tool_use" }) {
                let name = tu["name"] as? String ?? "tool"
                s.tool = name
                s.toolCount += 1
                set(&s, .working, describe(name, tu["input"] as? [String: Any] ?? [:]), ts)
            } else if let stop = msg?["stop_reason"] as? String, stop != "tool_use" {
                s.tool = nil
                set(&s, .done, text.isEmpty ? "Finished" : shortText(text, 90), ts)
            } else {
                set(&s, .thinking, text.isEmpty ? "Thinking…" : "Writing…", ts)
            }
        default:
            break
        }
    }

    private static func prompt(_ raw: String, _ s: inout Session, _ ts: Date) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("[Request interrupted") { s.tool = nil; set(&s, .idle, "Interrupted", ts); return }
        if text.hasPrefix("<") || text.isEmpty { return }   // slash-command echoes, reminders
        s.lastPrompt = shortText(text, 90)
        s.turnStart = ts
        s.toolCount = 0
        s.tool = nil
        set(&s, .thinking, "Thinking…", ts)
    }

    static func describe(_ name: String, _ input: [String: Any]) -> String {
        switch name {
        case "Read": return "Reading \(base(input["file_path"]) ?? "a file")"
        case "Edit", "MultiEdit": return "Editing \(base(input["file_path"]) ?? "a file")"
        case "Write": return "Writing \(base(input["file_path"]) ?? "a file")"
        case "NotebookEdit": return "Editing \(base(input["notebook_path"]) ?? "a notebook")"
        case "Bash": return "Running \(shortText(input["command"] as? String ?? "a command", 48))"
        case "Grep": return "Searching “\(shortText(input["pattern"] as? String ?? "", 30))”"
        case "Glob": return "Finding \(shortText(input["pattern"] as? String ?? "files", 30))"
        case "WebFetch": return "Reading a web page"
        case "WebSearch": return "Searching the web"
        case "Task", "Agent": return "Delegating: \(shortText(input["description"] as? String ?? "subagent", 40))"
        case "TodoWrite": return "Updating the todo list"
        case "Skill": return "Using skill \(input["skill"] as? String ?? "")"
        default:
            if name.hasPrefix("mcp__") {
                let tool = name.components(separatedBy: "__").last ?? name
                return "Using \(tool.replacingOccurrences(of: "_", with: " "))"
            }
            return "Using \(name)"
        }
    }
}

// MARK: - Codex (~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl)

enum CodexParser {
    static func apply(_ o: [String: Any], to s: inout Session) {
        let ts = parseDate(o["timestamp"]) ?? s.lastEvent
        let p = o["payload"] as? [String: Any] ?? [:]
        if let cwd = p["cwd"] as? String, !cwd.isEmpty {
            s.cwd = cwd
            s.project = (cwd as NSString).lastPathComponent
        }
        if let git = p["git"] as? [String: Any], let b = git["branch"] as? String, !b.isEmpty { s.branch = b }

        switch o["type"] as? String {
        case "event_msg":
            switch p["type"] as? String {
            case "task_started":
                s.turnStart = ts; s.toolCount = 0; s.tool = nil
                set(&s, .thinking, "Thinking…", ts)
            case "task_complete":
                s.tool = nil
                let msg = p["last_agent_message"] as? String ?? ""
                set(&s, .done, msg.isEmpty ? "Finished" : shortText(msg, 90), ts)
            case "turn_aborted":
                s.tool = nil
                set(&s, .idle, "Interrupted", ts)
            case "token_count":
                if let info = p["info"] as? [String: Any] {
                    if let last = info["last_token_usage"] as? [String: Any], let n = last["input_tokens"] as? Int { s.contextTokens = n }
                    if let w = info["model_context_window"] as? Int { s.contextLimit = w }
                }
                if let rl = p["rate_limits"] as? [String: Any] { s.codexLimits = UsageParser.codex(rl, at: ts) }
            case "error", "stream_error":
                set(&s, .error, shortText(p["message"] as? String ?? "Error", 70), ts)
            default: break
            }
        case "response_item":
            switch p["type"] as? String {
            case "message":
                let role = p["role"] as? String
                let text = (p["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }.joined(separator: " ")
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if role == "user", !trimmed.isEmpty, !trimmed.hasPrefix("<") {
                    s.lastPrompt = shortText(trimmed, 90)
                    if !s.phase.isBusy { s.turnStart = ts; set(&s, .thinking, "Thinking…", ts) }
                } else if role == "assistant", s.phase.isBusy {
                    set(&s, .thinking, "Writing…", ts)
                }
            case "function_call", "custom_tool_call", "local_shell_call", "web_search_call":
                let name = p["name"] as? String ?? (p["type"] as? String == "web_search_call" ? "web_search" : "shell")
                s.tool = name
                s.toolCount += 1
                set(&s, .working, describe(name, p), ts)
            case "function_call_output", "custom_tool_call_output", "local_shell_call_output":
                s.tool = nil
                if s.phase.isBusy { set(&s, .thinking, "Thinking…", ts) }
            case "reasoning":
                if s.phase == .thinking { set(&s, .thinking, "Reasoning…", ts) }
            default: break
            }
        default:
            break
        }
    }

    static func describe(_ name: String, _ p: [String: Any]) -> String {
        var args: [String: Any] = [:]
        if let a = p["arguments"] as? String, let o = jsonObject(a) { args = o }
        let input = p["input"] as? String ?? ""
        switch name {
        case "shell", "exec_command", "local_shell", "container.exec":
            var cmd = ""
            if let arr = (args["command"] ?? args["cmd"]) as? [String] { cmd = arr.last ?? "" }
            else if let c = (args["cmd"] ?? args["command"]) as? String { cmd = c }
            if let action = p["action"] as? [String: Any], let arr = action["command"] as? [String] { cmd = arr.last ?? cmd }
            return "Running \(shortText(cmd.isEmpty ? "a command" : cmd, 48))"
        case "apply_patch":
            let src = input.isEmpty ? (args["input"] as? String ?? "") : input
            for line in src.split(separator: "\n") {
                for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] where line.hasPrefix(prefix) {
                    return "Editing \((String(line.dropFirst(prefix.count)) as NSString).lastPathComponent)"
                }
            }
            return "Editing files"
        case "update_plan": return "Updating the plan"
        case "web_search": return "Searching the web"
        case "view_image": return "Looking at an image"
        default: return "Using \(name.replacingOccurrences(of: "_", with: " "))"
        }
    }
}
