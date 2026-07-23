//
//  HowItWorksView.swift
//  Dredfit
//
//  The regulator explained in seven sections (v1.4, +breaks in v1.5).
//  Onboarding says the app
//  adapts; this says how, for the user who wants to know why the plan moved.
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
            Section(id: 1,
                    title: String(localized: "The level"),
                    body: String(localized: """
                    One number per movement: it encodes both the variation and \
                    the reps. Top out the reps and the variation gets harder \
                    while the count starts over — and on the harder variations \
                    the count starts lower, so the change lands softly. The \
                    fourth variation is the last one — above it the sets grow \
                    instead, from three to five.
                    """)),
            Section(id: 2,
                    title: String(localized: "What your answer does"),
                    body: String(localized: """
                    “On plan” adds a step, “more” adds two, “less” takes one \
                    away. An exact number for a single exercise outweighs the \
                    overall rating. From a standing start an exact number sets \
                    the level immediately — the first workout calibrates the \
                    system. After that the level climbs at most two steps per \
                    workout.
                    """)),
            Section(id: 3,
                    title: String(localized: "Deload"),
                    body: String(localized: """
                    Three shortfalls in a row and the level rolls back three \
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
                    title: String(localized: "Breaks"),
                    body: String(localized: """
                    After two weeks away the plan meets you a couple of steps \
                    lower — further down the longer the break. Nothing is lost: \
                    the levels climb back quickly, and coming back is the only \
                    thing that matters.
                    """)),
            Section(id: 6,
                    title: String(localized: "Skips"),
                    body: String(localized: """
                    A skipped exercise simply doesn't count: its level stays \
                    where it was. No penalty, no rollback.
                    """)),
            Section(id: 7,
                    title: String(localized: "Why there are no questionnaires"),
                    body: String(localized: """
                    A questionnaire can be wrong; what you actually did cannot. \
                    Dredfit finds your level from real workouts and keeps the \
                    load right at the edge of what you can manage.
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

                    Text("Seven things worth knowing about the regulator.")
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
                // Settings sits underneath with its own "Got it" — both are in
                // the accessibility tree while this sheet is up.
                .accessibilityIdentifier("how-it-works-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func row(_ section: Section) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(section.id)")
                .dredfitFont(13, weight: .semibold)
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(Theme.ink, in: Circle())
                // Decorative ordering — the sections read fine without it.
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(section.title)
                    .dredfitFont(17, weight: .semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    // Header trait rather than combining title+body: it keeps
                    // the titles skimmable by rotor instead of forcing a
                    // full paragraph read per section.
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
