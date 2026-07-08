# swift-typewriter-console

A terminal-style console view for SwiftUI: timestamped log lines that **type themselves in with a
per-letter fade**, an optional **still-streaming live region** at the bottom (perfect for LLM/token
output), and — because everything renders into one AppKit/UIKit text view — **continuous text
selection across any number of lines that survives while output keeps streaming**, just like
Terminal or Xcode's console.

> Imported as `import TypewriterConsole` (the package is named `swift-typewriter-console`).

![TypewriterConsole demo: timestamped lines type themselves in with a per-letter fade, a progress line rewrites in place, and a streamed summary graduates into the log](assets/demo.gif)

## Requirements

- iOS 17+ / macOS 14+
- Swift 6.0+

## Installation

### Swift Package Manager

```swift
dependencies: [
    .package(url: "https://github.com/DerNoah/swift-typewriter-console", from: "1.0.0")
]
```

---

## Features

- **One selectable surface** — drag a selection across many lines, ⌘C copies them with timestamps.
  Streaming appends and the reveal animation never reset your selection.
- **Typewriter reveal** — new lines fade in letter by letter (configurable speed); lines re-rendered
  from history appear instantly. The animation is attribute-only, driven by a single shared timer
  that stops when nothing is animating.
- **Live streaming region** — feed it a growing string (e.g. coalesced LLM tokens); only the newest
  chunk animates, paced to finish within one flush interval whatever the token rate, so streaming
  reads as continuous typing. When the stream finishes, append the full text as a permanent entry —
  the handoff is pixel-identical.
- **Cheap at scale** — the view diffs your entries and performs incremental text-storage edits
  (append, rewrite-last, head drop, clear); huge logs never re-layout from scratch. Any other
  reshape falls back to a full rebuild, so arbitrary changes stay correct.
- **Terminal scrolling** — auto-scrolls only while the user is already at the bottom.

## Usage

```swift
import TypewriterConsole

struct MyConsole: View {
    @State private var lines: [ConsoleEntry] = []

    var body: some View {
        ConsoleView(entries: lines)
    }

    func log(_ text: String) {
        lines.append(ConsoleEntry(text: text))                      // types in now
    }

    func logError(_ text: String) {
        lines.append(ConsoleEntry(text: text, style: .error))
    }
}
```

### Streaming (e.g. LLM output)

Keep one growing string plus two pieces of chunk bookkeeping — where the newest chunk starts and
when it arrived:

```swift
ConsoleView(
    entries: lines,
    liveStream: ConsoleLiveStream(
        text: streamedText,          // the text so far (or a rolling tail of it)
        startedAt: generationStart,  // timestamp shown on the live line
        revealFrom: previousLength,  // Character offset where the newest chunk begins
        chunkAt: chunkArrivalDate    // when that chunk arrived
    )
)
```

When the generation completes, append its full text as a permanent entry with `revealAt: nil`
(it already typed itself in while streaming) and pass `liveStream: nil`:

```swift
lines.append(ConsoleEntry(text: fullText, style: .dimmedMonospaced, revealAt: nil))
streamedText = nil
```

### Entries

```swift
ConsoleEntry(
    id: UUID(),           // stable identity — reuse it to rewrite a line in place
    date: Date(),         // rendered as the HH:mm:ss prefix
    text: "Indexing 42 files…",
    style: .standard,     // .standard, .error, .dimmedMonospaced, or your own Style(font:color:)
    revealAt: Date()      // when the typewriter reveal began; nil = appear instantly
)
```

Mutating the **last** entry's `text` (progress lines like `"pulling… 10%"`, repeat counters like
`"…  (×3)"`) rewrites it in place without re-typing. Dropping entries from the **head** (your own
line cap) is likewise an incremental edit.

### Standalone typewriter text

The per-letter fade is also available as a plain SwiftUI view:

```swift
TypewriterText(text: "Hello, world.", start: revealStart)   // parent owns the start date
```

`start` is parent-owned so view re-creation resumes the reveal instead of replaying it; advance it
only when the text genuinely changes.

## How it works

All lines live in a single `NSTextStorage` rendered by `NSTextView` (macOS) / `UITextView` (iOS).
Model changes become incremental storage edits, which the platform shifts existing selections
through; the reveal animates only `foregroundColor` alpha, which doesn't touch selection at all.
Offsets are handled in UTF-16 units throughout.

## License

Released under the MIT License. See [LICENSE](LICENSE).
