import Foundation
import SwiftUI

enum Agent: String {
    case claude, codex

    var label: String { self == .claude ? "Claude" : "Codex" }
    var tint: Color {
        switch self {
        case .claude: return Color(red: 0.85, green: 0.47, blue: 0.34)
        case .codex: return Color(red: 0.40, green: 0.78, blue: 0.95)
        }
    }
    var glyph: String { self == .claude ? "✳︎" : ">_" }
}

enum Phase: Int, Equatable {
    // Raw value doubles as sort priority (lower = more urgent).
    case waiting = 0, working = 1, thinking = 2, error = 3, done = 4, idle = 5

    var label: String {
        switch self {
        case .waiting: return "Needs you?"
        case .working: return "Working"
        case .thinking: return "Thinking"
        case .error: return "Error"
        case .done: return "Done"
        case .idle: return "Idle"
        }
    }
    var color: Color {
        switch self {
        case .waiting: return Color(red: 1.0, green: 0.76, blue: 0.22)
        case .working, .thinking: return Color(red: 0.45, green: 0.72, blue: 1.0)
        case .error: return Color(red: 1.0, green: 0.42, blue: 0.42)
        case .done: return Color(red: 0.42, green: 0.88, blue: 0.56)
        case .idle: return Color.white.opacity(0.35)
        }
    }
    var isBusy: Bool { self == .working || self == .thinking }
}

struct Session: Identifiable, Equatable {
    let id: String          // transcript file path
    let agent: Agent
    var project: String = "…"
    var cwd: String?
    var branch: String?
    /// Where the agent runs: Claude's "entrypoint" (cli, claude-desktop…) or Codex's "originator".
    var client: String?
    var phase: Phase = .idle
    var activity: String = ""
    var tool: String?
    var lastPrompt: String = ""
    var turnStart: Date?
    var lastEvent: Date = .distantPast
    var toolCount: Int = 0
    /// Set by the optional permission hook; cleared by the next sign of progress in the transcript.
    var permission: String?
    /// Transcript time of the last line that shows the turn moved on (tool result, prompt, finish…).
    var lastProgress: Date = .distantPast
    /// Tokens in the context window after the last model call, and the window size when known.
    var contextTokens: Int?
    var contextLimit: Int?
    var costUSD: Double?
    var codexLimits: AgentUsage?

    func displayPhase(at now: Date) -> Phase {
        if permission != nil { return .waiting }
        let quiet = now.timeIntervalSince(lastEvent)
        if phase.isBusy && quiet > 600 { return .idle }
        // Without the hook, transcripts can't tell us about permission prompts, so a tool
        // call that has gone quiet for a while is shown as possibly needing the user.
        if phase == .working && quietHeuristicEnabled {
            let longRunning: Set<String> = ["Task", "Agent", "Bash", "shell", "exec_command", "local_shell", "BashOutput", "Monitor"]
            let threshold: TimeInterval = longRunning.contains(tool ?? "") ? 45 : 12
            if tool == "Task" || tool == "Agent" || tool == "Monitor" { return .working }
            if quiet > threshold { return .waiting }
        }
        return phase
    }
}

/// Off once the permission hook is installed: then "needs you" comes from real events only.
nonisolated(unsafe) var quietHeuristicEnabled = true

enum Mood: Hashable {
    case sleeping, awake, busy, alert, happy, sad
}

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let agent: Agent
    let phase: Phase
    let title: String
    let detail: String
    /// Overrides the block theme's popup header ("Advancement made!", "Needs you!"…).
    var header: String? = nil
    /// The session to jump to when the popup is clicked.
    var sessionID: String? = nil
}

func shortText(_ s: String, _ n: Int) -> String {
    let line = s.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    let t = line.trimmingCharacters(in: .whitespaces)
    return t.count > n ? String(t.prefix(n - 1)) + "…" : t
}

func relative(_ d: Date, now: Date) -> String {
    let s = Int(max(0, now.timeIntervalSince(d)))
    if s < 60 { return "\(s)s" }
    if s < 3600 { return "\(s / 60)m" }
    return "\(s / 3600)h"
}

func clock(_ seconds: TimeInterval) -> String {
    let s = Int(max(0, seconds))
    return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, (s / 60) % 60, s % 60)
                     : String(format: "%d:%02d", s / 60, s % 60)
}
