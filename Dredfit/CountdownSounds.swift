//
//  CountdownSounds.swift
//  Dredfit
//
//  The audible 3-2-1 countdown, played at *media* volume: a system sound
//  would follow the ringer volume, which routinely sits near zero while
//  music plays at full media volume.
//

import AVFoundation

/// Plays the countdown signals: a short tick on 3-2-1 and a longer two-tone
/// rise at zero. The `.ambient` session mixes with whatever is already
/// playing instead of pausing it, and the silent switch still mutes it
/// (haptics remain the silent-mode channel) — while the signals themselves
/// play at media volume, not ringer volume.
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

    /// Construction is the actual work — the session category, the generated
    /// tones and prepareToPlay all happen in init. Calling this when the
    /// workout flow appears means the first countdown tick pays none of it.
    func prime() {}

    func playTick() { play(tick) }
    func playGo() { play(go) }
    func playSwitch() { play(switchSides) }

    /// Rewinds before playing: ticks arrive one second apart and a firing
    /// must never be swallowed because the previous one is still tailing off.
    private func play(_ player: AVAudioPlayer?) {
        guard let player else { return }
        player.currentTime = 0
        player.play()
    }
}

/// The signal tones as generated WAV data — built once at first use instead
/// of shipped as opaque asset files, so the exact frequencies and envelope
/// live here in reviewable form and the unit tests can hold them to it.
enum SignalTone {

    /// The 3-2-1 tick: one short high beep (G6).
    static let tick = wav(segments: [(hz: 1568.0, seconds: 0.07)], amplitude: 0.85)

    /// The "go" at zero: a two-tone rise (C6 → G6), noticeably longer and
    /// louder than the tick — this is the moment worth not missing.
    static let go = wav(segments: [(hz: 1046.5, seconds: 0.09), (hz: 1568.0, seconds: 0.22)],
                        amplitude: 1.0)

    /// The side-switch pause opener (issue #35): the go inverted — a
    /// two-tone fall (G6 → C6) — so eyes-closed stretching can tell "switch
    /// sides" from "new position" without looking at the screen.
    static let switchSides = wav(segments: [(hz: 1568.0, seconds: 0.09), (hz: 1046.5, seconds: 0.22)],
                                 amplitude: 1.0)

    static let sampleRate = 44_100

    /// Mono 16-bit PCM WAV: consecutive sine segments with short linear
    /// attack/release ramps so segment edges never click.
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
                // are built in a `static let` — an amplitude raised past 1.0
                // would crash at the first countdown, not at the edit.
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
