//
//  Exercise catalog: ten patterns, 59 positions along their ladders (§40.1).
//  Base language English, translations in Resources/Localizable.xcstrings.
//  Technique: 3 steps + 2 common mistakes per position. Mirrors LIBRARY and
//  TECHNIQUE in the reference adaptive_engine.js.
//
//  The ladder is the ONLY place a difficulty measure lives, and it has exactly
//  two jobs (§40.0): the ORDER of the rungs, and the density invariant И1
//  (`w(N+1)/w(N) <= 1.50`). No dose is ever computed from `w` — the engine
//  measures what the trainee showed and never predicts it.
//

import Foundation

/// Three steps and two common mistakes — the card a person reads standing on
/// the mat. An assistance rung (kind `°` in the spec) inherits the technique
/// of the variation it assists with ONE line replaced, and `assisted` is the
/// only way to express that: two copies of one text drift exactly the way two
/// copies of one rule do, and here the drift is read by a human mid-set.
struct Technique: Equatable, Sendable {
    let steps: [String]
    let mistakes: [String]

    func assisted(step index: Int, _ line: String) -> Technique {
        var replaced = steps
        replaced[index] = line
        return Technique(steps: replaced, mistakes: mistakes)
    }
}

public struct ExerciseVariation: Equatable, Sendable {
    public let name: String
    public let unilateral: Bool
    /// The unit is a property of the VARIATION, not of the pattern: a ladder
    /// may cross from seconds to reps once, and `pull_bar` does.
    public let unit: LoadUnit
    /// Share of body weight on the working link, per rep — per second for a
    /// hold. Orders the ladder and bounds its density; never a dose (§40.0).
    public let w: Double
    public let steps: [String]
    public let mistakes: [String]
}

public struct ExerciseEntry: Equatable, Sendable {
    public let pattern: Pattern
    /// Index = variation − 1. Variations are 1-based everywhere else, because
    /// the state stores them that way and a person reads "variation 3 of 7".
    public let variations: [ExerciseVariation]

    public var count: Int { variations.count }

    /// Total by construction: reading the library must never trap. A plan
    /// built from a dirty state has to stay a valid input to `applyFeedback`
    /// (§17.4), and the sanitizer is not the only door into this type.
    public func variation(_ v: Int) -> ExerciseVariation {
        variations[Library.index(pattern: pattern, variation: v) - 1]
    }

    public func unit(forVariation v: Int) -> LoadUnit { variation(v).unit }

    /// The one boundary the density invariant skips: seconds and reps are not
    /// commensurable, so `w(N+1)/w(N)` is undefined across it and the only way
    /// in is a probe (§40.1, §40.10 п. 3).
    ///
    /// DERIVED from the units rather than carried as a flag. A stored
    /// `probeOnly` and the units it describes are two copies of one fact, and
    /// the fixture pins the derivation, so the copy cannot come back.
    public func probeOnly(variation v: Int) -> Bool {
        let i = Library.index(pattern: pattern, variation: v)
        return i > 1 && variations[i - 1].unit != variations[i - 2].unit
    }
}

/// Reading the ladders. The engine asks nothing else of the catalog.
public enum Library {

    public static func count(_ pattern: Pattern) -> Int {
        ExerciseLibrary.entry(for: pattern).count
    }

    /// 1-based and clamped. See `ExerciseEntry.variation` for why it clamps
    /// rather than traps.
    public static func index(pattern: Pattern, variation v: Int) -> Int {
        min(max(v, 1), count(pattern))
    }

    public static func at(_ pattern: Pattern, _ v: Int) -> ExerciseVariation {
        ExerciseLibrary.entry(for: pattern).variation(v)
    }

    public static func unit(_ pattern: Pattern, _ v: Int) -> LoadUnit { at(pattern, v).unit }

    /// 2 for a movement trained one side at a time, 1 otherwise — the factor
    /// every work measure multiplies by.
    public static func sides(_ pattern: Pattern, _ v: Int) -> Int {
        at(pattern, v).unilateral ? 2 : 1
    }

    public static func name(_ pattern: Pattern, _ v: Int) -> String { at(pattern, v).name }

    public static func isTop(_ pattern: Pattern, _ v: Int) -> Bool {
        index(pattern: pattern, variation: v) == count(pattern)
    }
}

public enum ExerciseLibrary {

    public static func entry(for pattern: Pattern) -> ExerciseEntry { entries[pattern]! }

    /// The module's resource bundle, exposed for tests: the generated
    /// `Bundle.module` is internal per target, and LibraryPinTests must
    /// resolve its expected keys through THIS bundle to stay locale-proof.
    static var localizationBundle: Bundle { .module }

    public static let entries: [Pattern: ExerciseEntry] = [
        .squat: ExerciseEntry(pattern: .squat, variations: squat),
        .pushH: ExerciseEntry(pattern: .pushH, variations: pushH),
        .hinge: ExerciseEntry(pattern: .hinge, variations: hinge),
        .pull: ExerciseEntry(pattern: .pull, variations: pull),
        .pushV: ExerciseEntry(pattern: .pushV, variations: pushV),
        .lunge: ExerciseEntry(pattern: .lunge, variations: lunge),
        .coreAntiExt: ExerciseEntry(pattern: .coreAntiExt, variations: coreAntiExt),
        .coreRot: ExerciseEntry(pattern: .coreRot, variations: coreRot),
        .calf: ExerciseEntry(pattern: .calf, variations: calf),
        .pullBar: ExerciseEntry(pattern: .pullBar, variations: pullBar),
    ]

    /// One rung of a ladder, spelled out so the ladder files read as the
    /// spec's tables do: name, difficulty, unit, sides, technique.
    static func rung(_ name: String, w: Double, unit: LoadUnit, perSide: Bool,
                     _ technique: Technique) -> ExerciseVariation {
        ExerciseVariation(name: name, unilateral: perSide, unit: unit, w: w,
                          steps: technique.steps, mistakes: technique.mistakes)
    }
}
