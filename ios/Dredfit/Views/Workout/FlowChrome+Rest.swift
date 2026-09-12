//
//  What a running set is doing right now, and the ring the rest screen counts
//  down inside — split out of FlowChrome.swift, which had grown into ten
//  unrelated leaf views sharing one file for no reason but their size.
//

import SwiftUI

/// The one line under the set dots: what the screen is doing right now, in
/// order of precedence — the second side, an entered actual, or plainly which
/// set is up.
///
/// The count-in and the side switch used to open this list, and they moved to
/// the caption directly under the big number (`WorkoutFlowView.loadCaption`).
/// Both are read from 1.5-2 m away, off a phone the screen itself told the
/// person to put on the floor, and at that distance a 14 pt word under the
/// dots is about 2.6 arc minutes — under the 5' it takes to recognise a
/// letter at all. Repeating them here as well would only be the same
/// unreadable word twice (UX review, 05.09.2026).
struct WorkStatusCaption: View {
    let secondSide: Bool
    /// The movement's LAST hold is behind and its seconds are recorded, but
    /// the set is not closed yet (`WorkoutFlowView.holdSettled`). It outranks
    /// the actual below deliberately: in this state the big number above IS
    /// what was held, so "actual 25" would repeat it while saying less — and
    /// what the screen has to say instead is that the effort is over and the
    /// number is still editable.
    var settled: Bool = false
    /// nil when the exercise is running to plan.
    let actual: Int?
    /// The hold-this-level mark (issue #78). A pin changes nothing visible in
    /// the plan, so the caption is where the tap confirms itself.
    let setIndex: Int
    let sets: Int
    /// What THIS set will run at, and whether that is worth printing. On an
    /// uneven plan the caption says the number, because "set 2 of 3" no longer
    /// tells you what to do — the sets differ. So does a set whose number was
    /// carried DOWN by a shortfall behind it: that is a plan the person did
    /// not choose and never saw named. The actual still outranks both: that is
    /// a set already performed.
    var planned: Int = 0
    var uneven: Bool = false

    var body: some View {
        if secondSide {
            accented(Text("second side"))
        } else if settled {
            accented(Text("Held"))
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
    /// Frozen: the ring stands still and the button offers the way back in.
    var paused: Bool = false
    /// nil on a rest whose clock starts nothing (R32). Only the rest of a
    /// hands-free hold run hands the next set to a timer, and that is the only
    /// rest where stepping away costs a set — everywhere else the person is
    /// what the flow is waiting for, and a Pause would promise to stop
    /// something that is not moving.
    var onPauseToggle: (() -> Void)?
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
                        // Dimmed while frozen, and the unit gives way to the
                        // state: `CountdownNumber` says it this way in both
                        // guided blocks, and a paused rest is the same fact.
                        .foregroundStyle(paused ? Theme.ink2 : Theme.ink)
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
            // Capped to still fit the narrowest screen with its 24pt margins.
            .frame(width: min(ringSize, 330), height: min(ringSize, 330))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(remaining) seconds of rest left"))
            // The label changes every second on an element a VoiceOver user is
            // very likely to be sitting on — this is exactly the trait for it:
            // the reader stops interrupting itself with the new number and the
            // number stays there to be asked for. Without it the only way to
            // hear the end of the rest was to hear all sixty seconds of it
            // (UX review, 05.09.2026).
            .accessibilityAddTraits(.updatesFrequently)

            VStack(spacing: 6) {
                // Two rests look identical and end differently: an ordinary
                // one hands the screen back and WAITS for a tap, while the
                // rest inside a hands-free hold run starts the next set on its
                // own go. Only the Pause capsule below said so, and it says it
                // by existing — the kicker is where the eye lands after the
                // ring, so it is where the difference belongs. Keyed off the
                // pause itself rather than a new flag: `onPauseToggle` is
                // non-nil on exactly the rest whose clock starts something
                // (R32, the doc comment above) (UX review, 05.09.2026).
                Kicker(text: onPauseToggle == nil
                       ? String(localized: "Next up")
                       : String(localized: "Starts by itself"))
                Text(nextLabel)
                    .dredfitFont(17, weight: .semibold)
            }
            .padding(.top, 44)

            TechniqueButton(action: onTechnique)
                .padding(.top, 16)

            if let onPauseToggle {
                BlockPauseButton(paused: paused, action: onPauseToggle)
                    .padding(.top, 12)
            }

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
        // `identifier:` stated, not left to default: BlockSkipButton falls back
        // to `identifier ?? title`, and `title` has already been through
        // String(localized:) — so an omitted argument makes the accessibility
        // identifier change with the display language, which is the one thing
        // an identifier exists not to do. `extend-rest` above always stated it.
        let skip = BlockSkipButton(title: String(localized: "Skip rest"),
                                   identifier: "skip-rest",
                                   action: onSkip)
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
