//
//  DredfitWidgetsBundle.swift
//  DredfitWidgets
//
//  v1.3: one extension hosts both the home-screen widget and the
//  workout Live Activity.
//

import WidgetKit
import SwiftUI

@main
struct DredfitWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayStatusWidget()
        RestLiveActivity()
    }
}

/// The widget mirrors the app's ink-and-accent palette. Kept local:
/// the design system itself lives in the app target.
enum WidgetTheme {
    static let accent = Color(red: 232 / 255, green: 89 / 255, blue: 12 / 255) // #E8590C
    static let ink = Color(red: 0.10, green: 0.10, blue: 0.10)
    static let ink2 = Color(red: 0.45, green: 0.45, blue: 0.45)
}
