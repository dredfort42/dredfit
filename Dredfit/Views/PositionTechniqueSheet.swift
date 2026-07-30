//
//  PositionTechniqueSheet.swift
//  Dredfit
//
//  The reduced technique sheet for warm-up and cool-down positions
//  (issue #34): name, a block capsule, 2–3 numbered steps, "Got it".
//  For a beginner "Lat stretch with support" is an empty label, and the
//  context is harsher than for exercises — a countdown is running, there
//  is no time to look anything up. The flow freezes that countdown while
//  the sheet is open: reading is not stretching.
//

import SwiftUI

/// What the sheet shows — built from a warm-up move or a cool-down
/// position, so the sheet itself needs to know about neither.
struct PositionTechnique: Identifiable, Equatable {
    let id: String
    let name: String
    let capsule: String
    let steps: [String]
}

extension PositionTechnique {
    init(warmup move: WarmupMove) {
        self.init(id: move.id, name: move.name,
                  capsule: String(localized: "positionSheet.warmup",
                                  defaultValue: "warm-up · \(Warmup.moveSeconds) s"),
                  steps: move.steps)
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

/// TechniqueSheet's little sibling: the same name, capsule and numbered
/// rows, without mistakes and the "In life" line — two or three steps are
/// read mid-block, not studied between sets.
struct PositionTechniqueSheet: View {
    let technique: PositionTechnique
    @Environment(\.dismiss) private var dismiss

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
                                .foregroundStyle(.white)
                                .frame(width: 26, height: 26)
                                .background(Theme.ink, in: Circle())
                            Text(step)
                                .dredfitFont(16.5)
                                .lineSpacing(4)
                        }
                        .padding(.vertical, 13)
                    }
                }
                .padding(.horizontal, 24)
            }

            PrimaryButton(title: String(localized: "Got it")) { dismiss() }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
        }
        // Medium fits two or three steps; large is there for the biggest
        // Dynamic Type sizes, with the ScrollView carrying the overflow.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
