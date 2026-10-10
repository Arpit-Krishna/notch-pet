import Foundation
import Testing
@testable import NotchPet

/// Installs into a scratch home folder, never the real ~/.claude or ~/.codex.
@Suite(.serialized) final class HookInstallerTests {
    let home: URL
    let realHome = HookInstaller.home
    var claudeSettings: URL { home.appendingPathComponent(".claude/settings.json") }
    var codexHooks: URL { home.appendingPathComponent(".codex/hooks.json") }

    init() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent("notchpet-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        HookInstaller.home = home
    }

    deinit {
        HookInstaller.home = realHome
        try? FileManager.default.removeItem(at: home)
    }

    // MARK: Helpers

    private func useCodex() throws {
        try FileManager.default.createDirectory(at: home.appendingPathComponent(".codex"), withIntermediateDirectories: true)
    }

    private func write(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    private func read(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    private func hooks(_ url: URL) throws -> [String: [[String: Any]]] {
        (try read(url)["hooks"] as? [String: [[String: Any]]]) ?? [:]
    }

    private func commands(_ entries: [[String: Any]]?) -> [String] {
        (entries ?? []).flatMap { ($0["hooks"] as? [[String: Any]] ?? []).compactMap { $0["command"] as? String } }
    }

    private func backups(of url: URL) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)) ?? []
        return names.filter { $0.hasPrefix(url.lastPathComponent + ".notchpet-backup-") }
    }

    /// Runs a hook script the way the agents do: `/bin/sh script args`, payload on stdin.
    @discardableResult
    private func run(_ script: URL, _ args: [String] = [], stdin: String) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script.path] + args
        p.environment = ["HOME": home.path, "PATH": "/usr/bin:/bin"]
        let input = Pipe(), output = Pipe()
        p.standardInput = input
        p.standardOutput = output
        try p.run()
        input.fileHandleForWriting.write(Data(stdin.utf8))
        try input.fileHandleForWriting.close()
        p.waitUntilExit()
        #expect(p.terminationStatus == 0)
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    private func lines(_ url: URL) throws -> [String] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map(String.init)
    }

    // MARK: Permission hooks

    @Test func installForBothAgents() throws {
        try useCodex()
        try HookInstaller.install()

        let claude = try hooks(claudeSettings)
        #expect(Set(claude.keys) == ["PermissionRequest", "Notification"])
        #expect(claude["Notification"]?.first?["matcher"] as? String == "permission_prompt")
        #expect(claude["PermissionRequest"]?.first?["matcher"] == nil)
        #expect(commands(claude["PermissionRequest"]) == ["/bin/sh \"\(HookInstaller.scriptURL.path)\" claude"])

        let codex = try hooks(codexHooks)
        #expect(Array(codex.keys) == ["PermissionRequest"])
        #expect(commands(codex["PermissionRequest"]) == ["/bin/sh \"\(HookInstaller.scriptURL.path)\" codex"])

        #expect(HookInstaller.isInstalled(.claude))
        #expect(HookInstaller.isInstalled(.codex))
        let perms = try FileManager.default.attributesOfItem(atPath: HookInstaller.scriptURL.path)[.posixPermissions] as? Int
        #expect(perms == 0o755)
    }

    @Test func codexSkippedWhenNotInstalled() throws {
        try HookInstaller.install()
        #expect(HookInstaller.isInstalled(.claude))
        #expect(!HookInstaller.isInstalled(.codex))
        #expect(!FileManager.default.fileExists(atPath: codexHooks.path))
    }

    @Test func keepsUserSettingsAndHooks() throws {
        try write(#"""
        {"model":"opus","permissions":{"allow":["Bash(ls)"]},
         "hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"say hi"}]}],
                  "Stop":[{"hooks":[{"type":"command","command":"afplay done.aiff"}]}]}}
        """#, to: claudeSettings)
        try HookInstaller.install()

        let root = try read(claudeSettings)
        #expect(root["model"] as? String == "opus")
        #expect((root["permissions"] as? [String: Any])?["allow"] as? [String] == ["Bash(ls)"])
        let h = try hooks(claudeSettings)
        #expect(commands(h["Stop"]) == ["afplay done.aiff"])
        #expect(commands(h["PermissionRequest"]).count == 2)
        #expect(commands(h["PermissionRequest"]).first == "say hi")   // Pip's entry goes after the user's
        #expect(backups(of: claudeSettings).count == 1)
    }

    @Test func installTwiceDoesNotDuplicate() throws {
        try HookInstaller.install()
        try HookInstaller.install()
        let h = try hooks(claudeSettings)
        #expect(commands(h["PermissionRequest"]).count == 1)
        #expect(commands(h["Notification"]).count == 1)
    }

    @Test func uninstallRemovesOnlyPip() throws {
        try useCodex()
        try write(#"{"hooks":{"PermissionRequest":[{"hooks":[{"type":"command","command":"say hi"}]}]}}"#, to: claudeSettings)
        try HookInstaller.install()
        try HookInstaller.uninstall()

        let h = try hooks(claudeSettings)
        #expect(Array(h.keys) == ["PermissionRequest"])
        #expect(commands(h["PermissionRequest"]) == ["say hi"])
        #expect(!HookInstaller.isInstalled)
        // Codex had nothing else, so its "hooks" key goes away entirely.
        #expect(try read(codexHooks)["hooks"] == nil)
    }

    @Test func uninstallWhenNothingInstalled() throws {
        try HookInstaller.uninstall()
        #expect(!HookInstaller.isInstalled)
        #expect(try read(claudeSettings).isEmpty)
    }

    @Test func refusesSettingsThatAreNotAnObject() throws {
        try write("[1, 2, 3]", to: claudeSettings)
        #expect(throws: (any Error).self) { try HookInstaller.install() }
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8) == "[1, 2, 3]")
    }

    @Test func refusesBrokenJSON() throws {
        try write(#"{"hooks": {"#, to: claudeSettings)
        #expect(throws: (any Error).self) { try HookInstaller.install() }
        #expect(try String(contentsOf: claudeSettings, encoding: .utf8) == #"{"hooks": {"#)
    }

    @Test func hookScriptAppendsOneLinePerEvent() throws {
        try HookInstaller.install()
        let out = try run(HookInstaller.scriptURL, ["codex"], stdin: "{\"tool_name\":\"Bash\",\n\"tool_input\":{\"command\":\"rm -rf build\"}}\n")
        #expect(out.isEmpty)   // the agent must see no output

        let events = try lines(HookInstaller.eventsURL)
        #expect(events.count == 1)
        let o = try #require(jsonObject(events[0]))
        #expect(o["agent"] as? String == "codex")
        #expect((o["at"] as? Double ?? 0) > 1_700_000_000)
        #expect((o["event"] as? [String: Any])?["tool_name"] as? String == "Bash")
    }

    @Test func hookScriptIgnoresEmptyPayload() throws {
        try HookInstaller.install()
        try run(HookInstaller.scriptURL, ["claude"], stdin: "")
        #expect(!FileManager.default.fileExists(atPath: HookInstaller.eventsURL.path))
    }

    // MARK: Status line

    @Test func statusLineWrapsAndRestoresPrevious() throws {
        try write(#"{"statusLine":{"type":"command","command":"echo mine","padding":2}}"#, to: claudeSettings)
        try HookInstaller.installStatusLine()

        let line = try #require(try read(claudeSettings)["statusLine"] as? [String: Any])
        #expect(line["command"] as? String == "/bin/sh \"\(HookInstaller.statusScriptURL.path)\"")
        #expect(line["padding"] as? Int == 2)
        #expect(HookInstaller.isStatusLineInstalled)
        #expect(try String(contentsOf: HookInstaller.previousStatusURL, encoding: .utf8) == "echo mine")

        // Installing again must not save Pip's own command as "previous".
        try HookInstaller.installStatusLine()
        #expect(try String(contentsOf: HookInstaller.previousStatusURL, encoding: .utf8) == "echo mine")

        try HookInstaller.uninstallStatusLine()
        let restored = try #require(try read(claudeSettings)["statusLine"] as? [String: Any])
        #expect(restored["command"] as? String == "echo mine")
        #expect(!HookInstaller.isStatusLineInstalled)
    }

    @Test func statusLineRemovedWhenThereWasNone() throws {
        try HookInstaller.installStatusLine()
        try HookInstaller.uninstallStatusLine()
        #expect(try read(claudeSettings)["statusLine"] == nil)
    }

    @Test func uninstallLeavesSomeoneElsesStatusLine() throws {
        try write(#"{"statusLine":{"type":"command","command":"starship"}}"#, to: claudeSettings)
        try HookInstaller.uninstallStatusLine()
        #expect((try read(claudeSettings)["statusLine"] as? [String: Any])?["command"] as? String == "starship")
    }

    @Test func statusScriptSavesPayloadAndRunsPrevious() throws {
        try write(#"{"statusLine":{"type":"command","command":"cat | wc -c | tr -d ' '"}}"#, to: claudeSettings)
        try HookInstaller.installStatusLine()

        let payload = "{\"rate_limits\":{\"five_hour\":\n{\"used_percentage\":12}}}"
        let out = try run(HookInstaller.statusScriptURL, stdin: payload)
        #expect(out.trimmingCharacters(in: .whitespacesAndNewlines) == "\(payload.utf8.count)")

        let saved = try lines(HookInstaller.statusURL)
        #expect(saved.count == 1)
        let u = UsageParser.claude(try #require(jsonObject(saved[0])), now: Date())
        #expect(u?.windows.first?.usedPct == 12)
    }
}
