import Foundation
import Testing
@testable import NotchPet

@Suite struct CodexParserTests {
    private func session() -> Session { Session(id: "/tmp/rollout.jsonl", agent: .codex) }

    private func apply(_ json: String, to s: inout Session) {
        CodexParser.apply(jsonObject(json)!, to: &s)
    }

    @Test func fixtureTurnEndsDone() throws {
        var s = session()
        feed(try Fixture.lines("codex-rollout.jsonl"), into: &s)

        #expect(s.phase == .done)
        #expect(s.activity == "Fixed the flaky test by waiting for the file.")
        #expect(s.lastPrompt == "Fix the flaky test")
        #expect(s.turnStart == date("2026-10-09T11:00:02.000Z"))
        #expect(s.toolCount == 2)
        #expect(s.tool == nil)
        #expect(s.cwd == "/Users/me/code/pip")
        #expect(s.project == "pip")
        #expect(s.branch == "feature/x")
        #expect(s.client == "codex_cli_rs")
        #expect(s.contextTokens == 42000)
        #expect(s.contextLimit == 272000)
    }

    @Test func fixtureStepByStep() throws {
        let lines = try Fixture.lines("codex-rollout.jsonl")
        var s = session()

        feed(Array(lines[0...1]), into: &s)   // metadata + environment context
        #expect(s.phase == .idle)
        #expect(s.lastPrompt == "")

        feed(Array(lines[2...4]), into: &s)   // task_started, prompt, reasoning
        #expect(s.phase == .thinking)
        #expect(s.activity == "Reasoning…")

        feed([lines[5]], into: &s)
        #expect(s.phase == .working)
        #expect(s.tool == "shell")
        #expect(s.activity == "Running swift test")

        feed([lines[6]], into: &s)
        #expect(s.phase == .thinking)
        #expect(s.tool == nil)

        feed([lines[7]], into: &s)
        #expect(s.activity == "Editing Store.swift")

        feed(Array(lines[8...10]), into: &s)
        #expect(s.activity == "Writing…")
    }

    @Test func fixtureRateLimits() throws {
        var s = session()
        feed(try Fixture.lines("codex-rollout.jsonl"), into: &s)
        let u = try #require(s.codexLimits)
        let ts = date("2026-10-09T11:00:11.000Z")

        #expect(u.updated == ts)
        #expect(u.plan == "plus")
        #expect(u.windows.map(\.label) == ["Session (5h)", "Weekly"])
        #expect(u.windows[0].usedPct == 37.5)
        #expect(u.windows[0].resetsAt == ts.addingTimeInterval(3600))
        #expect(u.windows[1].resetsAt == Date(timeIntervalSince1970: 1_791_000_000))
    }

    @Test func metadataFromFirstLineOnly() throws {
        // SessionStore reads just the first line when it discovers a rollout.
        let file = TempFile()
        try file.write(try Fixture.lines("codex-rollout.jsonl").joined(separator: "\n") + "\n")
        var s = session()
        let first = try #require(Tail(url: file.url).firstLine())
        CodexParser.apply(try #require(jsonObject(first)), to: &s)
        #expect(s.project == "pip")
        #expect(s.phase == .idle)
    }

    @Test func promptWhileIdleStartsTurn() {
        var s = session()
        apply(#"{"timestamp":"2026-10-09T11:00:00Z","type":"response_item","payload":{"type":"message","role":"user","content":[{"type":"input_text","text":"hello"}]}}"#, to: &s)
        #expect(s.phase == .thinking)
        #expect(s.turnStart == date("2026-10-09T11:00:00Z"))
    }

    @Test func assistantMessageWhenIdleIsIgnored() {
        var s = session()
        apply(#"{"timestamp":"2026-10-09T11:00:00Z","type":"response_item","payload":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hi"}]}}"#, to: &s)
        #expect(s.phase == .idle)
    }

    @Test func abortedTurn() {
        var s = session()
        apply(#"{"timestamp":"2026-10-09T11:00:00Z","type":"event_msg","payload":{"type":"task_started"}}"#, to: &s)
        apply(#"{"timestamp":"2026-10-09T11:00:01Z","type":"event_msg","payload":{"type":"turn_aborted"}}"#, to: &s)
        #expect(s.phase == .idle)
        #expect(s.activity == "Interrupted")
    }

    @Test(arguments: ["error", "stream_error"])
    func errors(kind: String) {
        var s = session()
        apply(#"{"timestamp":"2026-10-09T11:00:00Z","type":"event_msg","payload":{"type":"\#(kind)","message":"stream disconnected"}}"#, to: &s)
        #expect(s.phase == .error)
        #expect(s.activity == "stream disconnected")
    }

    @Test func webSearchWithoutName() {
        var s = session()
        apply(#"{"timestamp":"2026-10-09T11:00:00Z","type":"response_item","payload":{"type":"web_search_call"}}"#, to: &s)
        #expect(s.tool == "web_search")
        #expect(s.activity == "Searching the web")
    }

    @Test func localShellCallUsesAction() {
        var s = session()
        apply(#"{"timestamp":"2026-10-09T11:00:00Z","type":"response_item","payload":{"type":"local_shell_call","action":{"command":["bash","-lc","make"]}}}"#, to: &s)
        #expect(s.tool == "shell")
        #expect(s.activity == "Running make")
    }

    @Test(arguments: [
        ("exec_command", #"{"arguments":"{\"cmd\":\"git status\"}"}"#, "Running git status"),
        ("shell", #"{"arguments":"not json"}"#, "Running a command"),
        ("apply_patch", #"{"arguments":"{\"input\":\"*** Add File: docs/new.md\\n+hi\"}"}"#, "Editing new.md"),
        ("apply_patch", #"{"input":"garbage"}"#, "Editing files"),
        ("update_plan", "{}", "Updating the plan"),
        ("some_mcp_tool", "{}", "Using some mcp tool"),
    ])
    func describe(name: String, payload: String, expected: String) {
        #expect(CodexParser.describe(name, jsonObject(payload)!) == expected)
    }
}
