//
//  Theme.swift
//  Dredfit
//

import SwiftUI

enum Theme {
    static let ink = Color(red: 0x11/255, green: 0x12/255, blue: 0x14/255)
    static let ink2 = Color(red: 0x6E/255, green: 0x70/255, blue: 0x75/255)
    static let ink3 = Color(red: 0xA7/255, green: 0xA9/255, blue: 0xAD/255)
    static let hairline = Color(red: 0xEC/255, green: 0xED/255, blue: 0xEF/255)
    static let accent = Color(red: 0xE8/255, green: 0x59/255, blue: 0x0C/255)
    static let accentSoft = Color(red: 0xFB/255, green: 0xE3/255, blue: 0xD6/255)
    static let cardBG = Color(red: 0xF7/255, green: 0xF7/255, blue: 0xF5/255)
    /// The planned-day ring in the calendar — named so the grid and its
    /// legend can never drift apart again.
    static let planned = Color(red: 0xD9/255, green: 0xD9/255, blue: 0xDB/255)
}

// MARK: - Type that scales (v1.4)

/// The design is specified in absolute point sizes, but `.system(size:)` is
/// frozen — it ignores Dynamic Type entirely. This scales a design size
/// against the text style it belongs to, so the layout keeps its proportions
/// while still honouring the reader's setting.
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
    /// Design size in points, scaled with Dynamic Type.
    ///
    /// `relativeTo` is inferred from the size so call sites stay terse; pass it
    /// explicitly when a size sits at a bucket boundary and reads wrong.
    ///
    /// `cap` bounds the scaled result. Body text should never use it — clipping
    /// the reader's setting is the thing Dynamic Type exists to prevent. It is
    /// for the few display numbers (the rep counter, the total level) that are
    /// already enormous by design: past a point they stop gaining legibility
    /// and start pushing the rest of the screen off it.
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
    /// Buckets a design point size into the closest system text style, so
    /// scaling curves match what iOS does to text of that size natively.
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
