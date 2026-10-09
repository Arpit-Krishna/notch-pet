import AppKit
import SwiftUI

/// Brings the window running a session to the front.
///
/// Finds the agent process whose working directory matches the session, walks up its
/// parent processes to the app hosting it, then:
/// - Terminal / iTerm2: selects the exact tab by its tty (asks once for Automation permission)
/// - VS Code, Cursor, Windsurf, Zed: reopens the session's folder, which focuses that window
/// - anything else (Claude, ChatGPT/Codex, Warp, Ghostty…): activates the app
enum WindowJumper {
    private struct Proc { let pid: Int32; let ppid: Int32; let tty: String; let path: String }

    private static let folderEditors: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92",  // Cursor
        "com.exafunction.windsurf", "dev.zed.Zed", "com.vscodium",
    ]

    /// Returns false when no window could be found (the session's process is gone).
    @discardableResult
    static func jump(to s: Session) -> Bool {
        let procs = processTable()
        let byPid = Dictionary(procs.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let names = s.agent == .claude ? ["claude"] : ["codex"]
        let agents = procs.filter { p in names.contains((p.path as NSString).lastPathComponent.lowercased()) }
        let cwds = workingDirectories(agents.map(\.pid))
        // Prefer an agent running in the session's folder; newest process first.
        let match = agents.sorted { $0.pid > $1.pid }.first { s.cwd != nil && cwds[$0.pid] == s.cwd }

        if let agent = match, let app = hostApp(of: agent, byPid) {
            let bundle = app.bundleIdentifier ?? ""
            if bundle == "com.apple.Terminal", agent.tty != "??", runScript(terminalScript(tty: "/dev/" + agent.tty)) { return true }
            if bundle == "com.googlecode.iterm2", agent.tty != "??", runScript(itermScript(tty: "/dev/" + agent.tty)) { return true }
            if folderEditors.contains(bundle), let cwd = s.cwd, let appURL = app.bundleURL {
                NSWorkspace.shared.open([URL(fileURLWithPath: cwd)], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
                return true
            }
            bringToFront(app)
            return true
        }

        // No live process: fall back to the desktop app the session came from.
        for bundle in desktopBundles(for: s) {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first {
                bringToFront(app)
                return true
            }
        }
        return false
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

/// Click to jump: a pointing-hand cursor, a tooltip, and a tap that runs `jump`.
struct JumpOnClick: ViewModifier {
    let enabled: Bool
    let jump: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content
                .contentShape(Rectangle())
                .onTapGesture(perform: jump)
                .onHover { inside in if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() } }
                .help("Click to go to this chat's window")
        } else {
            content
        }
    }
}

extension View {
    func jumpOnClick(_ session: Session?) -> some View {
        modifier(JumpOnClick(enabled: session != nil) {
            if let s = session, !WindowJumper.jump(to: s) { NSSound.beep() }
        })
    }
}
