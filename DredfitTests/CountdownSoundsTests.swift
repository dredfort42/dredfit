//
//  CountdownSoundsTests.swift
//  DredfitTests
//

import XCTest
import AVFoundation
@testable import Dredfit

@MainActor
final class CountdownSoundsTests: XCTestCase {

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

    // MARK: - Format

    func testTonesAreValidMonoPCMWav() {
        for tone in [SignalTone.tick, SignalTone.go, SignalTone.switchSides] {
            XCTAssertEqual(String(bytes: tone[0..<4], encoding: .ascii), "RIFF")
            XCTAssertEqual(String(bytes: tone[8..<12], encoding: .ascii), "WAVE")
            XCTAssertEqual(le16(tone, 20), 1, "linear PCM")
            XCTAssertEqual(le16(tone, 22), 1, "mono")
            XCTAssertEqual(le32(tone, 24), SignalTone.sampleRate)
            XCTAssertEqual(le16(tone, 34), 16, "bits per sample")
            XCTAssertEqual(le32(tone, 40), tone.count - 44,
                           "data chunk size must match the actual payload")
        }
    }

    func testTonesArePlayableAtTheExpectedDuration() throws {
        let tick = try AVAudioPlayer(data: SignalTone.tick)
        XCTAssertEqual(tick.duration, 0.07, accuracy: 0.01)
        let go = try AVAudioPlayer(data: SignalTone.go)
        XCTAssertEqual(go.duration, 0.09 + 0.22, accuracy: 0.01)
        let switchSides = try AVAudioPlayer(data: SignalTone.switchSides)
        XCTAssertEqual(switchSides.duration, 0.09 + 0.22, accuracy: 0.01)
    }

    // MARK: - Loudness and envelope

    func testTonesAreNearFullScale() {
        let tickPeak = samples(SignalTone.tick).map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(tickPeak, Int(0.8 * 32_767), "the tick must not whisper")
        let goPeak = samples(SignalTone.go).map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(goPeak, Int(0.95 * 32_767), "the finale plays at full scale")
    }

    func testGoStandsOutFromTick() {
        XCTAssertGreaterThan(SignalTone.go.count, SignalTone.tick.count * 3)
        let tickPeak = samples(SignalTone.tick).map { abs(Int($0)) }.max() ?? 0
        let goPeak = samples(SignalTone.go).map { abs(Int($0)) }.max() ?? 0
        XCTAssertGreaterThan(goPeak, tickPeak)
    }

    /// The switch tone (issue #35) must be the go's mirror — falling where
    /// the go rises — or eyes-closed stretching cannot tell "switch sides"
    func testSwitchToneFallsWhereGoRises() {
        func crossings<S: Sequence>(_ s: S) -> Int where S.Element == Int16 {
            zip(Array(s), Array(s).dropFirst()).filter { ($0 < 0) != ($1 < 0) }.count
        }
        let go = samples(SignalTone.go)
        let sw = samples(SignalTone.switchSides)
        XCTAssertEqual(go.count, sw.count, "same prominence: a boundary signal, not a tick")
        XCTAssertGreaterThan(crossings(go.suffix(2000)), crossings(go.prefix(2000)),
                             "the go must rise")
        XCTAssertGreaterThan(crossings(sw.prefix(2000)), crossings(sw.suffix(2000)),
                             "the switch tone must fall")
    }

    func testToneEdgesAreClickFree() {
        for tone in [SignalTone.tick, SignalTone.go, SignalTone.switchSides] {
            let all = samples(tone)
            XCTAssertLessThan(abs(Int(all.first ?? .max)), 1_000)
            XCTAssertLessThan(abs(Int(all.last ?? .max)), 1_000)
        }
    }
}
