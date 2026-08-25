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
                exitButton(action: onExit)
                Spacer()
                Text(title)
                    .dredfitFont(13, weight: .semibold)
                    .kerning(0.5)
                    // ink2, not ink3: this is information, not decoration.
                    .foregroundStyle(Theme.ink2)
                Spacer()
                // Symmetry: the title is centred by two equal ends, so the
                // right one has to measure the same — including the 44 pt.
                exitButton(action: { }).hidden()
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

    /// The way out of a workout in progress, and the hidden twin that keeps
    /// the title centred. 44 pt: a bare 14 pt label is about 17, and this is
    /// the control someone reaches for when a set has gone wrong.
    private func exitButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            // ink2, not ink3: ink3 (~2.4:1) fails contrast for
            // interactive text.
            Text("Exit")
                .dredfitFont(14)
                .foregroundStyle(Theme.ink2)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
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
    let setIndex: Int
    let sets: Int
    /// What THIS set is planned to run at, and whether the exercise is uneven
    /// at all. On an uneven plan the caption says the number, because "set 2
    /// of 3" no longer tells you what to do — the sets differ. The actual
    /// still outranks it: that is today's number.
    var planned: Int = 0
    var uneven: Bool = false

    var body: some View {
        if switchingSides {
            accented(Text("Switch sides"))
        } else if secondSide {
            accented(Text("second side"))
        } else if let actual {
            accented(Text("actual \(actual)"))
        } else if uneven {
            accented(Text("set \(setIndex + 1) of \(sets) · \(planned)"))
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

/// What you can say about an exercise instead of doing it as planned
/// (issues #66, #78).
///
/// "hold this level" went with the input it armed, and "Something hurt" with
/// the channel behind it. What arrived instead is the other half of §38: the
/// two handles that used to stand on the plan are gone, and the decision they
/// asked for BEFORE the workout is taken here, mid-set, where the person
/// actually knows the answer.
///
/// So the row carries three things now — the honest number, the set in front
/// of you, and the movement. The engine measures the first against the tap it
/// replaces: honest numbers take someone with a capacity of one rep from
/// L24/tier 4 to L0/tier 1 in FOUR appearances, while the pain tap stranded
/// them at L16/tier 3 indefinitely.
struct ExerciseActionsRow: View {
    let onAdjust: () -> Void
    /// The set-level skip. Absent when it would take the whole movement with
    /// it (§38.2 rule 2) — the escape below then says so in its own label.
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
                Your level does not change.
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

/// The "ⓘ technique" affordance — one look shared by the work screen, the
/// rest screen and the warm-up/cool-down positions (issue #34).
/// The rest phase. The ring is the primary element here, which is why neither
/// control under it is a filled button: someone who is not recovered has to be
/// able to ask for more time about as easily as to cut the rest short. The
/// asymmetry that idea replaced was not a comfort problem — standing at an
/// expired timer or starting a set you cannot finish both reach the engine as
/// "tough".
///
/// What went with it, on the owner's read of the audit frames, is EQUAL WIDTH.
/// The two are not asked for equally often: the rest ends and the thumb comes
/// down on Skip, and halves put "+15 s" under a good share of those taps. It
/// keeps the same height, the same outline and the same weight — only a third
/// of the row instead of half.
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
            // A third and two thirds, not halves. The pair is not a choice
            // between equals: skipping is what the thumb comes down for, and
            // extending is the exception — equal widths put the rare button
            // under half of the taps meant for the common one.
            GeometryReader { proxy in
                let gap: CGFloat = 12
                let unit = max(0, (proxy.size.width - gap) / 3)
                HStack(spacing: gap) {
                    extend.frame(width: unit)
                    skip.frame(width: unit * 2)
                }
            }
            .frame(height: BlockSkipButton.height)
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
                // 44 pt, like the two escapes above — and for a harder
                // reason. This one is offered on five screens, three of them
                // mid-effort, where the hand that reaches for it is the hand
                // that just did the set. The bare label came to about 17 pt.
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        // Without an identifier the button answers only to its English
        // label, and a localized run cannot open the sheet at all.
        .accessibilityIdentifier("technique")
    }
}
