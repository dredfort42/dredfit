//
//  A completed workout viewed from the calendar.
//

import SwiftUI
import DredfitCore

struct HistorySheet: View {
    let record: WorkoutRecord
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// The neighbour walked to with the chevrons, if any. The sheet is opened
    /// with ONE record from three different screens, and none of them can be
    /// asked to hand over the journal around it — so the walk is state here,
    /// and every call site keeps the initialiser it always had (UX review
    /// 05.09.2026, finding 34).
    @State private var walked: WorkoutRecord?
    @State private var changeRatingShown = false

    /// The record actually being read.
    var shown: WorkoutRecord { walked ?? record }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Kicker(text: shown.date.screenDateText)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Workout \(shown.sessionNumber)")
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        // Named, not inherited: `.primary` is pure white in
                        // dark and pure black in light, and both stand outside
                        // the palette the rest of this sheet is drawn in
                        // (UX review 05.09.2026).
                        .foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                    neighbourControls
                }
                Text(resultCaption)
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if let minutes = clockMinutes {
                    Text("Took \(minutes) min, pauses included")
                        .dredfitFont(13.5)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                        .accessibilityIdentifier("history-duration")
                }
            }
            .padding(.top, 26)
            .padding(.horizontal, 24)

            if let exercises = shown.exercises, !exercises.isEmpty {
                List(exercises) { ex in
                    row(ex)
                        .padding(.vertical, 3)
                        .listRowSeparatorTint(Theme.hairline)
                        .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                // Not every record carries an exercise snapshot.
                Spacer()
                Text("No details saved for this workout.")
                    .dredfitFont(15)
                    .foregroundStyle(Theme.ink2)
                    .frame(maxWidth: .infinity)
                Spacer()
            }

            // A record written before v3 carries a number on a scale that no
            // longer exists, so the line is simply absent for it rather than
            // stated in the wrong unit.
            if let steps = shown.totalProgressAfter {
                HStack {
                    Text("Total steps after: \(steps)")
                        .dredfitFont(13.5)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            if canChangeRating {
                Button { changeRatingShown = true } label: {
                    Text(String(localized: "history.changeRating",
                                defaultValue: "Change rating"))
                        .pairedSecondaryLabel()
                }
                .accessibilityIdentifier("history-change-rating")
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            }

            // Its own name — see TechniqueSheet: four sheets close on the same
            // two words.
            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .accessibilityIdentifier("history-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        // `.large` alone, like the app's four other sheets: SwiftUI opens on
        // the SMALLEST detent, so medium meant a record opened showing two of
        // its six movements. It used to fit three — this wave's own additions
        // to the screen, the "Took N min" line in the header and the "Change
        // rating" button in the footer, took the third (nightly 06.09.2026).
        // A record is opened to be read, and a scroll to reach the third row
        // is not reading.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
        .alert(String(localized: "history.changeRating.title",
                      defaultValue: "Change the rating?"),
               isPresented: $changeRatingShown) {
            changeRatingActions
        } message: {
            Text(String(localized: "history.changeRating.body",
                        defaultValue: "The next plan is rebuilt from where this workout left it, exactly as the other answer would have."))
        }
    }

    /// The movement, what it cost, and — under both, at full width — what its
    /// last set was when that set was not a working one.
    ///
    /// The probe line goes UNDER rather than into the column on the right: the
    /// sentence is longer than that column, and the load has to keep its place.
    /// The same shape the plan gives its own probe line.
    private func row(_ ex: SessionExercise) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline) {
                Text(currentName(ex))
                    .dredfitFont(16, weight: .medium)
                    .foregroundStyle(Theme.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(ex.display)
                        .dredfitFont(15)
                        .monospacedDigit()
                        .foregroundStyle(Theme.ink2)
                    // Only a record written before the wave can carry this.
                    // History says what happened, and what happened is that
                    // the person reported it.
                    if shown.discomfort?.contains(ex.pattern) == true {
                        Text("hurt")
                            .dredfitFont(12.5)
                            .foregroundStyle(Theme.accentText)
                    } else if shown.skipped?.contains(ex.pattern) == true {
                        Text(Self.skipWord(ex, in: shown))
                            .dredfitFont(12.5)
                            .foregroundStyle(Theme.ink2)
                            // The one line on this row without a name of its
                            // own, while every neighbour carries one — so a
                            // test could only count anonymous labels, and
                            // counting them measured what fit on screen rather
                            // than what happened (nightly 06.09.2026).
                            .accessibilityIdentifier(
                                "history-skipword-\(ex.pattern.rawValue)")
                    } else if let fact = Self.setFacts(ex, in: shown) {
                        SetFactsLabel(values: fact.values,
                                      reported: fact.reported, size: 12.5)
                    }
                }
            }
            if let probe = Self.probeLine(ex, in: shown) {
                Text(probe)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-probe-\(ex.pattern.rawValue)")
            }
            if let dropped = Self.setsSkippedLine(ex, in: shown) {
                Text(dropped)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-setsskipped-\(ex.pattern.rawValue)")
            }
            // The one cause of a drop that lands on a session's point without
            // being that session's doing: the athlete moved the movement down
            // themselves, and two weeks later the chart shows a step they no
            // longer remember taking (UX review 05.09.2026, finding 64).
            if easedByHand.contains(ex.pattern) {
                Text(String(localized: "history.easedByHand",
                            defaultValue: "You chose an easier variation before this workout"))
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-easedbyhand-\(ex.pattern.rawValue)")
            }
            if let after = Self.afterLine(ex, in: shown) {
                Text(after)
                    .dredfitFont(12.5)
                    .foregroundStyle(Theme.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("history-after-\(ex.pattern.rawValue)")
            }
        }
    }

    /// Read once per sheet rather than per row: the answer is the same for
    /// every movement, and it is empty for every record but the last.
    private var easedByHand: [Pattern] { store.easedByHand(in: shown) }

    /// The facts worth printing for one exercise, or nil when it simply ran
    /// to plan. The sets lead: a near miss that stood down rather than claim
    /// the plan hands the engine no number at all, and the record of what was
    /// actually done must survive that. A record written before a fact
    /// belonged to its own set keeps one number for the whole exercise —
    /// that number was in force for every set of it, which is what a single
    /// value says.
    ///
    /// Cut to the sets that actually RAN. `SetFacts.allSets` walks the plan,
    /// carrying the last reported number forward over the sets ahead — which
    /// is right on the work screen, where those sets are still coming, and a
    /// claim in a record where they never happened: a hold stopped after
    /// three sets of five read "40 · 40 · 38 · 38 · 38" in the one place
    /// anybody checks whether the app is telling the truth (UX review
    /// 05.09.2026, finding 33). The prefix is applied here rather than inside
    /// `allSets`, which the work and rating screens share for the live case.
    ///
    /// And never cut below what was actually RECORDED. `setsSkipped` counts
    /// the sets that did not run; it does not say WHERE they were, and only
    /// the settlement of an abandoned workout drops a trailing block. A skip
    /// taken in the MIDDLE of a movement (`skipSet`) increments the same
    /// counter and then goes on to the next set, so cutting to `performed`
    /// threw away the tail that did run: plan 3×10, set 2 skipped, set 3
    /// reported as 7 printed "3 × 10" — the untouched plan — while the engine
    /// had already been handed the shortfall and the next plan came down for
    /// it (review 06.09.2026). Taking the longer of the two keeps the reported
    /// number on screen, and the "Sets skipped: N of M" line under the row
    /// says one of the printed sets is not one that ran. Without a mid-skip
    /// `known <= performed` and finding 33's cut is exactly as it was.
    ///
    /// Static and taking the record for the same reason `probeLine` is: a rule
    /// written as a private member of a SwiftUI view is a rule no unit test
    /// can reach.
    static func setFacts(_ ex: SessionExercise,
                         in record: WorkoutRecord) -> (values: [Int], reported: Int)? {
        let reported = record.actuals?[ex.pattern]
        let values: [Int]
        if let facts = record.setActuals, let known = facts[ex.pattern]?.count {
            let performed = max(ex.sets - setsSkipped(ex, in: record), 0)
            values = Array(SetFacts.allSets(facts, ex).prefix(max(performed, known)))
        } else if let reported {
            values = [reported]
        } else {
            return nil
        }
        guard let first = values.first,
              SetFacts.differs(values, from: ex) else { return nil }
        return (values, reported ?? first)
    }

    /// What the last set of this exercise was, when it was not a working set.
    ///
    /// The plan carried the probe all along — `SessionExercise.probe` is in the
    /// record's own CodingKeys — and this screen printed nothing about it, so a
    /// session of "2 × 15 plus a probe" read in history exactly like a session
    /// of two sets. What it could not say until now is the OUTCOME, and half of
    /// that is still an inference rather than a fact: the number comes from
    /// `record.probes`, which only exists from this wave on.
    ///
    /// The verdict does not re-implement §40.4. It is read off what actually
    /// happened — the position the session ended on, against the variation the
    /// probe offered — because a second copy of the pass rule in the app is a
    /// copy that can disagree with the engine.
    ///
    /// A missing number is deliberately NOT read as "skipped". A record written
    /// before this wave has no numbers either, and the two are indistinguishable
    /// from the file; "not this time" is true of both, and it is the sentence
    /// the work screen already gives an unresolved probe.
    /// Static, and taking the record rather than reading `self`, for the one
    /// reason the two rules named at the bottom of `ProbeChannelTests` are NOT
    /// covered: a policy written as a `private` member of a SwiftUI view is a
    /// policy no unit test can reach. This one is a pure function of a record
    /// and an exercise, so it is written as one.
    static func probeLine(_ ex: SessionExercise, in record: WorkoutRecord) -> String? {
        guard let probe = ex.probe,
              let after = record.positionsAfter?[ex.pattern] else { return nil }
        let name = (1...Library.count(ex.pattern)).contains(probe.variation)
            ? Library.name(ex.pattern, probe.variation)
            : probe.name
        let landed = after.variation >= probe.variation
        guard let reported = record.probes?[ex.pattern] else {
            return landed
                ? String(localized: "history.probePassedPlain",
                         defaultValue: "Probe: \(name) — passed")
                : String(localized: "history.probeUnresolved",
                         defaultValue: "Probe: \(name) — not this time")
        }
        // The probe's own unit, which is not always the exercise's (§40.1).
        let did = SessionProbe(variation: probe.variation, name: name, unit: probe.unit,
                               load: reported, perSide: probe.perSide).display
        return landed
            ? String(localized: "history.probePassed",
                     defaultValue: "Probe: \(name) · \(did) — passed")
            : String(localized: "history.probeShort",
                     defaultValue: "Probe: \(name) · \(did) — not this time")
    }

    /// How much of a movement's plan was dropped mid-workout, when any was.
    ///
    /// The number reached the journal and was read by nobody: the engine turns
    /// it into a cut, so the NEXT plan is lower and the point on the chart
    /// falls even under "on plan" — and the history sheet, the screen opened
    /// to find out why, showed a plan carried out in full (UX review
    /// 05.09.2026, finding 33).
    ///
    /// "N of M" like the rating screen's own row, and for its reason: it says
    /// the loss and the size of the movement in one figure, with no plural to
    /// inflect in any of the seven languages.
    ///
    /// Static and taking the record for the same reason `probeLine` is: a rule
    /// written as a private member of a SwiftUI view is a rule no unit test
    /// can reach.
    static func setsSkippedLine(_ ex: SessionExercise, in record: WorkoutRecord) -> String? {
        let lost = setsSkipped(ex, in: record)
        guard lost > 0 else { return nil }
        return String(localized: "history.setsSkipped",
                      defaultValue: "Sets skipped: \(lost) of \(ex.sets)")
    }

    /// Sets dropped from a movement that WAS trained. A movement nobody
    /// reached is skipped whole, and the row already says so on its right —
    /// the same exclusion the rating screen's `trainedShort` makes, so the two
    /// screens cannot count one interruption differently.
    static func setsSkipped(_ ex: SessionExercise, in record: WorkoutRecord) -> Int {
        guard record.skipped?.contains(ex.pattern) != true else { return 0 }
        return max(record.setsSkipped?[ex.pattern] ?? 0, 0)
    }

    /// What a movement that was not performed is called.
    ///
    /// The movement a workout was cut short ON is inside `skipped` like any
    /// other, and calling an effort that was started and left half-done
    /// "skipped" is exactly what `WorkoutRecord.interrupted` was added to stop
    /// (owner, 05.09.2026 — the difference is worth seeing). The rating screen
    /// already draws it; history is where it is looked up afterwards, and it
    /// was the half of that field nothing read.
    ///
    /// The rating screen's own two words, so the two screens cannot drift and
    /// six translations are not written twice.
    static func skipWord(_ ex: SessionExercise, in record: WorkoutRecord) -> String {
        record.interrupted == ex.pattern
            ? String(localized: "not finished")
            : String(localized: "skipped")
    }

    /// Where the movement stood once the answer had been applied.
    ///
    /// The load on the right of the row is the PLAN — the position as it was
    /// BEFORE the rating landed — so "I said 'on plan' and the push-up became
    /// 3×9" could only be recovered by finding the NEXT workout's record and
    /// reading two sheets against each other (UX review, 05.09.2026). The
    /// answer has been on disk since v3: `positionsAfter` carries all six
    /// coordinates, and this file already read it — once, to judge a probe.
    ///
    /// Silent when the position is the one the row above already prints, which
    /// is most movements of most sessions: a second line restating the first is
    /// how a screen stops being read at all.
    ///
    /// Static and taking the record for the same reason `probeLine` is: a rule
    /// written as a private member of a SwiftUI view is a rule no unit test can
    /// reach.
    static func afterLine(_ ex: SessionExercise, in record: WorkoutRecord) -> String? {
        guard let after = record.positionsAfter?[ex.pattern],
              (1...Library.count(ex.pattern)).contains(after.variation) else { return nil }
        let stood = asPlanned(ex.pattern, after)
        guard after.variation != ex.variation else {
            guard stood.display != ex.display,
                  !onlyMoreSets(stood, than: ex) else { return nil }
            return String(localized: "history.after",
                          defaultValue: "After: \(stood.display)")
        }
        // A movement that changed variation says which one: the dose alone
        // reads like a collapse ("3×15" → "3×4") where it is the grid floor of
        // a harder movement, and the probe line above says a probe passed
        // without ever saying where it landed.
        let name = Library.name(ex.pattern, after.variation)
        return String(localized: "history.afterVariation",
                      defaultValue: "After: \(name) · \(stood.display)")
    }

    /// Whether the one thing separating a position from the plan that ran is
    /// that the plan showed FEWER sets of it.
    ///
    /// The plan's set count is not the position's: §40.4 gives one of the
    /// working sets to the probe, and the pull slot caps the push of the same
    /// session. Both lower what the row prints without moving the position, so
    /// a position standing on MORE sets than the row is the row's own
    /// arithmetic rather than news — and a session where the sets genuinely
    /// grew is indistinguishable from it in a record that keeps only the
    /// position AFTER. Standing on FEWER sets is the descent this line exists
    /// to show, and nothing here catches that.
    private static func onlyMoreSets(_ stood: SessionExercise,
                                     than plan: SessionExercise) -> Bool {
        stood.load == plan.load && stood.sets > plan.sets
            && subSteps(stood) == subSteps(plan)
    }

    /// How many sets carry the higher dose, read back off the per-set doses —
    /// the way the engine's own `withSets` recovers the sub-step from an
    /// exercise it is handed rather than from the position behind it.
    private static func subSteps(_ ex: SessionExercise) -> Int {
        ex.loads?.filter { $0 > ex.load }.count ?? 0
    }

    /// One recorded position stated the way a plan states one.
    ///
    /// Built as a `SessionExercise` rather than spelled out here so the line
    /// under a row is written in the same words as the line on it — the use of
    /// that initialiser from outside the engine that its own doc comment
    /// sanctions — and so the two can be compared at all.
    ///
    /// Two of the six coordinates have to be resolved first. `cut` takes sets
    /// off WITHOUT moving `sets`, so the raw coordinate would read HIGHER than
    /// the plan right after a descent took some away (§36.3); `sub` is what
    /// makes a plan read "9-8-8" instead of "3×8". Both resolve the way
    /// `Engine.fit` resolves them, the top-rung disable included — above it the
    /// next rung belongs to another band, and adding a step there would print a
    /// dose the grid does not have.
    private static func asPlanned(_ pattern: Pattern,
                                  _ position: RecordedPosition) -> SessionExercise {
        let unit = Library.unit(pattern, position.variation)
        let grid = Dose.grid(unit)
        // Bounded by the SCALE, not by the record: `sets` comes back out of the
        // journal clamped only to a million, and this runs in a row body on the
        // main thread — the allocation `SessionExercise.perSetLoads` documents.
        // No position ever had more sets than the scale has bands, so the valid
        // domain never notices.
        let standing = position.sets
            - min(max(position.cut ?? 0, 0), Engine.cutMax(sets: position.sets))
        let sets = min(max(standing, 0), EngineConfig.setsMax)
        let sub = position.dose >= grid.max
            ? 0
            : min(max(position.sub ?? 0, 0), max(sets - 1, 0))
        let loads: [Int]? = sub > 0
            ? (0..<sets).map { $0 < sub ? position.dose + grid.step : position.dose }
            : nil
        return SessionExercise(pattern: pattern,
                               name: Library.name(pattern, position.variation),
                               variation: position.variation, unit: unit,
                               load: position.dose,
                               perSide: Library.sides(pattern, position.variation) == 2,
                               sets: sets, restSetSec: 0, restExerciseSec: 0,
                               loads: loads, probe: nil)
    }

    /// How long the workout occupied, and only while that clock can still be
    /// about the workout.
    ///
    /// Today promises "≈ 26–32 min" before a session, and nothing in the app
    /// let anyone hold that promise to their own sessions: `durationSec` is
    /// written on every workout and read by the Health export alone, which is
    /// off by default (UX review, 05.09.2026).
    ///
    /// It is a wall clock, not a measure of effort — `EnergyEstimate` calls it
    /// "a CEILING, never a source" and clamps it to the plan before pricing
    /// calories, because it also holds backgrounding, a paused hold and, for a
    /// workout resumed inside `workoutResumeWindow`, the whole gap between two
    /// visits. So the line names what it counts, and stands down once the clock
    /// has run past twice the plan: past that the number is about the day
    /// rather than the training, and "took 150 min" is a worse answer than no
    /// answer. A record with no exercise snapshot has no plan to be measured
    /// against and gets no line either.
    private var clockMinutes: Int? {
        guard let seconds = shown.durationSec, seconds > 0,
              let exercises = shown.exercises,
              let plan = EnergyEstimate.segments(exercises: exercises,
                                                 skipped: notPerformed,
                                                 warmupSec: shown.warmupSec,
                                                 cooldownSec: shown.cooldownSec),
              plan.isPlausible,
              Double(seconds) <= 2 * plan.totalSec else { return nil }
        return max(1, Int((Double(seconds) / 60).rounded()))
    }

    /// Skips and — in a record written by an older build — pain reports: both
    /// were "not performed", and the plan this clock is held against must not
    /// charge minutes to movements that never ran. The same union the Health
    /// export reads a record with.
    private var notPerformed: Set<Pattern> {
        (shown.skipped ?? []).union(shown.discomfort ?? [])
    }

    /// The snapshot froze `name` in the language active when the session was
    /// generated; resolve it again so history follows a language switch.
    ///
    /// The stored name stays the fallback for a variation the library no
    /// longer has — and, above all, for a record written before v3, which
    /// decodes with `variation == 0`: the old tier numbers point at different
    /// movements now, so those lines keep the names they were written with.
    private func currentName(_ ex: SessionExercise) -> String {
        guard (1...Library.count(ex.pattern)).contains(ex.variation) else { return ex.name }
        return Library.name(ex.pattern, ex.variation)
    }

    /// The answer, and — while the app can still say so honestly — which
    /// movements it actually eased.
    ///
    /// An unnamed "tough" moves ONE movement of six until the third in a row
    /// (`EngineConfig.lessRunToGlobal`), so "the next one will be easier" was a
    /// promise about the whole workout that was kept for a sixth of it, and
    /// the person who checked it the next morning found the other five
    /// carrying the same numbers (UX review 05.09.2026, finding 27).
    ///
    /// The list comes from the stamp taken when the rating was applied, not
    /// from the journal: between two entries the silent decay and an accepted
    /// comeback move positions too, so a difference of two records would
    /// credit this workout with a descent that was not its doing. An older
    /// record has no stamp, says nothing, and keeps the general sentence —
    /// which is true of every "tough", just less useful.
    private var resultCaption: String {
        switch shown.result {
        case .less:
            let eased = store.easedByRating(in: shown).map(\.displayName)
            guard !eased.isEmpty else {
                return String(localized: "Rating: tough — the next one will be easier")
            }
            // The names are capitalised and one of them carries a middle dot,
            // so they follow a colon rather than sit inside the sentence. The
            // list is built first: a locale joins two names its own way, and
            // that is the formatter's job, not the sentence's.
            let named = eased.formatted(.list(type: .and))
            return String(localized: "history.toughEased",
                          defaultValue: "Rating: tough — the next one eases off: \(named)")
        case .plan: return String(localized: "Rating: on plan — the next one adds a step to the movements that have room for one")
        case .more: return String(localized: "Rating: easy — progressing as fast as each movement allows")
        }
    }
}

// MARK: - Walking the journal (UX review 05.09.2026, finding 34)

/// An extension rather than more of the struct above: `type_body_length` is a
/// CI error at 600 lines and a file split is the wrong cure for it.
extension HistorySheet {

    /// The entries either side of the one being read. The journal is
    /// oldest-first, so "previous" is the workout before this one in time.
    ///
    /// Read from the store rather than passed in: the sheet is raised from
    /// three screens — the calendar grid, the chart and Today — and a
    /// neighbour argument would have to be computed, and kept honest, at each
    /// of them.
    var neighbours: (previous: WorkoutRecord?, next: WorkoutRecord?) {
        let all = store.records
        guard let here = all.firstIndex(where: { $0.id == shown.id }) else { return (nil, nil) }
        return (here > all.startIndex ? all[here - 1] : nil,
                here + 1 < all.endIndex ? all[here + 1] : nil)
    }

    /// "‹ ›", in the 44 pt targets and the ink2 the calendar's month switcher
    /// already uses — the same gesture, the same size, the same tone.
    ///
    /// Comparing two workouts is the whole reason this sheet is opened, and it
    /// used to cost closing the sheet, paging the calendar back to the right
    /// month and hunting for a black circle; from the chart, where the
    /// question is actually asked, there was no route at all.
    @ViewBuilder
    var neighbourControls: some View {
        HStack(spacing: 4) {
            stepButton(to: neighbours.previous, glyph: "chevron.left",
                       label: String(localized: "history.earlier",
                                     defaultValue: "Earlier workout"),
                       identifier: "history-earlier")
            stepButton(to: neighbours.next, glyph: "chevron.right",
                       label: String(localized: "history.later",
                                     defaultValue: "Later workout"),
                       identifier: "history-later")
        }
        .dredfitFont(16, weight: .medium)
        .foregroundStyle(Theme.ink2)
    }

    /// Dimmed rather than removed at the ends of the journal: the header must
    /// not change shape as the walk reaches the first or the last workout.
    /// Hidden from VoiceOver there, because a disabled control it can still
    /// land on says nothing about why it does nothing.
    private func stepButton(to target: WorkoutRecord?, glyph: String,
                            label: String, identifier: String) -> some View {
        Button {
            guard let target else { return }
            walked = target
        } label: {
            Image(systemName: glyph)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .disabled(target == nil)
        .opacity(target == nil ? 0.25 : 1)
        .accessibilityLabel(Text(label))
        .accessibilityHidden(target == nil)
        .accessibilityIdentifier(identifier)
    }
}

// MARK: - Taking the rating back (UX review 05.09.2026, finding 25)

extension HistorySheet {

    /// The rating is the one act of the workout that cannot be undone — every
    /// other irreversible step in the flow asks first — and since owner
    /// decision 1 (05.09.2026) a workout nobody rated is settled as "on plan"
    /// on the athlete's behalf, so the first rating a person ever meets may be
    /// one they never gave.
    ///
    /// The whole guard is `AppStore.canChangeLastRating`, which also refuses
    /// once anything else has moved the state; this only adds that the record
    /// on screen has to BE that last one — the walk above can be standing on
    /// any entry in the journal.
    var canChangeRating: Bool {
        store.canChangeLastRating && store.records.last?.id == shown.id
    }

    /// The rating already given is not offered back: the store answers a
    /// repeat with an empty list and changes nothing, and a button that does
    /// nothing is worse than an absent one.
    ///
    /// "Easy" is gated exactly as the rating screen gates it
    /// (`SetFacts.didFullPlan`) — a second door onto the same decision must
    /// not become the way around the rule the first one states out loud.
    @ViewBuilder
    var changeRatingActions: some View {
        if shown.result != .less {
            Button(String(localized: "Tough, did less")) { change(to: .less) }
        }
        if shown.result != .plan {
            Button(String(localized: "On plan")) { change(to: .plan) }
        }
        if shown.result != .more && canClaimEasy {
            Button(String(localized: "Easy, could do more")) { change(to: .more) }
        }
        // An alert, not a confirmationDialog, for the reason written out at
        // the workout's exit alert: iOS 26 draws the latter as an anchored
        // popover, and a popover suppresses its own cancel because tapping
        // outside IS the cancel. The escape here therefore carries both the
        // role and a name that says what it keeps.
        Button(String(localized: "history.changeRating.keep",
                      defaultValue: "Keep this rating"), role: .cancel) { }
    }

    private var canClaimEasy: Bool {
        guard let exercises = shown.exercises, !exercises.isEmpty else { return false }
        return SetFacts.didFullPlan(shown.setActuals ?? [:],
                                    skips: shown.setsSkipped ?? [:],
                                    skipped: shown.skipped ?? [],
                                    in: exercises)
    }

    /// The milestones the new answer earns are deliberately dropped. The
    /// milestone screen belongs to the workout it interrupts — raising one
    /// over a history sheet would celebrate a crossing in the middle of
    /// reading about a session from three weeks ago — and what actually
    /// changed is the plan, which Today draws the moment this sheet closes.
    private func change(to result: FeedbackResult) {
        store.changeLastRating(to: result)
        // The entry was REPLACED, not edited: re-point at the record that now
        // holds this workout, or the sheet keeps drawing the answer that was
        // just taken back.
        walked = store.records.last
    }
}
