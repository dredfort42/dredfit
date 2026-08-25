//
//  What a running set is doing right now, and the ring the rest screen counts
//  down inside — split out of FlowChrome.swift, which had grown into ten
//  unrelated leaf views sharing one file for no reason but their size.
//

import SwiftUI

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
