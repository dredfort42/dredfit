//
//  RootView.swift
//  Dredfit
//
//  If today's workout is already done, the app opens on the Calendar tab.
//  The switch happens only on cold start, never mid-session.
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    enum Tab: Hashable { case today, calendar, progress }
    @State private var tab: Tab = .today
    @State private var didSetInitialTab = false

    var body: some View {
        TabView(selection: $tab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "circle.inset.filled") }
                .tag(Tab.today)
            CalendarScreen()
                .tabItem { Label("Calendar", systemImage: "calendar") }
                .tag(Tab.calendar)
            ProgressScreen()
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(Tab.progress)
        }
        .tint(Theme.ink)
        .onAppear {
            guard !didSetInitialTab else { return }
            didSetInitialTab = true
            if store.doneToday { tab = .calendar }
        }
    }
}
