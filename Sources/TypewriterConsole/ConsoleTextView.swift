import SwiftUI

/// Owns the engine across representable updates.
@MainActor
final class ConsoleTextViewCoordinator {
    var engine: ConsoleTextEngine?
}

#if canImport(AppKit)
import AppKit

/// macOS host: an `NSTextView` in its scroll view — read-only, selectable, transparent, with the
/// engine writing into its text storage. Only `textStorage` is touched (never `layoutManager`,
/// which would force a TextKit-1 downgrade).
struct ConsoleTextView: NSViewRepresentable {
    let entries: [ConsoleEntry]
    let liveStream: ConsoleLiveStream?
    let timestampFormatter: DateFormatter?
    let perCharacter: Double
    let fadeWidth: Double

    func makeCoordinator() -> ConsoleTextViewCoordinator { ConsoleTextViewCoordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let textView = scroll.documentView as! NSTextView
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 7, height: 8)
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false

        let engine = ConsoleTextEngine(storage: textView.textStorage!,
                                       timestampFormatter: timestampFormatter,
                                       perCharacter: perCharacter, fadeWidth: fadeWidth)
        // Terminal-standard: auto-scroll only while the user is already at the bottom, so
        // scrolling up to read history isn't yanked away by streaming output.
        engine.isPinnedToBottom = { [weak textView] in
            guard let textView else { return true }
            return textView.visibleRect.maxY >= textView.bounds.maxY - 30
        }
        engine.scrollToBottom = { [weak textView] in
            guard let textView else { return }
            textView.scrollRangeToVisible(NSRange(location: textView.textStorage?.length ?? 0, length: 0))
        }
        context.coordinator.engine = engine
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.engine?.apply(entries: entries, live: liveStream)
    }

    static func dismantleNSView(_ nsView: NSScrollView, coordinator: ConsoleTextViewCoordinator) {
        coordinator.engine?.stopTimer()
    }
}

#else
import UIKit

/// iOS host: a `UITextView` (its own scroll view) — read-only, selectable, transparent, with the
/// engine writing into its text storage. Only `textStorage` is touched (never `layoutManager`,
/// which would force a TextKit-1 downgrade).
struct ConsoleTextView: UIViewRepresentable {
    let entries: [ConsoleEntry]
    let liveStream: ConsoleLiveStream?
    let timestampFormatter: DateFormatter?
    let perCharacter: Double
    let fadeWidth: Double

    func makeCoordinator() -> ConsoleTextViewCoordinator { ConsoleTextViewCoordinator() }

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = .clear
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 7, bottom: 8, right: 7)
        textView.alwaysBounceVertical = true

        let engine = ConsoleTextEngine(storage: textView.textStorage,
                                       timestampFormatter: timestampFormatter,
                                       perCharacter: perCharacter, fadeWidth: fadeWidth)
        // Terminal-standard: auto-scroll only while the user is already at the bottom, so
        // scrolling up to read history isn't yanked away by streaming output.
        engine.isPinnedToBottom = { [weak textView] in
            guard let textView else { return true }
            return textView.contentOffset.y + textView.bounds.height >= textView.contentSize.height - 30
        }
        engine.scrollToBottom = { [weak textView] in
            guard let textView else { return }
            textView.scrollRangeToVisible(NSRange(location: textView.textStorage.length, length: 0))
        }
        context.coordinator.engine = engine
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.engine?.apply(entries: entries, live: liveStream)
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: ConsoleTextViewCoordinator) {
        coordinator.engine?.stopTimer()
    }
}
#endif
