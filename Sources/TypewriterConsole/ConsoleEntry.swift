import Foundation

/// One permanent line in the console.
///
/// Entries are identified by `id`; the console diffs successive `entries` arrays, so reuse the
/// same `id` for a line you mutate in place (e.g. rewriting a progress line or appending a
/// "(×3)" repeat suffix to `text`) and it is rewritten without re-typing.
public struct ConsoleEntry: Identifiable, Equatable {
    public var id: UUID
    /// Rendered as the line's `HH:mm:ss` timestamp prefix.
    public var date: Date
    public var text: String
    public var style: Style
    /// When this line's typewriter reveal began; the console types the line in from this moment.
    /// `nil` (or a date far enough in the past) makes the line appear instantly — use that for
    /// text that already streamed in through the live region.
    public var revealAt: Date?

    public init(id: UUID = UUID(), date: Date = Date(), text: String,
                style: Style = .standard, revealAt: Date? = Date()) {
        self.id = id
        self.date = date
        self.text = text
        self.style = style
        self.revealAt = revealAt
    }

    /// How a line's message text is drawn (the timestamp prefix always uses the tertiary label
    /// color with monospaced digits).
    public struct Style: Equatable {
        public var font: PlatformFont
        public var color: PlatformColor

        public init(font: PlatformFont, color: PlatformColor) {
            self.font = font
            self.color = color
        }

        /// Regular caption text in the primary label color.
        public static var standard: Style {
            Style(font: .systemFont(ofSize: Platform.captionSize), color: Platform.label)
        }

        /// Caption text in red — error lines.
        public static var error: Style {
            Style(font: .systemFont(ofSize: Platform.captionSize), color: .systemRed)
        }

        /// Small monospaced text in the secondary label color — generated/model/tool output,
        /// visually distinct from the caller's own status lines.
        public static var dimmedMonospaced: Style {
            Style(font: .monospacedSystemFont(ofSize: Platform.caption2Size, weight: .regular),
                  color: Platform.secondaryLabel)
        }
    }
}

/// The transient, still-streaming text at the bottom of the console (e.g. an LLM generation in
/// progress). Rendered exactly like a `ConsoleEntry` line; when the stream finishes, append its
/// full text as a permanent entry with `revealAt: nil` and pass `nil` here — the handoff is
/// seamless (identical styling, no re-typing).
///
/// Only the newest chunk animates: characters before `revealFrom` render fully revealed, the
/// rest fade in paced to finish within ~100 ms (one typical flush interval) whatever the chunk
/// size, so streaming reads as continuous typing.
public struct ConsoleLiveStream: Equatable {
    public var text: String
    /// Timestamp shown on the live line (when the stream began).
    public var startedAt: Date?
    /// `Character` offset into `text` where the newest chunk begins.
    public var revealFrom: Int
    /// When the newest chunk arrived — the anchor its fade animates from.
    public var chunkAt: Date
    public var style: ConsoleEntry.Style

    public init(text: String, startedAt: Date? = nil, revealFrom: Int = 0,
                chunkAt: Date = Date(), style: ConsoleEntry.Style = .dimmedMonospaced) {
        self.text = text
        self.startedAt = startedAt
        self.revealFrom = revealFrom
        self.chunkAt = chunkAt
        self.style = style
    }
}
