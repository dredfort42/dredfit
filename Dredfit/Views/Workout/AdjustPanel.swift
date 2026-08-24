//
//  AdjustPanel.swift
//  Dredfit
//
//  The inline actual adjuster: −/value/+ and OK.
//

import SwiftUI
import DredfitCore

struct AdjustPanel: View {
    @Binding var value: Int
    /// Picks the corridor and the step — both defined once, in SetFacts, so
    /// what this panel offers and what a hold stopped early rounds to are the
    /// same grid.
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
                    .foregroundStyle(Theme.bg)
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
        let range = SetFacts.corridor(for: unit)
        let stepped = value + dir * SetFacts.step(for: unit)
        value = min(max(stepped, range.lowerBound), range.upperBound)
    }

    private func stepButton(_ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .dredfitFont(15, weight: .semibold)
                .foregroundStyle(Theme.ink)
                .frame(width: 40, height: 40)
                .background(Circle().stroke(Theme.hairline, lineWidth: 1.5))
        }
        .accessibilityLabel(Text(icon == "minus"
                                 ? String(localized: "Fewer")
                                 : String(localized: "More")))
        // Pinned so the label above does not move the symbol-derived id.
        .accessibilityIdentifier(icon)
    }
}
