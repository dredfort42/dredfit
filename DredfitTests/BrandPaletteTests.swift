//
//  BrandPaletteTests.swift
//  DredfitTests
//
//  The palette lives in Brand.xcassets and code only reaches it through the
//  Theme façade, so a colorset edited blind — or a façade string with no
//  colorset behind it — would ship without a compile error. These resolve
//  every token in both appearances, pin the values against the table in
//  Theme.swift, and re-derive the WCAG floors the dark values were chosen
//  to clear.
//

import XCTest
import UIKit
@testable import Dredfit

final class BrandPaletteTests: XCTestCase {

    private struct Token {
        let name: String
        let light: UInt32
        let dark: UInt32
    }

    /// Mirrors the table in Theme.swift — the same source the landing CSS
    /// and the store frame composer copy from.
    private static let palette = [
        Token(name: "bg", light: 0xFFFFFF, dark: 0x090A0C),
        Token(name: "cardBG", light: 0xF7F7F5, dark: 0x1E1F23),
        Token(name: "ink", light: 0x111214, dark: 0xF2F2F4),
        Token(name: "ink2", light: 0x6E7075, dark: 0x98999E),
        Token(name: "ink3", light: 0xA7A9AD, dark: 0x5C5D62),
        Token(name: "hairline", light: 0xECEDEF, dark: 0x2A2C30),
        Token(name: "restFill", light: 0xE2E3E6, dark: 0x35363A),
        Token(name: "accent", light: 0xE8590C, dark: 0xE8590C),
        // Dark accentText == accent on purpose: #E8590C clears 4.5:1 on the
        // dark ground, while the light scheme's #B44504 is unreadable there.
        Token(name: "accentText", light: 0xB44504, dark: 0xE8590C),
        Token(name: "accentSoft", light: 0xFBE3D6, dark: 0x3A2013),
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

    func testEveryTokenResolvesToItsSpecValueInBothSchemes() throws {
        for token in Self.palette {
            try assertToken(token.name, resolvesTo: token.light, in: .light)
            try assertToken(token.name, resolvesTo: token.dark, in: .dark)
        }
    }

    func testDarkPairsClearTheFloorsTheyWereChosenAgainst() throws {
        for pair in Self.darkFloors {
            let ink = components(of: try resolved(pair.ink, in: .dark))
            let ground = components(of: try resolved(pair.ground, in: .dark))
            let measured = contrast(ink, on: ground)
            XCTAssertGreaterThanOrEqual(
                measured, pair.ratio,
                "\(pair.ink) on \(pair.ground) is \(measured):1 in dark")
        }
    }

    // MARK: - Resolution

    /// `UIColor(named:)` is the typo net: a name with no colorset behind it
    /// resolves to nil and fails here, not in the store.
    private func resolved(_ name: String,
                          in style: UIUserInterfaceStyle) throws -> UIColor {
        let color = try XCTUnwrap(UIColor(named: name),
                                  "no colorset named '\(name)' in the catalog")
        return color.resolvedColor(
            with: UITraitCollection(userInterfaceStyle: style))
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

    private func assertToken(_ name: String, resolvesTo rgb: UInt32,
                             in style: UIUserInterfaceStyle) throws {
        let actual = try components(of: resolved(name, in: style))
        let scheme = style == .dark ? "dark" : "light"
        // Half a step of 8-bit precision: exact, minus float round-tripping.
        let accuracy = 0.5 / 255
        XCTAssertEqual(actual.red, Double((rgb >> 16) & 0xFF) / 255,
                       accuracy: accuracy, "\(name) red, \(scheme)")
        XCTAssertEqual(actual.green, Double((rgb >> 8) & 0xFF) / 255,
                       accuracy: accuracy, "\(name) green, \(scheme)")
        XCTAssertEqual(actual.blue, Double(rgb & 0xFF) / 255,
                       accuracy: accuracy, "\(name) blue, \(scheme)")
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
