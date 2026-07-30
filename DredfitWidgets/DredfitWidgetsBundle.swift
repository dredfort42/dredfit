//
//  DredfitWidgetsBundle.swift
//  DredfitWidgets
//
//  One extension hosts both the home-screen widget and the workout
//  Live Activity. The palette lives in WidgetTheme.swift — this file
//  carries @main and stays out of the unit test bundle.
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
