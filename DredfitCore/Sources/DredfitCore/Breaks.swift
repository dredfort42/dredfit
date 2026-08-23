//
//  Breaks.swift
//  DredfitCore
//
//  Time enters the engine here, and only here (issue #98, spec §7). The three
//  functions below are the whole of the model's date awareness, and two of
//  them read a single number — the gap since the last workout, from seven days
//  up. Below that the engine is blind by contract: `generateSession` and
//  `applyFeedback` never see a date, which is what makes them pure and the
//  golden fixture reproducible. Training frequency is therefore an app-layer
//  concern — seven workouts in seven days are legal here, and the quiet rest
//  offer that answers them lives in `AppStore+Signals`.
//
//  Split out of Engine.swift in v2.25, when the silent decay stopped being a
//  one-line subtraction and became a step of the descent like any other, and
//  the comeback's compensation had to reverse that step exactly.
//

import Foundation

extension Engine {

    /// All patterns drop, `pullBar` included even with `hasBar == false`: a
    /// break detrains the whole body. A freeze survives it untouched — the
    /// error is asymmetric, and a couple of sessions without growth cost less
    /// than a tendon — and so does a pain episode (v2.11, spec §21.2 p.8):
    /// levels drop as usual, the confirmation stays owed. `failStreak` must
    /// reset — otherwise the first underperformance after the return would
    /// ride the old streak into a deload and drop the level twice. `counter`
    /// does not move.
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
    /// v2.7 (spec §17.2): past the table's edge an absolute landing ceiling
    /// (`comebackLandingCeil`) — `min` composes with the alreadyDecayed
    /// weakening untouched, so the no-stacking identity holds by
    /// construction. And crossing a SET BAND snaps the rung to the band
    /// floor: preserving `L mod 8` across 40/32 made the first dose
    /// non-monotonic in the gap (90 days → 5×6, 140 days → 4×11).
    public static func applyComeback(state dirty: EngineState, gapDays rawGap: Int,
                                     alreadyDecayed: Bool = false) -> EngineState {
        // v2.13 (spec §24.1-24.2): heal the state, clamp the gap. A negative
        // gap already fell through this guard; the clamp also keeps
        // `gapDays - comebackMinGapDays` off Int.min.
        let state = dirty.sanitized()
        let gapDays = Engine.sanitizeGapDays(rawGap)
        guard gapDays >= EngineConfig.comebackMinGapDays else { return dirty }
        // v2.12 (spec §22.3): consecutive comebacks with no session between
        // deepen the drop by one each — the plan must slide faster than
        // fitness decays (A8b-9). The cap is the same table cap.
        let raw = EngineConfig.comebackBase
            + (gapDays - EngineConfig.comebackMinGapDays) / EngineConfig.comebackStepDays
            + state.returnRun
        let drop = min(max(raw, 2), EngineConfig.comebackMax) - (alreadyDecayed ? 1 : 0)
        let landingCeil = EngineConfig.comebackLandingCeil
            .first { gapDays >= $0.minGap }?.ceil ?? Int.max

        var next = state
        next.lessRun = 0            // v2.9: a break is not a continued run of "less"
        next.creditPaused = []      // v2.10: a break clears the strain evidence too
        // v2.22 (spec §33): a comeback is a DESCENT, and it takes the sub-steps
        // off every pattern — a break detrains the whole body, and the heavier
        // sets belonged to a dose that is gone.
        next.sub = [:]
        // v2.15 (spec §26.1): a comeback rebuilds the levels, which makes the
        // appearance window a record about DIFFERENT levels — it goes with
        // them. The silent decay (−1) barely moves the levels and keeps it.
        next.lessHist = [:]
        // v2.17 (spec §28.4): a comeback opens the limited-growth window.
        next.rampWindow = EngineConfig.rampWindowSessions
        // The weekly window is about a week that is now over.
        next.weekGain = [:]
        next.weekAgeDays = 0
        next.returnRun = state.returnRun + 1   // v2.12 (§22.3)
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
            // v2.25 (round 4): the compensation reverses THE DECAY'S REAL STEP
            // through `riseBy`, instead of adding one to the level. With §36.7
            // a decay walks in `fallBy` steps, and on a block floor it takes a
            // SET without touching the level — the old `stored + 1` then added
            // a level that never existed, and the §14.2 identity broke for the
            // statics at L16.
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
            // v2.7 priority, then v2.12 rep continuity on a tier crossing:
            // the same dose in an easier variation, never the top of the lower
            // tier (audit finding A3-1). The ceiling below is a deliberate
            // absolute — a tier bottom by construction.
            if pre.sets != post.sets {
                landed = (landed / EngineConfig.stepsPerTier) * EngineConfig.stepsPerTier
            } else if pre.tier != post.tier {
                // v2.25 (round 4, S6-2): continuity is computed in the UNIT OF
                // THE TARGET TIER. Until this fix it read the `reps` field of
                // a STATIC, where a dose in reps does not exist at all:
                // core_anti_ext L26 after a 35-day break was handed 3×17 s
                // instead of 3×12 s, and the `noHarder` gate rejected that
                // landing in 8 cells of 480 at a 119-day break. Word for word
                // the defect §36.7 declared fixed in the lens — the lens was
                // fixed and the comeback forgotten.
                //
                // A gate does not cure it: the gate reads `sub`/`cut`, and
                // those differ between "come back straight away" and "decay
                // then come back", which tears the §14.2 identity (measured:
                // 318 verify2 failures). It is cured at the root.
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
        // v2.25 (Ф3): the levels fell — the cut has to fit the new band.
        next.cut = EngineState.healCut(next.cut, levels: next.levels)
        // v2.25 (Ф7, FIXED): the memory of pain fades only on a LONG break.
        // Fourteen days was a plain mistake: a break is exactly what a person
        // in pain takes, so one break per report kept the memory at one for
        // ever, the "time to see a specialist" threshold became unreachable
        return next
    }

    /// v2.7 (spec §17.3): `failStreak` resets, same as the comeback. The old
    /// "deliberately untouched" reading inverted the 13/14-day boundary at a
    /// streak of 2: a 13-day pause plus the first honest "less" rode into a
    /// deload (−5 total) while a 14-day break cost −3. `counter` does not
    /// move.
    ///
    /// NOT idempotent, same as the comeback: the app layer applies it at most
    /// once per break, keyed to the last workout's date.
    public static func applySilentDecay(state dirty: EngineState, gapDays rawGap: Int) -> EngineState {
        let state = dirty.sanitized()
        let gapDays = Engine.sanitizeGapDays(rawGap)
        guard gapDays >= EngineConfig.silentDecayGapDays,
              gapDays < EngineConfig.comebackMinGapDays else { return dirty }
        var next = state
        next.lessRun = 0            // v2.9: same as the comeback (spec §19.1)
        next.creditPaused = []      // v2.10: and so does the pause
        next.sub = [:]              // v2.22 (§33): a decay is a descent too
        // v2.12 (§22.3): the decay belongs to the same break — it is not
        // a return, so `returnRun` stands.
        //
        // v2.25 (spec §36.7): A DECAY IS A DESCENT, and it has to walk the
        // same steps as every other one. The old `L − 1` failed the "no
        // harder" gate in 47 transitions of 470, 18 of them INSIDE one block:
        // squat 32 → 31 asked for 4×6 per side instead of 3×11 (+38 %), hinge
        // 24 → 23 for 3×4 instead of 3×12 per leg (+500 %). And all of it with
        // no tap at all, on opening the app after a week away — exactly when
        // the person is detrained.
        for p in Pattern.allCases {
            let landed = Level.fallBy(level: next.levels[p] ?? 0, sub: 0, cut: next.cutOf(p),
                                      by: 1, floor: EngineConfig.setsFloor)
            Self.setPosition(&next, p, landed)
            next.failStreak[p] = 0
        }
        // v2.25 (Ф3): the same guard on the decay path.
        next.cut = EngineState.healCut(next.cut, levels: next.levels)
        return next
    }

    /// v2.12 (spec §22.4): the "I was sick" one-tap — the sixth API function.
    /// An illness shorter than seven days is invisible to the time contract
    /// (§7) by construction, so the channel is explicit. The lens makes the
    /// plan one tier easier for `illnessSessions` restorative sessions
    /// without touching the stored levels; a repeat tap tops the lens back
    /// up (a prolongation, not an escalation), and on a fresh lens the call
}
