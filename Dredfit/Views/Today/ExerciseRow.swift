//
//  ExerciseRow.swift
//  Dredfit
//
//  One line of a plan: the movement, its number, and — since v2.25 — the one
//  sentence that says why the number is what it is. Shared by Today and the
//  next-workout sheet, so both draw the same card and cannot drift into two
//  different explanations of the same plan.
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
    /// v2.25 (spec §36.2): one line under the number, saying why it is the
    /// number it is. Under the number and not beside it — the sentence is
    /// longer than the column, and the load must keep its place.
    var note: String?
    @Environment(\.displayScale) private var displayScale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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
            if let note {
                Text(note)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("sets-note")
            }
        }
        .padding(.vertical, 4)
    }

    /// The wording for each rung of `AppStore.SetsNote`. Static and here
    /// rather than in either screen: Today and the next-workout sheet draw
    /// the same card and must not drift into two different explanations.
    static func note(_ kind: AppStore.SetsNote?) -> String? {
        switch kind {
        case .setBack:
            return String(localized: "A set is back — your body is coping.")
        case nil:
            return nil
        }
    }

    /// Text concatenation is the only SwiftUI flow that lets the pill follow
    /// the last word and wrap with it, so it travels as an inline image.
    private var nameWithBadge: some View {
        var name = Text(exercise.name)
        if let badge,
           let pill = BadgePill.image(text: badge, scale: displayScale,
                                      typeSize: dynamicTypeSize) {
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
        // v2.22 (spec §33): an uneven plan spells its sets out — "9-8-8". This
        // is where the sub-step becomes visible: a third of the sessions used
        // to read as "nothing changed", and the row is what says otherwise.
        // Explicit keys, not the bare "%@%@" a plain interpolation would mint.
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

/// Cached per text, display scale and Dynamic Type size. accentText on
/// accentSoft — accent itself is 2.91:1 on that fill. Not file-private any
/// more: Today's resting rows draw the same pill, and one renderer means one
/// cache and one set of metrics for both.
@MainActor
enum BadgePill {
    private static var cache: [String: UIImage] = [:]

    static func image(text: String, scale: CGFloat,
                      typeSize: DynamicTypeSize) -> UIImage? {
        let key = "\(text)|\(scale)|\(typeSize)"
        if let hit = cache[key] { return hit }
        let renderer = ImageRenderer(content:
            Text(text)
                .dredfitFont(11, weight: .semibold)
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.accentSoft, in: Capsule())
                .environment(\.dynamicTypeSize, typeSize)
        )
        renderer.scale = scale
        guard let image = renderer.uiImage else { return nil }
        cache[key] = image
        return image
    }
}
