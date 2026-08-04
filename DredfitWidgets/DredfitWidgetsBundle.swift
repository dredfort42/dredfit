//
//  DredfitWidgetsBundle.swift
//  DredfitWidgets
//
//  Carries @main and stays out of the unit test bundle.
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
