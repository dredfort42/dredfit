//
//  FlowChrome.swift
//  Dredfit
//
//  The small pieces every timed block of the workout flow shares: the big
//  rolling countdown number, the full-width outline escape button, and the
//  "ⓘ technique" affordance. One look, defined once — the warm-up, rest
//  and cool-down screens assemble these instead of restating them.
//

import SwiftUI

/// The bar every timed phase wears: the way out on the left, what the screen
/// is in the middle, and the per-exercise capsules underneath. The rating and
/// milestone screens carry no header at all, so this view never knows about
/// them.
struct FlowHeader: View {
    let title: String
    /// 0 hides the capsule row — the warm-up is not an exercise yet.
    let steps: Int
    let doneIndex: Int
    var onExit: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                // ink2, not ink3: ink3 (~2.4:1) fails contrast for
                // interactive text.
                Button(String(localized: "Exit"), action: onExit)
                    .dredfitFont(14)
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Text(title)
                    .dredfitFont(13, weight: .semibold)
                    .kerning(0.5)
                    // ink2, not ink3: this is information, not decoration.
                    .foregroundStyle(Theme.ink2)
                Spacer()
                Button(String(localized: "Exit")) { }.dredfitFont(14).hidden() // symmetry
            }
            if steps > 0 {
                HStack(spacing: 5) {
                    ForEach(0..<steps, id: \.self) { i in
                        Capsule()
                            .fill(i <= doneIndex ? Theme.ink : Theme.hairline)
                            .frame(height: 4)
                    }
                }
                .frame(width: 200)
            }
        }
        .padding(.top, 12)
    }
}

/// The big rolling number with its "sec" caption.
struct CountdownNumber: View {
    let value: Int
    let identifier: String
    /// Paused (issue #61) the number dims and the unit gives way to the
    /// state, so a glance says why nothing is moving.
    var paused = false

    var body: some View {
        VStack(spacing: 4) {
            Text("\(value)")
                .dredfitFont(112, weight: .heavy, cap: 150)
                .tracking(-4)
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .foregroundStyle(paused ? Theme.ink2 : Theme.ink)
                .accessibilityIdentifier(identifier)
            if paused {
                Text("Paused")
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(Theme.accentText)
            } else {
                Text("sec")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
            }
        }
    }
}

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

/// One definition for the warm-up, the cool-down and the transition — three
/// copies would drift.
struct BlockDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 10) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(i < current ? Theme.ink : (i == current ? Theme.accent : Theme.hairline))
                    .frame(width: 10, height: 10)
            }
        }
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
    let title: String
    var identifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .dredfitFont(17, weight: .medium)
                .foregroundStyle(Theme.ink2)
                .frame(maxWidth: .infinity, minHeight: 56)
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.hairline, lineWidth: 1.5))
        }
        .accessibilityIdentifier(identifier ?? title)
    }
}

/// The one line under the set dots: what the screen is doing right now, in
/// order of precedence — a side switch, the second side, an entered actual,
/// or plainly which set is up.
struct WorkStatusCaption: View {
    let switchingSides: Bool
    let secondSide: Bool
    /// nil when the exercise is running to plan.
    let actual: Int?
    /// The hold-this-level mark (issue #78). A pin changes nothing visible in
    /// the plan, so the caption is where the tap confirms itself; an entered
    /// actual still outranks it — that is today's number, this is trajectory.
    let held: Bool
    let setIndex: Int
    let sets: Int

    var body: some View {
        if switchingSides {
            accented(Text("Switch sides"))
        } else if secondSide {
            accented(Text("second side"))
        } else if let actual {
            accented(Text("actual \(actual)"))
        } else if held {
            accented(Text("level held"))
        } else {
            Text("set \(setIndex + 1) of \(sets)")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
        }
    }

    private func accented(_ text: Text) -> some View {
        text.dredfitFont(14, weight: .semibold).foregroundStyle(Theme.accentText)
    }
}

/// The four things you can say about an exercise instead of doing it as
/// planned — two rows of two (issues #66, #78): the first row is about today,
/// the second about the body and the trajectory. Two per row is the ceiling —
/// three overflow the longest labels at accessibility sizes — and at those
/// sizes even two truncate, so the rows stack into a single column there,
/// the same rule the rest ring's controls follow.
struct ExerciseActionsRow: View {
    /// The hold request is a toggle on an exercise still being done, and the
    /// row is where its state shows.
    let pinned: Bool
    let onAdjust: () -> Void
    let onSkip: () -> Void
    let onPin: () -> Void
    let onDiscomfort: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 12) {
                adjustButton
                skipButton
                pinButton
                discomfortButton
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 26) {
                    adjustButton
                    skipButton
                }
                HStack(spacing: 26) {
                    pinButton
                    discomfortButton
                }
            }
        }
    }

    private var adjustButton: some View {
        Button(String(localized: "Went differently"), action: onAdjust)
            .dredfitFont(14.5)
            .foregroundStyle(Theme.ink2)
    }

    private var skipButton: some View {
        Button(String(localized: "Skip exercise"), action: onSkip)
            .dredfitFont(14.5)
            .foregroundStyle(Theme.ink2)
    }

    /// One tap, no confirmation: nothing here is worth making someone in
    /// pain read a dialog.
    private var discomfortButton: some View {
        Button(String(localized: "Something hurt"), action: onDiscomfort)
            .dredfitFont(14.5, weight: .semibold)
            .foregroundStyle(Theme.accentText)
            .accessibilityIdentifier("report-discomfort")
            // One literal, split for width: a concatenation would resolve to
            // the verbatim initializer and never reach the catalog.
            .accessibilityHint(Text(String(localized: """
                The movement stays in the plan at this level and stops \
                getting harder for a while.
                """)))
    }

    /// A pin changes nothing visible in today's plan, so the confirmation is
    /// carried here: the label flips to a filled pill. accentText on
    /// accentSoft — the pairing the Today badge pill already vouches for.
    /// The label carries the state, so VoiceOver never depends on the fill.
    private var pinButton: some View {
        Button(action: onPin) {
            Group {
                if pinned {
                    Text("Holding")
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(Theme.accentSoft, in: Capsule())
                } else {
                    Text("Hold this level")
                }
            }
            .dredfitFont(14.5, weight: .semibold)
            .foregroundStyle(Theme.accentText)
        }
        .accessibilityIdentifier("hold-level")
        .accessibilityAddTraits(pinned ? [.isSelected] : [])
        .accessibilityHint(Text(String(localized: """
            Today's sets stay as planned; the movement stops getting harder \
            for a while. Tap again to change your mind.
            """)))
    }
}

/// The "ⓘ technique" affordance — one look shared by the work screen, the
/// rest screen and the warm-up/cool-down positions (issue #34).
/// The rest phase. The ring is the primary element here, which is why the two
/// controls under it carry equal weight and neither is a filled button:
/// someone who is not recovered has to be able to ask for more time as easily
/// as to cut the rest short. The asymmetry it replaces was not a comfort
/// problem — standing at an expired timer or starting a set you cannot finish
/// both reach the engine as "tough".
struct RestRing: View {
    let remaining: Int
    let fraction: CGFloat
    let ringSize: CGFloat
    let nextLabel: String
    let extensionSeconds: Int
    /// False at the cap. The button greys out instead of disappearing, so the
    /// row never jumps out from under the finger.
    let canExtend: Bool
    var onTechnique: () -> Void
    var onExtend: () -> Void
    var onSkip: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Theme.hairline, lineWidth: 7)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)
                VStack(spacing: 2) {
                    Text("\(remaining)")
                        .dredfitFont(72, weight: .heavy, cap: 104)
                        .tracking(-2)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                    Text("sec")
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                }
            }
            // Capped to still fit the narrowest screen with its 24pt margins.
            .frame(width: min(ringSize, 330), height: min(ringSize, 330))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(remaining) seconds of rest left"))

            VStack(spacing: 6) {
                Kicker(text: String(localized: "Next up"))
                Text(nextLabel)
                    .dredfitFont(17, weight: .semibold)
            }
            .padding(.top, 44)

            TechniqueButton(action: onTechnique)
                .padding(.top, 16)

            Spacer()

            controls
                .padding(.bottom, 20)
        }
    }

    /// Side by side while they fit; stacked once the labels grow, because two
    /// 56pt buttons and an accessibility-size label do not share a row.
    @ViewBuilder
    private var controls: some View {
        let extend = BlockSkipButton(title: String(localized: "+\(extensionSeconds) s"),
                                     identifier: "extend-rest",
                                     action: onExtend)
            .disabled(!canExtend)
            // .disabled alone changes nothing on a custom label — at the cap
            // the button has to LOOK spent, while keeping its place in the row.
            .opacity(canExtend ? 1 : 0.35)
            // "+15 s" is read as punctuation; the horizon has to be a phrase.
            .accessibilityLabel(Text("Add \(extensionSeconds) seconds of rest"))
        let skip = BlockSkipButton(title: String(localized: "Skip rest"), action: onSkip)
        if dynamicTypeSize.isAccessibilitySize {
            VStack(spacing: 10) { extend; skip }
        } else {
            HStack(spacing: 12) { extend; skip }
        }
    }
}

struct TechniqueButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(String(localized: "technique"), systemImage: "info.circle")
                .dredfitFont(14, weight: .medium)
                .foregroundStyle(Theme.ink2)
        }
        // Without an identifier the button answers only to its English
        // label, and a localized run cannot open the sheet at all.
        .accessibilityIdentifier("technique")
    }
}
