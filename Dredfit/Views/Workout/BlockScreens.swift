//
//  The three screens of a guided block: the "Get ready" transition, a
//  running warm-up move, and a running cool-down position.
//
//  Layout only — each is a pure function of what it is handed; the flow view
//  keeps the state machine and the timers.
//

import SwiftUI

struct GetReadyScreen: View {
    let name: String
    let remaining: Int
    let index: Int
    let count: Int
    /// The way back in after a pause borrows this screen (issue #61) and
    /// names its countdown differently, so the two can be told apart.
    var countdownIdentifier: String = "getready-countdown"
    /// Which block this transition belongs to — the transition is the ONE
    /// block screen both of them share, and through this it names its own
    /// escape instead of being handed the words twice.
    let block: GuidedBlock
    let paused: Bool
    /// Whether what is counting down is already the count-in — the last
    /// `GetReady.countInSeconds` of a transition, however it got there.
    let countingIn: Bool
    let onTechnique: () -> Void
    let onStart: () -> Void
    let onPauseToggle: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            // "Get ready" is under the big number now, not over the name.
            // It was a 12 pt kicker at the top of the screen, and it was the
            // ONE thing telling this screen from a position already running —
            // same name, same 112 pt countdown, same dots — read off a phone
            // the block itself has just told the person to put on the floor.
            // Under the digit is where the eye already is, which is where the
            // work screen says exactly this word (`loadCaption`)
            // (UX review, 05.09.2026).
            //
            // This line used to claim VoiceOver still got the sentence ONCE,
            // from the name below, and it does not. The kicker carried
            // `.accessibilityHidden(true)`, which is what made that true; the
            // caption does not, and `CountdownNumber` never merges it with the
            // number the way the work screen merges its own pair — the number
            // is pinned as an element of its own by its identifier and
            // `.updatesFrequently`. So the reader hears the name's "Get ready:
            // Cat-cow" and then a bare "Get ready" with nothing attached: once
            // per transition, twelve times across the two blocks (review
            // 06.09.2026, open). It closes in `CountdownNumber`'s `caption`
            // branch and only there — the `paused` branch above it stays
            // audible, because "Paused" is state the name does not carry, and
            // combining the pair HERE would swallow the `getready-countdown`
            // identifier three UI suites query.
            BlockPositionName(name: name)
                .accessibilityLabel(Text("Get ready: \(name)"))

            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining,
                            identifier: countdownIdentifier,
                            paused: paused,
                            caption: String(localized: "Get ready"))
                .padding(.top, 20)

            BlockPauseButton(paused: paused, action: onPauseToggle)
                .padding(.top, 12)

            // `upcoming`: the position at `index` has not begun, and a
            // filled accent dot said it had.
            BlockDots(count: count, current: index, upcoming: true)
                .padding(.top, 22)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            // Two reasons the transition has nothing left to start early.
            // Frozen, "I'm ready" would run a position the user has just
            // stopped. Inside the count-in it is simply spent: the cut it
            // makes is `min(remaining, countInSeconds)`, so once the
            // countdown is down there the tap can only return the same
            // number — a control that answers with nothing is worse than no
            // control, and the last five seconds are the count-in whether a
            // tap made them so or the transition ran down to them.
            //
            // hidden(), not removed: the escapes must not jump up under the
            // thumb. (Precedent: "Start hold" during the side-switch pause
            // and during its own count-in.)
            Group {
                if paused || countingIn {
                    PrimaryButton(title: String(localized: "I'm ready"), action: { }).hidden()
                } else {
                    PrimaryButton(title: String(localized: "I'm ready"), action: onStart)
                        .accessibilityIdentifier("get-ready-start")
                }
            }
            // 12 → 20 (UX review 05.09.2026). "I'm ready" is the tap of every
            // transition, taken on the way down to the mat; 12 pt under it
            // stands a button of the same full width and the same 56 pt that
            // ends the whole block, and it fires on contact. That is the
            // geometry `SkipConfirmation` was written for — at a LARGER gap
            // (18 pt, under the button that logs a set) — so until the block
            // escape gets its question too, the gap at least matches the one
            // the guarded pair already keeps.
            .padding(.bottom, 20)

            BlockSkipButton(title: block.skipTitle,
                            identifier: block.skipIdentifier,
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }
}

struct WarmupMoveScreen: View {
    let move: WarmupMove
    /// Which half of a split move is running (§41.12). A move with no halfway
    /// boundary has one stage and shows no line at all.
    let stage: Warmup.Stage
    let remaining: Int
    let index: Int
    let count: Int
    let paused: Bool
    let onTechnique: () -> Void
    let onPauseToggle: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            BlockPositionName(name: move.name)
            if let halves = move.halves {
                SplitStageLine(stage, halves: halves).padding(.top, 6)
            }

            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: "warmup-countdown", paused: paused)
                .padding(.top, 20)

            BlockPauseButton(paused: paused, action: onPauseToggle)
                .padding(.top, 12)

            BlockDots(count: count, current: index)
                .padding(.top, 22)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            BlockSkipButton(title: GuidedBlock.warmup.skipTitle,
                            identifier: GuidedBlock.warmup.skipIdentifier,
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }
}

struct CooldownPositionScreen: View {
    let position: CooldownPosition
    let stage: Cooldown.Stage
    let remaining: Int
    let index: Int
    let count: Int
    let paused: Bool
    let onTechnique: () -> Void
    let onPauseToggle: () -> Void
    let onSkipPosition: () -> Void
    let onSkipBlock: () -> Void

    var body: some View {
        BlockLayout {
            BlockPositionName(name: position.name)
            if position.perSide {
                SplitStageLine(stage).padding(.top, 6)
            }

            // Freezes the countdown mid-pause too: the switch waits.
            TechniqueButton(action: onTechnique)
                .padding(.top, 10)

            CountdownNumber(value: remaining, identifier: "cooldown-countdown", paused: paused)
                .padding(.top, 20)

            BlockPauseButton(paused: paused, action: onPauseToggle)
                .padding(.top, 12)

            BlockDots(count: count, current: index)
                .padding(.top, 22)

            PositionSkipButton(action: onSkipPosition)
                .padding(.top, 8)
        } footer: {
            BlockSkipButton(title: GuidedBlock.cooldown.skipTitle,
                            identifier: GuidedBlock.cooldown.skipIdentifier,
                            action: onSkipBlock)
                .padding(.bottom, 20)
        }
    }
}

/// Which of the two guided blocks a screen belongs to — and the words and
/// name of its block-level escape.
///
/// ONE definition per action, for the three places the escape appears: the
/// offer screen, the transition's footer and the running position's footer.
/// UX review 05.09.2026 found two English keys for one button — "Skip the
/// warm-up" on the offer against "Skip warm-up" in the footers — which five
/// languages had already collapsed into the same sentence typed twice, while
/// Spanish had drifted apart ("Omitir el calentamiento" against "Omitir
/// calentamiento"). A second key is a second thing to keep in step; the
/// keeping-in-step is what failed.
enum GuidedBlock {
    case warmup, cooldown

    var skipTitle: String {
        switch self {
        case .warmup:
            return String(localized: "Skip warm-up")
        case .cooldown:
            return String(localized: "cooldown.skip", defaultValue: "Skip cool-down")
        }
    }

    /// Stated rather than left to `BlockSkipButton`'s `identifier ?? title`:
    /// the title is localized, so an omitted identifier moves with the
    /// display language.
    var skipIdentifier: String {
        switch self {
        case .warmup:   return "skip-warmup"
        case .cooldown: return "skip-cooldown"
        }
    }
}

/// The line a split position shows over its countdown.
///
/// ONE view, not a copy per block: the two stage machines differ (`.single`
/// against `.move`), the three lines they show do not, and §41.12 — which gave
/// the warm-up the cool-down's counted switch — would otherwise have written
/// the second copy that drifts. Each block hands over its own stage; the
/// mapping lives here, so a new stage on either side is a compile error here
/// rather than a screen that quietly says nothing.
///
/// The words come from what is switched, and only the words do: sides and
/// directions run the same 15 + 5 + 15. Telling someone to switch SIDES on a
/// circle they are about to reverse would be a lie of the same size as the
/// silence §41.12 replaced.
private struct SplitStageLine: View {
    private enum Phase { case beforeTheSwitch, switching, secondHalf }
    private let phase: Phase
    private let halves: WarmupHalves

    init(_ stage: Warmup.Stage, halves: WarmupHalves) {
        self.halves = halves
        switch stage {
        case .switchPause: phase = .switching
        case .secondHalf:  phase = .secondHalf
        case .getReady, .move, .firstHalf: phase = .beforeTheSwitch
        }
    }

    /// The cool-down splits by side and by nothing else — its nine positions
    /// are stretches, and no stretch of the pool reverses.
    init(_ stage: Cooldown.Stage) {
        self.halves = .sides
        switch stage {
        case .switchPause: phase = .switching
        case .secondSide:  phase = .secondHalf
        case .getReady, .single, .firstSide: phase = .beforeTheSwitch
        }
    }

    private var words: SplitStageWords { SplitStageWords(halves: halves) }

    var body: some View {
        switch phase {
        // The switch is a TIER LOUDER than the second half that follows it,
        // and the work screen already draws this exact distinction: the pause
        // is the one moment a split position asks for something new, so it
        // takes the 17 pt accent its own count-in and side switch take under
        // the big number (`WorkoutFlowView.loadCaptionEmphasis`), while
        // "second side" — a state, not an instruction — keeps 14. From the
        // 1.5-2 m this screen is read at, 17 pt is no more legible than 14
        // (both under the 5' a letter needs) and what carries is the colour;
        // the size is what puts the line where it belongs in the hierarchy
        // (UX review, 05.09.2026).
        case .switching:       accent(words.switching, size: 17)
        case .secondHalf:      accent(words.secondHalf, size: 14)
        case .beforeTheSwitch: quiet(words.everyHalf)
        }
    }

    private func accent(_ text: String, size: CGFloat) -> some View {
        Text(text)
            .dredfitFont(size, weight: .semibold)
            .foregroundStyle(Theme.accentText)
    }

    private func quiet(_ text: String) -> some View {
        Text(text)
            .dredfitFont(14)
            .foregroundStyle(Theme.ink2)
    }
}

/// What a split position says at each of its three moments, given what the
/// person switches.
///
/// Its own type, and internal rather than private, for one reason: "Switch
/// sides" over a circle about to be reversed is the defect this whole
/// distinction exists to prevent, and a test cannot compare a SwiftUI `Text`
/// (it is not reliably equatable — the flake that rule came from). Words that
/// nothing can ask about are words nothing can pin.
struct SplitStageWords {
    let halves: WarmupHalves

    var switching: String {
        switch halves {
        case .sides:      return String(localized: "Switch sides")
        case .directions: return String(localized: "warmup.switchDirection",
                                        defaultValue: "Switch direction")
        }
    }

    var secondHalf: String {
        switch halves {
        case .sides:      return String(localized: "second side")
        case .directions: return String(localized: "warmup.otherWay",
                                        defaultValue: "the other way")
        }
    }

    var everyHalf: String {
        switch halves {
        // A `cooldown.` key read by the warm-up too: the key is older than the
        // warm-up's switch, the STRING is the same 15 s per side in both
        // blocks, and renaming it would cost six translations and the whole
        // screenshot set to say exactly what it says now.
        case .sides:      return String(localized: "cooldown.perSide",
                                        defaultValue: "15 s per side")
        case .directions: return String(localized: "warmup.perDirection",
                                        defaultValue: "15 s each way")
        }
    }
}

/// Content centred in whatever room is left, escapes pinned under it.
///
/// It scrolls rather than clips: at the largest accessibility sizes a
/// three-line position name plus the countdown outgrows the screen, and the
/// escapes must never be pushed out from under the user. Below that size
/// nothing scrolls and nothing moved.
private struct BlockLayout<Content: View, Footer: View>: View {
    @ViewBuilder var content: Content
    @ViewBuilder var footer: Footer

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        content
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
            footer
        }
    }
}

/// The long es/pt-BR names wrap to three lines at the largest Dynamic Type
/// sizes; let them.
private struct BlockPositionName: View {
    let name: String

    var body: some View {
        Text(name)
            .dredfitFont(23, weight: .bold)
            // The token, not the inherited `.primary`: the biggest word on
            // three screens of the flow was the one drawn in the system label
            // colour, so in the dark scheme it was a shade the palette never
            // measured against `bg` (UX review, 05.09.2026).
            .foregroundStyle(Theme.ink)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)
            .fixedSize(horizontal: false, vertical: true)
    }
}
