//
//  Technique sheet: name, variation tag, the step below, 3 steps, 2 common
//  mistakes.
//
//  It is addressed by (pattern, variation) rather than by a planned exercise,
//  because §40.4 gave it a second caller: the PROBE offers one set of the NEXT
//  variation, and the person has to be able to read how that movement is done
//  before doing it. An exercise-shaped sheet could not show a movement that is
//  not in the plan.
//
//  That same property is why the easier-variation handle moved here off the
//  plan (R30). A control that swaps the movement for the one below it needs a
//  screen that can show a movement which is not in the plan — this is the only
//  one — and the sheet already owns the ladder as a concept: the tag above the
//  block says "variation 3 of 7", so the rung under it is a fact the screen was
//  already stating, not a suggestion it starts making.
//
//  It is offered only where the sheet describes the UPCOMING workout, which is
//  Today (owner, 01.09.2026). The same sheet opens inside a running session and
//  there it carries nothing: the session is snapshotted at Start, so a switch
//  taken mid-workout moves the state under a plan already in flight and the
//  rating lands on the pair — measured, squat v6 3×15 switched to v5 and rated
//  "on plan" writes 15 into the journal of v5 where the person had shown 4, and
//  a probe passed later in the same session promotes past the rung they had
//  just chosen. `planned` is what keeps the two states from moving at once.
//

import SwiftUI
import DredfitCore

/// What a technique sheet is about. Identifiable so it can drive `.sheet(item:)`.
struct TechniqueTarget: Identifiable, Equatable {
    let pattern: Pattern
    let variation: Int
    let unit: LoadUnit

    var id: String { "\(pattern.rawValue)-\(variation)" }

    init(pattern: Pattern, variation: Int, unit: LoadUnit) {
        self.pattern = pattern
        self.variation = variation
        self.unit = unit
    }

    init(_ exercise: SessionExercise) {
        self.init(pattern: exercise.pattern, variation: exercise.variation, unit: exercise.unit)
    }

    /// The movement a probe offers — a different variation of the same
    /// pattern, and possibly in a different unit (§40.1, `pull_bar` 2→3).
    init(probe: SessionProbe, of pattern: Pattern) {
        self.init(pattern: pattern, variation: probe.variation, unit: probe.unit)
    }
}

struct TechniqueSheet: View {
    let target: TechniqueTarget
    /// True on the ONE screen where a step down can be taken safely: the plan
    /// of the workout that has not started. False everywhere else — inside a
    /// running session, where the state must not move under the plan in flight
    /// (see the file header), and on the next-workout preview, which looks at a
    /// session rather than deciding about one.
    var planned: Bool = false
    /// The step the person has asked for and not yet confirmed. Held rather
    /// than recomputed when the alert fires, for the reason `SkipConfirmation`
    /// holds its action: the tap that raised the question is the tap that runs,
    /// so a question about one movement cannot be answered onto another.
    @State private var pendingStepDown: AppStore.EasierStep?
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The rung the sheet is describing. Read from the STATE when the movement
    /// is a planned one, so the tap on "Switch" redraws this sheet onto the
    /// movement it just chose — technique, mistakes, "in life" and the tag all
    /// follow. Re-presenting the sheet with a new `target` would do the same
    /// thing visibly worse: `.sheet(item:)` sees a new `id` and plays a
    /// dismiss-and-present, so the screen blinks.
    ///
    /// Frozen to the target otherwise: a probe's sheet describes the probe's
    /// movement, and the state knows nothing about it.
    private var shownVariation: Int {
        planned ? store.engineState.position(target.pattern).variation : target.variation
    }

    private var variation: ExerciseVariation {
        Library.at(target.pattern, shownVariation)
    }

    /// Follows `shownVariation` for the same reason: on `pull_bar` the rungs
    /// are not all in the same unit (§40.1), so a switch can change what the
    /// tag's range should say.
    private var unit: LoadUnit {
        planned ? Library.unit(target.pattern, shownVariation) : target.unit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(variation.name)
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        .padding(.top, 30)
                        // What the step-down block promises is that this line
                        // becomes the movement it named, so a test has to be
                        // able to read it without going by a catalog string.
                        .accessibilityIdentifier("technique-title")

                    Text(variationTag)
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        .padding(.top, 10)

                    // Under the tag and above the technique, because the tag
                    // has just said which rung this is and the rung below it
                    // finishes that sentence. In the footer it would have to be
                    // scrolled to, and a handle nobody reaches is the state
                    // this block was moved here to leave behind.
                    if planned, let step = store.easierStep(target.pattern) {
                        stepDown(step)
                            .padding(.top, 18)
                    }

                    Kicker(text: String(localized: "Technique"))
                        .padding(.top, 28)
                    ForEach(Array(variation.steps.enumerated()), id: \.offset) { index, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(index + 1)")
                                .dredfitFont(13, weight: .semibold)
                                .foregroundStyle(Theme.bg)
                                .frame(width: 26, height: 26)
                                .background(Theme.ink, in: Circle())
                            Text(step)
                                .dredfitFont(16.5)
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 13)
                    }

                    Kicker(text: String(localized: "Common mistakes"))
                        .padding(.top, 18)
                    ForEach(Array(variation.mistakes.enumerated()), id: \.offset) { _, mistake in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "xmark")
                                .dredfitFont(11, weight: .bold)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 26, height: 26)
                                .background(Theme.accentSoft, in: Circle())
                                .accessibilityHidden(true)   // a bullet, not content
                            Text(mistake)
                                .dredfitFont(16.5)
                                .lineSpacing(4)
                                .foregroundStyle(Theme.ink2)
                        }
                        .padding(.vertical, 13)
                    }

                    Kicker(text: String(localized: "life.kicker", defaultValue: "In life"))
                        .padding(.top, 18)
                    Text(LifeBenefit.text(for: target.pattern, variation: shownVariation))
                        .dredfitFont(16.5)
                        .lineSpacing(4)
                        .foregroundStyle(Theme.ink2)
                        .padding(.vertical, 11)
                        .accessibilityIdentifier("technique-life")
                }
                .padding(.horizontal, 24)
            }

            // Four sheets in this app close on a button reading "Got it", and
            // a workout can have two of them stacked. Each names its own, the
            // way `how-it-works-done` and `milestone-done` already do.
            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .accessibilityIdentifier("technique-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        // Spends the one line on Today that says this door exists — from any
        // of the three doors, because the sentence is about the door and not
        // about the plan row that happens to be the widest of them.
        .task { store.markTechniqueOpened() }
        // The same guard the four skips carry, and for the same reason: this
        // plan has no undo (owner, 01.09.2026). An ALERT, like them — iOS 26
        // draws a confirmationDialog as an anchored popover, which suppresses
        // its own cancel and treats the stray tap as an answer.
        .alert(pendingStepDown.map(confirmTitle) ?? "",
               isPresented: Binding(get: { pendingStepDown != nil },
                                    set: { if !$0 { pendingStepDown = nil } }),
               presenting: pendingStepDown) { _ in
            Button(String(localized: "Keep going"), role: .cancel) { }
            // The verb of the control that raised it, and no `.destructive`
            // role: a movement that goes down a rung is an ordinary answer to
            // an ordinary day, not damage. Same position the skips took.
            Button(String(localized: "technique.stepDown.switch", defaultValue: "Switch")) {
                store.makeEasier(target.pattern)
            }
        } message: { _ in
            Text(verbatim: stepDownConfirmBody)
        }
    }

    /// Names the movement, so the question cannot be answered without reading
    /// which one it is about.
    private func confirmTitle(_ step: AppStore.EasierStep) -> String {
        String(localized: "technique.stepDown.confirmTitle",
               defaultValue: "Switch to \(step.name)?")
    }

    /// What is actually spent. The way back up is the probe (§40.4), and the
    /// probe is offered only once the dose has climbed to the ceiling of the
    /// variation again — several appearances, never a tap. A message that said
    /// "you can always go back" would be the lie this alert exists to prevent.
    private var stepDownConfirmBody: String {
        String(localized: "technique.stepDown.confirmBody", defaultValue: """
            This movement drops to the variation below. \
            The way back up is a probe, which the plan offers once the dose \
            is at the ceiling again.
            """)
    }

    // MARK: - One step below

    /// The handle, in the only place it can carry more than a name (R30).
    ///
    /// The block is NOT a button and the capsule is: a step down is one-way —
    /// the way back up is a probe, and a probe is several appearances away
    /// (§40.4) — so the target of the tap is the word, never the card around
    /// it. A stray tap on the description or a drag that starts on it must not
    /// rewrite the plan.
    ///
    /// And the capsule ASKS before it acts (owner, 01.09.2026, reversing this
    /// wave's own "the redraw is feedback enough"). It is the argument the four
    /// skips already settled: the plan has no undo, the way back up is measured
    /// in appearances rather than in taps, and a guard against a stray thumb
    /// has to stand in FRONT of the state change. Same alert, same two answers,
    /// same words.
    @ViewBuilder
    private func stepDown(_ step: AppStore.EasierStep) -> some View {
        let description = VStack(alignment: .leading, spacing: 4) {
            // ink2, not ink3: this kicker labels the one thing on the sheet
            // that DOES something, and 12 pt semibold is small text — 4.5:1 or
            // it does not ship (R16–R21).
            Kicker(text: String(localized: "technique.stepDown.kicker",
                                defaultValue: "One step below"),
                   color: Theme.ink2)
            Text(step.name)
                .dredfitFont(15.5, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(doseLine(step))
                .dredfitFont(13)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // One sentence, not four fragments read one swipe at a time. The
        // capsule keeps its own element — `children: .ignore` here rather than
        // on the whole block, which would swallow the only control on it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: a11yDescription(step)))

        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    description
                    switchButton(step)
                }
            } else {
                HStack(alignment: .center, spacing: 14) {
                    description
                    switchButton(step)
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(Theme.hairline, lineWidth: 1.5))
    }

    private func switchButton(_ step: AppStore.EasierStep) -> some View {
        Button {
            pendingStepDown = step
        } label: {
            Text(String(localized: "technique.stepDown.switch", defaultValue: "Switch"))
                .dredfitFont(14.5, weight: .medium)
                .foregroundStyle(Theme.accentText)
                .padding(.horizontal, 18)
                .frame(minHeight: 44)
                .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityIdentifier("technique-step-down")
        // The movement goes INSIDE the label: VoiceOver reads a control on its
        // own as often as in its context, and "Switch" alone answers "to what?"
        // with nothing.
        .accessibilityLabel(Text(String(localized: "technique.stepDown.a11ySwitch",
                                        defaultValue: "Switch to \(step.name)")))
    }

    /// "3×20 sec · holds instead of reps". The unit note is the half of the
    /// step a name and a number cannot carry: `pull_bar` 3 → 2 drops from
    /// negatives to a hang, and the seconds beside it read as a smaller number
    /// rather than as a different kind of work (§40.1).
    private func doseLine(_ step: AppStore.EasierStep) -> String {
        guard step.unitChanged else { return step.dose }
        let note = unit == .reps
            ? String(localized: "technique.stepDown.unitToHold",
                     defaultValue: "holds instead of reps")
            : String(localized: "technique.stepDown.unitToReps",
                     defaultValue: "reps instead of holds")
        return "\(step.dose) · \(note)"
    }

    private func a11yDescription(_ step: AppStore.EasierStep) -> String {
        let kicker = String(localized: "technique.stepDown.kicker",
                            defaultValue: "One step below")
        return "\(kicker): \(step.name), \(doseLine(step))"
    }

    /// "variation 3 of 7 · pull · 4–15 reps". The total comes from the library
    /// — the ladders are four to seven rungs long now (§40.1) — and the range
    /// is the grid the whole library shares (§40.2), not a per-tier one.
    private var variationTag: String {
        let range = unit == .reps
            ? String(localized: "4–15 reps")
            : String(localized: "15–45 s")
        let total = Library.count(target.pattern)
        // The catalog value verbatim, NEVER lowercased. German capitalises
        // every noun as grammar, not as style, so `.lowercased()` turned the
        // catalog's correct "Horizontales Drücken" into a misspelling —
        // harmless in the other six languages and wrong in the seventh
        // (App Store frame review, de/s9 against de/s8, which prints the same
        // pattern correctly). The catalog is the terminology fixed by the
        // glossary and is right in every language by definition; no
        // locale-aware lowering can help German here.
        let movement = target.pattern.displayName
        return String(localized: "variation \(shownVariation) of \(total) · \(movement) · \(range)")
    }
}
