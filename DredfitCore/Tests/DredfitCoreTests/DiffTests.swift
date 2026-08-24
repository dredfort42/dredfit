//
//  DiffTests.swift
//  DredfitCoreTests
//
//  The JS ↔ Swift differential, REWRITTEN for v2.26 — one call at a time.
//
//  It used to run ten thousand random TRAJECTORIES and fold them into a single
//  fingerprint. Audit 2026-08-23 (zone A2) named both faults of that shape: a
//  single cause is inherited into hundreds of later steps, so the diff cannot
//  be used to count how many causes there really are; and one shared
//  fingerprint does not even say where to look.
//
//  Here every case is ONE call on ONE pre-state, and the pre-state comes FROM
//  THE REFERENCE rather than being regenerated here — otherwise a divergence
//  in how the two sides build states would read as a divergence in the engine.
//
//  The comparison is BYTE-EXACT over a canonical string:
//    • fractional numbers as the IEEE 754 hex bit pattern (`DataView.
//      setFloat64` on one side, `Double.bitPattern` on the other), because the
//      two languages print decimals differently;
//    • sparse maps as a list of the keys that are PRESENT, because "no key"
//      and "key with value 0" are different states — and that difference is
//      exactly where the P0 of the previous wave lived: one missing decrement
//      gave 1876 diverging calls while 309 tests stayed green.
//
//  Regenerate with `node reference/difftest.js`; explain a failing case with
//  `node reference/difftest.js --explain <index>`.
//

import XCTest
@testable import DredfitCore

private typealias Pattern = DredfitCore.Pattern

private struct DiffFixture: Decodable {
    let generator: String
    let method: String
    let states: [String]
    let cases: [Case]

    struct Case: Decodable {
        let s: Int              // index into `states`
        let c: Call
        let d: String           // FNV-1a 64 of the canonical result
        let r: String?          // the full string, on the diagnostic sample
    }
    struct Call: Decodable {
        let k: String
        let r: String?          // feedback result
        let g: Double?          // gapDays / break length
        let ad: Int?            // alreadyDecayed
        let p: String?          // pattern
        let n: Int?             // number
        let ov: [String: Int]?  // overrides
        let sk: [String]?       // skipped
    }
}

final class DiffTests: XCTestCase {

    // MARK: - the canonical encoding, mirrored from `reference/difftest.js`

    private static func hex(_ x: Double) -> String {
        String(format: "%016llx", x.bitPattern)
    }

    /// Only the keys that are PRESENT, in `ALL_PATTERNS` order.
    private static func sparse(_ m: [Pattern: Int]) -> String {
        Pattern.allCases.filter { m[$0] != nil }
            .map { "\($0.rawValue):\(m[$0]!)" }.joined(separator: ",")
    }

    private static func dense(_ m: [Pattern: Int]) -> String {
        Pattern.ordered.map { String(m[$0] ?? 0) }.joined(separator: ",")
    }

    private static func canon(_ s: EngineState) -> String {
        [
            "c=\(s.counter)",
            "L=\(dense(s.levels))",
            "Lb=\(s.levels[.pullBar] ?? 0)",
            "F=\(dense(s.failStreak))",
            "Fb=\(s.failStreak[.pullBar] ?? 0)",
            "B=\(s.hasBar ? 1 : 0)",
            "s=\(sparse(s.sub))",
            "k=\(sparse(s.cut))",
            "h=\(sparse(s.setsHold))",
            "w=\(sparse(s.shownWork))",
            "o=\(sparse(s.shownOrd))",
            "g=\(sparse(s.weekGain))",
            "lh=\(sparse(s.lessHist))",
            "cp=" + Pattern.allCases.filter { s.creditPaused.contains($0) }
                .map(\.rawValue).joined(separator: ","),
            "lr=\(s.lessRun)",
            "rw=\(s.rampWindow)",
            "rr=\(s.returnRun)",
            "wa=\(hex(s.weekAgeDays))",
        ].joined(separator: ";")
    }

    private static func canon(_ w: Session) -> String {
        let exercises = w.exercises.map { e in
            [
                e.pattern.rawValue, String(e.tier), e.unit.rawValue, String(e.load),
                e.perSide ? "1" : "0", String(e.sets),
                String(e.restSetSec), String(e.restExerciseSec),
                e.loads.map { $0.map(String.init).joined(separator: "/") } ?? "-",
            ].joined(separator: ",")
        }.joined(separator: "|")
        return [
            "n=\(w.sessionNumber)", "wu=\(w.warmupMin)", "cd=\(w.cooldownMin)",
            "t=\(hex(w.estimatedTotalMin))", "E=" + exercises,
        ].joined(separator: ";")
    }

    private static func fnv(_ s: String) -> String {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in Array(s.utf8) {
            h ^= UInt64(byte)
            h = h &* 0x0000_0100_0000_01b3
        }
        return String(format: "%016llx", h)
    }

    // MARK: - parsing a pre-state the reference wrote

    private static func parseSparse(_ raw: String) -> [Pattern: Int] {
        var out: [Pattern: Int] = [:]
        for pair in raw.split(separator: ",") where !pair.isEmpty {
            let kv = pair.split(separator: ":")
            guard kv.count == 2, let p = Pattern(rawValue: String(kv[0])),
                  let v = Int(kv[1]) else { continue }
            out[p] = v
        }
        return out
    }

    private static func parseState(_ raw: String) throws -> EngineState {
        var f: [String: String] = [:]
        for part in raw.split(separator: ";", omittingEmptySubsequences: false) {
            guard let eq = part.firstIndex(of: "=") else { continue }
            f[String(part[part.startIndex..<eq])] = String(part[part.index(after: eq)...])
        }
        var s = EngineState.initial
        s.counter = Int(f["c"] ?? "0") ?? 0
        let levels = (f["L"] ?? "").split(separator: ",").map { Int($0) ?? 0 }
        let streaks = (f["F"] ?? "").split(separator: ",").map { Int($0) ?? 0 }
        for (i, p) in Pattern.ordered.enumerated() {
            s.levels[p] = i < levels.count ? levels[i] : 0
            s.failStreak[p] = i < streaks.count ? streaks[i] : 0
        }
        s.levels[.pullBar] = Int(f["Lb"] ?? "0") ?? 0
        s.failStreak[.pullBar] = Int(f["Fb"] ?? "0") ?? 0
        s.hasBar = (f["B"] ?? "0") == "1"
        s.sub = parseSparse(f["s"] ?? "")
        s.cut = parseSparse(f["k"] ?? "")
        s.setsHold = parseSparse(f["h"] ?? "")
        s.shownWork = parseSparse(f["w"] ?? "")
        s.shownOrd = parseSparse(f["o"] ?? "")
        s.weekGain = parseSparse(f["g"] ?? "")
        s.lessHist = parseSparse(f["lh"] ?? "")
        s.creditPaused = Set((f["cp"] ?? "").split(separator: ",")
            .compactMap { Pattern(rawValue: String($0)) })
        s.lessRun = Int(f["lr"] ?? "0") ?? 0
        s.rampWindow = Int(f["rw"] ?? "0") ?? 0
        s.returnRun = Int(f["rr"] ?? "0") ?? 0
        s.weekAgeDays = Double(bitPattern: UInt64(f["wa"] ?? "0", radix: 16) ?? 0)
        return s
    }

    // MARK: - one isolated call

    private static func run(_ state: EngineState, _ call: DiffFixture.Call) throws -> String {
        switch call.k {
        case "gen":
            return canon(Engine.generateSession(state))
        case "fb":
            let w = Engine.generateSession(state)
            var overrides: [Pattern: Int] = [:]
            for (raw, v) in call.ov ?? [:] {
                overrides[try XCTUnwrap(Pattern(rawValue: raw))] = v
            }
            let skipped = Set((call.sk ?? []).compactMap { Pattern(rawValue: $0) })
            // Every optional passed explicitly — the rule of the v2.25 wave.
            return canon(Engine.applyFeedback(
                state: state, session: w,
                result: try XCTUnwrap(FeedbackResult(rawValue: try XCTUnwrap(call.r))),
                overrides: overrides, skipped: skipped, gapDays: call.g))
        case "come":
            return canon(Engine.applyComeback(state: state,
                                              gapDays: Int(try XCTUnwrap(call.g)),
                                              alreadyDecayed: call.ad == 1))
        case "decay":
            return canon(Engine.applySilentDecay(state: state,
                                                 gapDays: Int(try XCTUnwrap(call.g))))
        case "shown":
            return canon(Engine.recordShown(state: state,
                                            session: Engine.generateSession(state)))
        case "setCut":
            return canon(Engine.setCut(state: state,
                                       pattern: try XCTUnwrap(Pattern(rawValue: try XCTUnwrap(call.p))),
                                       cut: try XCTUnwrap(call.n)))
        case "shorter":
            return canon(Engine.shorterSession(state: state, steps: try XCTUnwrap(call.n)))
        case "easier":
            return canon(Engine.easierVariation(state: state,
                                                pattern: try XCTUnwrap(Pattern(rawValue: try XCTUnwrap(call.p)))))
        case "easierL":
            let p = try XCTUnwrap(Pattern(rawValue: try XCTUnwrap(call.p)))
            let to = Engine.easierLevel(pattern: p, level: state.levels[p] ?? 0,
                                        sub: state.sub[p] ?? 0, cut: state.cut[p] ?? 0)
            return "easierLevel=\(to.map(String.init) ?? "nil")"
        default:
            XCTFail("unknown call kind \(call.k)")
            return ""
        }
    }

    // MARK: - the test

    func testEveryIsolatedCallMatchesTheReference() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "difftest",
                                                  withExtension: "json"))
        let fx = try JSONDecoder().decode(DiffFixture.self, from: try Data(contentsOf: url))
        XCTAssertEqual(fx.generator, "adaptive_engine.js v2.26.0",
                       "the fixture was written by a different engine")
        XCTAssertEqual(fx.method, "isolated-call",
                       "the trajectory method is the one this wave replaced")
        XCTAssertGreaterThanOrEqual(fx.cases.count, 10_000,
                                    "the differential must be at least 10 000 calls")

        // Pre-states are parsed once: they come from the reference, and a
        // divergence in parsing them would masquerade as an engine divergence.
        let states = try fx.states.map { try Self.parseState($0) }
        // A pre-state must survive the round trip, or the comparison below is
        // measuring the parser rather than the engine.
        for (i, s) in states.enumerated() {
            XCTAssertEqual(Self.canon(s), fx.states[i],
                           "pre-state \(i) did not round-trip through the canonical form")
        }

        struct Mismatch { let index: Int; let got: String; let want: String }
        var mismatches: [Mismatch] = []
        for (i, c) in fx.cases.enumerated() {
            let got = try Self.run(states[c.s], c.c)
            if Self.fnv(got) != c.d {
                mismatches.append(Mismatch(index: i, got: got,
                                           want: c.r ?? "(digest \(c.d))"))
            }
        }
        if !mismatches.isEmpty {
            // The point of the isolated method: a COUNT of causes, and the
            // first few spelled out rather than folded into one number.
            for m in mismatches.prefix(5) {
                let (i, got, want) = (m.index, m.got, m.want)
                let call = fx.cases[i].c
                XCTFail("""
                    case \(i) (\(call.k)) diverged
                      pre  : \(fx.states[fx.cases[i].s])
                      got  : \(got)
                      want : \(want)
                      explain: node reference/difftest.js --explain \(i)
                    """)
            }
        }
        XCTAssertEqual(mismatches.count, 0,
                       "\(mismatches.count) of \(fx.cases.count) isolated calls diverged")
    }

    /// The sample carries full strings, so a typical failure is readable
    /// straight out of the fixture. This asserts the sample is really there —
    /// a fixture regenerated without it would silently lose the diagnosis.
    func testTheFixtureCarriesADiagnosticSample() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "difftest",
                                                  withExtension: "json"))
        let fx = try JSONDecoder().decode(DiffFixture.self, from: try Data(contentsOf: url))
        XCTAssertGreaterThanOrEqual(fx.cases.filter { $0.r != nil }.count, 100)
        for c in fx.cases where c.r != nil {
            XCTAssertEqual(Self.fnv(try XCTUnwrap(c.r)), c.d,
                           "the sample string and its digest disagree in the fixture itself")
        }
    }
}
