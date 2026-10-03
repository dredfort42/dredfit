//
//  The buttons a person taps to change course mid-workout: pause, the skips,
//  "Went differently", and a hold's "Set the time" and Stop. The header, the
//  countdown and the dots live in FlowChrome.swift.
//

import SwiftUI

/// The pause of the guided blocks (issue #61) and of a rest that starts the
/// next set by itself — compact, the same weight as the technique
/// affordance above it. The outline says "control" where a bare label would
/// read as one more caption.
///
/// `Theme.targetStroke` for that outline: on `bg` hairline is 1.17:1 and ink3
/// 2.35:1 in the light scheme, both short of the 3:1 that 1.4.11 asks of the
/// line a person is supposed to aim at. The token names the ROLE, which keeps
/// the three outlines of this file, the adjuster's steppers and the summary
/// cards from drifting apart.
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
                .overlay(Capsule().stroke(Theme.targetStroke, lineWidth: 1.5))
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
/// "Skip rest", "Skip cool-down" — and the rest's "+N s" beside it.
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
                // targetStroke, like the pause capsule above and the two
                // secondary labels below. Nothing else says this is a control:
                // hairline on `bg` is 1.17:1, so the outline of a full-width
                // button would disappear outright, and ink3 is 2.35:1 light,
                // under the 3:1 of 1.4.11.
                .overlay(RoundedRectangle(cornerRadius: 18)
                    .stroke(Theme.targetStroke, lineWidth: 1.5))
        }
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// The two escapes of an exercise: skip the set in front of you, or the rest
/// of the movement. The decision is taken here, mid-set, where the person
/// actually knows the answer.
struct ExerciseActionsRow: View {
    /// The set-level skip. Absent when it would take the whole movement with
    /// it — the escape below then says so in its own label.
    let onSkipSet: (() -> Void)?
    /// True when the set under the buttons is the PROBE: skipping it takes no
    /// volume off anything — the probe just comes back next appearance — so
    /// the hint that promises "kept off next time" would be false there.
    let skipsProbe: Bool
    /// The exercise-level escape, and the landing its title names. Absent on
    /// the probe set, and on a last set the set-level skip already covers.
    let escape: Escape?

    struct Escape {
        let title: String
        let identifier: String
        let action: () -> Void
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The two escapes. "Went differently" is a control of its own, ABOVE the
    /// primary button: it answers a different question from these two.
    ///
    /// One row while both labels fit it, stacked when they do not, and always
    /// stacked at accessibility sizes. Measured rather than assumed: the same
    /// words run longer in German, and a row that truncates the escape is a
    /// row that hides the way out.
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

    /// 44 pt and ink2, like the escape beside it: skipping a set is an
    /// ordinary answer, not a failure, and it must not read louder than the
    /// number that says what was actually done.
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
/// primary one rather than under it.
///
/// Secondary, not accent: it is the alternative to finishing the set at plan,
/// not a rival to it — the filled button is what the screen expects, the
/// outlined one is the other answer.
///
/// `targetStroke` for the outline, as on `pairedSecondaryLabel`: hairline is
/// 1.17:1 on `bg` and ink3 2.35:1 in light, both under the 3:1 that 1.4.11
/// asks of the boundary of a target. The ink2 label keeps the 4.5:1 small
/// text needs.
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
/// is worth would be to take it. It is `PrimaryButton`'s look, restated rather
/// than wrapped, because the label needs `monospacedDigit` and a numeric
/// transition — a figure that changes every second must not make the whole
/// button breathe.
///
/// ONE localized string per state, never a concatenation of `Text`s, so a
/// translation places the figure itself. The figure is the point of the
/// control, so it keeps the label's own contrast (`Theme.bg` on `Theme.ink`)
/// rather than a quieter step.
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
                .strokeBorder(Theme.targetStroke, lineWidth: 1.5))
    }
}

/// "Set the time" — the ONE thing a hold takes before the effort: how long it
/// is going to run.
///
/// It is not "Went differently" under a kinder name, and the difference is
/// the tense. That control asks how a set WENT, which before the effort is a
/// question about something that has not happened — which is why this screen
/// does not carry it. This one asks what the clock should be set to, which
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
