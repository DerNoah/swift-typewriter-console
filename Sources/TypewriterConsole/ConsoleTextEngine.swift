import Foundation
#if canImport(AppKit)
import AppKit
#else
import UIKit
#endif

/// The console's text-storage engine: renders `ConsoleEntry` lines and the trailing live stream
/// into one `NSTextStorage` via incremental edits, and drives the typewriter reveal as
/// attribute-only color-alpha animation.
///
/// Everything lives in a single storage so a selection can span any number of lines; incremental
/// edits (append a line, rewrite the last line, drop the head, replace the live region) mean the
/// platform text view shifts existing selections through them instead of resetting, and huge logs
/// never re-layout from scratch. Attribute edits (the reveal animation) never disturb a selection
/// at all.
///
/// Platform-neutral: `NSTextStorage` exists in both AppKit and UIKit; the owning text view
/// supplies the two scrolling hooks. Constructible against a bare storage, which is how the
/// unit tests drive it. All offsets/lengths are UTF-16 units (`NSAttributedString` addressing),
/// converted at the seams.
@MainActor
final class ConsoleTextEngine {
    private let storage: NSTextStorage
    private let timestampFormatter: DateFormatter
    /// Seconds between successive letters of a line's reveal.
    private let perCharacter: Double
    /// A letter's fade spans ~this many letter-steps.
    private let fadeWidth: Double

    /// Supplied by the owning text view: whether the user is currently at (or near) the bottom.
    var isPinnedToBottom: () -> Bool = { true }
    /// Supplied by the owning text view: scroll so the end of the document is visible.
    var scrollToBottom: () -> Void = {}

    init(storage: NSTextStorage, timestampFormatter: DateFormatter? = nil,
         perCharacter: Double = 0.0075, fadeWidth: Double = 1.6) {
        self.storage = storage
        self.perCharacter = perCharacter
        self.fadeWidth = fadeWidth
        if let timestampFormatter {
            self.timestampFormatter = timestampFormatter
        } else {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss"
            self.timestampFormatter = f
        }
    }

    // MARK: - Mirror state

    /// Mirror of the rendered lines, in storage order. `length` is the line's rendered UTF-16
    /// length including its trailing newline; offsets are prefix sums over this array.
    private struct Row {
        let id: UUID
        var text: String
        var style: ConsoleEntry.Style
        var length: Int
    }
    private var rows: [Row] = []
    /// Rendered UTF-16 length of the transient live region at the very end (0 = none).
    private var liveLength = 0

    /// An in-flight typewriter reveal over one line's message characters.
    private struct Reveal {
        let rowID: UUID
        let startOffsetInRow: Int   // UTF-16 offset of the message within the line
        let charCount: Int          // UTF-16 length of the animating message
        let anchor: Date
        let color: PlatformColor
        var painted = 0             // leading units already set to full alpha
    }
    private var reveals: [Reveal] = []

    /// The live region's reveal: only units from `from` (region-relative) animate.
    private struct LiveReveal {
        let from: Int
        let charCount: Int
        let anchor: Date
        let perChar: Double
        let color: PlatformColor
        var painted = 0
    }
    private var liveReveal: LiveReveal?

    private var timer: Timer?

    // MARK: - Line rendering

    /// Hanging indent: wrapped lines align under the message column.
    private lazy var paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        let font = PlatformFont.monospacedDigitSystemFont(ofSize: Platform.caption2Size, weight: .regular)
        style.headIndent = ("00:00:00  " as NSString).size(withAttributes: [.font: font]).width
        style.paragraphSpacing = 4
        return style
    }()

    private let timestampFont = PlatformFont.monospacedDigitSystemFont(
        ofSize: Platform.caption2Size, weight: .regular)

    /// One rendered line: "HH:mm:ss  text\n" (timestamp tertiary, message per `style`).
    private func attributedRow(date: Date, text: String, style: ConsoleEntry.Style,
                               messageAlpha: CGFloat = 1) -> (line: NSMutableAttributedString, messageStart: Int) {
        let prefix = timestampFormatter.string(from: date) + "  "
        let line = NSMutableAttributedString(string: prefix, attributes: [
            .font: timestampFont, .foregroundColor: Platform.tertiaryLabel,
            .paragraphStyle: paragraphStyle,
        ])
        let messageStart = line.length
        line.append(NSAttributedString(string: text + "\n", attributes: [
            .font: style.font,
            .foregroundColor: style.color.withAlphaComponent(messageAlpha),
            .paragraphStyle: paragraphStyle,
        ]))
        return (line, messageStart)
    }

    // MARK: - Applying model changes

    func apply(entries: [ConsoleEntry], live: ConsoleLiveStream?) {
        let pinned = isPinnedToBottom()
        storage.beginEditing()
        syncRows(entries)
        syncLive(live)
        storage.endEditing()
        if pinned { scrollToBottom() }
        ensureTimer()
    }

    /// Diff `entries` against the mirror. Optimized for console-shaped changes — append at the
    /// end, mutate the LAST entry (progress rewrites, "(×N)" suffixes), drop from the head (a
    /// line cap), or clear; anything else falls back to a full rebuild for correctness.
    private func syncRows(_ entries: [ConsoleEntry]) {
        if entries.isEmpty {
            if !rows.isEmpty {
                storage.deleteCharacters(in: NSRange(location: 0, length: rowsTotalLength))
                rows = []
                reveals = []
            }
            return
        }

        // Head drop (line cap): mirror rows before the first current entry are gone.
        if let firstID = entries.first?.id, let idx = rows.firstIndex(where: { $0.id == firstID }), idx > 0 {
            let dropped = rows[0..<idx].reduce(0) { $0 + $1.length }
            storage.deleteCharacters(in: NSRange(location: 0, length: dropped))
            let droppedIDs = Set(rows[0..<idx].map(\.id))
            rows.removeFirst(idx)
            reveals.removeAll { droppedIDs.contains($0.rowID) }
        } else if let firstID = entries.first?.id, !rows.isEmpty, rows.first?.id != firstID,
                  !rows.contains(where: { $0.id == firstID }) {
            return rebuildRows(entries)
        }

        // Overlap must match pairwise; only the last mirrored row may have mutated.
        guard rows.count <= entries.count else { return rebuildRows(entries) }
        for (i, row) in rows.enumerated() where row.id != entries[i].id {
            return rebuildRows(entries)
        }

        if let last = rows.indices.last {
            let entry = entries[last]
            if rows[last].text != entry.text || rows[last].style != entry.style {
                // Rewrite the last line in place. Any in-flight reveal on it is dropped — the
                // rewritten line shows at full alpha.
                let offset = rowsTotalLength - rows[last].length
                let (line, _) = attributedRow(date: entry.date, text: entry.text, style: entry.style)
                storage.replaceCharacters(in: NSRange(location: offset, length: rows[last].length),
                                          with: line)
                rows[last].text = entry.text
                rows[last].style = entry.style
                rows[last].length = line.length
                reveals.removeAll { $0.rowID == entry.id }
            }
        }

        // Append new trailing entries (before the live region), registering reveals.
        for entry in entries[rows.count...] {
            appendRow(entry)
        }
    }

    private func appendRow(_ entry: ConsoleEntry) {
        let revealing = isRevealPending(entry.revealAt, charCount: (entry.text as NSString).length)
        let (line, messageStart) = attributedRow(date: entry.date, text: entry.text,
                                                 style: entry.style,
                                                 messageAlpha: revealing ? 0 : 1)
        storage.insert(line, at: rowsTotalLength)
        rows.append(Row(id: entry.id, text: entry.text, style: entry.style, length: line.length))
        if revealing, let revealAt = entry.revealAt {
            reveals.append(Reveal(rowID: entry.id,
                                  startOffsetInRow: messageStart,
                                  charCount: line.length - messageStart - 1,   // exclude "\n"
                                  anchor: revealAt,
                                  color: entry.style.color))
        }
    }

    /// A reveal is worth animating only if it hasn't already fully elapsed (e.g. lines restored
    /// from persistence or re-synced via rebuild render instantly).
    private func isRevealPending(_ revealAt: Date?, charCount: Int) -> Bool {
        guard let revealAt else { return false }
        let duration = Double(charCount) * perCharacter + fadeWidth * perCharacter
        return Date().timeIntervalSince(revealAt) < duration
    }

    private func rebuildRows(_ entries: [ConsoleEntry]) {
        storage.deleteCharacters(in: NSRange(location: 0, length: rowsTotalLength))
        rows = []
        reveals = []
        for entry in entries {
            let (line, _) = attributedRow(date: entry.date, text: entry.text, style: entry.style)
            storage.insert(line, at: rowsTotalLength)
            rows.append(Row(id: entry.id, text: entry.text, style: entry.style, length: line.length))
        }
    }

    /// Replace the trailing live region wholesale on each flush (a few KB — cheap). Units before
    /// `revealFrom` render at full alpha; the fresh chunk starts at 0 and fades in via the timer.
    /// `revealFrom` counts Swift `Character`s — converted to UTF-16 here.
    private func syncLive(_ live: ConsoleLiveStream?) {
        let regionStart = rowsTotalLength
        guard let live, !live.text.isEmpty else {
            if liveLength > 0 {
                storage.deleteCharacters(in: NSRange(location: regionStart, length: liveLength))
                liveLength = 0
            }
            liveReveal = nil
            return
        }

        let (line, messageStart) = attributedRow(date: live.startedAt ?? Date(),
                                                 text: live.text, style: live.style)
        let revealFromUTF16 = String(live.text.prefix(live.revealFrom)).utf16.count
        let chunkUnits = line.length - messageStart - 1 - revealFromUTF16   // exclude "\n"
        if chunkUnits > 0 {
            line.addAttribute(.foregroundColor,
                              value: live.style.color.withAlphaComponent(0),
                              range: NSRange(location: messageStart + revealFromUTF16, length: chunkUnits))
            // Paced to finish within ~100ms (one typical flush interval) whatever the chunk size.
            liveReveal = LiveReveal(from: messageStart + revealFromUTF16, charCount: chunkUnits,
                                    anchor: live.chunkAt, perChar: 0.1 / Double(chunkUnits),
                                    color: live.style.color)
        } else {
            liveReveal = nil
        }
        storage.replaceCharacters(in: NSRange(location: regionStart, length: liveLength), with: line)
        liveLength = line.length
    }

    private var rowsTotalLength: Int { rows.reduce(0) { $0 + $1.length } }

    // MARK: - Reveal animation (attribute-only edits — never disturbs selection)

    private func ensureTimer() {
        guard timer == nil, !(reveals.isEmpty && liveReveal == nil) else { return }
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            // The timer is scheduled on the main run loop, so this already runs on the main
            // actor — assume it instead of hopping through a Task every frame.
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)   // keeps animating while the user scrolls
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        let now = Date()

        storage.beginEditing()
        var offset = 0
        var offsets: [UUID: Int] = [:]
        for row in rows { offsets[row.id] = offset; offset += row.length }

        reveals = reveals.compactMap { reveal in
            guard let rowStart = offsets[reveal.rowID] else { return nil }
            var reveal = reveal
            paint(&reveal.painted, base: rowStart + reveal.startOffsetInRow,
                  charCount: reveal.charCount, anchor: reveal.anchor, perChar: perCharacter,
                  color: reveal.color, now: now)
            return reveal.painted >= reveal.charCount ? nil : reveal
        }
        if var live = liveReveal {
            paint(&live.painted, base: rowsTotalLength + live.from, charCount: live.charCount,
                  anchor: live.anchor, perChar: live.perChar, color: live.color, now: now)
            liveReveal = live.painted >= live.charCount ? nil : live
        }
        storage.endEditing()

        if reveals.isEmpty && liveReveal == nil { stopTimer() }
    }

    /// One animation step over `[painted..<charCount]` at `base`: everything the cursor has fully
    /// passed becomes one full-alpha run; the ~`fadeWidth` units inside the fade window get
    /// per-unit partial alpha. Mirrors `TypewriterText.rendered(elapsed:)`.
    private func paint(_ painted: inout Int, base: Int, charCount: Int, anchor: Date,
                       perChar: Double, color: PlatformColor, now: Date) {
        let progress = now.timeIntervalSince(anchor) / perChar
        let fullUpTo = min(charCount, max(0, Int((progress - fadeWidth).rounded(.down)) + 1))
        let visibleUpTo = min(charCount, max(fullUpTo, Int(progress.rounded(.up))))
        guard base + charCount <= storage.length else { painted = charCount; return }
        if fullUpTo > painted {
            storage.addAttribute(.foregroundColor, value: color,
                                 range: NSRange(location: base + painted, length: fullUpTo - painted))
            painted = fullUpTo
        }
        for i in fullUpTo..<visibleUpTo {
            let alpha = min(max((progress - Double(i)) / fadeWidth, 0), 1)
            storage.addAttribute(.foregroundColor, value: color.withAlphaComponent(alpha),
                                 range: NSRange(location: base + i, length: 1))
        }
    }
}
