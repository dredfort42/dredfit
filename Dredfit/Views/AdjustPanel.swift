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
    /// The corridors the engine prescribes in: holds step by 5 within 5…90,
    /// reps by 1 within 0…30.
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
        .accessibilityLabel(Text(icon == "minus"
                                 ? String(localized: "Fewer")
                                 : String(localized: "More")))
        // Pinned so the label above does not move the symbol-derived id.
        .accessibilityIdentifier(icon)
    }
}
