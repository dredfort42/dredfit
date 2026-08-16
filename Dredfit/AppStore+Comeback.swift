//
//  AppStore+Comeback.swift
//  Dredfit
//
//  The read-only companions of the comeback card and the illness lens
//  (v2.12, issues #127/#133): what the two offers actually are in numbers,
//  when the quiet "I was sick" tap belongs on Today, and how much of the
//  recovery fortnight is left. Nothing here mutates state — the mutations
//  (acceptComeback, markIllness) stay in AppStore proper.
//

import Foundation
import DredfitCore

extension AppStore {

    /// Both offers of the comeback card as the same movement, in numbers
    /// (#127): the pull slot is in every session, so it is the honest
    /// exemplar of what "easier" — or "as it was" — actually means.
    func comebackPreview(now: Date? = nil) -> (was: String, easier: String)? {
        guard let gap = gapDays(now: now) else { return nil }
        let after = Engine.applyComeback(state: engineState, gapDays: gap,
                                         alreadyDecayed: silentDecayAppliedForCurrentBreak)
        let slot: (EngineState) -> SessionExercise? = { state in
            Engine.generateSession(state).exercises.first { Pattern.pullSide.contains($0.pattern) }
        }
        guard let was = slot(engineState), let easier = slot(after) else { return nil }
        return ("\(was.name) · \(was.display)", "\(easier.name) · \(easier.display)")
    }

    /// After a silent decay for the same break this is the weakened
    /// remainder — what accepting would actually subtract now.
    func comebackDrop(now: Date? = nil) -> Int {
        guard let gap = gapDays(now: now) else { return 0 }
        let before = engineState
        let after = Engine.applyComeback(state: before, gapDays: gap,
                                         alreadyDecayed: silentDecayAppliedForCurrentBreak)
        return (before.levels[.pull] ?? 0) - (after.levels[.pull] ?? 0)
    }

    /// Gentler workouts left under the illness lens; 0 = the lens is off.
    var illnessSessionsLeft: Int { engineState.illness }

    /// The quiet offer on Today, shown exactly in the window the engine
    /// cannot see (gap 2–13 days: below the comeback, at or past a missed
    /// beat) — a longer break carries the same tap on the comeback card.
    /// Unless the break is the trainee's own rhythm (v2.13, spec §23.3):
    /// rhythm breaks have no card, so the quiet offer stays for them.
    func shouldOfferIllnessTap(now: Date? = nil) -> Bool {
        guard engineState.illness == 0, let gap = gapDays(now: now) else { return false }
        if gap >= EngineConfig.comebackMinGapDays { return isRhythmBreak(gap) }
        return gap >= 2
    }
}
