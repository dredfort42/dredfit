//
//  The palette lives in Brand.xcassets and code only reaches it through the
//  Theme façade, so a colorset edited blind — or a façade string with no
//  colorset behind it — would ship without a compile error. These resolve
//  every token in all four appearances (light and dark, each with the
//  Increased Contrast variant), pin the values against the table in
//  Theme.swift, and re-derive the WCAG floors the values were chosen to
//  clear.
//

import XCTest
import UIKit
@testable import Dredfit

// MainActor: UIMutableTraits' properties are main-actor-isolated in the
// current SDK, and the trait-building closure below mutates them.
@MainActor
final class BrandPaletteTests: XCTestCase {

    private struct Token {
        let name: String
        let light: UInt32
        let lightHC: UInt32
        let dark: UInt32
        let darkHC: UInt32
    }

    /// Mirrors the table in Theme.swift — the same source the landing CSS
    /// and the store frame composer copy from.
    private static let palette = [
        Token(name: "bg", light: 0xFFFFFF, lightHC: 0xFFFFFF,
              dark: 0x090A0C, darkHC: 0x090A0C),
        Token(name: "cardBG", light: 0xF7F7F5, lightHC: 0xE0E0DD,
              dark: 0x1E1F23, darkHC: 0x25262B),
        Token(name: "ink", light: 0x111214, lightHC: 0x111214,
              dark: 0xF2F2F4, darkHC: 0xF2F2F4),
        Token(name: "ink2", light: 0x6E7075, lightHC: 0x535558,
              dark: 0x98999E, darkHC: 0xA2A3A8),
        Token(name: "ink3", light: 0xA7A9AD, lightHC: 0x727478,
              dark: 0x5C5D62, darkHC: 0x7B7C82),
        Token(name: "hairline", light: 0xECEDEF, lightHC: 0xD0D2D5,
              dark: 0x2A2C30, darkHC: 0x2F3136),
        Token(name: "restFill", light: 0xE2E3E6, lightHC: 0xC4C6CA,
              dark: 0x35363A, darkHC: 0x35363A),
        Token(name: "accent", light: 0xE8590C, lightHC: 0xC94D07,
              dark: 0xE8590C, darkHC: 0xE8590C),
        // Dark accentText == accent on purpose: #E8590C clears 4.5:1 on the
        // dark ground, while the light scheme's #B44504 is unreadable there.
        Token(name: "accentText", light: 0xB44504, lightHC: 0x993B04,
              dark: 0xE8590C, darkHC: 0xFF7526),
        Token(name: "accentSoft", light: 0xFBE3D6, lightHC: 0xFBE3D6,
              dark: 0x3A2013, darkHC: 0x3A2013),
    ]

    private struct Floor {
        let ink: String
        let ground: String
        let ratio: Double
    }

    /// The acceptance list of the token wave (#116) — dark scheme only. The
    /// light values predate these floors and are pinned by value instead:
    /// light hairline-on-bg is 1.17 and ink3-on-bg 2.35 by design.
    private static let darkFloors = [
        Floor(ink: "ink", ground: "bg", ratio: 7),
        Floor(ink: "ink", ground: "cardBG", ratio: 7),
        Floor(ink: "ink2", ground: "bg", ratio: 4.5),
        Floor(ink: "ink2", ground: "cardBG", ratio: 4.5),
        Floor(ink: "ink3", ground: "bg", ratio: 3),
        Floor(ink: "hairline", ground: "bg", ratio: 1.3),
        Floor(ink: "restFill", ground: "bg", ratio: 1.3),
        Floor(ink: "accent", ground: "bg", ratio: 3),
        Floor(ink: "accentText", ground: "bg", ratio: 4.5),
        Floor(ink: "ink", ground: "accentSoft", ratio: 4.5),
        Floor(ink: "cardBG", ground: "bg", ratio: 1.2),
    ]

    /// One tier up for Increased Contrast (#119), both schemes. The one
    /// deliberate exception: ink2-on-cardBG holds ≥ 5.5, because pushing it
    /// to 7 would either erase the ink/ink2 hierarchy or the card/bg
    /// separation.
    private static let highContrastFloors = [
        Floor(ink: "ink", ground: "bg", ratio: 7),
        Floor(ink: "ink", ground: "cardBG", ratio: 7),
        Floor(ink: "ink2", ground: "bg", ratio: 7),
        Floor(ink: "ink2", ground: "cardBG", ratio: 5.5),
        Floor(ink: "ink3", ground: "bg", ratio: 4.5),
        Floor(ink: "hairline", ground: "bg", ratio: 1.5),
        Floor(ink: "restFill", ground: "bg", ratio: 1.6),
        Floor(ink: "accent", ground: "bg", ratio: 4.5),
        Floor(ink: "accentText", ground: "bg", ratio: 7),
        Floor(ink: "ink", ground: "accentSoft", ratio: 7),
        Floor(ink: "cardBG", ground: "bg", ratio: 1.3),
    ]

    func testEveryTokenResolvesToItsSpecValueInAllFourAppearances() throws {
        for token in Self.palette {
            try assertToken(token.name, resolvesTo: token.light,
                            style: .light, contrast: .normal)
            try assertToken(token.name, resolvesTo: token.lightHC,
                            style: .light, contrast: .high)
            try assertToken(token.name, resolvesTo: token.dark,
                            style: .dark, contrast: .normal)
            try assertToken(token.name, resolvesTo: token.darkHC,
                            style: .dark, contrast: .high)
        }
    }

    func testDarkPairsClearTheFloorsTheyWereChosenAgainst() throws {
        try assertFloors(Self.darkFloors, style: .dark, contrast: .normal)
    }

    func testHighContrastPairsClearTheSteppedUpFloorsInBothSchemes() throws {
        try assertFloors(Self.highContrastFloors, style: .light, contrast: .high)
        try assertFloors(Self.highContrastFloors, style: .dark, contrast: .high)
    }

    // MARK: - Resolution

    /// `UIColor(named:)` is the typo net: a name with no colorset behind it
    /// resolves to nil and fails here, not in the store.
    private func resolved(_ name: String, style: UIUserInterfaceStyle,
                          contrast: UIAccessibilityContrast) throws -> UIColor {
        let color = try XCTUnwrap(UIColor(named: name),
                                  "no colorset named '\(name)' in the catalog")
        let traits = UITraitCollection { mutable in
            mutable.userInterfaceStyle = style
            mutable.accessibilityContrast = contrast
        }
        return color.resolvedColor(with: traits)
    }

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double
    }

    private func components(of color: UIColor) -> RGB {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        // On failure the zeros fail the value assertions loudly anyway.
        XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha),
                      "the token did not resolve into RGB components")
        XCTAssertEqual(Double(alpha), 1, "every token in the palette is opaque")
        return RGB(red: Double(red), green: Double(green), blue: Double(blue))
    }

    private func label(_ style: UIUserInterfaceStyle,
                       _ contrast: UIAccessibilityContrast) -> String {
        (style == .dark ? "dark" : "light") + (contrast == .high ? " HC" : "")
    }

    private func assertToken(_ name: String, resolvesTo rgb: UInt32,
                             style: UIUserInterfaceStyle,
                             contrast: UIAccessibilityContrast) throws {
        let actual = components(of: try resolved(name, style: style,
                                                 contrast: contrast))
        let scheme = label(style, contrast)
        // Half a step of 8-bit precision: exact, minus float round-tripping.
        let accuracy = 0.5 / 255
        XCTAssertEqual(actual.red, Double((rgb >> 16) & 0xFF) / 255,
                       accuracy: accuracy, "\(name) red, \(scheme)")
        XCTAssertEqual(actual.green, Double((rgb >> 8) & 0xFF) / 255,
                       accuracy: accuracy, "\(name) green, \(scheme)")
        XCTAssertEqual(actual.blue, Double(rgb & 0xFF) / 255,
                       accuracy: accuracy, "\(name) blue, \(scheme)")
    }

    private func assertFloors(_ floors: [Floor], style: UIUserInterfaceStyle,
                              contrast: UIAccessibilityContrast) throws {
        for pair in floors {
            let ink = components(of: try resolved(pair.ink, style: style,
                                                  contrast: contrast))
            let ground = components(of: try resolved(pair.ground, style: style,
                                                     contrast: contrast))
            let measured = self.contrast(ink, on: ground)
            XCTAssertGreaterThanOrEqual(
                measured, pair.ratio,
                "\(pair.ink) on \(pair.ground) is \(measured):1 in \(label(style, contrast))")
        }
    }

    // MARK: - WCAG arithmetic

    /// The same formula the wave's acceptance table was computed with
    /// (WCAG 2.x relative luminance).
    private func contrast(_ ink: RGB, on ground: RGB) -> Double {
        let lighter = max(luminance(of: ink), luminance(of: ground))
        let darker = min(luminance(of: ink), luminance(of: ground))
        return (lighter + 0.05) / (darker + 0.05)
    }

    private func luminance(of rgb: RGB) -> Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.04045 ? channel / 12.92
                               : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.red)
             + 0.7152 * linear(rgb.green)
             + 0.0722 * linear(rgb.blue)
    }
}
