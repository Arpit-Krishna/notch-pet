import Foundation
import Testing
@testable import NotchPet

@Suite struct AlertSettingsTests {
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    func at(_ hour: Int) -> Date { date(String(format: "2026-10-10T%02d:30:00Z", hour)) }

    @Test func everythingOnByDefault() {
        let s = AlertSettings()
        for kind in AlertKind.allCases {
            #expect(s.popup(.claude, kind) && s.sound(.claude, kind))
            #expect(s.popup(.codex, kind) && s.sound(.codex, kind))
        }
        #expect(!s.isQuiet(at: at(23), calendar: utc))
    }

    @Test func togglesArePerAgentAndKind() {
        var s = AlertSettings()
        s.toggle(sound: .codex, .done)
        s.toggle(popup: .claude, .error)
        #expect(!s.sound(.codex, .done))
        #expect(s.sound(.claude, .done))
        #expect(!s.popup(.claude, .error))
        #expect(s.popup(.codex, .error))
        s.toggle(sound: .codex, .done)
        #expect(s.sound(.codex, .done))
    }

    @Test(arguments: [(21, false), (22, true), (23, true), (0, true), (7, true), (8, false), (12, false)])
    func quietHoursAcrossMidnight(hour: Int, quiet: Bool) {
        var s = AlertSettings()
        s.quietHours = true   // default window 22:00 → 08:00
        #expect(s.isQuiet(at: at(hour), calendar: utc) == quiet)
    }

    @Test func quietHoursSameDayWindow() {
        var s = AlertSettings()
        s.quietHours = true
        s.quietStart = 13
        s.quietEnd = 14
        #expect(s.isQuiet(at: at(13), calendar: utc))
        #expect(!s.isQuiet(at: at(14), calendar: utc))
        #expect(!s.isQuiet(at: at(12), calendar: utc))
    }

    @Test func settingsSurviveEncoding() throws {
        var s = AlertSettings()
        s.toggle(popup: .codex, .waiting)
        s.quietHours = true
        s.quietStart = 23
        let back = try JSONDecoder().decode(AlertSettings.self, from: JSONEncoder().encode(s))
        #expect(back == s)
    }
}
