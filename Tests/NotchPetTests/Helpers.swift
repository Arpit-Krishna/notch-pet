import Foundation
@testable import NotchPet

enum Fixture {
    static let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")

    static func lines(_ name: String) throws -> [String] {
        let text = try String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)
        return text.split(separator: "\n").map(String.init)
    }
}

func date(_ iso: String) -> Date {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f.date(from: iso) ?? ISO8601DateFormatter().date(from: iso)!
}

/// Feeds lines through the same path SessionStore uses: unparseable lines are skipped.
@discardableResult
func feed(_ lines: [String], into s: inout Session) -> Int {
    var applied = 0
    for line in lines {
        guard let o = jsonObject(line) else { continue }
        switch s.agent {
        case .claude: ClaudeParser.apply(o, to: &s)
        case .codex: CodexParser.apply(o, to: &s)
        }
        applied += 1
    }
    return applied
}

/// A scratch file that is removed when the test finishes.
final class TempFile {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("notchpet-tests-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    func write(_ s: String) throws { try Data(s.utf8).write(to: url) }

    func append(_ s: String) throws {
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(s.utf8))
    }
}
