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
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: Hashable { case today, calendar, progress }
    @State private var tab: Tab = .today
    @State private var didSetInitialTab = false
    @State private var settingsShown = false
    @State private var onboardingShown = false

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
                    .dredfitFont(17, weight: .medium)
                    .foregroundStyle(Theme.ink2)
                    .frame(width: 44, height: 44)
            }
            .accessibilityIdentifier("settings")
            .accessibilityLabel(Text("Settings"))
            .padding(.top, 4)
            .padding(.trailing, 11)
        }
        .sheet(isPresented: $settingsShown) {
            SettingsSheet()
        }
        .fullScreenCover(isPresented: $onboardingShown) {
            OnboardingView {
                store.completeOnboarding()
                onboardingShown = false
            }
        }
        .onAppear {
            guard !didSetInitialTab else { return }
            didSetInitialTab = true
            if store.doneToday { tab = .calendar }
            // Deliberately after the tab decision: a fresh install has nothing
            // done today, so the cover always opens over Today.
            onboardingShown = store.shouldShowOnboarding
        }
        // A cold start cannot have a workout in progress — any Live Activity
        // still alive belongs to a killed session and must leave the lock
        // screen now, not when its multi-hour system cap expires.
        .task { WorkoutActivityController.endOrphans() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Re-anchor "today": an overnight suspension must not keep
                // showing yesterday's "completed" state without a Start button.
                store.refreshDay()
            case .background:
                // The widget snapshot covers 7 days from its last write; each
                // backgrounding restarts that window so the widget survives a
                // week without a cold launch.
                store.refreshWidgetSnapshot()
            default:
                break
            }
        }
    }
}
