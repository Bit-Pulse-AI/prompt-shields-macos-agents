import SwiftUI
import AppKit

extension NSFont {
    public static var heading4: NSFont {
        return NSFont.systemFont(ofSize: 20, weight: .bold)
    }
    public static var heading2: NSFont {
        return NSFont.systemFont(ofSize: 34, weight: .bold)
    }
    public static var heading3: NSFont {
        return NSFont.systemFont(ofSize: 26, weight: .medium)
    }
    public static var interBold: NSFont {
        return NSFont.systemFont(ofSize: 26, weight: .bold)
    }
    public static var body1Variant: NSFont {
        return NSFont.systemFont(ofSize: 16, weight: .semibold)
    }
    /// Create a font with the large title text style.
    public static var body1: NSFont {
        return NSFont.systemFont(ofSize: 16, weight: .regular)
    }

    public static var body2: NSFont {
        return NSFont.systemFont(ofSize: 14, weight: .regular)
    }

    public static var body4: NSFont {
        return NSFont.systemFont(ofSize: 14, weight: .medium)
    }

    public static var body3: NSFont {
        return NSFont.systemFont(ofSize: 12, weight: .regular)
    }
    /// Create a font with the large title text style.
    public var swiftUIFont: Font {
        Font(self as CTFont)
    }
}
