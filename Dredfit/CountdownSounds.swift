//
//  CountdownSounds.swift
//  Dredfit
//
//  Played at *media* volume: a system sound would follow the ringer volume,
//  which routinely sits near zero while music plays.
//

import AVFoundation

/// `.ambient` + `.mixWithOthers` mixes with whatever is already playing
/// instead of pausing it; the silent switch still mutes it (haptics remain
/// the silent-mode channel).
@MainActor
final class CountdownSounds {

    static let shared = CountdownSounds()

    private let tick: AVAudioPlayer?
    private let go: AVAudioPlayer?
    private let switchSides: AVAudioPlayer?

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        tick = try? AVAudioPlayer(data: SignalTone.tick)
        go = try? AVAudioPlayer(data: SignalTone.go)
        switchSides = try? AVAudioPlayer(data: SignalTone.switchSides)
        tick?.prepareToPlay()
        go?.prepareToPlay()
        switchSides?.prepareToPlay()
    }

    /// Construction is the actual work (category, tone generation,
    /// prepareToPlay); calling this early means the first tick pays none of it.
    func prime() {}

    func playTick() { play(tick) }
    func playGo() { play(go) }
    func playSwitch() { play(switchSides) }

    /// Rewinds first: ticks arrive one second apart and a firing must not be
    /// swallowed because the previous one is still tailing off.
    private func play(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

/// Generated WAV data rather than shipped asset files, so the frequencies
/// and envelope stay reviewable and unit-testable.
enum SignalTone {

    static let tick = wav(segments: [(hz: 1568.0, seconds: 0.07)], amplitude: 0.85)

    /// A two-tone rise (C6 → G6), longer and louder than the tick.
    static let go = wav(segments: [(hz: 1046.5, seconds: 0.09), (hz: 1568.0, seconds: 0.22)],
                        amplitude: 1.0)

    /// The go inverted (G6 → C6), so eyes-closed stretching can tell "switch
    /// sides" from "new position" without looking.
    static let switchSides = wav(segments: [(hz: 1568.0, seconds: 0.09), (hz: 1046.5, seconds: 0.22)],
                                 amplitude: 1.0)

    static let sampleRate = 44_100

    /// Mono 16-bit PCM WAV. The attack/release ramps keep segment edges from
    /// clicking.
    static func wav(segments: [(hz: Double, seconds: Double)], amplitude: Double) -> Data {
        let rate = Double(sampleRate)
        var samples: [Int16] = []
        for segment in segments {
            let count = Int(segment.seconds * rate)
            let attack = min(Int(0.005 * rate), count / 4)
            let release = min(Int(0.015 * rate), count / 3)
            for i in 0..<count {
                var value = sin(2 * .pi * segment.hz * Double(i) / rate) * amplitude
                if i < attack { value *= Double(i) / Double(attack) }
                if count - i < release { value *= Double(count - i) / Double(release) }
                // Clamped: Int16(Double) traps out of range, and these tones
                // are built in a `static let` — an amplitude past 1.0 would
                // crash at the first countdown, not at the edit.
                samples.append(Int16(min(max(value * 32_767, -32_767), 32_767)))
            }
        }
        return wavFile(samples: samples)
    }

    private static func wavFile(samples: [Int16]) -> Data {
        let dataSize = samples.count * 2
        var out = Data(capacity: 44 + dataSize)
        out.append(contentsOf: Array("RIFF".utf8))
        appendLE(UInt32(36 + dataSize), to: &out)
        out.append(contentsOf: Array("WAVE".utf8))
        out.append(contentsOf: Array("fmt ".utf8))
        appendLE(UInt32(16), to: &out)                 // PCM chunk size
        appendLE(UInt16(1), to: &out)                  // linear PCM
        appendLE(UInt16(1), to: &out)                  // mono
        appendLE(UInt32(sampleRate), to: &out)
        appendLE(UInt32(sampleRate * 2), to: &out)     // byte rate
        appendLE(UInt16(2), to: &out)                  // block align
        appendLE(UInt16(16), to: &out)                 // bits per sample
        out.append(contentsOf: Array("data".utf8))
        appendLE(UInt32(dataSize), to: &out)
        for sample in samples { appendLE(UInt16(bitPattern: sample), to: &out) }
        return out
    }

    private static func appendLE<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }
}
