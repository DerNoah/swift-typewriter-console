import SwiftUI

/// A terminal-style console view: timestamped log lines that type themselves in with a per-letter
/// fade, plus an optional still-streaming live region at the bottom — all in ONE selectable text
/// surface, so a selection can span any number of lines and survives while output keeps streaming
/// (like Terminal or Xcode's console).
///
/// ```swift
/// ConsoleView(
///     entries: lines,                       // [ConsoleEntry] — append-mostly
///     liveStream: streaming.map {           // optional in-progress generation
///         ConsoleLiveStream(text: $0.text, startedAt: $0.startedAt,
///                           revealFrom: $0.revealFrom, chunkAt: $0.chunkAt)
///     }
/// )
/// ```
///
/// Behavior notes:
/// - Lines type in from their `revealAt` anchor; pass `revealAt: nil` to appear instantly
///   (e.g. when a finished stream's text becomes a permanent entry — the handoff is seamless).
/// - Updates are diffed against the previous `entries`: appends, a mutation of the *last* entry
///   (progress rewrites, "(×N)" suffixes), head drops (line caps), and clears are all incremental
///   edits; any other reshape falls back to a full rebuild, so arbitrary changes stay correct.
/// - Auto-scrolls only while the user is already at the bottom.
public struct ConsoleView: View {
    private let entries: [ConsoleEntry]
    private let liveStream: ConsoleLiveStream?
    private let timestampFormatter: DateFormatter?
    private let perCharacter: Double
    private let fadeWidth: Double

    /// - Parameters:
    ///   - entries: The permanent log lines, oldest first.
    ///   - liveStream: The still-streaming text below the log, if any.
    ///   - timestampFormatter: Formats each line's timestamp prefix; defaults to `HH:mm:ss`.
    ///   - perCharacter: Seconds between successive letters of a line's typewriter reveal.
    ///   - fadeWidth: Each letter's fade spans ~this many letter-steps.
    public init(entries: [ConsoleEntry], liveStream: ConsoleLiveStream? = nil,
                timestampFormatter: DateFormatter? = nil,
                perCharacter: Double = 0.0075, fadeWidth: Double = 1.6) {
        self.entries = entries
        self.liveStream = liveStream
        self.timestampFormatter = timestampFormatter
        self.perCharacter = perCharacter
        self.fadeWidth = fadeWidth
    }

    public var body: some View {
        ConsoleTextView(entries: entries, liveStream: liveStream,
                        timestampFormatter: timestampFormatter,
                        perCharacter: perCharacter, fadeWidth: fadeWidth)
    }
}
