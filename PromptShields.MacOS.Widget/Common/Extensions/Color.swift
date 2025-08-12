import SwiftUI

extension Color {
    static var additionalBlue: Color {
        Color(hex: "EDF6FF")
    }
    static var blue500: Color {
        Color(hex: "0080FF")
    }
    static var grayScale50: Color {
        Color(hex: "F9FAFB")
    }
    static var lightGray: Color {
        Color(hex: "0F1115")
    }
    
    static var onBackground: Color {
        Color(hex: "0F1115")
    }
    
    static var someSurface: Color {
        Color(hex: "F2F3F5")
    }
    
    static var surface: Color {
        Color(hex: "FFFFFF")
    }
    
    static var additionalBlue100: Color {
        Color(hex: "D8EBFF")
    }
    
    static var doubleChevron: Color {
        Color(hex: "374957")
    }
    static var background: Color {
        Color(hex: "F1F3F5")
    }
    
    static var border: Color {
        Color(hex: "DBDFE6")
    }
    
    static var primary: Color {
        Color(hex: "0F1115")
    }
    
    static var onPrimary: Color {
        Color(hex: "FFFFFF")
    }
    
    static var onSurface: Color {
        Color(hex: "3A4150")
    }
    
    static var onSurfaceVariant: Color {
        Color(hex: "9AA3B7")
    }
    
    static var grayScale200: Color {
        Color(hex: "EAECF0")
    }
    
    static var primaryDisabled: Color {
        Color(hex: "C3C9D5")
    }
    
    var nsColor: NSColor {
        NSColor(self)
    }
    
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
