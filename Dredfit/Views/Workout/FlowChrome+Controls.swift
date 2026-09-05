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
            Text("Skip this position")
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
    /// The set-level skip. Absent when it would take the whole movement with
    /// it — the escape below then says so in its own label.
    let onSkipSet: (() -> Void)?
    /// True when the set under the buttons is the PROBE: skipping it takes no
    /// volume off anything — the probe just comes back next appearance
    /// (§40.4) — so the hint that promises "kept off next time" would be
    /// false there (UI-truth audit, 27.08.2026).
    let skipsProbe: Bool
    /// The exercise-level escape, and the landing its title names. Absent on
    /// the last set, where "the remaining sets" are the one beside it.
    let escape: Escape?

    struct Escape {
        let title: String
        let identifier: String
        let action: () -> Void
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The two escapes. "Went differently" left this row on 27.08.2026 and
    /// became a control of its own ABOVE the primary button — it answers a
    /// different question from these two, and it is the one people use.
    ///
    /// One row while both labels fit it, stacked when they do not. Measured
    /// rather than assumed: the same words are half again as long in German,
    /// and a row that truncates the escape is a row that hides the way out.
    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                skipSetButton
                escapeButton
            }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) {
                    skipSetButton
                    escapeButton
                }
                VStack(spacing: 4) {
                    skipSetButton
                    escapeButton
                }
            }
        }
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
            .accessibilityHint(Text(skipsProbe
                ? String(localized: """
                    The probe just comes back next time. \
                    The working sets lose nothing.
                    """)
                : String(localized: """
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


/// "Went differently" — the SECOND control of the pair, standing above the
/// primary one rather than under it (owner, 27.08.2026).
///
/// Secondary, not accent: it is the alternative to finishing the set at plan,
/// not a rival to it, and the pair now reads the way every other pair in the
/// app does — the filled one is what the screen expects, the outlined one is
/// the other answer.
///
/// ink3 for the outline, not hairline. `pairedSecondaryLabel` uses hairline,
/// but both of its call sites draw on `cardBG`; here the ground is `bg`, where
/// hairline comes to ≈1.2:1 and the border is simply not there. ink3 reads
/// ≈2.4:1 — past the 1.5:1 the palette holds for quiet graphics — while the
/// ink2 label keeps the 4.5:1 small text needs.
struct WentDifferentlyButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Went differently").flowSecondaryLabel()
        }
        .accessibilityIdentifier("exercise-adjust")
        // One literal, split for width: a concatenation would resolve to the
        // verbatim initializer and never reach the catalog.
        .accessibilityHint(Text(String(localized: """
            Enter what you actually did. \
            The plan follows your numbers.
            """)))
    }
}

/// "Stop · 60 s" — the primary control of a running hold, naming the figure it
/// will write (R29).
///
/// A hold ends with the phone out of reach, so the number the tap records has
/// to be legible from the floor: without it the only way to learn what a Stop
/// was worth was to take it. It is `PrimaryButton`'s look, restated rather
/// than wrapped, because the label needs `monospacedDigit` and a numeric
/// transition — a figure that changes every second must not make the whole
/// button breathe.
///
/// ONE localized string per state, never a concatenation. The mock paints the
/// separator and the figure a step quieter than the word, and that is what a
/// concatenation would buy: three `Text`s resolve to the verbatim initializer
/// and never reach the catalog, which is the warning already standing on
/// `WentDifferentlyButton`. The figure is the point of the control, so it
/// keeps the label's own contrast (`Theme.bg` on `Theme.ink`) instead.
struct HoldStopButton: View {
    /// What a tap right now records — nil inside the mis-tap grace, where the
    /// tap cancels the set and writes nothing at all. A figure there would be
    /// a lie about a number that is never stored.
    let records: Int?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            label
                .dredfitFont(17, weight: .semibold)
                .foregroundStyle(Theme.bg)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
        }
        .accessibilityIdentifier("hold-stop")
        // Spelled out: "Stop · 60 s" read aloud is a middle dot and a unit
        // nobody asked about, and what the listener needs is the consequence.
        .accessibilityLabel(records.map {
            Text(String(localized: "Stop, records \($0) seconds"))
        } ?? Text(String(localized: "Stop")))
    }

    @ViewBuilder
    private var label: some View {
        if let records {
            Text("Stop · \(records) s")
        } else {
            Text("Stop")
        }
    }
}

/// The look the two secondary controls above the primary button share — the
/// alternative answer, never a rival to it. Extracted rather than restated
/// because a second copy of an outline that has a measured reason for every
/// value in it is a second copy that drifts.
extension View {
    func flowSecondaryLabel() -> some View {
        dredfitFont(15.5, weight: .medium)
            .foregroundStyle(Theme.ink2)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Theme.ink3, lineWidth: 1.5))
    }
}

/// "Set the time" — the ONE thing a hold takes before the effort: how long it
/// is going to run.
///
/// It is not "Went differently" under a kinder name, and the difference is
/// the tense. That control asks how a set WENT, which before the effort is a
/// question about something that has not happened — the objection that took
/// it off this screen. This one asks what the clock should be set to, which
/// is the only question a person standing in front of a plank can actually
/// answer, and the answer is a target: what reaches the engine is still
/// whatever the clock then measured, cut down by Stop if the hold ends early.
///
/// Neutral by name, and deliberately: the same control lowers the time on a
/// day when the plan is too much. Naming it "hold longer" would have made the
/// downward answer look like a failure of the button rather than an ordinary
/// decision.
struct SetHoldTimeButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Set the time").flowSecondaryLabel()
        }
        .accessibilityIdentifier("hold-set-time")
        .accessibilityHint(Text(String(localized: """
            How long every set of this exercise runs. \
            Stop ends one early and records what you held.
            """)))
    }
}
