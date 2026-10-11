//
//  The few app symbols the linked iOS files name but this probe has no use
//  for — none of them a persisted type, none ever called. Each exists only so
//  the app's files compile unchanged outside the app.
//

import SwiftUI
import DredfitCore

/// On macOS SwiftUI exports a `Pattern` of its own, and SetFacts.swift
/// imports both modules; a declaration in this module outranks both imports,
/// so the app's file reads `Pattern` as the engine's, as it does on iOS.
typealias Pattern = DredfitCore.Pattern

/// AppSettings.swift ends with `extension AppStore` (the settings-only
/// switches) and SetFacts.swift with a SwiftUI label. The probe reads and
/// writes JSON and never runs either, so these stand in for the store and the
/// theme and trap if anything ever reaches them.
final class AppStore {
    var settings: AppSettings { fatalError("the probe has no store") }
    func update(_ change: (inout PersistedState) -> Void) { fatalError("the probe has no store") }
}

enum Theme {
    static var accentText: Color { fatalError("the probe draws nothing") }
}

extension View {
    func dredfitFont(_ size: CGFloat, weight: Font.Weight = .regular) -> some View {
        font(.system(size: size, weight: weight))
    }
}
