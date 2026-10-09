import Foundation
import Testing
@testable import NotchPet

@Suite struct UsageWindowTests {
    let now = date("2026-10-09T12:00:00Z")

    @Test func beforeResetKeepsPercentage() {
        let w = LimitWindow(label: "Weekly", usedPct: 64, resetsAt: now.addingTimeInterval(60))
        #expect(w.effective(at: now) == 64)
    }

    @Test func atAndAfterResetIsZero() {
        let w = LimitWindow(label: "Weekly", usedPct: 64, resetsAt: now)
        #expect(w.effective(at: now) == 0)
        #expect(w.effective(at: now.addingTimeInterval(3600)) == 0)
    }

    @Test func unknownResetNeverExpires() {
        let w = LimitWindow(label: "Limit", usedPct: 80, resetsAt: nil)
        #expect(w.effective(at: .distantFuture) == 80)
    }

    @Test func newerCodexReadingReplacesRenewedWindow() throws {
        // A 5h window renews; the next token_count reports the fresh window.
        var s = Session(id: "/tmp/rollout.jsonl", agent: .codex)
        CodexParser.apply(jsonObject(#"{"timestamp":"2026-10-09T07:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":95,"window_minutes":300,"resets_in_seconds":3600}}}}"#)!, to: &s)
        let old = try #require(s.codexLimits?.windows.first)
        #expect(old.effective(at: now) == 0)   // reset at 08:00, it is now 12:00

        CodexParser.apply(jsonObject(#"{"timestamp":"2026-10-09T12:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":3,"window_minutes":300,"resets_in_seconds":18000}}}}"#)!, to: &s)
        let fresh = try #require(s.codexLimits?.windows.first)
        #expect(fresh.effective(at: now) == 3)
        #expect(fresh.resetsAt == now.addingTimeInterval(18000))
    }

    @Test(arguments: [
        (nil, ""),
        (-5, "reset"),
        (0, "reset"),
        (90, "resets in 1m"),
        (2 * 3600 + 5 * 60, "resets in 2h 5m"),
        (3 * 86400 + 4 * 3600, "resets in 3d 4h"),
    ] as [(TimeInterval?, String)])
    func untilTextFormatting(offset: TimeInterval?, expected: String) {
        #expect(untilText(offset.map { now.addingTimeInterval($0) }, now: now) == expected)
    }
}

@Suite struct ClaudeUsageParserTests {
    let now = date("2026-10-09T12:00:00Z")

    @Test func windowsOrderedAndLabelled() throws {
        let payload = jsonObject(#"""
        {"rate_limits":{
          "some_new_limit":{"used_percentage":1},
          "seven_day_opus":{"used_percentage":5},
          "seven_day":{"used_percentage":20,"resets_at":1791000000},
          "five_hour":{"used_percentage":42.5,"resets_at":1791000000000},
          "not_a_window":"ignored"
        }}
        """#)!
        let u = try #require(UsageParser.claude(payload, now: now))
        #expect(u.windows.map(\.label) == ["Session (5h)", "Weekly", "Weekly Opus", "Some New Limit"])
        #expect(u.windows[0].usedPct == 42.5)
        #expect(u.updated == now)
        // Seconds and milliseconds epochs land on the same instant.
        #expect(u.windows[0].resetsAt == Date(timeIntervalSince1970: 1_791_000_000))
        #expect(u.windows[1].resetsAt == Date(timeIntervalSince1970: 1_791_000_000))
    }

    @Test func acceptsUtilizationStringsAndISODates() throws {
        let payload = jsonObject(#"{"rate_limits":{"five_hour":{"utilization":"77","resets_at":"2026-10-09T15:00:00.000Z"}}}"#)!
        let w = try #require(UsageParser.claude(payload, now: now)?.windows.first)
        #expect(w.usedPct == 77)
        #expect(w.resetsAt == date("2026-10-09T15:00:00.000Z"))
    }

    @Test func clampsPercentages() throws {
        let payload = jsonObject(#"{"rate_limits":{"five_hour":{"used_percentage":150},"seven_day":{"used_percentage":-3}}}"#)!
        let u = try #require(UsageParser.claude(payload, now: now))
        #expect(u.windows.map(\.usedPct) == [100, 0])
    }

    @Test func zeroOrMissingResetIsUnknown() throws {
        let payload = jsonObject(#"{"rate_limits":{"five_hour":{"used_percentage":10,"resets_at":0}}}"#)!
        #expect(try #require(UsageParser.claude(payload, now: now)).windows[0].resetsAt == nil)
    }

    @Test func nothingUsable() {
        #expect(UsageParser.claude([:], now: now) == nil)
        #expect(UsageParser.claude(jsonObject(#"{"rate_limits":{"five_hour":{"resets_at":1}}}"#)!, now: now) == nil)
    }
}

@Suite struct CodexUsageParserTests {
    let ts = date("2026-10-09T12:00:00Z")

    @Test(arguments: [
        (300, "Session (5h)"),
        (10080, "Weekly"),
        (0, "Limit"),
        (2880, "2-day"),
        (120, "2-hour"),
    ])
    func windowLabels(minutes: Int, expected: String) {
        let u = UsageParser.codex(["primary": ["used_percent": 1, "window_minutes": minutes]], at: ts)
        #expect(u.windows.first?.label == expected)
    }

    @Test func absoluteResetWinsOverRelative() {
        let u = UsageParser.codex(["primary": ["used_percent": 1, "resets_at": 1_791_000_000, "resets_in_seconds": 60]], at: ts)
        #expect(u.windows[0].resetsAt == Date(timeIntervalSince1970: 1_791_000_000))
    }

    @Test func windowWithoutPercentIsSkipped() {
        let u = UsageParser.codex(["primary": ["window_minutes": 300], "secondary": ["used_percent": 9]], at: ts)
        #expect(u.windows.count == 1)
        #expect(u.windows[0].usedPct == 9)
    }

    @Test func planAndCredits() {
        #expect(UsageParser.codex(["plan_type": "plus", "credits": ["unlimited": true]], at: ts).plan == "plus · unlimited credits")
        #expect(UsageParser.codex(["plan_type": "pro", "credits": ["balance": "12"]], at: ts).plan == "pro · 12 credits")
        #expect(UsageParser.codex(["credits": ["balance": 12.4]], at: ts).plan == "12 credits")
        #expect(UsageParser.codex([:], at: ts).plan == nil)
    }
}
