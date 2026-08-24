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
    /// carrying a levelsAfter snapshot; the movement is the largest gain
    /// since, ties in rotation order. A gain of zero or less returns nil
    /// rather than celebrating standing still.
    static func make(records: [WorkoutRecord],
                     currentLevels: [Pattern: Int],
                     now: Date = .now) -> Retrospective? {
        guard let base = records.first(where: { $0.levelsAfter != nil }),
              let baseLevels = base.levelsAfter else { return nil }

        // pull_bar last — it is outside the rotation.
        let order = Pattern.ordered + [.pullBar]
        var best: (pattern: Pattern, delta: Int)?
        for pattern in order {
            guard let then = baseLevels[pattern],
                  let current = currentLevels[pattern] else { continue }
            let delta = current - then
            if delta > (best?.delta ?? 0) { best = (pattern, delta) }
        }
        guard let best else { return nil }

        let thenLevel = baseLevels[best.pattern] ?? 0
        let nowLevel = currentLevels[best.pattern] ?? 0
        return Retrospective(
            thenLine: String(localized: "Then: \(line(best.pattern, thenLevel))"),
            nowLine: String(localized: "Now: \(line(best.pattern, nowLevel))"),
            sinceLine: since(from: base.date, to: now))
    }

    // MARK: - Formatting (core helpers only)

    /// Variation, sets and load exactly as the engine encodes them.
    private static func line(_ pattern: Pattern, _ level: Int) -> String {
        let decoded = Level.decode(level)
        let entry = ExerciseLibrary.entry(for: pattern)
        let name = entry.variations[decoded.tier - 1].name
        switch entry.unit(forTier: decoded.tier) {
        case .reps:
            return String(localized: "\(name) · \(decoded.sets)×\(decoded.reps)")
        case .hold:
            return String(localized: "\(name) · \(decoded.sets)×\(decoded.hold) s")
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
