//
//  Theme.swift
//  Dredfit
//

import SwiftUI

/// The palette lives in `Design/Brand.xcassets`, one colorset per token with
/// a light and a dark value, shared by the app and the widget extension.
/// This façade is the only place in code allowed to name the assets — views
/// keep saying `Theme.ink`, and `BrandPaletteTests` pins every value.
///
/// The table is the source of truth for the tools that cannot read an asset
/// catalog — the landing CSS (`sitegen/build.py`) and the store frame
/// composer (`appstore/tools/compose.py`). Without it the palette audit has
/// nothing to compare against.
///
///     token       light     dark
///     bg          #FFFFFF   #090A0C
///     cardBG      #F7F7F5   #1E1F23
///     ink         #111214   #F2F2F4
///     ink2        #6E7075   #98999E
///     ink3        #A7A9AD   #5C5D62
///     hairline    #ECEDEF   #2A2C30
///     restFill    #E2E3E6   #35363A
///     accent      #E8590C   #E8590C
///     accentText  #B44504   #E8590C
///     accentSoft  #FBE3D6   #3A2013
///
/// Dark `bg` and `cardBG` sit one step off the first candidates
/// (#0E0F11 / #1A1B1E): the wave's floors ink3-on-bg ≥ 3:1 and
/// cardBG-on-bg ≥ 1.2:1 only clear at #090A0C / #1E1F23 (3.02 and 1.20).
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
                .foregroundStyle(.white)
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
