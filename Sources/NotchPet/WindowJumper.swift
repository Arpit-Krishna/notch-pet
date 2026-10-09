import AppKit
import SwiftUI

/// Brings the window running a session to the front.
///
/// Finds the agent process running the session (see `resolve`), walks up its parent
/// processes to the app hosting it, then:
/// - Terminal / iTerm2: selects the exact tab by its tty (asks once for Automation permission)
/// - VS Code, Cursor, Windsurf, Zed: reopens the session's folder, which focuses that window
/// - anything else (Claude, ChatGPT/Codex, Warp, Ghostty…): activates the app
enum WindowJumper {
    fileprivate struct Proc { let pid: Int32; let ppid: Int32; let tty: String; let path: String }

    private static let folderEditors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf", "dev.zed.Zed", "com.vscodium",
    ]

    /// Where a click on a session would land.
    struct Target {
        fileprivate let agent: Proc?
        let app: NSRunningApplication?
        /// The process was tied to this very transcript, not just guessed from its folder.
        let exact: Bool
        /// How many agent processes run in the session's folder when we had to guess.
        let sameFolder: Int

        var ambiguous: Bool { !exact && sameFolder > 1 }
    }

    /// Finds the process behind a session. Exact links come first:
    /// - Claude Code writes ~/.claude/sessions/<pid>.json naming the session it runs, and
    ///   the transcript file is named after that session.
    /// - Codex keeps its rollout file open, so lsof shows which process writes it.
    /// Only when neither works does it fall back to matching the working directory.
    static func resolve(_ s: Session) -> Target? {
        let procs = processTable()
        let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let name = s.agent == .claude ? "claude" : "codex"
        let agents = procs.filter { ($0.path as NSString).lastPathComponent.lowercased() == name }
        let live = Dictionary(agents.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })

        let owner = s.agent == .claude ? claudeOwner(of: s.id, live: live) : codexOwner(of: s.id, pids: agents.map(\.pid))
        if let p = owner.flatMap({ live[$0] }) {
            return Target(agent: p, app: hostApp(of: p, byPid), exact: true, sameFolder: 1)
        }

        let cwds = workingDirectories(agents.map(\.pid))
        let inFolder = agents.filter { s.cwd != nil && cwds[$0.pid] == s.cwd }.sorted { $0.pid > $1.pid }
        if let p = inFolder.first {
            return Target(agent: p, app: hostApp(of: p, byPid), exact: false, sameFolder: inFolder.count)
        }
        // No live process: fall back to the desktop app the session came from.
        for bundle in desktopBundles(for: s) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
                return Target(agent: nil, app: app, exact: false, sameFolder: 0)
            }
        }
        return nil
    }

    /// Returns false when no window could be found (the session's process is gone).
    @discardableResult
    static func jump(to s: Session) -> Bool {
        guard let t = resolve(s), let app = t.app else { return false }
        let bundle = app.bundleIdentifier ?? ""
        if let agent = t.agent, agent.tty != "??" {
            if bundle == "com.apple.Terminal", runScript(terminalScript(tty: "/dev/" + agent.tty)) { return true }
            if bundle == "com.googlecode.iterm2", runScript(itermScript(tty: "/dev/" + agent.tty)) { return true }
        }
        if t.agent != nil, folderEditors.contains(bundle), let cwd = s.cwd, let appURL = app.bundleURL {
            NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            return true
        }
        bringToFront(app)
        return true
    }

    /// Tooltip for a session row: where a click goes, and whether that is a guess.
    static func hint(for s: Session) -> String {
        guard let t = resolve(s), let app = t.app else { return "Its window is gone (the chat has ended)" }
        let place = app.localizedName ?? "its app"
        if t.ambiguous {
            return "Click to go to \(place). \(t.sameFolder) chats run in this folder, so this may open the wrong one."
        }
        return "Click to go to this chat in \(place)"
    }

    private static func claudeOwner(of transcript: String, live: [Int32: Proc]) -> Int32? {
        let session = ((transcript as NSString).lastPathComponent as NSString).deletingPathExtension
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/sessions")
        for pid in live.keys {
            guard let data = try? Data(contentsOf: dir.appendingPathComponent("\(pid).json")),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            if o["sessionId"] as? String == session && (o["pid"] as? NSNumber)?.int32Value ?? pid == pid { return pid }
        }
        return nil
    }

    private static func codexOwner(of transcript: String, pids: [Int32]) -> Int32? {
        guard !pids.isEmpty else { return nil }
        var current: Int32?
        for line in run("/usr/sbin/lsof", ["-Fpn", "-p", pids.map(String.init).joined(separator: ",")]).split(separator: "\n") {
            if line.hasPrefix("p") { current = Int32(line.dropFirst()) }
            else if line.hasPrefix("n"), line.dropFirst() == transcript[...] { return current }
        }
        return nil
    }

    /// Desktop apps a session may have come from, most likely first.
    private static func desktopBundles(for s: Session) -> [String] {
        let client = (s.client ?? "").lowercased()
        guard client.contains("desktop") else { return [] }
        return s.agent == .claude ? ["com.anthropic.claudefordesktop"] : ["com.openai.codex", "com.openai.chat"]
    }

    /// Pip is a background app, so a plain `activate()` can be refused; asking Launch
    /// Services to open the running app always brings it forward.
    private static func bringToFront(_ app: NSRunningApplication) {
        guard let url = app.bundleURL else { app.activate(); return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config)
    }

    /// Walks up the parent chain to the first regular (Dock) app.
    private static func hostApp(of p: Proc, _ byPid: [Int32: Proc]) -> NSRunningApplication? {
        var pid = p.ppid
        var hops = 0
        while pid > 1 && hops < 40 {
            if let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular { return app }
            guard let parent = byPid[pid] else { break }
            pid = parent.ppid
            hops += 1
        }
        return nil
    }

    private static func run(_ tool: String, _ args: [String]) -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = args
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    private static func processTable() -> [Proc] {
        run("/bin/ps", ["-axo", "pid=,ppid=,tty=,comm="]).split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard parts.count == 4, let pid = Int32(parts[0]), let ppid = Int32(parts[1]) else { return nil }
            return Proc(pid: pid, ppid: ppid, tty: String(parts[2]), path: parts[3].trimmingCharacters(in: .whitespaces))
        }
    }

    private static func workingDirectories(_ pids: [Int32]) -> [Int32: String] {
        guard !pids.isEmpty else { return [:] }
        var out: [Int32: String] = [:]
        var current: Int32?
        for line in run("/usr/sbin/lsof", ["-a", "-d", "cwd", "-Fpn", "-p", pids.map(String.init).joined(separator: ",")]).split(separator: "\n") {
            if line.hasPrefix("p") { current = Int32(line.dropFirst()) }
            else if line.hasPrefix("n"), let pid = current { out[pid] = String(line.dropFirst()) }
        }
        return out
    }

    private static func runScript(_ source: String) -> Bool {
        var err: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&err)
        return err == nil && result?.booleanValue == true
    }

    private static func terminalScript(tty: String) -> String {
        """
        tell application "Terminal"
          repeat with w in windows
            repeat with t in tabs of w
              if tty of t is "\(tty)" then
                set selected tab of w to t
                set index of w to 1
                activate
                return true
              end if
            end repeat
          end repeat
        end tell
        return false
        """
    }

    private static func itermScript(tty: String) -> String {
        """
        tell application "iTerm2"
          repeat with w in windows
            repeat with t in tabs of w
              repeat with s in sessions of t
                if tty of s is "\(tty)" then
                  select w
                  select t
                  select s
                  activate
                  return true
                end if
              end repeat
            end repeat
          end repeat
        end tell
        return false
        """
    }
}

/// Click to jump: a pointing-hand cursor, a tooltip saying where the click goes (and
/// whether it is a guess), and a tap that jumps.
struct JumpOnClick: ViewModifier {
    let session: Session?
    @State private var hint = "Click to go to this chat's window"

    func body(content: Content) -> some View {
        if let session {
            content
                .contentShape(Rectangle())
                .onTapGesture { if !WindowJumper.jump(to: session) { NSSound.beep() } }
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                        // ps and lsof take a moment, so work out the tooltip off the main thread.
                        Task.detached(priority: .userInitiated) {
                            let text = WindowJumper.hint(for: session)
                            await MainActor.run { hint = text }
                        }
                    } else {
                        NSCursor.pop()
                    }
                }
                .help(hint)
        } else {
            content
        }
    }
}

extension View {
    func jumpOnClick(_ session: Session?) -> some View { modifier(JumpOnClick(session: session)) }
}
