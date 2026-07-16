//
//  Theme.swift
//  Dredfit
//

import SwiftUI

enum Theme {
    static let ink = Color(red: 0x11/255, green: 0x12/255, blue: 0x14/255)
    static let ink2 = Color(red: 0x6E/255, green: 0x70/255, blue: 0x75/255)
    static let ink3 = Color(red: 0xA7/255, green: 0xA9/255, blue: 0xAD/255)
    static let hairline = Color(red: 0xEC/255, green: 0xED/255, blue: 0xEF/255)
    static let accent = Color(red: 0xE8/255, green: 0x59/255, blue: 0x0C/255)
    static let accentSoft = Color(red: 0xFB/255, green: 0xE3/255, blue: 0xD6/255)
    static let cardBG = Color(red: 0xF7/255, green: 0xF7/255, blue: 0xF5/255)
}

struct PrimaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(Theme.ink, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

struct Kicker: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(Theme.ink3)
    }
}
