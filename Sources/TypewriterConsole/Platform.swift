#if canImport(AppKit)
import AppKit

/// The platform color/font types the console styles are expressed in (`NSColor`/`NSFont` on
/// macOS, `UIColor`/`UIFont` on iOS). Text rendering happens in an AppKit/UIKit text view, so
/// styles use the platform types directly — SwiftUI `Font`/`Color` can't be converted losslessly.
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
#else
import UIKit

/// The platform color/font types the console styles are expressed in (`NSColor`/`NSFont` on
/// macOS, `UIColor`/`UIFont` on iOS). Text rendering happens in an AppKit/UIKit text view, so
/// styles use the platform types directly — SwiftUI `Font`/`Color` can't be converted losslessly.
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
#endif

/// Bridges the small naming differences between AppKit and UIKit for the colors/fonts the
/// console's default styles use.
enum Platform {
    static var label: PlatformColor {
        #if canImport(AppKit)
        .labelColor
        #else
        .label
        #endif
    }

    static var secondaryLabel: PlatformColor {
        #if canImport(AppKit)
        .secondaryLabelColor
        #else
        .secondaryLabel
        #endif
    }

    static var tertiaryLabel: PlatformColor {
        #if canImport(AppKit)
        .tertiaryLabelColor
        #else
        .tertiaryLabel
        #endif
    }

    static var captionSize: CGFloat {
        PlatformFont.preferredFont(forTextStyle: .caption1).pointSize
    }

    static var caption2Size: CGFloat {
        PlatformFont.preferredFont(forTextStyle: .caption2).pointSize
    }
}
