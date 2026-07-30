//
//  WidgetTheme.swift
//  DredfitWidgets
//
//  Split out of DredfitWidgetsBundle.swift: the bundle file carries @main,
//  and the unit tests compile the widget views — the palette must not drag
//  a second entry point into the test bundle.
//

import SwiftUI
import UIKit

// Explicit @MainActor for the same reason as in TodayProvider.swift: the
// unit tests compile this file without the widget target's default
// MainActor isolation.

/// The widget mirrors the app's ink-and-accent palette. Kept local:
/// the design system itself lives in the app target.
///
/// Unlike the app — which is deliberately light-only, forever — a widget sits
/// on someone else's screen and follows the system appearance, so every ink
/// carries a dark counterpart. The accent does not need one: #E8590C reads
/// 3.58:1 on white but 5.27:1 on the dark ground, so on dark it clears the
/// small-text threshold without the darker `accentText` cut the app needs.
///
/// There is no asset catalog in this extension; a dynamic UIColor keeps the
/// whole palette in one place instead of adding one for six colors.
@MainActor
enum WidgetTheme {
    static let accent = Color(red: 232 / 255, green: 89 / 255, blue: 12 / 255) // #E8590C

    static let background = adaptive(light: 0xFFFFFF, dark: 0x1C1C1E)
    static let ink = adaptive(light: 0x111214, dark: 0xF2F2F4)
    static let ink2 = adaptive(light: 0x6E7075, dark: 0x98999E)
    /// The quietest ink. It carries the weekday letter of a day that was
    /// missed — the Calendar dims those digits to exactly this rather than
    /// erasing them, and the strip follows.
    static let ink3 = adaptive(light: 0xA7A9AD, dark: 0x5C5D62)
    /// The planned-day ring in the week strip. ink3, as in the app's `Theme`.
    static let planned = ink3
    /// The rest-day fill in the week strip — the Calendar's `restFill`.
    static let restFill = adaptive(light: 0xE2E3E6, dark: 0x35363A)
    /// The rules between plan rows on the large family.
    static let hairline = adaptive(light: 0xECEDEF, dark: 0x2A2C30)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    /// 0xRRGGBB, so the palette above reads like the hex in Theme.swift.
    convenience init(rgb: UInt32) {
        self.init(red: CGFloat((rgb >> 16) & 0xFF) / 255,
                  green: CGFloat((rgb >> 8) & 0xFF) / 255,
                  blue: CGFloat(rgb & 0xFF) / 255,
                  alpha: 1)
    }
}
