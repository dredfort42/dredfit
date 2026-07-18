//
//  RootView.swift
//  Dredfit
//
//  If today's workout is already done, the app opens on the Calendar tab.
//  The switch happens only on cold start, never mid-session.
//
//  The settings icon lives here, not in ProgressScreen: it overlays the
//  TabView at a fixed position so it's reachable from any tab, not just
//  the one it happened to be bolted onto.
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store

    enum Tab: Hashable { case today, calendar, progress }
    @State private var tab: Tab = .today
    @State private var didSetInitialTab = false
    @State private var settingsShown = false

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
        .overlay(alignment: .topTrailing) {
            Button {
                settingsShown = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("settings")
            .padding(.top, 4)
            .padding(.trailing, 11)
        }
        .sheet(isPresented: $settingsShown) {
            SettingsSheet()
        }
        .onAppear {
            guard !didSetInitialTab else { return }
            didSetInitialTab = true
            if store.doneToday { tab = .calendar }
        }
    }
}
