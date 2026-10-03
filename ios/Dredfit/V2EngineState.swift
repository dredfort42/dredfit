//
//  The shape of an engine state written before v3, and nothing more.
//
//  This type exists to READ a format the app no longer writes. It is
//  deliberately small: only the fields the migration carries over. Everything
//  else a v2 state held has nowhere to land in v3.
//
//  Every field but `levels` — the one that makes a state v2 — falls back to a
//  default, per the project's rule for persisted types: a v2 file written by
//  any build of that era must decode, and one missing key must not throw the
//  whole thing away.
//

import Foundation
import DredfitCore

struct V2EngineState: Codable {
    var counter: Int = 0
    var hasBar: Bool = false
    var levels: [Pattern: Int] = [:]
    var failStreak: [Pattern: Int] = [:]

    /// `levels` is what makes a state v2: v3 has no such field, and its
    /// absence is what sends `AppStore`'s decode on to `EngineState.initial`.
    enum CodingKeys: String, CodingKey { case counter, hasBar, levels, failStreak }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Not `decodeIfPresent`: without `levels` this is not a v2 state at
        // all, and failing here is how the caller learns that.
        levels = try Self.patternMap(c, .levels)
        guard !levels.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .levels, in: c,
                                                   debugDescription: "not a v2 state")
        }
        // `decode`, not `decodeIfPresent`: under `try?` a missing key and a
        // malformed one both fall to the default either way, and the plain
        // form yields a single optional rather than a double one.
        counter = (try? c.decode(Int.self, forKey: .counter)) ?? 0
        hasBar = (try? c.decode(Bool.self, forKey: .hasBar)) ?? false
        failStreak = (try? Self.patternMap(c, .failStreak)) ?? [:]
    }

    /// v2 encoded `[Pattern: Int]` as an UNKEYED array — [rawValue, count, …] —
    /// for the same reason v3 does: `Pattern` is a plain String-raw enum and
    /// never adopted `CodingKeyRepresentable`. Reading it back means walking
    /// the pairs, and an odd-length array is simply the end of what is legible.
    private static func patternMap(_ c: KeyedDecodingContainer<CodingKeys>,
                                   _ key: CodingKeys) throws -> [Pattern: Int] {
        guard c.contains(key) else { return [:] }
        var out: [Pattern: Int] = [:]
        var u = try c.nestedUnkeyedContainer(forKey: key)
        while !u.isAtEnd {
            guard let raw = try? u.decode(String.self), let value = try? u.decode(Int.self) else { break }
            if let p = Pattern(rawValue: raw) { out[p] = value }
        }
        return out
    }

    var asEngineInput: Engine.V2State {
        Engine.V2State(counter: counter, hasBar: hasBar,
                       levels: levels, failStreak: failStreak)
    }
}
