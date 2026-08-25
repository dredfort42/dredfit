//
//  The "then → now" block for anniversary milestones (issue #26), built from
//  the journal's levelsAfter snapshots.
//
//  Every number goes through core helpers (Level.decode + the library) so a
//  future recoding of levels cannot leave this block silently wrong.
//  Degradations are silent: missing snapshot, no growth, or a pattern absent
//  from the base — the jubilee just looks the way it always did.
//

import Foundation
import DredfitCore

struct Retrospective: Equatable {
    let thenLine: String
    let nowLine: String
    let sinceLine: String

    /// For surfaces that want the comparison as one sentence (the share card).
    var comparisonLine: String { "\(thenLine) — \(nowLine)" }

    // MARK: - Builder

    /// nil when there is nothing honest to say. Base is the first record
    /// carrying a position snapshot; the movement is the largest gain since,
    /// ties in rotation order. A gain of zero or less returns nil rather than
    /// celebrating standing still.
    ///
    /// Records written before v3 carry no `positionsAfter` and are skipped —
    /// their scale was a different one, and the honest answer to "how far have
    /// I come" is measured from the first session this engine actually saw.
    static func make(records: [WorkoutRecord],
                     current: [Pattern: RecordedPosition],
                     now: Date = .now) -> Retrospective? {
        guard let base = records.first(where: { $0.positionsAfter != nil }),
              let basePositions = base.positionsAfter else { return nil }

        var best: (pattern: Pattern, delta: Int)?
        for pattern in Pattern.allCases {
            guard let then = basePositions[pattern], let now = current[pattern] else { continue }
            let delta = progress(pattern, now) - progress(pattern, then)
            if delta > (best?.delta ?? 0) { best = (pattern, delta) }
        }
        guard let best, let then = basePositions[best.pattern],
              let nowPosition = current[best.pattern] else { return nil }

        return Retrospective(
            thenLine: String(localized: "Then: \(line(best.pattern, then))"),
            nowLine: String(localized: "Now: \(line(best.pattern, nowPosition))"),
            sinceLine: since(from: base.date, to: now))
    }

    // MARK: - Formatting (core helpers only)

    private static func progress(_ pattern: Pattern, _ position: RecordedPosition) -> Int {
        Engine.progress(pattern, variation: position.variation,
                        sets: position.sets, dose: position.dose)
    }

    /// Movement, sets and dose exactly as the plan stated them.
    private static func line(_ pattern: Pattern, _ position: RecordedPosition) -> String {
        let name = Library.name(pattern, position.variation)
        switch Library.unit(pattern, position.variation) {
        case .reps:
            return String(localized: "\(name) · \(position.sets)×\(position.dose)")
        case .hold:
            return String(localized: "\(name) · \(position.sets)×\(position.dose) s")
        }
    }

    /// Whole weeks up to 8, months from week 9 — the spec pins the boundary.
    private static func since(from start: Date, to now: Date) -> String {
        let days = max(0, Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0)
        let weeks = days / 7
        if weeks < 9 {
            return String(localized: "\(max(weeks, 1)) weeks since your first workout")
        }
        let months = max(1, Calendar.current.dateComponents([.month], from: start, to: now).month ?? 1)
        return String(localized: "\(months) months since your first workout")
    }
}
