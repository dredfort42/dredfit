//
//  The store's read-only derivations: the next plan, the progress curve
//  and what the journal says about a given day. Nothing here writes.
//

import Foundation
import DredfitCore

extension AppStore {

    /// IMPORTANT: right after a workout is completed the counter has
    /// advanced, so this is the NEXT workout. Never present it under today's
    /// date — only with nextTrainingDate. A workout in progress: `session(for:)`.
    var nextSession: Session { session(for: engineState) }

    /// Conservative on missing data: records without an exercise snapshot
    /// cannot vouch for what was done, so a pattern with no snapshotted
    /// history is never badged — better a missed badge than "new variation"
    /// on an exercise the user has done for weeks.
    var debutPatterns: Set<Pattern> {
        var maxPerformed: [Pattern: Int] = [:]
        for record in records {
            guard let exercises = record.exercises else { continue }
            // A painful exercise was not performed either. A record written by
            // an older build keeps its pain reports, and they were "not
            // performed" exactly as a skip was — so reading history has to
            // count both. Nothing writes `discomfort` any more.
            let skipped = (record.skipped ?? []).union(record.discomfort ?? [])
            for ex in exercises where !skipped.contains(ex.pattern) {
                maxPerformed[ex.pattern] = max(maxPerformed[ex.pattern] ?? 0, ex.variation)
            }
        }
        var debuts: Set<Pattern> = []
        for ex in nextSession.exercises {
            if let seen = maxPerformed[ex.pattern], ex.variation > seen {
                debuts.insert(ex.pattern)
            }
        }
        return debuts
    }

    /// How far along their ladders every movement stands, summed. A clean
    /// start reads zero.
    var totalProgress: Int { Engine.totalProgress(engineState) }

    /// The position of every movement right now, in the form the journal
    /// records it.
    var currentPositions: [Pattern: RecordedPosition] { Self.positions(of: engineState) }

    static func positions(of state: EngineState) -> [Pattern: RecordedPosition] {
        var out: [Pattern: RecordedPosition] = [:]
        for p in Pattern.allCases {
            let pos = state.position(p)
            out[p] = RecordedPosition(variation: pos.variation, sets: pos.sets, dose: pos.dose,
                                      sub: pos.sub > 0 ? pos.sub : nil,
                                      cut: pos.cut > 0 ? pos.cut : nil)
        }
        return out
    }

    /// Oldest first. `through` cuts it at a date: a milestone card must not
    /// draw a curve running past the event it celebrates. Records written
    /// before v3 carry no point on this scale and are left out rather than
    /// plotted on the wrong one.
    func progressCurve(through date: Date? = nil) -> [Int] {
        let run = recordsSinceReset
        let history = date.map { cut in run.filter { $0.date <= cut } } ?? run
        return history.compactMap(\.totalProgressAfter)
    }

    /// Where the journal starts describing the CURRENT plan. `resetProgress`
    /// restarts the session counter and leaves the journal standing — which is
    /// what `WorkoutRecord.id` already says out loud — so the first record
    /// whose number does not exceed its predecessor's opens the new run.
    ///
    /// The curve is cut here rather than at each caller because every chart
    /// of it needs the cut: the milestone card and the share card would
    /// otherwise draw the pre-reset PEAK above a plan that has just been wiped.
    /// The workout COUNT still spans the whole journal: the history really
    /// does stay, which is what the reset promises.
    var recordsSinceReset: [WorkoutRecord] {
        let resumed = records.indices.dropFirst().last {
            records[$0].sessionNumber <= records[$0 - 1].sessionNumber
        }
        // The falling pair finds a reset only from the NEXT workout on:
        // `resetProgress` writes no record of its own, it just returns the
        // engine to `.initial` and leaves the journal standing. In the window
        // between the reset and the first workout after it there is no pair to
        // find, and the whole journal would come back while `totalProgress` is
        // already 0 — the old peak under a headline saying zero. The counter
        // moves at the reset itself.
        return records[(resumed ?? records.startIndex)...]
            .filter { $0.sessionNumber <= engineState.counter }
    }

    var lastRecord: WorkoutRecord? { records.last }

    var doneToday: Bool { isDone(on: today) }

    func isDone(on date: Date) -> Bool {
        guard let last = records.last else { return false }
        return Calendar.current.isDate(last.date, inSameDayAs: date)
    }

    func isRestDay(_ date: Date) -> Bool {
        settings.restWeekdays.contains(Calendar.current.component(.weekday, from: date))
    }

    /// The workout completed on the given day, if any (for calendar history).
    func record(on date: Date) -> WorkoutRecord? {
        let cal = Calendar.current
        return records.last { cal.isDate($0.date, inSameDayAs: date) }
    }
}
