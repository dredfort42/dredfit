//
// One line of a plan: the movement, its number, and the sentences that say why
// the number is what it is — including the one that says the number does not
// count the last set at all, because that set is a probe. Shared by Today and
// the next-workout sheet, so both draw the same card and cannot drift into two
// different explanations of the same plan.
//

import SwiftUI
import DredfitCore

struct ExerciseRow: View {
    let exercise: SessionExercise
    /// The pill rides INLINE at the end of the name and wraps with it as a
    /// unit: the longest catalog name is wider than the content column by
    /// itself, so a sibling HStack pill would push the load off screen. Not
    /// an ellipsis either — sibling variations differ at the END of the name.
    var badge: String?
    /// Lines under the number, saying why it is the number it is. Under the
    /// number and not beside it — the sentence is longer than the column, and
    /// the load must keep its place.
    ///
    /// A LIST because two of them can be true at once: a set that came back is
    /// about the number on the right, and a probe is about a set the number
    /// does not count at all. Joined into one sentence they would read as one
    /// fact with two halves.
    var notes: [String] = []
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Both feed the cache key: the pill is a bitmap, so what the palette
    /// resolved to when it was rendered is baked in.
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                nameWithBadge
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(shortLoad)
                    .dredfitFont(15.5)
                    .monospacedDigit()
                    .foregroundStyle(Theme.ink2)
                Image(systemName: "chevron.right")
                    .dredfitFont(12, weight: .semibold)
                    .foregroundStyle(Theme.ink3.opacity(0.7))
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 4)
    }

    /// The words for the one thing the card explains about its own number.
    /// Static and here rather than in either screen: Today and the
    /// next-workout sheet draw the same card and must not drift into two
    /// different explanations.
    ///
    /// The store answers whether there is anything to say
    /// (`AppStore.aSetJustCameBack(in:)`); the sentence for it lives on this
    /// side of the line, with the view that draws it.
    static func note(setCameBack: Bool) -> String? {
        guard setCameBack else { return nil }
        return String(localized: "A set is back — your body is coping.")
    }

    /// The other one, and it exists because the row was quietly lying without
    /// it: `sets` on an exercise that carries a probe is already one LOWER —
    /// the probe replaces the last of them (§40.4) — so a plan of three sets
    /// where the third is a probe rendered as "2 × 15" and said nothing about
    /// the third at all. The announced duration counts that set; the row did
    /// not mention it.
    ///
    /// It names the movement, because the whole point of the probe is that the
    /// last set is a DIFFERENT exercise — one nobody has done before.
    static func probeNote(_ exercise: SessionExercise) -> String? {
        guard let probe = exercise.probe else { return nil }
        return String(localized: "plan.probeNote",
                      defaultValue: "Then a probe: one set of \(probe.name) · \(probe.display)")
    }

    /// Both, in the order they are read: what happened to the number on the
    /// right, then what is standing after it. One place, so Today and the
    /// next-workout sheet cannot drift into two explanations of one plan.
    static func notes(_ exercise: SessionExercise, setCameBack: Bool) -> [String] {
        [note(setCameBack: setCameBack), probeNote(exercise)].compactMap { $0 }
    }

    /// Text concatenation is the only SwiftUI flow that lets the pill follow
    /// the last word and wrap with it, so it travels as an inline image.
    private var nameWithBadge: some View {
        var name = Text(exercise.name)
        if let badge,
           let pill = BadgePill.image(text: badge, scale: displayScale,
                                      typeSize: dynamicTypeSize,
                                      colorScheme: colorScheme,
                                      contrast: colorSchemeContrast) {
            name = name + Text(verbatim: " ")
                + Text(Image(uiImage: pill)).baselineOffset(-4)
        }
        return name
            .dredfitFont(16.5, weight: .medium)
            .foregroundStyle(Theme.ink)
            .accessibilityLabel(badge.map { Text(verbatim: "\(exercise.name), \($0)") }
                ?? Text(verbatim: exercise.name))
    }

    private var shortLoad: String {
        let side = exercise.perSide ? String(localized: " /side") : ""
        // An uneven plan spells its sets out — "9-8-8". This is where the
        // sub-step becomes visible: a third of the sessions used to read as
        // "nothing changed", and the row is what says otherwise. Explicit
        // keys, not the bare "%@%@" a plain interpolation would mint.
        if let loads = exercise.loads {
            let spelled = loads.map(String.init).joined(separator: "-")
            switch exercise.unit {
            case .reps: return String(localized: "plan.perSet",
                                      defaultValue: "\(spelled)\(side)")
            case .hold: return String(localized: "plan.perSetHold",
                                      defaultValue: "\(spelled) s\(side)")
            }
        }
        switch exercise.unit {
        case .reps: return String(localized: "\(exercise.sets) × \(exercise.load)\(side)")
        case .hold: return String(localized: "\(exercise.sets) × \(exercise.load) s\(side)")
        }
    }
}

/// Cached per text, display scale, Dynamic Type size AND appearance.
/// accentText on accentSoft — accent itself is 2.91:1 on that fill.
///
/// The appearance is part of the key because the product here is a BITMAP:
/// `ImageRenderer` resolves the two tokens once, at render time, and both
/// have four values in the asset catalog. Keyed on the text alone, the pill
/// drawn on a light Today survived into dark mode — light accentSoft on the
/// dark card — until something else evicted it.
///
/// The key alone would only guarantee a re-render; the render also has to
/// land on the appearance it is keyed for, and inside `ImageRenderer` a
/// `Theme` token would resolve against whatever the renderer inherits. So
/// the two colours arrive already resolved, from `Theme.badgePillColors`.
///
/// Nothing invalidates the cache, and nothing needs to: a stale entry is
/// unreachable rather than wrong, and one badge text costs at most four
/// entries per Dynamic Type size.
///
/// Not file-private: `BadgePillTests` is the only thing that can tell two
/// appearances of one bitmap apart, and it needs the entry point.
@MainActor
enum BadgePill {
    private static var cache: [String: UIImage] = [:]

    static func image(text: String, scale: CGFloat,
                      typeSize: DynamicTypeSize,
                      colorScheme: ColorScheme,
                      contrast: ColorSchemeContrast) -> UIImage? {
        let key = "\(text)|\(scale)|\(typeSize)|\(colorScheme)|\(contrast)"
        if let hit = cache[key] { return hit }
        let palette = Theme.badgePillColors(colorScheme: colorScheme, contrast: contrast)
        let renderer = ImageRenderer(content:
            Text(text)
                .dredfitFont(11, weight: .semibold)
                .foregroundStyle(palette.text)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(palette.fill, in: Capsule())
                .environment(\.dynamicTypeSize, typeSize)
        )
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        cache[key] = image
        return image
    }
}
