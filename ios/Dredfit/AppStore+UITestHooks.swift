//
//  DEBUG-only launch-argument hooks the UI tests use to start from a known
//  state. Kept out of AppStore.swift so the store reads without them; the
//  whole file compiles away in release, so no flag can reach a user's journal.
//

import Foundation
import DredfitCore

#if DEBUG
extension AppStore {
    func applyUITestHooks() {
        // Reset means "clean state", not "first run".
        if CommandLine.arguments.contains("--uitest-reset"),
           !CommandLine.arguments.contains("--uitest-onboarding") {
            settings.onboardingCompleted = true
        }
        // The suite must not depend on the weekday it runs on, so these flags
        // clear the rest days outright. --uitest-restday puts today back as a
        // rest day further down, but it does NOT have the last word:
        // --uitest-comeback-long runs after it and the seedLoneWorkout it
        // calls ends by clearing restWeekdays again, so the two flags together
        // leave no rest day at all. No test passes both today — the order is
        // written down here so the next one that wants to does not have to
        // find it out from a failure.
        let seedFlags = ["--uitest-reset", "--uitest-session2", "--uitest-milestone",
                         "--uitest-long-session"]
        if seedFlags.contains(where: CommandLine.arguments.contains) {
            settings.restWeekdays = []
        }
        // Session 1 completed yesterday → today offers session 2, the only
        // deterministic way to reach hold exercises.
        if CommandLine.arguments.contains("--uitest-session2") {
            engineState = .initial
            records = []
            completeWorkout(session: Engine.generateSession(engineState),
                            result: .plan,
                            date: Calendar.current.date(byAdding: .day, value: -1, to: .now)!)
        }
        seedStateIfRequested()
        // Make today a rest day, whichever weekday that is.
        if CommandLine.arguments.contains("--uitest-restday") {
            settings.restWeekdays = [Calendar.current.component(.weekday, from: .now)]
        }
        // Only workout 95 days ago → the comeback card with the paths it
        // still has: the numbered offers and "Start from scratch" (#127). The
        // sick row went with the illness lens.
        if CommandLine.arguments.contains("--uitest-comeback-long") {
            seedLoneWorkout(daysAgo: 95)
        }
        // `--uitest-illness` seeded a five-day gap so the quiet "I was sick"
        // offer would appear. The offer is gone, no test passed the flag any
        // more, and a hook nothing reaches is a branch that will be trusted by
        // the next reader.
    }

    /// The hooks that only build a STATE — no settings, no journal beyond the
    /// one record a break needs. Split off so the flag walk above stays inside
    /// the linter's complexity bound: it grows by one branch every wave, and
    /// the bound is a CI error rather than a style opinion.
    private func seedStateIfRequested() {
        // A trainee at the top of every ladder: band 4, six movements, 67
        // minutes (the number moved with the v3 ladders). The
        // state the mid-workout skip exists for — a plan of three sets can
        // only ever give one of them away and still count as trained, so the
        // escape that takes the REST of a movement has nothing to show at the
        // bottom of the scale.
        if CommandLine.arguments.contains("--uitest-long-session") {
            var seeded = EngineState.initial
            for p in Pattern.allCases {
                // The top variation is the only place bands live (§40.5), so
                // "four sets" is a position, not a number that can be set on
                // its own.
                let top = Library.count(p)
                seeded.vars[p] = top
                seeded.doses[p] = Dose.grid(Library.unit(p, top)).max
                seeded.sets[p] = 4
            }
            engineState = seeded
        }
        // One workout away from several milestones. Seeds state only — the
        // milestones and the retrospective still come from the real path.
        if CommandLine.arguments.contains("--uitest-milestone") {
            var seeded = EngineState.initial
            seeded.counter = 9
            // One growth event from a new SET BAND — which fires on a plain
            // "on plan" tap. A new variation would need a probe passed inside
            // the workout, and a seed cannot promise the driver will pass it.
            for ex in Engine.generateSession(seeded).exercises.prefix(2) {
                let top = Library.count(ex.pattern)
                seeded.vars[ex.pattern] = top
                seeded.doses[ex.pattern] = Dose.grid(Library.unit(ex.pattern, top)).max
            }
            engineState = seeded
            records = [WorkoutRecord(
                sessionNumber: 1,
                date: Calendar.current.date(byAdding: .day, value: -63, to: .now)!,
                result: .plan,
                totalProgressAfter: 0,
                positionsAfter: Self.positions(of: .initial))]
        }
        // Only workout 20 days ago → today opens on the comeback card.
        if CommandLine.arguments.contains("--uitest-comeback") {
            seedLoneWorkout(daysAgo: 20)
        }
    }

    /// A single workout `daysAgo`, every movement a couple of variations up —
    /// the seed the three break-shaped UI-test states share; only the gap
    /// differs. The journal is filled in so a descent has somewhere to land
    /// (§40.6): without it a comeback would land every pattern on 3×4.
    private func seedLoneWorkout(daysAgo: Int) {
        var seeded = EngineState.initial
        seeded.counter = 11
        for p in Pattern.allCases {
            let target = min(3, Library.count(p))
            seeded.vars[p] = target
            seeded.doses[p] = Dose.grid(Library.unit(p, target)).max
            var journal: [Int: Int] = [:]
            for v in 1...target { journal[v] = Dose.grid(Library.unit(p, v)).max }
            seeded.shown[p] = journal
        }
        engineState = seeded
        records = [WorkoutRecord(
            sessionNumber: 11,
            date: Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)!,
            result: .plan,
            totalProgressAfter: Engine.totalProgress(seeded),
            positionsAfter: Self.positions(of: seeded))]
        settings.comebackDecidedFor = nil
        settings.restWeekdays = []
    }
}
#endif
