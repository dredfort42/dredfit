//
//  The buttons a person taps to change course mid-block: pause, skip this
//  position, skip the block outright, or say what an exercise actually did.
//  FlowChrome.swift held these next to the header and the countdown only
//  because all ten started small; this file gives the controls their own
//  place.
//

import SwiftUI

/// The pause both guided blocks carry on every timed screen (issue #61) —
/// compact, one slot under the countdown, the same weight as the technique
/// affordance above it. The outline says "control" where a bare label would
/// read as one more caption.
struct BlockPauseButton: View {
    let paused: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(paused ? String(localized: "Resume") : String(localized: "Pause"),
                  systemImage: paused ? "play.fill" : "pause.fill")
                .dredfitFont(14, weight: .medium)
                .foregroundStyle(paused ? Theme.accentText : Theme.ink2)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1.5))
        }
        // The identifier carries the state, not just the control: a localized
        // run must still be able to tell a paused block from a running one.
        .accessibilityIdentifier(paused ? "block-resume" : "block-pause")
    }
}

/// The per-position escape both guided blocks carry.
struct PositionSkipButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Skip this move")
                .dredfitFont(14, weight: .medium)
                .foregroundStyle(Theme.ink2)
                .frame(minHeight: 44)
        }
    }
}

/// The full-width outline escape at the bottom of a block — "Skip warm-up",
/// "Skip rest", "Skip cool-down".
struct BlockSkipButton: View {
    /// Named because the rest screen lays its pair out by hand and has to
    /// reserve exactly this much: two definitions of 56 would drift.
    static let height: CGFloat = 56

    let title: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dredfitFont(17, weight: .medium)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: Self.height)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1.5))
        }
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// What you can say about an exercise instead of doing it as planned
/// (issues #66, #78).
///
/// "hold this level" went with the input it armed, and "Something hurt" with
/// the channel behind it. What arrived instead is the other half of the same
/// idea: the two handles that used to stand on the plan are gone, and the
/// decision they asked for BEFORE the workout is taken here, mid-set, where
/// the person actually knows the answer.
///
/// So the row carries three things now — the honest number, the set in front
/// of you, and the movement. The engine measures the first against the tap it
/// replaces: honest numbers take someone with a capacity of one rep from
/// L24/tier 4 to L0/tier 1 in FOUR appearances, while the pain tap stranded
/// them at L16/tier 3 indefinitely.
struct ExerciseActionsRow: View {
    let onAdjust: () -> Void
    /// The set-level skip. Absent when it would take the whole movement with
    /// it — the escape below then says so in its own label.
    let onSkipSet: (() -> Void)?
    /// The exercise-level escape, and the landing its title names. Absent on
    /// the last set, where "the remaining sets" are the one beside it.
    let escape: Escape?

    struct Escape {
        let title: String
        let identifier: String
        let action: () -> Void
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// One row while the three labels fit it, two when they do not, three
    /// stacked at the accessibility sizes. Measured rather than assumed: the
    /// same three words are 313 pt in English and half again in German, and a
    /// row that truncates the escape is a row that hides the way out.
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                adjustButton
                skipSetButton
                escapeButton
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 22) {
                    adjustButton
                    skipSetButton
                    escapeButton
                }
                VStack(spacing: 4) {
                    adjustButton
                    HStack(spacing: 24) {
                        skipSetButton
                        escapeButton
                    }
                }
                VStack(spacing: 4) {
                    adjustButton
                    skipSetButton
                    escapeButton
                }
            }
        }
    }

    /// 44 pt of target, not the 18 pt the bare label came to. It sits under
    /// the primary button, and the primary button on this screen LOGS THE SET
    /// — a thumb that lands a few points high does not miss, it finishes the
    /// set at plan. The height is the fix; `contentShape` is what makes the
    /// whole of it answer.
    private var adjustButton: some View {
        Button(action: onAdjust) {
            Text("Went differently")
                .dredfitFont(14.5, weight: .semibold)
                .foregroundStyle(Theme.accentText)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
            .accessibilityIdentifier("exercise-adjust")
            // One literal, split for width: a concatenation would resolve to
            // the verbatim initializer and never reach the catalog.
            .accessibilityHint(Text(String(localized: """
                Enter what you actually did. \
                The plan follows your numbers.
                """)))
    }

    /// 44 pt like the two beside it, and ink2 like the escape: skipping a set
    /// is an ordinary answer, not a failure, and it must not read louder than
    /// the number that says what was actually done.
    @ViewBuilder
    private var skipSetButton: some View {
        if let onSkipSet {
            Button(action: onSkipSet) {
                Text("Skip this set")
                    .dredfitFont(14.5)
                    .foregroundStyle(Theme.ink2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityIdentifier("exercise-skip-set")
            .accessibilityHint(Text(String(localized: """
                The plan keeps this set off next time. \
                Nothing else about the movement changes.
                """)))
        }
    }

    @ViewBuilder
    private var escapeButton: some View {
        if let escape {
            Button(action: escape.action) {
                Text(verbatim: escape.title)
                    .dredfitFont(14.5)
                    .foregroundStyle(Theme.ink2)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            // The title is one of two sentences and the identifier says which,
            // so a localized run can tell a movement that was TRAINED SHORT
            // from one that was not trained at all.
            .accessibilityIdentifier(escape.identifier)
        }
    }
}
