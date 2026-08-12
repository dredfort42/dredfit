//
//  Theme.swift
//  Dredfit
//

import SwiftUI

/// The palette lives in `Design/Brand.xcassets`, one colorset per token with
/// four appearances — light and dark, each with an Increased Contrast
/// variant — shared by the app and the widget extension. This façade is the
/// only place in code allowed to name the assets — views keep saying
/// `Theme.ink`, and `BrandPaletteTests` pins every value.
///
/// The table is the source of truth for the tools that cannot read an asset
/// catalog — the landing CSS (`sitegen/build.py`) and the store frame
/// composer (`appstore/tools/compose.py`). Without it the palette audit has
/// nothing to compare against.
///
///     token       light     light HC  dark      dark HC
///     bg          #FFFFFF   #FFFFFF   #090A0C   #090A0C
///     cardBG      #F7F7F5   #E0E0DD   #1E1F23   #25262B
///     ink         #111214   #111214   #F2F2F4   #F2F2F4
///     ink2        #6E7075   #535558   #98999E   #A2A3A8
///     ink3        #A7A9AD   #727478   #5C5D62   #7B7C82
///     hairline    #ECEDEF   #D0D2D5   #2A2C30   #2F3136
///     restFill    #E2E3E6   #C4C6CA   #35363A   #35363A
///     accent      #E8590C   #C94D07   #E8590C   #E8590C
///     accentText  #B44504   #993B04   #E8590C   #FF7526
///     accentSoft  #FBE3D6   #FBE3D6   #3A2013   #3A2013
///
/// Dark `bg` and `cardBG` sit one step off the first candidates
/// (#0E0F11 / #1A1B1E): the wave's floors ink3-on-bg ≥ 3:1 and
/// cardBG-on-bg ≥ 1.2:1 only clear at #090A0C / #1E1F23 (3.02 and 1.20).
///
/// The HC columns step every floor up one tier (ink2 ≥ 7:1 on bg, ink3
/// ≥ 4.5:1, quiet graphics ≥ 1.5:1, cards ≥ 1.3:1) with one deliberate
/// exception: ink2-on-cardBG holds ≥ 5.5:1, because pushing it to 7 would
/// either erase the ink/ink2 hierarchy or the card/bg separation. The HC
/// accent darkens (light) or brightens `accentText` (dark) only as far as
/// the floors demand — the brand hue stays.
enum Theme {
    /// The ground everything sits on. The light scheme kept it implicit
    /// (system white); dark needs it named, because every other token is
    /// measured against it.
    static let bg = Color("bg", bundle: .main)
    static let ink = Color("ink", bundle: .main)
    static let ink2 = Color("ink2", bundle: .main)
    static let ink3 = Color("ink3", bundle: .main)
    static let hairline = Color("hairline", bundle: .main)
    static let accent = Color("accent", bundle: .main)
    /// Accent for TEXT, not graphics: #E8590C is 3.58:1 on white — fine for
    /// rings and chart lines (3:1), short of the 4.5:1 small text needs.
    /// Its dark value equals `accent` on purpose, not by a copy-paste slip:
    /// #E8590C reads 5.5:1 on the dark ground, where #B44504 drops under it.
    static let accentText = Color("accentText", bundle: .main)
    static let accentSoft = Color("accentSoft", bundle: .main)
    static let cardBG = Color("cardBG", bundle: .main)
    /// Named so the calendar grid and its legend cannot drift apart. ink3,
    /// not lighter: meaningful graphics near 1.4:1 are invisible on real
    /// screens.
    static let planned = ink3
    /// Grid AND legend. hairline (1.17:1) is too faint for a 13pt legend dot;
    /// this half-step (≈1.35:1) reads at dot size without shouting at cell size.
    static let restFill = Color("restFill", bundle: .main)
}

// MARK: - Type that scales

/// `.system(size:)` is frozen — it ignores Dynamic Type entirely. This
/// scales a design size against the text style it belongs to.
private struct ScaledFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let cap: CGFloat?

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle,
         cap: CGFloat?) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
        self.cap = cap
    }

    func body(content: Content) -> some View {
        content.font(.system(size: min(size, cap ?? .greatestFiniteMagnitude),
                             weight: weight))
    }
}

extension View {
    /// `cap` bounds the scaled result. Body text must never use it —
    /// clipping the reader's setting is what Dynamic Type exists to prevent.
    /// It is for the few display numbers that are already enormous by design.
    func dredfitFont(_ size: CGFloat,
                     weight: Font.Weight = .regular,
                     relativeTo style: Font.TextStyle? = nil,
                     cap: CGFloat? = nil) -> some View {
        modifier(ScaledFont(size: size,
                            weight: weight,
                            relativeTo: style ?? Font.TextStyle.forDesignSize(size),
                            cap: cap))
    }
}

extension Font.TextStyle {
    /// So scaling curves match what iOS does to text of that size natively.
    static func forDesignSize(_ size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<11.5: return .caption2
        case ..<12.5: return .caption
        case ..<13.5: return .footnote
        case ..<15.5: return .subheadline
        case ..<16.5: return .callout
        case ..<18: return .body
        case ..<21: return .title3
        case ..<26: return .title2
        case ..<32: return .title
        default: return .largeTitle
        }
    }
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dredfitFont(17, weight: .semibold)
                // bg, not .white: on the ink fill the label must flip with
                // the scheme, or dark mode paints white on near-white.
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct Kicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .dredfitFont(12, weight: .semibold)
            .kerning(0.8)
            .foregroundStyle(Theme.ink3)
    }
}
