//
// Time enters the engine here, and only here (issue #98). The three functions
// below are the whole of the model's date awareness, and two of them read a
// single number — the gap since the last workout, from seven days up. Below
// that the engine is blind by contract: `generateSession` and `applyFeedback`
// never see a date, which is what makes them pure and the golden fixture
// reproducible. Training frequency is therefore an app-layer concern — seven
// workouts in seven days are legal here, and the quiet rest offer that answers
// them lives in `AppStore+Signals`.
//
// Split out of Engine.swift when the silent decay stopped being a one-line
// subtraction and became a step of the descent like any other, and the
// comeback's compensation had to reverse that step exactly.
//

import Foundation

extension Engine {

    /// All patterns drop, `pullBar` included even with `hasBar == false`: a
    /// break detrains the whole body. A freeze survives it untouched — the
    /// error is asymmetric, and a couple of sessions without growth cost less
    /// than a tendon. `failStreak` must reset — otherwise the first
    /// underperformance after the return would ride the old streak into a
    /// deload and drop the level twice. `counter` does not move.
    ///
    /// NOT idempotent: every call subtracts the drop again. The caller must
    /// apply it at most once per break (the app keys this on
    /// `comebackDecidedFor`).
    ///
    /// `alreadyDecayed`: the silent −1 already hit this same break, so the
    /// comeback weakens by one and the two drops do not stack. Exact even at
    /// the clamp: `max(max(L−1,0) − (drop−1), 0) == max(L − drop, 0)` for
    /// drop ≥ 2.
    ///
    /// Past the table's edge an absolute landing ceiling
    /// (`comebackLandingCeil`) — `min` composes with the alreadyDecayed
    /// weakening untouched, so the no-stacking identity holds by construction.
    /// And crossing a SET BAND snaps the rung to the band floor: preserving `L
    /// mod 8` across 40/32 made the first dose non-monotonic in the gap (90
    /// days → 5×6, 140 days → 4×11).
    public static func applyComeback(state dirty: EngineState, gapDays rawGap: Int,
                                     alreadyDecayed: Bool = false) -> EngineState {
        // Heal the state, clamp the gap. A negative gap already fell through
        // this guard; the clamp also keeps `gapDays - comebackMinGapDays` off
        // Int.min.
        let state = dirty.sanitized()
        let gapDays = Engine.sanitizeGapDays(rawGap)
        guard gapDays >= EngineConfig.comebackMinGapDays else { return dirty }
        // Consecutive comebacks with no session between deepen the drop by one
        // each — the plan must slide faster than fitness decays. The
        // cap is the same table cap.
        let raw = EngineConfig.comebackBase
            + (gapDays - EngineConfig.comebackMinGapDays) / EngineConfig.comebackStepDays
            + state.returnRun
        let drop = min(max(raw, 2), EngineConfig.comebackMax) - (alreadyDecayed ? 1 : 0)
        let landingCeil = EngineConfig.comebackLandingCeil
            .first { gapDays >= $0.minGap }?.ceil ?? Int.max

        var next = state
        next.lessRun = 0            // a break is not a continued run of "less"
        next.creditPaused = []      // a break clears the strain evidence too
        // A comeback is a DESCENT, and it takes the sub-steps off every
        // pattern — a break detrains the whole body, and the heavier sets
        // belonged to a dose that is gone.
        next.sub = [:]
        // A comeback rebuilds the levels, which makes the appearance window a
        // record about DIFFERENT levels — it goes with them. The silent decay
        // (−1) barely moves the levels and keeps it.
        next.lessHist = [:]
        // A comeback opens the limited-growth window.
        next.rampWindow = EngineConfig.rampWindowSessions
        // The weekly window is about a week that is now over.
        next.weekGain = [:]
        next.weekAgeDays = 0
        next.returnRun = state.returnRun + 1
        // The sub-steps of the ENTRY state. `next.sub` is already empty (a
        // comeback is a descent), and reading from it would lose exactly the
        // coordinate the compensation has to reverse.
        let entrySubs = state.sub
        for p in Pattern.allCases {
            let stored = state.levels[p] ?? 0
            // The level BEFORE the break: with alreadyDecayed the input
            // already carries the silent step, and reading the band or the
            // tier from it would break the identity exactly at the boundaries.
            //
            // The compensation reverses THE DECAY'S REAL STEP through
            // `riseBy`, instead of adding one to the level. A decay walks in
            // `fallBy` steps, and on a block floor it takes a SET without
            // touching the level — the old `stored + 1` then added a level
            // that never existed, and the identity broke for the statics at
            // L16.
            //
            // The hold on a returning set is deliberately NOT passed here:
            // this is not a growth event but the inverse of one step of the
            // decay, and the compensation has to reverse exactly what the
            // decay did or the identity tears.
            let back = alreadyDecayed
                ? Level.riseBy(level: stored, sub: entrySubs[p] ?? 0, cut: next.cutOf(p),
                               by: 1, allowSetsBack: true)
                : Position(level: stored, sub: entrySubs[p] ?? 0, cut: next.cutOf(p))
            let pre = Level.decode(back.level)
            var landed = max(0, stored - drop)
            let post = Level.decode(landed)
            // The snap applies to the DROP's result only; the band keeps its
            // priority, then rep continuity on a tier crossing: the same dose
            // in an easier variation, never the top of the lower tier. The
            // ceiling below is a deliberate absolute — a tier bottom by
            // construction.
            if pre.sets != post.sets {
                landed = (landed / EngineConfig.stepsPerTier) * EngineConfig.stepsPerTier
            } else if pre.tier != post.tier {
                // Continuity is computed in the UNIT OF THE TARGET TIER. Until
                // this fix it read the `reps` field of a STATIC, where a dose
                // in reps does not exist at all: core_anti_ext L26 after a
                // 35-day break was handed 3×17 s instead of 3×12 s, and the
                // `noHarder` gate rejected that landing in 8 cells of 480 at a
                // 119-day break. Word for word the defect declared fixed in
                // the lens — the lens was fixed and the comeback forgotten.
                //
                // A gate does not cure it: the gate reads `sub`/`cut`, and
                // those differ between "come back straight away" and "decay
                // then come back", which tears the identity (measured: 318
                // verify2 failures). It is cured at the root.
                let lib = ExerciseLibrary.entry(for: p)
                let step: Int
                if lib.unit(forTier: post.tier) == .reps {
                    step = Level.rung(tier: post.tier, reps: pre.reps)
                } else {
                    // The ladder is taken by the target tier's BASE band — a
                    // pure function of one tier. Reading `post.sets` would tie
                    // it to the level, and the level differs by one between the
                    // two paths, so the identity would tear for the statics.
                    let baseBand = Level.decode((post.tier - 1) * EngineConfig.stepsPerTier).sets
                    step = min(max(Level.holdRung(Level.ladder(tier: post.tier, sets: baseBand),
                                                  pre.hold), 0),
                               EngineConfig.stepsPerTier - 1)
                }
                landed = (post.tier - 1) * EngineConfig.stepsPerTier + step
            }
            next.levels[p] = min(landed, landingCeil)
            next.failStreak[p] = 0
        }
        // The levels fell — the cut has to fit the new band.
        next.cut = EngineState.healCut(next.cut, levels: next.levels)
        return next
    }

    /// `failStreak` resets, same as the comeback. The old "deliberately
    /// untouched" reading inverted the 13/14-day boundary at a streak of 2: a
    /// 13-day pause plus the first honest "less" rode into a deload (−5 total)
    /// while a 14-day break cost −3. `counter` does not move.
    ///
    /// NOT idempotent, same as the comeback: the app layer applies it at most
    /// once per break, keyed to the last workout's date.
    public static func applySilentDecay(state dirty: EngineState, gapDays rawGap: Int) -> EngineState {
        let state = dirty.sanitized()
        let gapDays = Engine.sanitizeGapDays(rawGap)
        guard gapDays >= EngineConfig.silentDecayGapDays,
              gapDays < EngineConfig.comebackMinGapDays else { return dirty }
        var next = state
        next.lessRun = 0            // same as the comeback
        next.creditPaused = []      // and so does the pause
        next.sub = [:]              // a decay is a descent too
        // The decay belongs to the same break — it is not a return, so
        // `returnRun` stands.
        //
        // A DECAY IS A DESCENT, and it has to walk the same steps as every
        // other one. The old `L − 1` failed the "no harder" gate in 47
        // transitions of 470, 18 of them INSIDE one block: squat 32 → 31 asked
        // for 4×6 per side instead of 3×11 (+38 %), hinge 24 → 23 for 3×4
        // instead of 3×12 per leg (+500 %). And all of it with no tap at all,
        // on opening the app after a week away — exactly when the person is
        // detrained.
        for p in Pattern.allCases {
            let landed = Level.fallBy(level: next.levels[p] ?? 0, sub: 0, cut: next.cutOf(p),
                                      by: 1)
            Self.setPosition(&next, p, landed)
            next.failStreak[p] = 0
        }
        // The same guard on the decay path.
        next.cut = EngineState.healCut(next.cut, levels: next.levels)
        return next
    }
}
