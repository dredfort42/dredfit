//
//  Each signal as a pair: the tone (silenced by the mute switch) and its
//  haptic counterpart (the silent-mode channel), behind the one sounds
//  toggle. The pairs live here so WorkoutFlowView's wrappers stay one line
//  each — the flow file sits at the lint ceiling.
//

import UIKit

@MainActor
enum WorkoutSignals {

    // Held, not built per firing, and re-primed after every one. The Taptic
    // Engine idles between countdowns — a rest is 60–120 s and the ticks are
    // its last three seconds — and an unprepared generator pays the engine's
    // wake-up on its first impulse, so the first tick of every countdown
    // arrived after its second. The tone half of each pair has bought that
    // cost ahead of time since #84 (`CountdownSounds.prime()`); the haptic
    // half, which is the whole channel in silent mode, never did
    // (UX review 05.09.2026).
    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private static let notice = UINotificationFeedbackGenerator()

    /// Warms every generator, including the ones the caller is not about to
    /// use: a countdown ends `tick, tick, tick, go`, and the go is a
    /// different generator than the ticks.
    ///
    /// Worth calling a second or two BEFORE a countdown reaches its signalling
    /// window — `prepare()` holds the engine for a few seconds only, so this
    /// is not the same kind of one-off as the audio session's `prime()`.
    static func prime() {
        light.prepare()
        medium.prepare()
        rigid.prepare()
        notice.prepare()
    }

    /// One second of the countdown — the lightest touch.
    static func tick(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playTick()
        light.impactOccurred()
        prime()
    }

    /// Something starts.
    static func go(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playGo()
        notice.notificationOccurred(.success)
        prime()
    }

    /// Change sides — its own haptic weight, so silent mode can tell it
    /// from a tick.
    static func switchSides(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playSwitch()
        medium.impactOccurred()
        prime()
    }

    /// The hold is over — release. `.rigid`, so silent mode can tell "stop
    /// holding" from both the tick and the go.
    static func done(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playDone()
        rigid.impactOccurred()
        prime()
    }

    /// The workout is assembled.
    static func workoutDone(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playWorkoutDone()
        notice.notificationOccurred(.success)
        prime()
    }

    /// A milestone was earned. One `.success` only: the tone itself is the
    /// celebration, and a delayed second impulse would need timer machinery
    /// for marginal gain.
    static func milestone(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playMilestone()
        notice.notificationOccurred(.success)
        prime()
    }
}
