import SwiftUI
import UIKit

/// The palette lives in `Design/Brand.xcassets`, one colorset per token with
/// four appearances — light and dark, each with an Increased Contrast
/// variant — shared by the app and the widget extension. This façade is the
/// only place in code allowed to name the assets — views keep saying
/// `Theme.ink`, and `BrandPaletteTests` pins every value.
///
/// The table is the source of truth for the tools that cannot read an asset
/// catalog — the landing CSS (`sitegen/build.py`) and the store frame
/// composer (`store/appstore/tools/compose.py`). Without it the palette audit has
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
    /// The quiet tone, and a GRAPHICS one: measured inside a single scheme it
    /// is 2.35:1 on `bg` in light and 3.02:1 in dark (4.68 / 4.76 under
    /// Increased Contrast, which is off by default). Both are under the 4.5:1
    /// small text needs, so words take `ink2` — the low-contrast ink3 text
    /// found across the app was an oversight, not a quiet-by-design choice
    /// (owner's call, UX review 05.09.2026).
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
    /// The boundary of a TARGET — the outline that is the only thing saying
    /// "this is a control" where no fill says it. 1.4.11 asks 3:1 of exactly
    /// that line, and the two tones the app reached for are not there:
    /// `hairline` is 1.17:1 on `bg` in light and `ink3` 2.35:1, so the border
    /// a person is supposed to aim at is missing rather than quiet
    /// (finding 31, UX review 05.09.2026).
    ///
    /// An alias, not an eleventh colorset: `ink2` is the only token that
    /// clears 3:1 in all four environments (4.96:1 light, 6.97:1 dark, both
    /// higher under Increased Contrast) and `BrandPaletteTests` already gates
    /// every one of those numbers, while a new colorset would need four
    /// appearances, its own pin, and a palette decision that is the owner's —
    /// and moving a token invalidates the whole store screenshot set. Naming
    /// the ROLE is what lets the remaining hairline targets (FlowChrome, the
    /// two technique sheets, AdjustPanel, SettingsSheet) come here one file at
    /// a time without a second opinion about the value.
    static let targetStroke = ink2
}

// MARK: - The palette, resolved for a bitmap

/// For the badge pill, which is drawn to a bitmap and then shown inline
/// inside a `Text`. `ImageRenderer` renders outside any view hierarchy, so
/// the appearance has to be handed to it — and a SwiftUI environment can
/// carry `colorScheme` but not `colorSchemeContrast`, a get-only key, while
/// the palette has a separate Increased Contrast column. A trait collection
/// carries both, so the resolve happens in UIKit: here, where the asset
/// names already live, rather than at the call site.
///
/// The share card renders to a bitmap too and does not need this. It is a
/// picture leaving the app, fixed in the light palette on purpose, so it
/// has no appearance to follow.
extension Theme {
    static func badgePillColors(colorScheme: ColorScheme,
                                contrast: ColorSchemeContrast) -> (text: Color, fill: Color) {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: colorScheme == .dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: contrast == .increased ? .high : .normal),
        ])
        // `ink`, not accentText: on the accentSoft fill accentText measures
        // 4.20:1 in the dark scheme, under the 4.5 an 11 pt semibold pill owes
        // (I-21). This was the LAST of the six sites drawing that pair — the
        // probe badge, the held-set card, the maximum note, Today's
        // "day N in a row" card and the onboarding chip moved to `ink` before
        // it, where `BrandPaletteTests` gates the pair at 4.5 dark and 7 under
        // Increased Contrast and it actually measures 15.23:1 light / 13.46:1
        // dark (UX review 05.09.2026, finding 16).
        //
        // The traits keep carrying the contrast, and `BadgePill` keeps keying
        // its cache on it, even though neither `ink` nor `accentSoft` has a
        // separate Increased Contrast value today: resolving through the
        // catalog is what makes that a palette fact instead of a call-site
        // assumption, so the day a column is added the pill follows with no
        // second edit here.
        return (resolved("ink", traits), resolved("accentSoft", traits))
    }

    /// `resolvedColor`, not the `compatibleWith:` initializer: that one hands
    /// back a colour that is still dynamic, and SwiftUI then resolves it a
    /// second time in the renderer's own environment — which is how a dark
    /// pill came out light. This flattens it to one value before SwiftUI ever
    /// sees it.
    ///
    /// clear on a miss, not a plausible stand-in: `BrandPaletteTests` pins
    /// every colorset, so a missing name is a red test — and an invisible
    /// pill is a louder report than a pill in the wrong orange.
    private static func resolved(_ name: String, _ traits: UITraitCollection) -> Color {
        guard let named = UIColor(named: name, in: .main, compatibleWith: nil) else { return .clear }
        return Color(uiColor: named.resolvedColor(with: traits))
    }
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

/// The two actions of a side-by-side pair: filled and outlined, 46 pt tall
/// on a 14 pt radius. Deliberately smaller and squarer than `PrimaryButton`
/// above, which is the single full-width action of a screen.
///
/// Applied to the Button's LABEL, not to the Button, so the call sites keep
/// their own actions and accessibility identifiers exactly as they were.
extension View {
    func pairedPrimaryLabel() -> some View {
        dredfitFont(15.5, weight: .semibold)
            .foregroundStyle(Theme.bg)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(Theme.ink, in: RoundedRectangle(cornerRadius: 14))
    }

    func pairedSecondaryLabel() -> some View {
        dredfitFont(15.5, weight: .medium)
            .foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity, minHeight: 46)
            // The outline IS the button here — there is no fill behind it, so
            // it owes 1.4.11's 3:1 and `hairline` gave 1.17:1 in light
            // (finding 31, UX review 05.09.2026).
            .background(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.targetStroke, lineWidth: 1.5))
    }
}

/// The date line every screen puts above the day's card: weekday, day,
/// month. One spelling in one place, so Today, the history sheet and the
/// calendar cannot drift apart.
///
/// Deliberately uncapitalised. `Kicker` uppercases whatever it is handed,
/// and the calendar's accessibility line wants the date spelled the way the
/// locale spells it.
extension Date {
    var screenDateText: String {
        formatted(.dateTime.weekday(.wide).day().month(.wide))
    }
}

struct Kicker: View {
    let text: String
    /// ink2, not ink3. The rule this default used to carry — ink3 for a
    /// SECTION heading, ink2 only for a kicker over the one actionable thing —
    /// was justified as "4.96:1 against 3.02:1", and those two numbers come
    /// from DIFFERENT schemes: 4.96 is light ink2 on light `bg`, 3.02 is dark
    /// ink3 on dark `bg`. Read inside one scheme, ink3 is 2.35:1 light /
    /// 3.02:1 dark, and 12 pt semibold is small text, where the floor is 4.5
    /// (R16–R21). ink2 clears it in both — 4.96:1 / 6.97:1 — so every kicker
    /// takes it (UX review 05.09.2026). `color` stays for the rare kicker that
    /// wants another tone; nothing in the app may hand it ink3 back.
    var color: Color = Theme.ink2
    var body: some View {
        Text(text.uppercased())
            .dredfitFont(12, weight: .semibold)
            .kerning(0.8)
            .foregroundStyle(color)
    }
}
