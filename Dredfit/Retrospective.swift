//
//  Retrospective.swift
//  Dredfit
//
//  The "then → now" block for anniversary milestones (issue #26): the most
//  honest answer to "is this working?" is a comparison with the very first
//  workout, and the journal has carried the data for it (levelsAfter
//  snapshots) since 1.1. Lives in the app layer; the engine knows nothing.
//
//  Every number is produced by core helpers (Level.decode + the library), so
//  the app never re-implements level arithmetic — repStart/holdStart of
//  engine v2.3 are respected for free, and a future recoding cannot leave
//  this block silently wrong.
//
//  Degradations are silent by design: no snapshot in the journal, no growth,
//  or a pattern missing from the base (pull_bar joined later, old installs
//  predate snapshots) — the jubilee simply looks the way it always did.
//

import Foundation
import DredfitCore

struct Retrospective: Equatable {
    /// "Then: Knee push-up · 3×8"
    let thenLine: String
    /// "Now: Push-up · 3×14"
    let nowLine: String
    /// "12 weeks since your first workout" (months once weeks reach 9).
    let sinceLine: String

    /// One line for surfaces that want the comparison as a single sentence
    /// (the share card): "Then: … — Now: …".
    var comparisonLine: String { "\(thenLine) — \(nowLine)" }

    // MARK: - Builder

    /// The comparison for an anniversary, or nil when there is nothing honest
    /// to say.
    ///
    /// Base: the first journal record that carries a levelsAfter snapshot.
    /// Movement: the largest level gain between the base snapshot and the
    /// current levels; ties resolve in rotation order (pull_bar last, it is
    /// outside the rotation). A gain of zero or less is not a story — return
    /// nil rather than celebrate standing still.
    static func make(records: [WorkoutRecord],
                     currentLevels: [Pattern: Int],
                     now: Date = .now) -> Retrospective? {
        guard let base = records.first(where: { $0.levelsAfter != nil }),
              let baseLevels = base.levelsAfter else { return nil }

        // Rotation order first, the bar module last: the tie-break must be
        // deterministic and read as "the order the app always uses".
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

    /// "Push-up · 3×14" / "Plank · 3×30 s" — variation, sets and load exactly
    /// as the engine encodes them for this level.
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

    /// Whole weeks up to 8, whole months from week 9 on — a jubilee after two
    /// months reads better in months, and the spec pins the boundary.
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
