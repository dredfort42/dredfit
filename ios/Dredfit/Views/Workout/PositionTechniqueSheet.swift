//
//  The reduced technique sheet for warm-up and cool-down positions: name,
//  block capsule, 2–3 steps. The flow freezes the countdown while it is open.
//

import SwiftUI

/// Built from a warm-up move or a cool-down position, so the sheet itself
/// needs to know about neither.
struct PositionTechnique: Identifiable, Equatable {
    let id: String
    let name: String
    let capsule: String
    let steps: [String]
}

extension PositionTechnique {
    init(warmup move: WarmupMove) {
        // A split move says the length of ONE half, the way the cool-down twin
        // below always has: since §41.12 its slot is two halves with the switch
        // pause between them, and "warm-up · 30 s" would be the number of
        // neither half.
        let capsule: String
        switch move.halves {
        case .sides:
            capsule = String(localized: "positionSheet.warmupPerSide",
                             defaultValue: "warm-up · \(Warmup.halfSeconds) s per side")
        case .directions:
            capsule = String(localized: "positionSheet.warmupPerDirection",
                             defaultValue: "warm-up · \(Warmup.halfSeconds) s each way")
        case nil:
            capsule = String(localized: "positionSheet.warmup",
                             defaultValue: "warm-up · \(Warmup.moveSeconds) s")
        }
        self.init(id: move.id, name: move.name, capsule: capsule, steps: move.steps)
    }

    init(cooldown position: CooldownPosition) {
        let capsule = position.perSide
            ? String(localized: "positionSheet.cooldownPerSide",
                     defaultValue: "cool-down · \(Cooldown.sideSeconds) s per side")
            : String(localized: "positionSheet.cooldown",
                     defaultValue: "cool-down · \(Cooldown.positionSeconds) s")
        self.init(id: position.id, name: position.name,
                  capsule: capsule, steps: position.steps)
    }
}

struct PositionTechniqueSheet: View {
    let technique: PositionTechnique
    @Environment(\.dismiss) private var dismiss
    /// Reached through the environment rather than through the initializer:
    /// the sheet is presented by `WorkoutFlowView` with the technique alone,
    /// and the way in for finding 49 must not change that call.
    @Environment(AppStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(technique.name)
                        .dredfitFont(28, weight: .heavy)
                        .tracking(-0.5)
                        .padding(.top, 30)

                    Text(technique.capsule)
                        .dredfitFont(13)
                        .foregroundStyle(Theme.ink2)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .overlay(Capsule().stroke(Theme.hairline, lineWidth: 1))
                        .padding(.top, 10)

                    Kicker(text: String(localized: "Technique")).padding(.top, 28)
                    ForEach(Array(technique.steps.enumerated()), id: \.offset) { i, step in
                        HStack(alignment: .top, spacing: 14) {
                            Text("\(i + 1)")
                                .dredfitFont(13, weight: .semibold)
                                .foregroundStyle(Theme.bg)
                                .frame(width: 26, height: 26)
                                .background(Theme.ink, in: Circle())
                            Text(step)
                                .dredfitFont(16.5)
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 13)
                    }

                    setAsideControl
                    setAsideList
                }
                .padding(.horizontal, 24)
            }

            // Its own name — see TechniqueSheet: four sheets close on the same
            // two words, and this one opens OVER a running block, so a test
            // that closed the wrong sheet would leave the block running.
            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .accessibilityIdentifier("position-technique-done")
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        // large is for the biggest Dynamic Type sizes; the ScrollView
        // carries the overflow.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }

    // MARK: - "Not this one" (UX review 05.09.2026, finding 49)

    /// The one place in the app where a warm-up move or a cool-down position
    /// can be refused for good.
    ///
    /// Before this, "not this one" cost the same tap on the same position in
    /// every single workout — cat-cow fell in 100 % of warm-ups and the wall
    /// stretch stood second in every cool-down — and the cheap way out of that
    /// was already on screen: skip the whole block. So the block loses one
    /// position and composes another in its place; the pool is nine against
    /// six shown, which is exactly what pays for it.
    ///
    /// The tap closes the sheet, because the answer to "don't show me this"
    /// is not to go on showing it: the block restarts the slot on its own
    /// transition (`rebaseWarmupOnComposition`).
    @ViewBuilder
    private var setAsideControl: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                store.setBlockMoveHidden(technique.id, true)
                dismiss()
            } label: {
                Text("Don't show this again").pairedSecondaryLabel()
            }
            .disabled(!store.canHideAnotherBlockMove)
            .accessibilityIdentifier("position-technique-hide")

            // The cap is named rather than enforced in silence: a control that
            // does nothing when tapped is the defect this line exists against.
            // The number is interpolated rather than spelled, because the cap
            // is `AppStore.maxHiddenBlockMoves` and a spelled "three" would go
            // on saying three after the pool grew.
            Text(store.canHideAnotherBlockMove
                 ? String(localized: "Something else takes its place.")
                 : String(localized: """
                     \(AppStore.maxHiddenBlockMoves) is the most that can be set aside. \
                     Bring one back to make room.
                     """))
                .dredfitFont(13)
                .foregroundStyle(Theme.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 18)
    }

    /// The way back, and the reason the button above is not a one-way door.
    ///
    /// It lives here rather than in Settings because this is the only screen
    /// the ids can be read from: a move that has been set aside never reaches
    /// the block again, so its own sheet can no longer be opened. Nothing is
    /// drawn until something has been set aside.
    @ViewBuilder
    private var setAsideList: some View {
        let entries = setAsideEntries
        if !entries.isEmpty {
            Kicker(text: String(localized: "Not shown any more")).padding(.top, 26)
            ForEach(entries) { entry in
                HStack(spacing: 12) {
                    Text(entry.name)
                        .dredfitFont(15)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(String(localized: "Bring back")) {
                        store.setBlockMoveHidden(entry.id, false)
                    }
                    .dredfitFont(14.5, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .frame(minHeight: 44)
                    // "Bring back" three times over is one label three times
                    // over to VoiceOver, which reads the buttons and not the
                    // rows they sit in.
                    .accessibilityLabel(String(localized: "Bring back \(entry.name)"))
                    .accessibilityIdentifier("position-technique-restore-\(entry.id)")
                }
                .padding(.top, 4)
            }
        }
    }

    /// A row of the list above. A struct rather than the tuple this wanted to
    /// be: `ForEach` needs `Identifiable` or a key path, and Swift has no key
    /// path into a tuple.
    private struct SetAside: Identifiable {
        let id: String
        let name: String
    }

    /// Ids to names, asking both pools: one list covers the warm-up and the
    /// cool-down, and neither knows the other's ids. Sorted by name so the
    /// rows do not reshuffle on every redraw — `Set` has no order.
    private var setAsideEntries: [SetAside] {
        store.settings.hiddenBlockMoveIDs
            .compactMap { id in
                // An id from a build that knew a move this one does not has
                // nothing to name and nothing to offer — the composers pass
                // over it too.
                guard let name = Warmup.name(ofMove: id) ?? Cooldown.name(ofPosition: id) else {
                    return nil
                }
                return SetAside(id: id, name: name)
            }
            .sorted { $0.name < $1.name }
    }
}
