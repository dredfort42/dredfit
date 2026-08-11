//
//  RootView.swift
//  Dredfit
//
//  The settings icon overlays the TabView so it is reachable from any tab,
//  not owned by one screen.
//

import SwiftUI

struct RootView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase

    enum Tab: Hashable { case today, calendar, progress }
    @State private var tab: Tab = .today
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
            // A cold launch renders already `.active`, so the phase change
            // below never fires for it — without this call a comeback after
            // 7–13 days away would train on pre-break levels.
            store.activate()
            onboardingShown = store.shouldShowOnboarding
        }
        // A cold start never has a live workout: anything still alive belongs
        // to a killed process and must leave the lock screen now, not at the
        // system's hours-long cap.
        .task { WorkoutActivityController.endOrphans() }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // An active scene proves the device is unlocked: the journal
                // gets its second read, the day re-anchors with the
                // blind-zone decay, and the reminder window is rebuilt so it
                // never runs dry while the app is in use.
                store.activate()
            case .background:
                store.refreshWidgetSnapshot()
            default:
                break
            }
        }
    }
}
