//
//  Every number here is a fact from DredfitCore, not a marketing round-up:
//  ±1/+2 are EngineConfig.delta*, three shortfalls and −3 are failsToDeload
//  and deloadDrop, "five times in eight workouts" falls out of 8 rotating
//  patterns over 5 slots with a shift of 3. If the engine changes, this
//  screen changes with it.
//

import SwiftUI

struct HowItWorksView: View {
    @Environment(\.dismiss) private var dismiss

    private struct Section: Identifiable {
        let id: Int
        let title: String
        let body: String
    }

    private var sections: [Section] {
        [
            // Rewritten for v3: the single number is gone, and with it the
            // encoding this section used to explain. What a person now has is
            // two plain facts, which is also all the engine has.
            Section(id: 1,
                    title: String(localized: "Variation and dose"),
                    body: String(localized: """
                    Two facts per movement, not one number: WHICH variation you \
                    do, and HOW MUCH of it. Every movement has a ladder of four \
                    to seven variations, and neighbouring rungs stand close \
                    enough together that the next one is never a leap. The dose \
                    is reps per set — or seconds for a hold — and it grows only \
                    to what you have already shown.
                    """)),
            Section(id: 2,
                    title: String(localized: "What your answer does"),
                    body: String(localized: """
                    “On plan” adds a step, “more” adds two, “less” steps \
                    back the movement that made it hard. An exact number for \
                    a single exercise outweighs the overall rating — and when \
                    your sets show more than the plan, the next plan starts \
                    from what you showed. Nothing is estimated: whatever \
                    you are given, you have already done. The plan climbs at \
                    most two steps per workout — and only one wherever the \
                    tissue doing the work needs the slower pace: tendons \
                    remodel on a longer clock than muscle. A step lands on one \
                    set, not on all of them.
                    """)),
            Section(id: 3,
                    title: String(localized: "Deload"),
                    body: String(localized: """
                    Three shortfalls in a row and the dose rolls back three \
                    steps. Not a punishment — a breather, so you come back with \
                    something in reserve.
                    """)),
            Section(id: 4,
                    title: String(localized: "Rotation"),
                    body: String(localized: """
                    Pull is in every workout — that is what keeps your shoulders \
                    balanced. The rest come round in a cycle: over eight workouts \
                    each one turns up five times. With the pull-up bar switched \
                    on, the pull alternates between horizontal and vertical.
                    """)),
            Section(id: 5,
                    title: String(localized: "Weekly rhythm"),
                    body: String(localized: """
                    3–4 workouts a week is the sweet spot: strength grows \
                    while joints and tendons keep up. Muscle adapts in weeks, \
                    tendons in months — rest days protect the slower half.
                    """)),
            Section(id: 6,
                    title: String(localized: "Breaks"),
                    body: String(localized: """
                    After two weeks away the plan meets you a couple of steps \
                    lower — further down the longer the break. It never drops \
                    below something you have actually done. Nothing is lost: it \
                    climbs back quickly, and coming back is the only thing that \
                    matters.
                    """)),
            Section(id: 7,
                    title: String(localized: "Skips"),
                    body: String(localized: """
                    A skipped exercise simply doesn't count: it stays exactly \
                    where it was. No penalty, no rollback. A skipped SET is a \
                    different answer: the movement still counts as done, and \
                    the next plan comes back with one set fewer — until you \
                    earn it back.
                    """)),
            // This section used to explain the pain channel — a tap that
            // rested a movement for three appearances. The channel is gone,
            // and the case it served is answered by the easier variation and
            // by the skip inside the workout. The stop rule stays: what was
            // removed is a state machine, not the warning.
            Section(id: 8,
                    title: String(localized: "Too much today"),
                    body: String(localized: """
                    Muscles giving out and a joint hurting are different \
                    things, and the app does not ask which. When a movement \
                    is too much today, you answer with the plan and not with \
                    a diagnosis: take the same movement in an easier \
                    variation, or skip a set while you are doing it. Nothing \
                    has to be decided in advance — the plan says how long the \
                    full workout takes and how short it can get, and the rest \
                    you settle set by set. Sharp pain is always a reason to \
                    stop.
                    """)),
            // This section used to explain the hold-this-level input. The
            // input is cancelled — it was used zero times in 24 real sessions
            // — and the case it served is what the sub-step now handles
            // without being asked.
            Section(id: 9,
                    title: String(localized: "One set at a time"),
                    body: String(localized: """
                    Getting harder does not mean every set at once. A step \
                    adds a rep to ONE set: 3×8 becomes 9-8-8, then 9-9-8, \
                    then 3×9. The plan settles where you actually are, and \
                    overshooting costs one rep in one set instead of a whole \
                    variation.
                    """)),
            Section(id: 10,
                    title: String(localized: "Trying the next movement"),
                    body: String(localized: """
                    A harder variation is never handed to you on a guess. When \
                    you top out the reps, the LAST set of that exercise becomes \
                    a probe: one set of the next movement, four reps or fifteen \
                    seconds. Manage it and the next workout starts you there, \
                    at three sets of four. Fall short and nothing moves — you \
                    stay where you are and the probe comes round again. There \
                    is no wrong answer to give it, and the volume of the \
                    workout does not change either way.
                    """)),
            Section(id: 11,
                    title: String(localized: "Why there are no questionnaires"),
                    body: String(localized: """
                    A questionnaire can be wrong; what you actually did cannot. \
                    Dredfit learns what you can do from real workouts and keeps \
                    the load right at the edge of it.
                    """)),
            // The interference effect, said once and statically. It is a
            // scheduling hint, not a rule the engine can act on — Dredfit
            // cannot see the run you went on — so it belongs on the explainer
            // screen and nowhere else: no notification, no card, no repeat.
            Section(id: 12,
                    title: String(localized: "Cardio and strength"),
                    body: String(localized: """
                    If you also run, swim or cycle, try to put that and your \
                    strength work in different halves of the day. A couple of \
                    hours apart and they barely get in each other's way. Back \
                    to back, the interference shows. If splitting them is not \
                    an option, no harm done: at home volumes the difference is \
                    small.
                    """))
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("How it works")
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        .padding(.top, 30)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Twelve things worth knowing about the regulator.")
                        .dredfitFont(15)
                        .foregroundStyle(Theme.ink2)
                        .padding(.top, 8)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(sections) { section in
                        row(section).padding(.top, 26)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
            }

            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                // Settings sits underneath with its own "Got it" — both are
                // in the accessibility tree while this sheet is up.
                .accessibilityIdentifier("how-it-works-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }

    private func row(_ section: Section) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(section.id)")
                .dredfitFont(13, weight: .semibold)
                .foregroundStyle(Theme.bg)
                .frame(width: 26, height: 26)
                .background(Theme.ink, in: Circle())
                // Decorative ordering — the sections read fine without it.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(section.title)
                    .dredfitFont(17, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    // Header trait rather than combining title+body: keeps
                    // the titles skimmable by rotor.
                    .accessibilityAddTraits(.isHeader)
                Text(section.body)
                    .dredfitFont(15.5)
                    .foregroundStyle(Theme.ink2)
                    .lineSpacing(3.5)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
