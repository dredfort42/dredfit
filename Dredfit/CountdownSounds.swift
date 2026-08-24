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
    private let done: AVAudioPlayer?
    private let workoutDone: AVAudioPlayer?
    private let milestone: AVAudioPlayer?
    // No player for SignalTone.reminder: it never plays in-app — it exists
    // for the notification channel.

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: .mixWithOthers)
        tick = try? AVAudioPlayer(data: SignalTone.tick)
        go = try? AVAudioPlayer(data: SignalTone.go)
        switchSides = try? AVAudioPlayer(data: SignalTone.switchSides)
        done = try? AVAudioPlayer(data: SignalTone.done)
        workoutDone = try? AVAudioPlayer(data: SignalTone.workoutDone)
        milestone = try? AVAudioPlayer(data: SignalTone.milestone)
        tick?.prepareToPlay()
        go?.prepareToPlay()
        switchSides?.prepareToPlay()
        done?.prepareToPlay()
        workoutDone?.prepareToPlay()
        milestone?.prepareToPlay()
    }

    /// Construction is the actual work (category, tone generation,
    /// prepareToPlay); calling this early means the first tick pays none of it.
    func prime() {}

    func playTick() { play(tick) }
    func playGo() { play(go) }
    func playSwitch() { play(switchSides) }
    func playDone() { play(done) }
    func playWorkoutDone() { play(workoutDone) }
    func playMilestone() { play(milestone) }

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
///
/// The "Minimal+" set (issue #84): the same C-major language — a fifth up
/// means start, a flat double tap means switch — but every note is an
/// additive pair (fundamental + a 15% octave harmonic) with an exponential
/// decay, so the tones carry warmth and survive over music instead of
/// piercing through it. Peaks sit below full scale on a strict loudness
/// hierarchy: the frequent is quiet, the rare is bright —
/// tick < switchSides = done < go < workoutDone < milestone.
///
/// Every signal owns a *shape*, not just a melody: one quiet note counts,
/// two notes up start, two notes down from above release, three notes up
/// close the workout, an arpeggio crowns a milestone — and two fast notes
/// at one pitch change the side.
enum SignalTone {

    static let sampleRate = 44_100

    // The vocabulary's four pitches.
    private static let c6 = 1046.50
    private static let e6 = 1318.51
    private static let g6 = 1567.98
    private static let c7 = 2093.00

    /// One second of the 3-2-1 countdown: a short G6, the quietest voice.
    static let tick = mix([(start: 0, samples: note(hz: g6, seconds: 0.18, tau: 0.040))],
                          total: 0.20, peak: 0.32)

    /// Something starts: the fifth up, C6 → G6.
    static let go = mix([(start: 0, samples: note(hz: c6, seconds: 0.30, tau: 0.080)),
                         (start: 0.095, samples: note(hz: g6, seconds: 0.45, tau: 0.128))],
                        total: 0.55, peak: 0.80)

    /// Switch sides: two fast taps on one pitch — G6, G6, 75 ms apart
    /// against the 95–110 ms of the melodic pairs. A rhythmic identity, not
    /// a contour: the mirrored go it replaces was still a two-note melody
    /// and, eyes closed mid-stretch, read as either a start or a release.
    static let switchSides = mix([(start: 0, samples: note(hz: g6, seconds: 0.18, tau: 0.060)),
                                  (start: 0.075, samples: note(hz: g6, seconds: 0.40, tau: 0.130))],
                                 total: 0.48, peak: 0.66)

    /// The effort is over: top-down C7 → G6 — light, not another direction
    /// of the two already in use.
    static let done = mix([(start: 0, samples: note(hz: c7, seconds: 0.30, tau: 0.072)),
                           (start: 0.110, samples: note(hz: g6, seconds: 0.50, tau: 0.136))],
                          total: 0.62, peak: 0.66)

    /// The workout is assembled: the go's motif completed by the octave,
    /// C6 → G6 → C7.
    static let workoutDone = mix([(start: 0, samples: note(hz: c6, seconds: 0.40, tau: 0.112)),
                                  (start: 0.130, samples: note(hz: g6, seconds: 0.45, tau: 0.128)),
                                  (start: 0.260, samples: note(hz: c7, seconds: 0.70, tau: 0.176))],
                                 total: 1.00, peak: 0.85)

    /// A milestone: the major arpeggio C6–E6–G6–C7 with a −6 dB echo of the
    /// top note — the brightest and rarest voice of the set.
    static let milestone = mix([(start: 0, samples: note(hz: c6, seconds: 0.45, tau: 0.112)),
                                (start: 0.120, samples: note(hz: e6, seconds: 0.45, tau: 0.120)),
                                (start: 0.240, samples: note(hz: g6, seconds: 0.50, tau: 0.136)),
                                (start: 0.360, samples: note(hz: c7, seconds: 0.85, tau: 0.224)),
                                (start: 0.520, samples: note(hz: c7, seconds: 0.80, tau: 0.240,
                                                            amp: 0.5))],
                               total: 1.35, peak: 0.88)

    /// The reminder: the go's motif slowed down and softened. Not played
    /// in-app — it exists for the notification channel (stage C of #84).
    static let reminder = mix([(start: 0, samples: note(hz: c6, seconds: 0.50, tau: 0.144)),
                               (start: 0.140, samples: note(hz: g6, seconds: 0.90, tau: 0.240))],
                              total: 1.05, peak: 0.50)

    /// One additive note: fundamental + 15% octave harmonic under an
    /// exponential decay. A 4 ms half-cosine ramp opens it and a 5 ms one
    /// closes it — the tail has decayed to 2–3% of the peak by the cut, but
    /// the last note of a sound has no successor to mask even that.
    static func note(hz: Double, seconds: Double, tau: Double,
                     amp: Double = 1.0) -> [Double] {
        let rate = Double(sampleRate)
        let count = Int(seconds * rate)
        let attack = 176                        // 4 ms
        let release = min(220, count / 3)       // 5 ms
        var out = [Double](repeating: 0, count: count)
        for i in 0..<count {
            let t = Double(i) / rate
            var value = (sin(2 * .pi * hz * t) + 0.15 * sin(4 * .pi * hz * t))
                * exp(-t / tau) * amp
            if i < attack {
                value *= 0.5 - 0.5 * cos(.pi * Double(i) / Double(attack - 1))
            }
            if count - i <= release {
                value *= 0.5 - 0.5 * cos(.pi * Double(count - i) / Double(release))
            }
            out[i] = value
        }
        return out
    }

    /// Overlap-add of notes into one buffer, then one normalization of the
    /// MIXED signal to the sound's target peak — per note would break the
    /// loudness hierarchy the set is built on. Clamped before Int16: a peak
    /// past 1.0 must distort at the edit, not trap at the first countdown.
    static func mix(_ events: [(start: Double, samples: [Double])],
                    total: Double, peak: Double) -> Data {
        let rate = Double(sampleRate)
        var buffer = [Double](repeating: 0, count: Int(total * rate))
        for event in events {
            let offset = Int(event.start * rate)
            for (i, value) in event.samples.enumerated() where offset + i < buffer.count {
                buffer[offset + i] += value
            }
        }
        let maxAbs = buffer.map(abs).max() ?? 0
        let scale = maxAbs > 0 ? peak / maxAbs : 0
        let samples = buffer.map { value -> Int16 in
            let clamped = min(max(value * scale, -1.0), 1.0)
            return Int16((clamped * 32_767).rounded())
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
