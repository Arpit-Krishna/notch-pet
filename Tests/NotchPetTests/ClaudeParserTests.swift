import Foundation
import Testing
@testable import NotchPet

@Suite struct ClaudeParserTests {
    private func session() -> Session { Session(id: "/tmp/claude.jsonl", agent: .claude) }

    private func apply(_ json: String, to s: inout Session) {
        ClaudeParser.apply(jsonObject(json)!, to: &s)
    }

    @Test func fixtureTurnEndsDone() throws {
        var s = session()
        let applied = feed(try Fixture.lines("claude-session.jsonl"), into: &s)

        #expect(applied == 8)   // the "not json at all" line is skipped
        #expect(s.phase == .done)
        #expect(s.activity == "All tests pass.")   // only the first line of the reply
        #expect(s.tool == nil)
        #expect(s.toolCount == 2)
        #expect(s.lastPrompt == "Add tests for the parsers")
        #expect(s.turnStart == date("2026-10-09T10:00:00.000Z"))
        #expect(s.lastEvent == date("2026-10-09T10:00:10.000Z"))
        #expect(s.cwd == "/Users/me/code/notch-pet")
        #expect(s.project == "notch-pet")
        #expect(s.branch == "main")
        #expect(s.client == "cli")
        #expect(s.contextTokens == 2310)
    }

    @Test func fixtureStepByStep() throws {
        let lines = try Fixture.lines("claude-session.jsonl")
        var s = session()

        feed(Array(lines[0...1]), into: &s)   // prompt + ignored meta line
        #expect(s.phase == .thinking)
        #expect(s.activity == "Thinking…")
        #expect(s.lastEvent == date("2026-10-09T10:00:00.000Z"))

        feed([lines[2]], into: &s)
        #expect(s.phase == .working)
        #expect(s.tool == "Read")
        #expect(s.activity == "Reading Parsers.swift")

        feed([lines[3]], into: &s)
        #expect(s.phase == .thinking)
        #expect(s.tool == nil)

        feed([lines[4]], into: &s)
        #expect(s.phase == .working)
        #expect(s.activity == "Running swift test")
    }

    @Test func interruptGoesIdle() {
        var s = session()
        apply(#"{"type":"user","timestamp":"2026-10-09T10:00:00Z","message":{"content":"Fix it"}}"#, to: &s)
        apply(#"{"type":"user","timestamp":"2026-10-09T10:00:05Z","message":{"content":[{"type":"text","text":"[Request interrupted by user]"}]}}"#, to: &s)
        #expect(s.phase == .idle)
        #expect(s.activity == "Interrupted")
        #expect(s.lastPrompt == "Fix it")
    }

    @Test func slashCommandEchoIsNotAPrompt() {
        var s = session()
        apply(#"{"type":"user","timestamp":"2026-10-09T10:00:00Z","message":{"content":"<command-name>/clear</command-name>"}}"#, to: &s)
        #expect(s.phase == .idle)
        #expect(s.lastPrompt == "")
    }

    @Test func promptFromTextBlock() {
        var s = session()
        apply(#"{"type":"user","timestamp":"2026-10-09T10:00:00Z","message":{"content":[{"type":"text","text":"  Ship it\nplease  "}]}}"#, to: &s)
        #expect(s.phase == .thinking)
        #expect(s.lastPrompt == "Ship it")
    }

    @Test func sidechainCountsAsSubagent() {
        var s = session()
        apply(#"{"type":"assistant","isSidechain":true,"timestamp":"2026-10-09T10:00:00Z","message":{"content":[{"type":"text","text":"done"}],"stop_reason":"end_turn"}}"#, to: &s)
        #expect(s.phase == .working)
        #expect(s.tool == "Task")
        #expect(s.activity == "Subagent at work")
    }

    @Test func apiErrorMessage() {
        var s = session()
        apply(#"{"type":"assistant","isApiErrorMessage":true,"timestamp":"2026-10-09T10:00:00Z","message":{"content":[{"type":"text","text":"API Error: 529 Overloaded"}]}}"#, to: &s)
        #expect(s.phase == .error)
        #expect(s.activity == "API Error: 529 Overloaded")
    }

    @Test func streamingTextIsWriting() {
        var s = session()
        apply(#"{"type":"assistant","timestamp":"2026-10-09T10:00:00Z","message":{"content":[{"type":"text","text":"partial"}],"stop_reason":null}}"#, to: &s)
        #expect(s.phase == .thinking)
        #expect(s.activity == "Writing…")
    }

    @Test func detachedHeadBranchIgnored() {
        var s = session()
        s.branch = "main"
        apply(#"{"type":"user","gitBranch":"HEAD","timestamp":"2026-10-09T10:00:00Z","message":{"content":"x"}}"#, to: &s)
        #expect(s.branch == "main")
    }

    @Test func missingTimestampKeepsLastEvent() {
        var s = session()
        let earlier = date("2026-10-09T09:00:00Z")
        s.lastEvent = earlier
        apply(#"{"type":"user","message":{"content":"no timestamp here"}}"#, to: &s)
        #expect(s.lastEvent == earlier)
        #expect(s.lastPrompt == "no timestamp here")
    }

    @Test func permissionClearsOnProgressNotOnNewToolCall() {
        var s = session()
        s.permission = "Bash"
        apply(#"{"type":"assistant","timestamp":"2026-10-09T10:00:00Z","message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"ls"}}]}}"#, to: &s)
        #expect(s.permission == "Bash")
        apply(#"{"type":"user","timestamp":"2026-10-09T10:00:01Z","message":{"content":[{"type":"tool_result","content":"ok"}]}}"#, to: &s)
        #expect(s.permission == nil)
        #expect(s.lastProgress == date("2026-10-09T10:00:01Z"))
    }

    @Test(arguments: [
        ("Edit", #"{"file_path":"/a/b/Main.swift"}"#, "Editing Main.swift"),
        ("Write", "{}", "Writing a file"),
        ("Grep", #"{"pattern":"TODO"}"#, "Searching “TODO”"),
        ("Task", #"{"description":"Find callers"}"#, "Delegating: Find callers"),
        ("mcp__github__create_pull_request", "{}", "Using create pull request"),
        ("SomethingNew", "{}", "Using SomethingNew"),
    ])
    func describe(name: String, input: String, expected: String) {
        #expect(ClaudeParser.describe(name, jsonObject(input)!) == expected)
    }
}
