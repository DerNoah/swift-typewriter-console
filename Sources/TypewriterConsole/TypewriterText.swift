import SwiftUI

/// Renders `text` as a typewriter reveal: letters appear left-to-right, each fading in via opacity.
/// Pure SwiftUI (no `TextRenderer`, macOS 14 / iOS 17 compatible): a single concatenated `Text`
/// whose per-letter opacity is driven by elapsed time from a `TimelineView`, so it wraps naturally
/// and needs no `Animatable` conformance. Layout always reserves the full final size (hidden
/// letters render at opacity 0), so a revealing line never shifts its neighbors.
///
/// `start` (when the reveal began) is owned by the parent, not local `@State`, so the reveal
/// survives view re-creation: if the enclosing hierarchy churns and SwiftUI tears down/recreates
/// this view, the same `start` flows back in and the reveal resumes at the correct position
/// instead of replaying. Advance `start` only when the line genuinely changes — that is what makes
/// a new line type in fresh.
///
/// Designed to stay cheap when many instances exist: only the ~`fadeWidth` letters currently
/// fading are rendered per-character (the revealed prefix and hidden suffix are single `Text`
/// runs), and once the reveal has fully elapsed the view settles into one plain static `Text`
/// with no per-frame timeline.
public struct TypewriterText: View {
    public var text: String
    /// When this reveal began; owned by the parent (see type docs).
    public var start: Date
    /// Letters before this index are always fully shown — lets a streaming caller animate only
    /// the newest chunk of a growing string.
    public var revealFrom: Int
    /// Seconds between successive letters.
    public var perCharacter: Double
    /// Each letter's fade spans ~this many letter-steps.
    public var fadeWidth: Double
    public var color: Color
    public var font: Font

    public init(text: String, start: Date, revealFrom: Int = 0, perCharacter: Double = 0.0075,
                fadeWidth: Double = 1.6, color: Color = .secondary,
                font: Font = .caption2.italic()) {
        self.text = text
        self.start = start
        self.revealFrom = revealFrom
        self.perCharacter = perCharacter
        self.fadeWidth = fadeWidth
        self.color = color
        self.font = font
    }

    /// Flipped by a one-shot task once the reveal has fully elapsed, so settled instances render
    /// a plain `Text` instead of ticking a per-frame `TimelineView` forever.
    @State private var completed = false

    public var body: some View {
        Group {
            // `completed` alone can be stale when the parent advances `start` for new content
            // (a streaming caller reuses one view identity), so also require that the *current*
            // reveal has actually elapsed before settling.
            if completed, Date().timeIntervalSince(start) >= totalDuration {
                Text(text).foregroundStyle(color).font(font)
            } else {
                TimelineView(.animation) { context in
                    rendered(elapsed: context.date.timeIntervalSince(start))
                }
            }
        }
        .task(id: start) {
            completed = false
            let remaining = totalDuration - Date().timeIntervalSince(start)
            if remaining > 0 { try? await Task.sleep(for: .seconds(remaining)) }
            completed = true
        }
    }

    /// How long until every letter is fully opaque.
    private var totalDuration: Double {
        Double(max(0, text.count - revealFrom)) * perCharacter + fadeWidth * perCharacter
    }

    /// Build the line as one concatenated `Text`; letter `i` ramps 0→1 opacity once the reveal
    /// "cursor" (elapsed measured in letter-steps, starting at `revealFrom`) passes it. Only
    /// the letters inside the fade window are emitted individually — the fully revealed prefix
    /// and the still-hidden suffix are single runs.
    private func rendered(elapsed: Double) -> Text {
        let chars = Array(text)
        let progress = Double(revealFrom) + elapsed / perCharacter
        // opacity(i) = clamp((progress − i) / fadeWidth): 1 for i ≤ progress − fadeWidth,
        // 0 for i ≥ progress. Letters before `revealFrom` are pinned fully opaque.
        let opaqueEnd = min(chars.count, max(revealFrom, Int((progress - fadeWidth).rounded(.down)) + 1))
        let hiddenStart = min(chars.count, max(opaqueEnd, Int(progress.rounded(.up))))
        var line = Text(String(chars[0..<opaqueEnd])).foregroundStyle(color)
        for i in opaqueEnd..<hiddenStart {
            let opacity = min(max((progress - Double(i)) / fadeWidth, 0), 1)
            line = line + Text(String(chars[i])).foregroundStyle(color.opacity(opacity))
        }
        if hiddenStart < chars.count {
            line = line + Text(String(chars[hiddenStart...])).foregroundStyle(color.opacity(0))
        }
        return line.font(font)
    }
}
