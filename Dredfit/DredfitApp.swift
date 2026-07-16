//
//  DredfitApp.swift
//  Dredfit
//

import SwiftUI

@main
@MainActor
struct DredfitApp: App {
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(.light)
        }
    }
}
