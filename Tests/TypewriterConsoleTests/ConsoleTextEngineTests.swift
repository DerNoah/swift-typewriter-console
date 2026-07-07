import XCTest
@testable import TypewriterConsole

/// Drives `ConsoleTextEngine` against a bare `NSTextStorage` — no text view needed — and asserts
/// the rendered text after each console-shaped change (append, last-line rewrite, head drop,
/// clear, live streaming + graduation, and the full-rebuild fallback).
@MainActor
final class ConsoleTextEngineTests: XCTestCase {
    private let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

    private let date = Date(timeIntervalSince1970: 1_700_000_000)
    private var stamp: String { formatter.string(from: date) }

    private func makeEngine() -> (ConsoleTextEngine, NSTextStorage) {
        let storage = NSTextStorage()
        return (ConsoleTextEngine(storage: storage), storage)
    }

    /// `revealAt: nil` by default so lines render at full alpha and tests need no animation.
    private func entry(_ text: String, id: UUID = UUID(), revealAt: Date? = nil,
                       style: ConsoleEntry.Style = .standard) -> ConsoleEntry {
        ConsoleEntry(id: id, date: date, text: text, style: style, revealAt: revealAt)
    }

    func testAppendRendersTimestampedLines() {
        let (engine, storage) = makeEngine()
        engine.apply(entries: [entry("one"), entry("two")], live: nil)
        XCTAssertEqual(storage.string, "\(stamp)  one\n\(stamp)  two\n")
    }

    func testAppendIsIncremental() {
        let (engine, storage) = makeEngine()
        let first = entry("one")
        engine.apply(entries: [first], live: nil)
        engine.apply(entries: [first, entry("two")], live: nil)
        XCTAssertEqual(storage.string, "\(stamp)  one\n\(stamp)  two\n")
    }

    func testLastLineRewritesInPlace() {
        let (engine, storage) = makeEngine()
        let id = UUID()
        let stable = entry("stable")
        engine.apply(entries: [stable, entry("progress 5%", id: id)], live: nil)
        engine.apply(entries: [stable, entry("progress 10%  (×2)", id: id)], live: nil)
        XCTAssertEqual(storage.string, "\(stamp)  stable\n\(stamp)  progress 10%  (×2)\n")
    }

    func testHeadDropRemovesLeadingLines() {
        let (engine, storage) = makeEngine()
        let a = entry("a"), b = entry("b"), c = entry("c")
        engine.apply(entries: [a, b, c], live: nil)
        engine.apply(entries: [b, c], live: nil)
        XCTAssertEqual(storage.string, "\(stamp)  b\n\(stamp)  c\n")
    }

    func testClearEmptiesStorage() {
        let (engine, storage) = makeEngine()
        engine.apply(entries: [entry("a"), entry("b")], live: nil)
        engine.apply(entries: [], live: nil)
        XCTAssertEqual(storage.string, "")
    }

    func testLiveRegionStreamsAndGraduatesWithoutDuplication() {
        let (engine, storage) = makeEngine()
        let note = entry("running")
        engine.apply(entries: [note],
                     live: ConsoleLiveStream(text: "hel", startedAt: date, revealFrom: 0, chunkAt: date))
        XCTAssertEqual(storage.string, "\(stamp)  running\n\(stamp)  hel\n")

        // Next flush replaces the live region in place.
        engine.apply(entries: [note],
                     live: ConsoleLiveStream(text: "hello", startedAt: date, revealFrom: 3, chunkAt: date))
        XCTAssertEqual(storage.string, "\(stamp)  running\n\(stamp)  hello\n")

        // Graduation: the finished text lands as a permanent entry, live region removed —
        // exactly one copy remains.
        engine.apply(entries: [note, entry("hello")], live: nil)
        XCTAssertEqual(storage.string, "\(stamp)  running\n\(stamp)  hello\n")
    }

    func testReshuffleFallsBackToFullRebuild() {
        let (engine, storage) = makeEngine()
        let a = entry("a"), b = entry("b"), c = entry("c")
        engine.apply(entries: [a, b, c], live: nil)
        engine.apply(entries: [c, a], live: nil)   // not a console-shaped change
        XCTAssertEqual(storage.string, "\(stamp)  c\n\(stamp)  a\n")
    }

    func testFreshRevealStartsTransparentAndOldRevealRendersOpaque() {
        let (engine, storage) = makeEngine()
        engine.apply(entries: [entry("typing", revealAt: Date()),
                               entry("settled", revealAt: Date(timeIntervalSinceNow: -60))],
                     live: nil)
        let messageStart = (stamp + "  ").utf16.count
        let freshColor = storage.attribute(.foregroundColor, at: messageStart,
                                           effectiveRange: nil) as? PlatformColor
        XCTAssertEqual(freshColor?.cgColor.alpha, 0, "a fresh reveal's message starts invisible")

        let secondLineStart = (stamp + "  typing\n").utf16.count
        let settledColor = storage.attribute(.foregroundColor, at: secondLineStart + messageStart,
                                             effectiveRange: nil) as? PlatformColor
        XCTAssertEqual(settledColor?.cgColor.alpha, 1, "an already-elapsed reveal renders opaque")
        engine.stopTimer()
    }
}
