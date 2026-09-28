import SwiftUI

/// Shared visual language for the main window and diagnostics.
enum MacDuoTheme {
    static let background = Color(red: 0.055, green: 0.057, blue: 0.061)
    static let canvas = Color(red: 0.045, green: 0.047, blue: 0.050)
    static let line = Color.white.opacity(0.11)
    static let primary = Color.white.opacity(0.92)
    static let secondary = Color.white.opacity(0.52)
    static let muted = Color.white.opacity(0.34)
    static let accent = Color(red: 0.82, green: 0.78, blue: 0.72)
    static let ready = Color(red: 0.50, green: 0.72, blue: 0.56)
}
