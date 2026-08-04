//
//  WidgetTheme.swift
//  DredfitWidgets
//
//  Kept out of DredfitWidgetsBundle.swift: that file carries @main, and the
//  unit tests compile the widget views — the palette must not drag a second
//  entry point into the test bundle.
//

import SwiftUI
import UIKit

/// Explicit @MainActor, like TodayProvider: the unit tests compile this file
/// without the widget target's default MainActor isolation.
///
/// Unlike the app — light-only by design — a widget follows the system
/// appearance, so every ink carries a dark counterpart. The accent needs
/// none: #E8590C is 3.58:1 on white but 5.27:1 on the dark ground, clearing
/// the small-text threshold without the app's darker `accentText` cut.
@MainActor
enum WidgetTheme {
    static let accent = Color(red: 232 / 255, green: 89 / 255, blue: 12 / 255) // #E8590C

    static let background = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let ink = adaptive(light: 0x111214, dark: 0xF2F2F4)
    static let ink2 = adaptive(light: 0x6E7075, dark: 0x98999E)
    static let ink3 = adaptive(light: 0xA7A9AD, dark: 0x5C5D62)
    static let planned = ink3
    static let restFill = adaptive(light: 0xE2E3E6, dark: 0x35363A)
    static let hairline = adaptive(light: 0xECEDEF, dark: 0x2A2C30)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
