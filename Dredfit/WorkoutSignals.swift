//
//  Each signal as a pair: the tone (silenced by the mute switch) and its
//  haptic counterpart (the silent-mode channel), behind the one sounds
//  toggle. The pairs live here so WorkoutFlowView's wrappers stay one line
//  each — the flow file sits at the lint ceiling.
//

import UIKit

@MainActor
enum WorkoutSignals {

    /// One second of the countdown — the lightest touch.
    static func tick(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playTick()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Something starts.
    static func go(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playGo()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// Change sides — its own haptic weight, so silent mode can tell it
    /// from a tick.
    static func switchSides(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playSwitch()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    /// The hold is over — release. `.rigid`, so silent mode can tell "stop
    /// holding" from both the tick and the go.
    static func done(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playDone()
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
    }

    /// The workout is assembled.
    static func workoutDone(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playWorkoutDone()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// A milestone was earned. One `.success` only: the tone itself is the
    /// celebration, and a delayed second impulse would need timer machinery
    /// for marginal gain.
    static func milestone(_ enabled: Bool) {
        guard enabled else { return }
        CountdownSounds.shared.playMilestone()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}
