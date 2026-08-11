//
//  CountdownSoundsTests.swift
//  DredfitTests
//
//  The "Minimal+" set of issue #84: seven generated sounds, one synthesis
//  rule, a strict loudness hierarchy. Everything here reads the WAV bytes —
//  the tones are code, so their frequencies, peaks and envelopes are facts
//  a test can hold.
//

import XCTest
import AVFoundation
@testable import Dredfit

@MainActor
final class CountdownSoundsTests: XCTestCase {

    private struct Sound {
        let name: String
        let tone: Data
        let seconds: Double
        let peak: Double
    }

    /// Every sound of the set with its spec'd duration and peak target.
    private let set: [Sound] = [
        Sound(name: "tick", tone: SignalTone.tick, seconds: 0.20, peak: 0.32),
        Sound(name: "go", tone: SignalTone.go, seconds: 0.55, peak: 0.80),
        Sound(name: "switchSides", tone: SignalTone.switchSides, seconds: 0.55, peak: 0.66),
        Sound(name: "done", tone: SignalTone.done, seconds: 0.62, peak: 0.66),
        Sound(name: "workoutDone", tone: SignalTone.workoutDone, seconds: 1.00, peak: 0.85),
        Sound(name: "milestone", tone: SignalTone.milestone, seconds: 1.35, peak: 0.88),
        Sound(name: "reminder", tone: SignalTone.reminder, seconds: 1.05, peak: 0.50)
    ]

    // MARK: - WAV plumbing

    private func le16(_ data: Data, _ offset: Int) -> Int {
        Int(data[offset]) | Int(data[offset + 1]) << 8
    }

    private func le32(_ data: Data, _ offset: Int) -> Int {
        le16(data, offset) | le16(data, offset + 2) << 16
    }

    private func samples(_ data: Data) -> [Int16] {
        stride(from: 44, to: data.count, by: 2).map {
            Int16(bitPattern: UInt16(data[$0]) | UInt16(data[$0 + 1]) << 8)
        }
    }

    private func peak(_ data: Data) -> Double {
        Double(samples(data).map { abs(Int($0)) }.max() ?? 0) / 32_767
    }

    private func crossings<S: Sequence>(_ s: S) -> Int where S.Element == Int16 {
        zip(Array(s), Array(s).dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
    }

    // MARK: - Format

    func testTonesAreValidMonoPCMWav() {
        for sound in set {
            let tone = sound.tone
            XCTAssertEqual(String(bytes: tone[0..<4], encoding: .ascii), "RIFF", sound.name)
            XCTAssertEqual(String(bytes: tone[8..<12], encoding: .ascii), "WAVE", sound.name)
            XCTAssertEqual(le16(tone, 20), 1, "\(sound.name): linear PCM")
            XCTAssertEqual(le16(tone, 22), 1, "\(sound.name): mono")
            XCTAssertEqual(le32(tone, 24), SignalTone.sampleRate, sound.name)
            XCTAssertEqual(le16(tone, 34), 16, "\(sound.name): bits per sample")
            XCTAssertEqual(le32(tone, 40), tone.count - 44,
                           "\(sound.name): data chunk size must match the actual payload")
        }
    }

    func testTonesArePlayableAtTheExpectedDuration() throws {
        for sound in set {
            let player = try AVAudioPlayer(data: sound.tone)
            XCTAssertEqual(player.duration, sound.seconds, accuracy: 0.01, sound.name)
        }
    }

    // MARK: - Loudness: the hierarchy is the design

    /// Peaks land on their targets, and the order holds: the frequent is
    /// quiet, the rare is bright.
    func testPeaksMatchTheHierarchy() {
        for sound in set {
            XCTAssertEqual(peak(sound.tone), sound.peak, accuracy: sound.peak * 0.02,
                           "\(sound.name): peak off its target")
        }
        let tick = peak(SignalTone.tick)
        let switchSides = peak(SignalTone.switchSides)
        let done = peak(SignalTone.done)
        let go = peak(SignalTone.go)
        let workoutDone = peak(SignalTone.workoutDone)
        let milestone = peak(SignalTone.milestone)
        XCTAssertLessThan(tick, switchSides)
        XCTAssertEqual(switchSides, done, accuracy: 0.01,
                       "the two mid-hierarchy signals share a level")
        XCTAssertLessThan(done, go)
        XCTAssertLessThan(go, workoutDone)
        XCTAssertLessThan(workoutDone, milestone)
    }

    func testGoStandsOutFromTick() {
        XCTAssertGreaterThan(SignalTone.go.count, SignalTone.tick.count * 2)
        XCTAssertGreaterThan(peak(SignalTone.go), peak(SignalTone.tick))
    }

    // MARK: - Shape: direction is meaning

    /// The switch tone (issue #35) must be the go's mirror — falling where
    /// the go rises — or eyes-closed stretching cannot tell "switch sides".
    func testSwitchToneFallsWhereGoRises() {
        let go = samples(SignalTone.go)
        let sw = samples(SignalTone.switchSides)
        XCTAssertEqual(go.count, sw.count, "same prominence: a boundary signal, not a tick")
        XCTAssertGreaterThan(crossings(go.suffix(2000)), crossings(go.prefix(2000)),
                             "the go must rise")
        XCTAssertGreaterThan(crossings(sw.prefix(2000)), crossings(sw.suffix(2000)),
                             "the switch tone must fall")
    }

    /// "Done" comes down from above — C7 into G6: the effort is released,
    /// not a third direction colliding with go and switch.
    func testDoneFalls() {
        let done = samples(SignalTone.done)
        XCTAssertGreaterThan(crossings(done.prefix(2000)), crossings(done.suffix(2000)),
                             "done must open high and settle low")
    }

    /// The finale completes the go's motif with the octave: it must end
    /// higher than it starts.
    func testWorkoutDoneAscends() {
        let tone = samples(SignalTone.workoutDone)
        // 0.85–0.90 s: past the C6 (ends 0.40) and the G6 (ends 0.58) —
        // the C7 alone, before the trailing silence.
        let lateStart = Int(0.85 * Double(SignalTone.sampleRate))
        let late = Array(tone[lateStart..<(lateStart + 2000)])
        XCTAssertGreaterThan(crossings(late), crossings(tone.prefix(2000)),
                             "the finale must end above its start")
    }

    /// The milestone's echo: the fifth note is the fourth at half voice.
    func testMilestoneEchoIsQuieter() {
        let fourth = SignalTone.note(hz: 2093.00, seconds: 0.85, tau: 0.224)
        let fifth = SignalTone.note(hz: 2093.00, seconds: 0.80, tau: 0.240, amp: 0.5)
        let fourthPeak = fourth.map(abs).max() ?? 0
        let fifthPeak = fifth.map(abs).max() ?? 0
        XCTAssertEqual(fifthPeak, fourthPeak * 0.5, accuracy: fourthPeak * 0.05,
                       "the echo sits ~6 dB under the note it repeats")
    }

    // MARK: - Envelope and determinism

    func testToneEdgesAreClickFree() {
        for sound in set {
            let all = samples(sound.tone)
            XCTAssertLessThan(abs(Int(all.first ?? .max)), 1_000, sound.name)
            XCTAssertLessThan(abs(Int(all.last ?? .max)), 1_000, sound.name)
        }
    }

    /// No RNG anywhere in the set: two independent builds are byte-identical.
    func testGenerationIsDeterministic() {
        let first = SignalTone.mix(
            [(start: 0, samples: SignalTone.note(hz: 1046.50, seconds: 0.30, tau: 0.080)),
             (start: 0.095, samples: SignalTone.note(hz: 1567.98, seconds: 0.45, tau: 0.128))],
            total: 0.55, peak: 0.80)
        let second = SignalTone.mix(
            [(start: 0, samples: SignalTone.note(hz: 1046.50, seconds: 0.30, tau: 0.080)),
             (start: 0.095, samples: SignalTone.note(hz: 1567.98, seconds: 0.45, tau: 0.128))],
            total: 0.55, peak: 0.80)
        XCTAssertEqual(first, second, "the synthesis must be fully deterministic")
        XCTAssertEqual(first, SignalTone.go, "and reproduce the shipped tone exactly")
    }
}
