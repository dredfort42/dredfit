//
//  AdjustPanel.swift
//  Dredfit
//
//  The inline actual adjuster: −/value/+ and OK. Moved out of
//  WorkoutFlowView wholesale — the flow file sits at the linter's honest
//  file-length ceiling, and the panel is its one self-contained piece of
//  chrome. Behaviour is unchanged.
//

import SwiftUI
import DredfitCore

struct AdjustPanel: View {
    @Binding var value: Int
    /// Holds step by 5 within 5…90 and show a trailing "s"; reps by 1
    /// within 0…30 — the same corridors the engine prescribes in.
    let unit: LoadUnit
    let onConfirm: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            stepButton("minus") { bump(-1) }
            Text(unit == .hold ? "\(value) s" : "\(value)")
                .dredfitFont(26, weight: .heavy)
                .monospacedDigit()
                .frame(minWidth: 76)
            stepButton("plus") { bump(+1) }

            Button(action: onConfirm) {
                Text("OK")
                    .dredfitFont(15, weight: .semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 10)
                    .background(Theme.ink, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Theme.cardBG, in: RoundedRectangle(cornerRadius: 18))
    }

    private func bump(_ dir: Int) {
        let step = unit == .hold ? 5 : 1
        let range = unit == .hold ? 5...90 : 0...30
        value = min(max(value + dir * step, range.lowerBound), range.upperBound)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .dredfitFont(15, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().stroke(Theme.hairline, lineWidth: 1.5))
        }
        // "minus"/"plus" alone is what VoiceOver would otherwise announce.
        .accessibilityLabel(Text(icon == "minus"
                                 ? String(localized: "Fewer")
                                 : String(localized: "More")))
        // Pinned so the label change does not move the symbol-derived id.
        .accessibilityIdentifier(icon)
    }
}
