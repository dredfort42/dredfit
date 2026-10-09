// Probe driver: everything persisted goes through the app's own types
// (AppData, AppSettings, WorkoutRecord, WorkoutSnapshot — linked, not
// copied) and DredfitCore, with the same plain JSONEncoder/JSONDecoder the
// app uses. See README.md for what each command writes.

import Foundation
import DredfitCore

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func write(_ data: Data, to path: String) {
    do { try data.write(to: URL(fileURLWithPath: path), options: .atomic) } catch {
        fail("cannot write \(path): \(error)")
    }
}

func read(_ path: String) -> Data {
    do { return try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
        fail("cannot read \(path): \(error)")
    }
}

func printJSON(_ data: Data) {
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
}

let sorted: JSONEncoder = {
    let e = JSONEncoder()
    e.outputFormatting = [.sortedKeys]
    return e
}()

/// Mirror of `AppStore.positions(of:)` (ios/Dredfit/AppStore+Derived.swift).
func positions(of state: EngineState) -> [Pattern: RecordedPosition] {
    var out: [Pattern: RecordedPosition] = [:]
    for p in Pattern.allCases {
        let pos = state.position(p)
        out[p] = RecordedPosition(variation: pos.variation, sets: pos.sets, dose: pos.dose,
                                  sub: pos.sub > 0 ? pos.sub : nil,
                                  cut: pos.cut > 0 ? pos.cut : nil)
    }
    return out
}

func date(_ iso: String) -> Date {
    guard let d = ISO8601DateFormatter().date(from: iso) else { fail("bad date \(iso)") }
    return d
}

// MARK: - sessions

func sessions(_ out: String) {
    var list: [Session] = []
    var notes: [String] = []
    list.append(Engine.generateSession(.initial))
    notes.append("[0] initial")
    var bar = EngineState.initial
    bar.hasBar = true
    // The bar takes the pull slot on odd counters only (Session.swift `useBar`).
    bar.counter = 1
    let barSession = Engine.generateSession(bar)
    list.append(barSession)
    notes.append("[1] hasBar = true, counter 1: pull_bar shown = "
                 + "\(barSession.exercises.contains { $0.pattern == .pullBar })")

    var state = EngineState.initial
    var firstLoads: (Int, Session)?
    var firstProbe: (Int, Session)?
    for n in 1...60 {
        let session = Engine.generateSession(state)
        if firstLoads == nil, session.exercises.contains(where: { $0.loads != nil }) {
            firstLoads = (n, session)
        }
        if firstProbe == nil, session.exercises.contains(where: { $0.probe != nil }) {
            firstProbe = (n, session)
        }
        if firstLoads != nil && firstProbe != nil { break }
        // Mostly "more", every third "plan".
        let result: FeedbackResult = n % 3 == 0 ? .plan : .more
        state = Engine.applyFeedback(state: state, session: session, result: result)
    }
    if let (n, s) = firstLoads {
        list.append(s)
        let p = s.exercises.filter { $0.loads != nil }.map(\.pattern.rawValue)
        notes.append("[\(list.count - 1)] run session \(n): first with uneven loads (\(p))")
    } else {
        notes.append("no session with loads within 60")
    }
    if let (n, s) = firstProbe {
        if n != firstLoads?.0 { list.append(s) }
        let p = s.exercises.filter { $0.probe != nil }.map(\.pattern.rawValue)
        notes.append("[\(list.count - 1)] run session \(n): first with a probe (\(p))")
    } else {
        notes.append("no session with a probe within 60")
    }
    do { write(try JSONEncoder().encode(list), to: out) } catch { fail("encode: \(error)") }
    print("wrote \(list.count) sessions to \(out)")
    notes.forEach { print("  " + $0) }
}

// MARK: - backup

func backup(_ out: String, _ pendingPath: String) {
    var state = EngineState.initial
    var records: [WorkoutRecord] = []
    let start = date("2026-09-01T10:00:00Z")
    let results: [FeedbackResult] = [.plan, .more, .plan, .less, .more, .plan]
    var beforeLast = state
    var lastSession = Engine.generateSession(state)
    for (i, result) in results.enumerated() {
        let session = Engine.generateSession(state)
        let ex = session.exercises
        let a = ex[0].pattern, b = ex[1].pattern, c = ex[2].pattern
        var overrides: [Pattern: Double] = [:]
        var skipped: Set<Pattern> = []
        var setsSkipped: [Pattern: Int] = [:]
        var probes: [Pattern: Int] = [:]
        var raised: [Pattern: Int] = [:]
        var record = WorkoutRecord(sessionNumber: session.sessionNumber,
                                   date: start.addingTimeInterval(Double(i) * 2 * 86_400),
                                   result: result)
        switch i {
        case 0:
            overrides[a] = Double(ex[0].load - 1)
            record.actuals = [a: ex[0].load - 1]
            record.setActuals = [a: Array(repeating: ex[0].load, count: ex[0].sets - 1) + [ex[0].load - 3]]
            record.durationSec = 1_534
            record.warmupSec = 360
            record.cooldownSec = 0
            record.healthExported = true
        case 1:
            setsSkipped[b] = 1
            record.setsSkipped = [b: 1]
            record.skippedSetIndices = [b: [ex[1].sets - 1]]
            record.skippedWithNumberIndices = [b: [ex[1].sets - 1]]
            raised[c] = 1
            record.raisedSteps = [c: 1]
            record.raisedLanded = [c: 1]
            record.durationSec = 1_710
        case 2:
            skipped = [c]
            record.skipped = [c]
            record.interrupted = c
            record.heldBack = [.pushH]
            record.raisedSteps = [a: 2]
            record.raisedLanded = [:]
        case 3:
            record.discomfort = [b]
            skipped = [b]
            record.skipped = [b]
            probes[a] = 6
            record.probes = [a: 6]
            record.warmupSec = 412
            record.cooldownSec = 300
        default:
            record.actuals = [b: ex[1].load + 1]
            overrides[b] = Double(ex[1].load + 1)
            record.healthExported = true
        }
        if i == results.count - 1 { beforeLast = state; lastSession = session }
        state = Engine.applyFeedback(state: state, session: session, result: result,
                                     overrides: overrides, skipped: skipped,
                                     setsSkipped: setsSkipped, gapDays: nil,
                                     probes: probes, raised: raised)
        record.totalProgressAfter = Engine.totalProgress(state)
        record.exercises = session.exercises
        record.positionsAfter = positions(of: state)
        records.append(record)
    }

    var settings = AppSettings()
    settings.restWeekdays = [1, 4, 7]
    settings.soundsEnabled = false
    settings.reminderEnabled = true
    settings.reminderHour = 7
    settings.reminderMinute = 30
    settings.healthEnabled = true
    settings.healthExportedThrough = 3
    settings.bodyMassKg = 72.5
    settings.bodyMassFromHealth = true
    settings.bodyMassDate = date("2026-08-30T08:15:00Z")
    settings.watchRecordsWorkouts = true
    settings.onboardingCompleted = true
    settings.careAcknowledgedAt = date("2026-08-31T19:00:00Z")
    settings.lastReviewRequestAt = date("2026-09-05T12:00:00Z")
    settings.comebackDecidedFor = date("2026-09-09T00:00:00Z")
    settings.weakLinkPromptAnsweredFor = 4
    settings.silentDecayAppliedFor = date("2026-09-09T00:00:00Z")
    settings.migrationNoticePending = false
    settings.hasOpenedTechnique = true
    settings.hasReportedOwnNumber = true
    settings.hiddenBlockMoveIDs = ["a", "b"]
    settings.playsTonesInSilentMode = true
    settings.appearance = .dark
    settings.comebackDecidedAtGap = 20
    settings.planMoves = PlanMoves(session: state.counter + 1, byHand: [.squat], byRating: [])
    settings.ratingMoves = PlanMoves(session: state.counter, byHand: [.calf],
                                     byRating: [.hinge, .coreRot])
    settings.lastRatingUndo = RatingUndo(state: beforeLast, session: lastSession)

    let data = AppData(engineState: state, records: records, settings: settings)
    do { write(try JSONEncoder().encode(data), to: out) } catch { fail("encode: \(error)") }
    print("wrote \(out): \(records.count) records, counter \(state.counter), "
          + "totalProgress \(Engine.totalProgress(state))")

    // The state-file shape: the same data plus an unfinished workout.
    let next = Engine.generateSession(state)
    let p0 = next.exercises[0].pattern, p1 = next.exercises[1].pattern
    let snapshot = WorkoutSnapshot(
        sessionNumber: next.sessionNumber, exIndex: 1, setIndex: 2,
        restEndDate: date("2026-09-13T10:21:30Z"), restTotalSec: 120, restPlannedSec: 90,
        setActuals: [p0: [10, 9, 9]], setsSkipped: [p1: 1],
        skippedSetIndices: [p1: [1]], skippedWithNumberIndices: [p1: [1]],
        probes: [p0: 5], actuals: [p0: 9], skipped: [p1], discomfort: [p1],
        workoutStart: date("2026-09-13T10:00:00Z"), savedAt: date("2026-09-13T10:20:00Z"),
        fingerprint: WorkoutSnapshot.fingerprint(of: next), atFeedback: false,
        atExerciseSummary: true, holdDeclaredSec: 35, approxSets: [0, 2], tapEndedSets: [2],
        holdMeasuredSec: [0: 30, 2: 25], interrupted: p1, warmupSec: 365, cooldownSec: 0,
        awaySec: 42, raisedSteps: [p0: 1])
    let pending = AppData(engineState: state, records: records, settings: settings,
                          pendingWorkout: snapshot)
    do { write(try JSONEncoder().encode(pending), to: pendingPath) } catch { fail("encode: \(error)") }
    print("wrote \(pendingPath): same + pendingWorkout (session \(next.sessionNumber))")
}

// MARK: - decode

struct DecodeReport: Encodable {
    let ok = true
    let engineStateReset: Bool
    let settingsUnreadable: Bool
    let engineStateMigrated: Bool
    let droppedRecordCount: Int
    let recordCount: Int
    let counter: Int
    let totalProgress: Int
    let hasPending: Bool
    let settings: AppSettings?
    let engineState: EngineState
    let records: [WorkoutRecord]

    enum CodingKeys: String, CodingKey {
        case ok, engineStateReset, settingsUnreadable, engineStateMigrated, droppedRecordCount
        case recordCount, counter, totalProgress, hasPending, settings, engineState, records
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(ok, forKey: .ok)
        try c.encode(engineStateReset, forKey: .engineStateReset)
        try c.encode(settingsUnreadable, forKey: .settingsUnreadable)
        try c.encode(engineStateMigrated, forKey: .engineStateMigrated)
        try c.encode(droppedRecordCount, forKey: .droppedRecordCount)
        try c.encode(recordCount, forKey: .recordCount)
        try c.encode(counter, forKey: .counter)
        try c.encode(totalProgress, forKey: .totalProgress)
        try c.encode(hasPending, forKey: .hasPending)
        try c.encode(settings, forKey: .settings)   // null when absent/unreadable
        try c.encode(engineState, forKey: .engineState)
        try c.encode(records, forKey: .records)
    }
}

func errorJSON(_ error: Error) -> Data {
    let body: [String: Any] = ["ok": false, "error": String(describing: error)]
    return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]))
        ?? Data("{\"ok\":false}".utf8)
}

func decode(_ path: String) {
    do {
        let d = try JSONDecoder().decode(AppData.self, from: read(path))
        let report = DecodeReport(
            engineStateReset: d.engineStateReset, settingsUnreadable: d.settingsUnreadable,
            engineStateMigrated: d.engineStateMigrated, droppedRecordCount: d.droppedRecordCount,
            recordCount: d.records.count, counter: d.engineState.counter,
            totalProgress: Engine.totalProgress(d.engineState), hasPending: d.pendingWorkout != nil,
            settings: d.settings, engineState: d.engineState, records: d.records)
        printJSON(try sorted.encode(report))
    } catch {
        printJSON(errorJSON(error))
    }
}

func decodeSessions(_ path: String) {
    do {
        let s = try JSONDecoder().decode([Session].self, from: read(path))
        printJSON(try sorted.encode(s))
    } catch {
        printJSON(errorJSON(error))
    }
}

func roundtrip(_ input: String, _ output: String) {
    do {
        let d = try JSONDecoder().decode(AppData.self, from: read(input))
        write(try JSONEncoder().encode(d), to: output)
        print("wrote \(output)")
    } catch {
        printJSON(errorJSON(error))
        exit(1)
    }
}

// MARK: - main

let args = CommandLine.arguments
let usage = "usage: swift-backup-probe sessions <out> | backup <out> <pending-out> | decode <in> | decode-session <in> | roundtrip <in> <out>"
guard args.count >= 3 else { fail(usage) }
switch args[1] {
case "sessions": sessions(args[2])
case "backup":
    guard args.count >= 4 else { fail(usage) }
    backup(args[2], args[3])
case "decode": decode(args[2])
case "decode-session": decodeSessions(args[2])
case "roundtrip":
    guard args.count >= 4 else { fail(usage) }
    roundtrip(args[2], args[3])
default: fail(usage)
}
