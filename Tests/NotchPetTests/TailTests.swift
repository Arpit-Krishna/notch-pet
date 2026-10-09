import Foundation
import Testing
@testable import NotchPet

@Suite struct TailTests {
    @Test func missingFileReadsNothing() {
        let tail = Tail(url: URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString).jsonl"))
        #expect(tail.readNew().isEmpty)
        #expect(tail.firstLine() == nil)
    }

    @Test func readsOnlyNewLines() throws {
        let f = TempFile()
        try f.write("a\nb\n")
        let tail = Tail(url: f.url)
        #expect(tail.readNew() == ["a", "b"])
        #expect(tail.readNew().isEmpty)
        try f.append("c\n")
        #expect(tail.readNew() == ["c"])
    }

    @Test func halfWrittenLineWaitsForNewline() throws {
        let f = TempFile()
        try f.write(#"{"type":"user"}"# + "\n" + #"{"type":"assis"#)
        let tail = Tail(url: f.url)
        #expect(tail.readNew() == [#"{"type":"user"}"#])

        try f.append(#"tant","message""#)
        #expect(tail.readNew().isEmpty)

        try f.append(":{}}\n")
        let lines = tail.readNew()
        #expect(lines == [#"{"type":"assistant","message":{}}"#])
        #expect(jsonObject(lines[0])?["type"] as? String == "assistant")
    }

    @Test func fileWithNoNewlineYet() throws {
        let f = TempFile()
        try f.write(#"{"partial":"#)
        let tail = Tail(url: f.url)
        #expect(tail.readNew().isEmpty)
        try f.append("1}\n")
        #expect(tail.readNew() == [#"{"partial":1}"#])
    }

    @Test func multibyteCharacterSplitAcrossWrites() throws {
        let f = TempFile()
        let bytes = Array("café\n".utf8)   // "é" is two bytes
        try Data(bytes[..<4]).write(to: f.url)
        let tail = Tail(url: f.url)
        #expect(tail.readNew().isEmpty)
        let h = try FileHandle(forWritingTo: f.url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(bytes[4...]))
        try h.close()
        #expect(tail.readNew() == ["café"])
    }

    @Test func invalidUTF8LineIsDropped() throws {
        let f = TempFile()
        try Data([0x61, 0x0A, 0xFF, 0xFE, 0x0A, 0x62, 0x0A]).write(to: f.url)
        #expect(Tail(url: f.url).readNew() == ["a", "b"])
    }

    @Test func truncatedFileStartsOver() throws {
        let f = TempFile()
        try f.write("one\ntwo\nthree\n")
        let tail = Tail(url: f.url)
        #expect(tail.readNew().count == 3)

        try f.write("new\n")   // shorter than what was read: truncated or rotated
        #expect(tail.readNew() == ["new"])
        try f.append("next\n")
        #expect(tail.readNew() == ["next"])
    }

    @Test func truncationDropsStalePartialLine() throws {
        let f = TempFile()
        try f.write("done\nhalf-writ")
        let tail = Tail(url: f.url)
        #expect(tail.readNew() == ["done"])

        try f.write("x\n")
        #expect(tail.readNew() == ["x"])   // not "half-writx"
    }

    @Test func rotatedToLargerFileIsReadFromStart() throws {
        let f = TempFile()
        try f.write("old\n")
        let tail = Tail(url: f.url)
        #expect(tail.readNew() == ["old"])

        // A new file swapped in at the same path that is already longer than the old offset.
        try f.write("first\nsecond\n")
        #expect(tail.readNew() == ["first", "second"])
    }

    @Test func firstReadBackfillSkipsCutLine() throws {
        let f = TempFile()
        try f.write("aaaaaaaaaa\nbbbbbbbbbb\ncccccccccc\n")   // 33 bytes
        let tail = Tail(url: f.url)
        // Starting 15 bytes from the end lands inside "bbb…", which must not be returned.
        #expect(tail.readNew(backfill: 15) == ["cccccccccc"])
        try f.append("d\n")
        #expect(tail.readNew(backfill: 15) == ["d"])
    }

    @Test func backfillLargerThanFileReadsEverything() throws {
        let f = TempFile()
        try f.write("a\nb\n")
        #expect(Tail(url: f.url).readNew(backfill: 1024) == ["a", "b"])
    }

    @Test func zeroBackfillOnlySeesNewLines() throws {
        // How SessionStore skips old hook events at startup.
        let f = TempFile()
        try f.write("old\n")
        let tail = Tail(url: f.url)
        #expect(tail.readNew(backfill: 0).isEmpty)
        try f.append("fresh\n")
        #expect(tail.readNew(backfill: 0) == ["fresh"])
    }

    @Test func firstLine() throws {
        let f = TempFile()
        try f.write("meta\nrest\n")
        #expect(Tail(url: f.url).firstLine() == "meta")
    }

    @Test func firstLineNotFinishedYet() throws {
        let f = TempFile()
        try f.write(#"{"type":"session_meta""#)
        #expect(Tail(url: f.url).firstLine() == nil)
    }

    @Test func firstLineSpanningChunks() throws {
        let f = TempFile()
        let long = String(repeating: "x", count: 100 * 1024)
        try f.write(long + "\nsecond\n")
        #expect(Tail(url: f.url).firstLine() == long)
    }
}
